class_name Player
extends CharacterBody3D
## Playable Vampire Hunter with explicit State Machine, Resource-driven combos,
## Animation Canceling, i-frame dodging, aerial combos, and optional Class Skill.

signal class_changed(new_class: HunterClassData)
signal combo_step_changed(step_label: String)

const GRAVITY: float = 24.5
const INPUT_BUFFER_WINDOW: float = 0.16

@export var class_data: HunterClassData = null
@export var camera_rig_path: NodePath = NodePath()

@onready var state_machine: StateMachine = $StateMachine
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hitbox: Hitbox3D = $VisualRoot/Hitbox3D
@onready var weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var weapon_blade_mesh: MeshInstance3D = $VisualRoot/WeaponPivot/BladeMesh
@onready var weapon_trail: WeaponTrail3D = $VisualRoot/WeaponPivot/WeaponTrail3D
@onready var cloak_mesh: MeshInstance3D = $VisualRoot/BodyCloak
@onready var accent_mesh: MeshInstance3D = $VisualRoot/CrimsonScarf
@onready var parry_aura_mesh: MeshInstance3D = $VisualRoot/ParryAuraMesh

var camera_rig: CombatCameraRig = null
var current_weapon: WeaponData = null

# Combat runtime flags & timers
var dodge_cooldown_remaining: float = 0.0
var skill_cooldown_remaining: float = 0.0
var air_dodge_used: bool = false
var air_combo_used: bool = false
var is_parry_window_active: bool = false
var parry_counter_triggered: bool = false
var last_parried_attacker: Node3D = null

# Telemetry for Debug HUD
var current_combo_label: String = "None"
var cancel_window_status: String = "-"
var last_cancel_note: String = ""

var _input_buffers: Dictionary = {}
var _spawn_position: Vector3 = Vector3.ZERO
var _cloak_material: StandardMaterial3D = null
var _accent_material: StandardMaterial3D = null
var _blade_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position

	if not camera_rig_path.is_empty():
		camera_rig = get_node_or_null(camera_rig_path) as CombatCameraRig

	if hurtbox != null:
		hurtbox.owner_entity = self
		hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	if hitbox != null:
		hitbox.owner_entity = self
		hitbox.hit_confirmed.connect(_on_hitbox_hit_confirmed)
	if health != null:
		health.died.connect(_on_died)

	_setup_dynamic_materials()

	if class_data == null:
		class_data = load("res://data/classes/vanguard_inquisitor.tres") as HunterClassData
	apply_class_data(class_data)

	state_machine.initialize(self)


func _unhandled_input(event: InputEvent) -> void:
	for action_name: StringName in [&"attack_light", &"attack_launcher", &"dodge", &"jump", &"class_skill"]:
		if event.is_action_pressed(action_name):
			_input_buffers[action_name] = Time.get_ticks_msec() / 1000.0
	state_machine.handle_input(event)


func _process(delta: float) -> void:
	if dodge_cooldown_remaining > 0.0:
		dodge_cooldown_remaining = maxf(0.0, dodge_cooldown_remaining - delta)
	if skill_cooldown_remaining > 0.0:
		skill_cooldown_remaining = maxf(0.0, skill_cooldown_remaining - delta)
	state_machine.update(delta)


func _physics_process(delta: float) -> void:
	if is_on_floor():
		air_dodge_used = false
		air_combo_used = false
	state_machine.physics_update(delta)


func apply_class_data(new_class: HunterClassData) -> void:
	if new_class == null:
		return
	class_data = new_class
	current_weapon = class_data.default_weapon
	if health != null:
		health.configure_max_health(class_data.max_health, true)

	if _cloak_material != null:
		_cloak_material.albedo_color = class_data.cloak_color
	if _accent_material != null:
		_accent_material.albedo_color = class_data.accent_color
		_accent_material.emission = class_data.accent_color

	if current_weapon != null:
		if _blade_material != null:
			_blade_material.albedo_color = current_weapon.blade_color
		if weapon_blade_mesh != null:
			var length_scale: float = clampf(current_weapon.blade_length / 1.6, 0.75, 1.35)
			weapon_blade_mesh.scale = Vector3(1.0, length_scale, 1.0)
		if weapon_trail != null:
			weapon_trail.set_trail_color(current_weapon.trail_color)

	dodge_cooldown_remaining = 0.0
	skill_cooldown_remaining = 0.0
	class_changed.emit(class_data)


func reset_for_gym() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	dodge_cooldown_remaining = 0.0
	skill_cooldown_remaining = 0.0
	air_dodge_used = false
	air_combo_used = false
	is_parry_window_active = false
	parry_counter_triggered = false
	clear_all_buffers()
	if health != null:
		health.is_invulnerable = false
		health.reset_health()
	if hitbox != null:
		hitbox.deactivate()
	if weapon_trail != null:
		weapon_trail.emitting = false
		weapon_trail.clear_trail()
	reset_weapon_pose()
	state_machine.transition_to(&"Idle")


func get_move_input_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func get_camera_relative_move_direction() -> Vector3:
	var input_vec: Vector2 = get_move_input_vector()
	if input_vec.length_squared() < 0.001:
		return Vector3.ZERO
	var cam_basis: Basis = camera_rig.get_horizontal_basis() if camera_rig != null else global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var direction: Vector3 = (right * input_vec.x) + (forward * -input_vec.y)
	return direction.normalized()


func get_facing_direction() -> Vector3:
	var forward: Vector3 = -visual_root.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func face_direction(direction: Vector3, turn_speed: float, delta: float) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-flat.x, -flat.z)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func face_locked_or_input_immediately() -> void:
	if camera_rig != null and camera_rig.locked_target != null and is_instance_valid(camera_rig.locked_target):
		var to_target: Vector3 = camera_rig.locked_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			visual_root.rotation.y = atan2(-to_target.x, -to_target.z)
			return
	var move_dir: Vector3 = get_camera_relative_move_direction()
	if move_dir.length_squared() > 0.01:
		visual_root.rotation.y = atan2(-move_dir.x, -move_dir.z)


func can_dodge() -> bool:
	if dodge_cooldown_remaining > 0.0:
		return false
	if not is_on_floor() and air_dodge_used:
		return false
	return true


func can_use_skill() -> bool:
	if class_data == null or class_data.special_skill == HunterClassData.SpecialSkillType.NONE:
		return false
	return skill_cooldown_remaining <= 0.0


func has_buffered_action(action_name: StringName) -> bool:
	if not _input_buffers.has(action_name):
		return false
	var now: float = Time.get_ticks_msec() / 1000.0
	return (now - float(_input_buffers[action_name])) <= INPUT_BUFFER_WINDOW


func consume_buffered_action(action_name: StringName) -> bool:
	if has_buffered_action(action_name):
		_input_buffers.erase(action_name)
		return true
	return false


func clear_all_buffers() -> void:
	_input_buffers.clear()


func set_combo_debug_label(label_text: String) -> void:
	current_combo_label = label_text
	combo_step_changed.emit(label_text)


func set_weapon_swing_pose(yaw_deg: float, pitch_deg: float, roll_deg: float) -> void:
	if weapon_pivot != null:
		weapon_pivot.rotation_degrees = Vector3(pitch_deg, yaw_deg, roll_deg)


func reset_weapon_pose() -> void:
	if weapon_pivot != null:
		weapon_pivot.rotation_degrees = Vector3(16.0, -34.0, -18.0)


func set_parry_aura_visible(is_visible: bool) -> void:
	if parry_aura_mesh != null:
		parry_aura_mesh.visible = is_visible


func spawn_dodge_ghost(tint: Color = Color(0.92, 0.10, 0.20, 0.55), duration: float = 0.24) -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var ghost_xform: Transform3D = global_transform
	ghost_xform.origin += Vector3(0.0, 0.9, 0.0)
	DodgeAfterimage.spawn(parent_node, ghost_xform, tint, 1.7, 0.35, duration)


func get_height_above_ground() -> float:
	return maxf(0.0, global_position.y)


func _on_hurtbox_hit_received(info: DamageInfo) -> void:
	# 1) Optional Crimson Parry interception (Vanguard Inquisitor)
	if is_parry_window_active:
		parry_counter_triggered = true
		last_parried_attacker = info.source
		if GameFeelManager != null:
			GameFeelManager.trigger_hitstop(0.095, 0.03)
			GameFeelManager.request_screen_shake(0.26, 0.18)
			GameFeelManager.log_combat_event("CRIMSON PARRY! Counter-slash triggered.")
		return

	# 2) Primary defense: Dodge i-frames
	if health != null and health.is_invulnerable:
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("PERFECT EVADE (i-frames)!")
		return

	# 3) Apply damage & enter brief hitstun
	if health != null:
		var dealt: float = health.apply_damage(info)
		if dealt > 0.0:
			if GameFeelManager != null:
				GameFeelManager.trigger_hitstop(0.055, 0.05)
				GameFeelManager.request_screen_shake(0.24, 0.16)
				GameFeelManager.log_combat_event("Hunter hit for %.0f DMG" % dealt)
			state_machine.transition_to(&"Hitstun", {"info": info})


func _on_hitbox_hit_confirmed(target_entity: Node3D, info: DamageInfo) -> void:
	if GameFeelManager != null:
		GameFeelManager.trigger_hitstop(info.hitstop_duration, 0.04)
		GameFeelManager.request_screen_shake(info.screen_shake, 0.13)
		var tag: String = " [LAUNCHER]" if info.is_launcher else (" [AERIAL]" if info.is_aerial else (" [COUNTER]" if info.is_counter else ""))
		GameFeelManager.log_combat_event("Hit %s for %.0f%s" % [target_entity.name, info.amount, tag])


func _on_died() -> void:
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("Hunter fell in Combat Gym -> Auto-restoring HP.")
	if health != null:
		health.reset_health()


func _setup_dynamic_materials() -> void:
	if cloak_mesh != null:
		_cloak_material = StandardMaterial3D.new()
		_cloak_material.roughness = 0.88
		_cloak_material.metallic = 0.08
		cloak_mesh.material_override = _cloak_material
	if accent_mesh != null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.roughness = 0.45
		_accent_material.emission_enabled = true
		_accent_material.emission_energy_multiplier = 1.2
		accent_mesh.material_override = _accent_material
	if weapon_blade_mesh != null:
		_blade_material = StandardMaterial3D.new()
		_blade_material.roughness = 0.25
		_blade_material.metallic = 0.85
		weapon_blade_mesh.material_override = _blade_material

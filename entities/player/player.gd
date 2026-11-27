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
@onready var combat_comp: PlayerCombatComponent = $PlayerCombatComponent
@onready var modifiers: CombatModifierComponent = $CombatModifierComponent
@onready var inventory: InventoryComponent = get_node_or_null("InventoryComponent") as InventoryComponent
@onready var death_ragdoll: DeathRagdollComponent = get_node_or_null("DeathRagdollComponent") as DeathRagdollComponent
@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hitbox: Hitbox3D = $VisualRoot/Hitbox3D
@onready var weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var weapon_blade_mesh: MeshInstance3D = $VisualRoot/WeaponPivot/BladeMesh
@onready var weapon_trail: WeaponTrail3D = $VisualRoot/WeaponPivot/WeaponTrail3D
@onready var cloak_mesh: MeshInstance3D = $VisualRoot/BodyCloak
@onready var accent_mesh: MeshInstance3D = $VisualRoot/CrimsonScarf
@onready var parry_aura_mesh: MeshInstance3D = $VisualRoot/ParryAuraMesh
@onready var character_model: Node3D = get_node_or_null("VisualRoot/CharacterModel") as Node3D

var camera_rig: CombatCameraRig = null
var current_weapon: WeaponData = null
var model_anim_player: AnimationPlayer = null

# Combat runtime flags & timers
var dodge_cooldown_remaining: float = 0.0
var skill_cooldown_remaining: float = 0.0
var slide_cooldown_remaining: float = 0.0
var air_dodge_used: bool = false
var air_combo_used: bool = false
var is_sliding: bool = false
var is_backflip_dodge: bool = false
var is_parry_window_active: bool = false
var parry_counter_triggered: bool = false
var last_parried_attacker: Node3D = null
var is_dead: bool = false

# Telemetry for Debug HUD
var current_combo_label: String = "None"
var cancel_window_status: String = "-"
var last_cancel_note: String = ""

var _input_buffers: Dictionary = {}
var _spawn_position: Vector3 = Vector3.ZERO
var _last_damage_dir: Vector3 = Vector3.BACK
var _model_skeleton: Skeleton3D = null
var _last_requested_anim: StringName = &"Idle"
var _last_requested_speed: float = 1.0
var _last_requested_blend: float = 0.14
var _claymore_item: ItemData = preload("res://data/items/crimson_claymore_item.tres")
var _twinblade_item: ItemData = preload("res://data/items/silver_twinblade_item.tres")
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
	if inventory != null and not inventory.selected_slot_changed.is_connected(_on_hotbar_selection_changed):
		inventory.selected_slot_changed.connect(_on_hotbar_selection_changed)

	_setup_dynamic_materials()
	_setup_character_model()

	if class_data == null:
		class_data = load("res://data/classes/vanguard_inquisitor.tres") as HunterClassData
	apply_class_data(class_data)

	state_machine.initialize(self)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	for i: int in range(9):
		var hb_action: StringName = StringName("hotbar_%d" % (i + 1))
		if InputMap.has_action(hb_action) and event.is_action_pressed(hb_action):
			if inventory != null:
				inventory.select_hotbar_slot(i)
			return
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and inventory != null:
			inventory.cycle_hotbar(-1)
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and inventory != null:
			inventory.cycle_hotbar(1)
			return

	for action_name: StringName in [&"attack_light", &"attack_launcher", &"dodge", &"slide", &"jump", &"class_skill"]:
		if event.is_action_pressed(action_name):
			_input_buffers[action_name] = Time.get_ticks_msec() / 1000.0
	state_machine.handle_input(event)


func _process(delta: float) -> void:
	if is_dead:
		return
	if dodge_cooldown_remaining > 0.0:
		dodge_cooldown_remaining = maxf(0.0, dodge_cooldown_remaining - delta)
	if skill_cooldown_remaining > 0.0:
		skill_cooldown_remaining = maxf(0.0, skill_cooldown_remaining - delta)
	if slide_cooldown_remaining > 0.0:
		slide_cooldown_remaining = maxf(0.0, slide_cooldown_remaining - delta)
	if combat_comp != null:
		combat_comp.tick(delta)
	if modifiers != null:
		modifiers.tick(delta)
	state_machine.update(delta)


func _physics_process(delta: float) -> void:
	if is_dead:
		if death_ragdoll != null:
			death_ragdoll.step_physics(delta)
		return
	if is_on_floor():
		air_dodge_used = false
		air_combo_used = false
		if combat_comp != null:
			combat_comp.reset_air_jumps()
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

	# Place the class's signature sword into Hotbar Slot 1 (index 0)
	if inventory != null:
		var sword_item: ItemData = _resolve_item_for_weapon(class_data.default_weapon)
		inventory.set_hotbar_slot(0, sword_item, 1)
		_apply_equipped_weapon(inventory.get_selected_weapon())
	else:
		_apply_equipped_weapon(class_data.default_weapon)

	dodge_cooldown_remaining = 0.0
	skill_cooldown_remaining = 0.0
	class_changed.emit(class_data)


func _resolve_item_for_weapon(wpn: WeaponData) -> ItemData:
	if wpn != null and wpn.weapon_name.to_lower().contains("twinblade"):
		return _twinblade_item
	return _claymore_item


func _on_hotbar_selection_changed(_slot_index: int, _slot: InventorySlotData) -> void:
	if inventory == null:
		return
	_apply_equipped_weapon(inventory.get_selected_weapon())


func _apply_equipped_weapon(wpn: WeaponData) -> void:
	var prev_had_weapon: bool = (current_weapon != null)
	current_weapon = wpn
	var now_has_weapon: bool = (current_weapon != null)
	if weapon_pivot != null:
		weapon_pivot.visible = now_has_weapon
	if weapon_trail != null and not now_has_weapon:
		weapon_trail.emitting = false
		weapon_trail.clear_trail()
	if current_weapon != null:
		if _blade_material != null:
			_blade_material.albedo_color = current_weapon.blade_color
		if weapon_blade_mesh != null:
			var length_scale: float = clampf(current_weapon.blade_length / 1.6, 0.75, 1.35)
			weapon_blade_mesh.scale = Vector3(1.0, length_scale, 1.0)
		if weapon_trail != null:
			weapon_trail.set_trail_color(current_weapon.trail_color)
	if prev_had_weapon != now_has_weapon and not is_dead and model_anim_player != null:
		if _last_requested_anim in [&"Idle", &"Run", &"Jump", &"Dodge", &"Slide"]:
			play_character_animation(_last_requested_anim, _last_requested_speed, 0.18, false)


func reset_for_gym() -> void:
	is_dead = false
	if death_ragdoll != null:
		death_ragdoll.reset_ragdoll()
	global_position = _spawn_position
	velocity = Vector3.ZERO
	dodge_cooldown_remaining = 0.0
	skill_cooldown_remaining = 0.0
	slide_cooldown_remaining = 0.0
	air_dodge_used = false
	air_combo_used = false
	is_sliding = false
	is_backflip_dodge = false
	is_parry_window_active = false
	parry_counter_triggered = false
	clear_all_buffers()
	if health != null:
		health.is_invulnerable = false
		health.reset_health()
	if combat_comp != null:
		combat_comp.reset()
	if modifiers != null:
		modifiers.clear_all()
	var tdm: Node = get_tree().root.get_node_or_null("TimeDilationManager")
	if tdm != null and tdm.has_method("cancel_witch_time"):
		tdm.call("cancel_witch_time")
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
	var world_yaw: float = atan2(-flat.x, -flat.z)
	var local_target_yaw: float = wrapf(world_yaw - global_rotation.y, -PI, PI)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, local_target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func face_locked_or_input_immediately() -> void:
	if camera_rig != null and camera_rig.locked_target != null and is_instance_valid(camera_rig.locked_target):
		var to_target: Vector3 = camera_rig.locked_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			visual_root.rotation.y = wrapf(atan2(-to_target.x, -to_target.z) - global_rotation.y, -PI, PI)
			return
	var move_dir: Vector3 = get_camera_relative_move_direction()
	if move_dir.length_squared() > 0.01:
		visual_root.rotation.y = wrapf(atan2(-move_dir.x, -move_dir.z) - global_rotation.y, -PI, PI)


func face_locked_target(turn_speed: float, delta: float) -> bool:
	if camera_rig != null and camera_rig.locked_target != null and is_instance_valid(camera_rig.locked_target):
		var to_target: Vector3 = camera_rig.locked_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			face_direction(to_target, turn_speed, delta)
			return true
	return false


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


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_holding_slide() -> bool:
	return Input.is_action_pressed(&"slide")


func is_on_slope() -> bool:
	if not is_on_floor():
		return false
	var n: Vector3 = get_floor_normal()
	return Vector2(n.x, n.z).length() > 0.08


func can_slide(override_speed: float = -1.0) -> bool:
	if slide_cooldown_remaining > 0.0:
		return false
	if not is_on_floor():
		return false
	# Deadlock rule: any slope/stairs allows instant sliding regardless of entry speed
	if is_on_slope():
		return true
	var spd: float = override_speed if override_speed >= 0.0 else get_horizontal_speed()
	var threshold: float = class_data.slide_min_speed if class_data != null else 8.4
	return spd >= threshold


func should_backflip_dodge(dash_dir: Vector3) -> bool:
	var flat_dash: Vector3 = Vector3(dash_dir.x, 0.0, dash_dir.z)
	if flat_dash.length_squared() < 0.001:
		return false
	flat_dash = flat_dash.normalized()

	# 1) When locked onto a target: dodging away from the target triggers Backflip
	if camera_rig != null and camera_rig.locked_target != null and is_instance_valid(camera_rig.locked_target):
		var to_target: Vector3 = camera_rig.locked_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			return flat_dash.dot(to_target.normalized()) < -0.25

	# 2) Free camera: dodging backward relative to camera forward (pressing S) OR opposite to current facing
	var cam_basis: Basis = camera_rig.get_horizontal_basis() if camera_rig != null else global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	cam_forward.y = 0.0
	if cam_forward.length_squared() > 0.001 and flat_dash.dot(cam_forward.normalized()) < -0.35:
		return true
	return flat_dash.dot(get_facing_direction()) < -0.25


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


func set_weapon_swing_pose(_yaw_deg: float, _pitch_deg: float, _roll_deg: float) -> void:
	# Skeletal animations drive Hand.R directly when CharacterModel is present.
	if character_model == null and weapon_pivot != null:
		weapon_pivot.rotation_degrees = Vector3(_pitch_deg, _yaw_deg, _roll_deg)


func reset_weapon_pose() -> void:
	if weapon_pivot != null:
		weapon_pivot.position = Vector3(0.0, 0.09, 0.0)
		weapon_pivot.rotation_degrees = Vector3(106.06, -43.47, 90.44)


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


func get_effective_damage_multiplier() -> float:
	return modifiers.get_multiplier(&"damage_mult") if modifiers != null else 1.0


func get_effective_attack_speed(base_speed: float) -> float:
	var mult: float = modifiers.get_multiplier(&"attack_speed_mult") if modifiers != null else 1.0
	return base_speed * mult


func get_effective_move_speed() -> float:
	if class_data == null:
		return 7.6
	var mult: float = modifiers.get_multiplier(&"move_speed_mult") if modifiers != null else 1.0
	return class_data.move_speed * mult


func get_active_combat_target(search_dir: Vector3 = Vector3.ZERO) -> Node3D:
	if camera_rig != null and camera_rig.locked_target != null and is_instance_valid(camera_rig.locked_target):
		return camera_rig.locked_target
	if combat_comp != null:
		var dir: Vector3 = search_dir if search_dir.length_squared() > 0.01 else get_facing_direction()
		return combat_comp.find_soft_lock_target(global_position, dir, get_tree().get_nodes_in_group("enemies"))
	return null


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

	# 2) Primary defense: Dodge i-frames (Perfect Dodge against strike triggers Witch Time!)
	if health != null and health.is_invulnerable:
		if combat_comp != null:
			combat_comp.try_trigger_witch_time(global_position, get_tree().get_nodes_in_group("enemies"), modifiers, true)
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("PERFECT EVADE (i-frames)!")
		return

	# 3) Apply damage & enter brief hitstun
	if is_dead:
		return
	if info.knockback_vector.length_squared() > 0.01:
		_last_damage_dir = info.knockback_vector.normalized()
	elif info.source != null and info.source is Node3D:
		_last_damage_dir = (global_position - (info.source as Node3D).global_position).normalized()
	if health != null:
		var dealt: float = health.apply_damage(info)
		if dealt > 0.0 and not is_dead:
			if GameFeelManager != null:
				GameFeelManager.trigger_hitstop(0.055, 0.05)
				GameFeelManager.request_screen_shake(0.24, 0.16)
				GameFeelManager.log_combat_event("Hunter hit for %.0f DMG" % dealt)
			state_machine.transition_to(&"Hitstun", {"info": info})


func _on_hitbox_hit_confirmed(target_entity: Node3D, info: DamageInfo) -> void:
	if GameFeelManager != null:
		GameFeelManager.trigger_hitstop(info.get_effective_hitstop_duration(), 0.04)
		GameFeelManager.request_screen_shake(info.screen_shake, 0.13)
		var tag: String = " [LAUNCHER]" if info.is_launcher else (" [AERIAL]" if info.is_aerial else (" [COUNTER]" if info.is_counter else ""))
		GameFeelManager.log_combat_event("Hit %s for %.0f%s" % [target_entity.name, info.amount, tag])


func _on_died() -> void:
	if is_dead:
		return
	is_dead = true
	set_combo_debug_label("DEAD (Ragdoll)")
	cancel_window_status = "FALLEN"
	if hitbox != null:
		hitbox.deactivate()
	if weapon_trail != null:
		weapon_trail.emitting = false
	if GameFeelManager != null:
		GameFeelManager.trigger_hitstop(0.08, 0.04)
		GameFeelManager.request_screen_shake(0.35, 0.24)
		GameFeelManager.log_combat_event("Hunter fell in Combat Gym -> Death & Ragdoll!")
	if death_ragdoll != null:
		death_ragdoll.trigger_death(_last_damage_dir, 6.2)
	var timer: SceneTreeTimer = get_tree().create_timer(1.55)
	await timer.timeout
	if is_inside_tree() and is_dead:
		is_dead = false
		if death_ragdoll != null:
			death_ragdoll.reset_ragdoll()
		if health != null:
			health.reset_health()
		velocity = Vector3.ZERO
		state_machine.transition_to(&"Idle")


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


func _setup_character_model() -> void:
	if character_model == null:
		return
	model_anim_player = character_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if model_anim_player == null:
		for child: Node in character_model.find_children("*", "AnimationPlayer", true, false):
			model_anim_player = child as AnimationPlayer
			break
	if model_anim_player != null:
		model_anim_player.playback_default_blend_time = 0.16
		for anim_name: StringName in [&"Idle", &"Idle_Unarmed", &"Run", &"Run_Unarmed", &"Jump", &"Jump_Unarmed", &"Slide", &"Slide_Unarmed"]:
			if model_anim_player.has_animation(anim_name):
				var anim: Animation = model_anim_player.get_animation(anim_name)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
		play_character_animation(&"Idle", 1.0, 0.18)

	var skel: Skeleton3D = character_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		for child: Node in character_model.find_children("*", "Skeleton3D", true, false):
			skel = child as Skeleton3D
			break
	_model_skeleton = skel
	if death_ragdoll != null:
		death_ragdoll.configure(self, visual_root, _model_skeleton, model_anim_player, GRAVITY)
	if skel != null and weapon_pivot != null and skel.find_bone("Hand.R") != -1:
		var attachment: BoneAttachment3D = BoneAttachment3D.new()
		attachment.name = "RightHandAttachment"
		attachment.bone_name = "Hand.R"
		skel.add_child(attachment)
		weapon_pivot.get_parent().remove_child(weapon_pivot)
		attachment.add_child(weapon_pivot)
		reset_weapon_pose()


func play_character_animation(anim_name: StringName, custom_speed: float = 1.0, blend_time: float = 0.14, force_restart: bool = false) -> void:
	_last_requested_anim = anim_name
	_last_requested_speed = custom_speed
	_last_requested_blend = blend_time
	if model_anim_player == null:
		return
	var resolved_anim: StringName = anim_name
	if current_weapon == null:
		var unarmed_candidate: StringName = StringName("%s_Unarmed" % String(anim_name))
		if model_anim_player.has_animation(unarmed_candidate):
			resolved_anim = unarmed_candidate
	if not model_anim_player.has_animation(resolved_anim):
		return
	var effective_blend: float = maxf(blend_time, 0.08)
	var target_name: String = String(resolved_anim)
	if model_anim_player.current_animation != target_name:
		# Never call stop() before play(): Godot crossfade blending requires the outgoing animation to remain active!
		model_anim_player.play(resolved_anim, effective_blend, custom_speed)
	elif force_restart:
		model_anim_player.seek(0.0, true)
		model_anim_player.play(resolved_anim, effective_blend, custom_speed)
	else:
		model_anim_player.speed_scale = custom_speed


func play_attack_animation_for_step(mode: StringName, step_index: int, total_duration: float) -> void:
	var target_anim: StringName = &"Attack_G1"
	match mode:
		&"ground":
			if step_index == 0:
				target_anim = &"Attack_G1"
			elif step_index == 1:
				target_anim = &"Attack_G2"
			else:
				target_anim = &"Attack_G3"
		&"launcher":
			target_anim = &"Attack_Launcher"
		&"stinger":
			target_anim = &"Attack_G1"
		&"air_slam":
			target_anim = &"Attack_A3"
		&"air":
			if step_index == 0:
				target_anim = &"Attack_A1"
			elif step_index == 1:
				target_anim = &"Attack_A2"
			else:
				target_anim = &"Attack_A3"
	var speed_scale: float = 1.0
	if model_anim_player != null and model_anim_player.has_animation(target_anim) and total_duration > 0.05:
		var anim_len: float = model_anim_player.get_animation(target_anim).length
		if anim_len > 0.01:
			speed_scale = clampf(anim_len / total_duration, 0.45, 2.8)
	play_character_animation(target_anim, speed_scale, 0.11, true)


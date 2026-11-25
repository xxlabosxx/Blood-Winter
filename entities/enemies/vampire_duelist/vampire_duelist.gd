class_name VampireDuelist
extends CharacterBody3D
## Lethal, tactical single-target Vampire opponent for Combat Gym validation.
## Supports patrolling, combat strafing, reactive sidestepping, clear red attack telegraphs,
## knockback, vertical launch, and aerial juggle suspension.

const GRAVITY: float = 24.5

@export var enemy_data: EnemyData = null

@onready var state_machine: StateMachine = $StateMachine
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hitbox: Hitbox3D = $VisualRoot/Hitbox3D
@onready var weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var weapon_trail: WeaponTrail3D = $VisualRoot/WeaponPivot/WeaponTrail3D
@onready var telegraph_ring: MeshInstance3D = $VisualRoot/TelegraphRing
@onready var telegraph_light: OmniLight3D = $VisualRoot/TelegraphLight
@onready var body_mesh: MeshInstance3D = $VisualRoot/BodyMesh

var target_player: Node3D = null
var attack_cooldown_remaining: float = 0.0
var evade_cooldown_remaining: float = 0.0
var is_juggled_in_air: bool = false
var is_telegraphing: bool = false

var _spawn_position: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _hit_flash_timer: float = 0.0
var _body_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("enemies")
	_spawn_position = global_position
	_rng.randomize()

	if enemy_data == null:
		enemy_data = load("res://data/enemies/crimson_duelist.tres") as EnemyData

	if health != null:
		health.configure_max_health(enemy_data.max_health, true)
		health.died.connect(_on_died)
	if hurtbox != null:
		hurtbox.owner_entity = self
		hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	if hitbox != null:
		hitbox.owner_entity = self

	_setup_materials()
	set_telegraph_active(false, 0.0)
	reset_weapon_pose()
	state_machine.initialize(self)


func _process(delta: float) -> void:
	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta)
	if evade_cooldown_remaining > 0.0:
		evade_cooldown_remaining = maxf(0.0, evade_cooldown_remaining - delta)

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _body_material != null:
			_body_material.emission_enabled = _hit_flash_timer > 0.0

	state_machine.update(delta)


func _physics_process(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
	state_machine.physics_update(delta)


func reset_for_gym() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	attack_cooldown_remaining = 0.4
	evade_cooldown_remaining = 0.0
	is_juggled_in_air = false
	set_telegraph_active(false, 0.0)
	if hitbox != null:
		hitbox.deactivate()
	if weapon_trail != null:
		weapon_trail.emitting = false
		weapon_trail.clear_trail()
	if health != null:
		health.reset_health()
	reset_weapon_pose()
	state_machine.transition_to(&"Patrol")


func get_distance_to_player() -> float:
	if target_player == null or not is_instance_valid(target_player):
		return 999.0
	return global_position.distance_to(target_player.global_position)


func get_direction_to_player_flat() -> Vector3:
	if target_player == null or not is_instance_valid(target_player):
		return get_facing_direction()
	var delta_vec: Vector3 = target_player.global_position - global_position
	delta_vec.y = 0.0
	if delta_vec.length_squared() < 0.0001:
		return get_facing_direction()
	return delta_vec.normalized()


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


func set_telegraph_active(active: bool, pulse: float = 1.0) -> void:
	is_telegraphing = active
	if telegraph_ring != null:
		telegraph_ring.visible = active
		if active:
			var s: float = lerpf(0.72, 1.28, clampf(pulse, 0.0, 1.0))
			telegraph_ring.scale = Vector3(s, s, s)
	if telegraph_light != null:
		telegraph_light.visible = active
		telegraph_light.light_energy = lerpf(2.0, 6.5, clampf(pulse, 0.0, 1.0))


func set_weapon_pose(yaw_deg: float, pitch_deg: float, roll_deg: float) -> void:
	if weapon_pivot != null:
		weapon_pivot.rotation_degrees = Vector3(pitch_deg, yaw_deg, roll_deg)


func reset_weapon_pose() -> void:
	set_weapon_pose(26.0, 12.0, 14.0)


func spawn_evade_ghost() -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var gx: Transform3D = global_transform
	gx.origin += Vector3(0.0, 0.95, 0.0)
	DodgeAfterimage.spawn(parent_node, gx, Color(0.85, 0.04, 0.14, 0.52), 1.9, 0.36, 0.25)


func roll_chance(probability: float) -> bool:
	return _rng.randf() <= probability


func randf_range_val(min_val: float, max_val: float) -> float:
	return _rng.randf_range(min_val, max_val)


func get_height_above_ground() -> float:
	return maxf(0.0, global_position.y)


func _on_hurtbox_hit_received(info: DamageInfo) -> void:
	if health == null:
		return
	var dealt: float = health.apply_damage(info)
	if dealt <= 0.0:
		return

	_hit_flash_timer = 0.11
	if _body_material != null:
		_body_material.emission_enabled = true
		_body_material.emission = Color(0.95, 0.12, 0.18, 1.0)
		_body_material.emission_energy_multiplier = 1.6

	state_machine.transition_to(&"Hitstun", {"info": info})


func _on_died() -> void:
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("%s slain! Auto-respawning in Combat Gym." % enemy_data.enemy_name)
	# Brief delay then respawn fresh for uninterrupted combo practice
	var timer: SceneTreeTimer = get_tree().create_timer(0.85)
	await timer.timeout
	if is_inside_tree():
		reset_for_gym()


func _setup_materials() -> void:
	if body_mesh != null:
		_body_material = StandardMaterial3D.new()
		_body_material.albedo_color = Color(0.07, 0.06, 0.09, 1.0)
		_body_material.roughness = 0.82
		_body_material.metallic = 0.12
		body_mesh.material_override = _body_material

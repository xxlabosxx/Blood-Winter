class_name VampireDuelist
extends CharacterBody3D
## Lethal, tactical single-target Vampire opponent for Combat Gym validation.
## Supports patrolling, combat strafing, reactive sidestepping, clear red attack telegraphs,
## knockback, vertical launch, and aerial juggle suspension.

const GRAVITY: float = 24.5

@export var enemy_data: EnemyData = null

@onready var state_machine: StateMachine = $StateMachine
@onready var health: HealthComponent = $HealthComponent
@onready var reaction_component: EnemyReactionComponent = $EnemyReactionComponent
@onready var death_ragdoll: DeathRagdollComponent = get_node_or_null("DeathRagdollComponent") as DeathRagdollComponent
@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hitbox: Hitbox3D = $VisualRoot/Hitbox3D
@onready var weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var weapon_trail: WeaponTrail3D = $VisualRoot/WeaponPivot/WeaponTrail3D
@onready var telegraph_ring: MeshInstance3D = $VisualRoot/TelegraphRing
@onready var telegraph_light: OmniLight3D = $VisualRoot/TelegraphLight
@onready var body_mesh: MeshInstance3D = $VisualRoot/BodyMesh
@onready var character_model: Node3D = get_node_or_null("VisualRoot/CharacterModel") as Node3D

var target_player: Node3D = null
var model_anim_player: AnimationPlayer = null
var _model_skeleton: Skeleton3D = null
var _active_anim_speed: float = 1.0
var attack_cooldown_remaining: float = 0.0
var evade_cooldown_remaining: float = 0.0
var is_juggled_in_air: bool = false
var is_telegraphing: bool = false
var is_dead: bool = false
var _last_damage_dir: Vector3 = Vector3.BACK

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
	if reaction_component != null:
		reaction_component.configure(self, visual_root, health, enemy_data, GRAVITY)
		reaction_component.poise_broken.connect(_on_poise_broken)
		reaction_component.ground_bounced.connect(_on_ground_bounced)
		reaction_component.air_breakaway_triggered.connect(_on_air_breakaway)
		reaction_component.reaction_state_changed.connect(_on_reaction_state_changed)

	_setup_materials()
	_setup_character_model()
	set_telegraph_active(false, 0.0)
	reset_weapon_pose()
	state_machine.initialize(self)


func _process(delta: float) -> void:
	var w_scale: float = get_world_time_scale()
	var scaled_delta: float = delta * w_scale

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(0.0, _hit_flash_timer - delta)
		if _body_material != null:
			_body_material.emission_enabled = _hit_flash_timer > 0.0

	if is_dead:
		return

	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - scaled_delta)
	if evade_cooldown_remaining > 0.0:
		evade_cooldown_remaining = maxf(0.0, evade_cooldown_remaining - scaled_delta)

	if reaction_component != null:
		reaction_component.time_slow_multiplier = w_scale
		reaction_component.tick_passive(scaled_delta)
		if model_anim_player != null:
			if reaction_component.is_in_hitstop():
				model_anim_player.speed_scale = 0.0
			else:
				model_anim_player.speed_scale = _active_anim_speed * w_scale

	state_machine.update(scaled_delta)


func _physics_process(delta: float) -> void:
	if target_player == null or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D
	var w_scale: float = get_world_time_scale()
	var scaled_delta: float = delta * w_scale
	if is_dead:
		if death_ragdoll != null:
			death_ragdoll.step_physics(scaled_delta)
		return
	if reaction_component != null:
		reaction_component.time_slow_multiplier = w_scale
	state_machine.physics_update(scaled_delta)


func get_world_time_scale() -> float:
	var tdm: Node = get_tree().root.get_node_or_null("TimeDilationManager")
	if tdm != null:
		return float(tdm.get("world_time_scale"))
	return 1.0


func is_in_witch_time_window() -> bool:
	if state_machine != null and state_machine.get_current_state_name() == &"Attack":
		var atk_state: Node = state_machine.get_node_or_null("Attack")
		if atk_state != null and atk_state.has_method("is_in_witch_time_window"):
			return bool(atk_state.call("is_in_witch_time_window"))
	return false


func reset_for_gym() -> void:
	is_dead = false
	if death_ragdoll != null:
		death_ragdoll.reset_ragdoll()
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
	if reaction_component != null:
		reaction_component.reset()
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
	var world_yaw: float = atan2(-flat.x, -flat.z)
	var local_target_yaw: float = wrapf(world_yaw - global_rotation.y, -PI, PI)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, local_target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


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


func set_weapon_pose(_yaw_deg: float, _pitch_deg: float, _roll_deg: float) -> void:
	# Kept for compatibility; skeletal animations drive Hand.R directly when BoneAttachment3D is active.
	if character_model == null and weapon_pivot != null:
		weapon_pivot.rotation_degrees = Vector3(_pitch_deg, _yaw_deg, _roll_deg)


func reset_weapon_pose() -> void:
	if weapon_pivot != null:
		weapon_pivot.position = Vector3(0.0, 0.09, 0.0)
		weapon_pivot.rotation_degrees = Vector3(106.06, -43.47, 90.44)


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
	if health == null or is_dead:
		return
	if info.impact_direction.length_squared() > 0.001:
		_last_damage_dir = info.impact_direction
	elif info.knockback_vector.length_squared() > 0.001:
		_last_damage_dir = info.knockback_vector.normalized()
	elif info.source is Node3D:
		var d: Vector3 = global_position - (info.source as Node3D).global_position
		d.y = 0.0
		if d.length_squared() > 0.001:
			_last_damage_dir = d.normalized()

	var dealt: float = health.apply_damage(info)
	if dealt <= 0.0:
		return

	_hit_flash_timer = 0.11
	if _body_material != null:
		_body_material.emission_enabled = true
		_body_material.emission = Color(0.95, 0.12, 0.18, 1.0)
		_body_material.emission_energy_multiplier = 1.6

	if reaction_component != null:
		var result: Dictionary = reaction_component.process_hit(info)
		if bool(result.get("breakaway", false)):
			state_machine.transition_to(&"Evade")
			return
		if bool(result.get("entered_reaction", false)):
			_play_reaction_animation_for_current_state(true)
			state_machine.transition_to(&"Hitstun", {"info": info})
	else:
		play_timed_vampire_animation(&"Hitstun_Ground", enemy_data.hitstun_duration, 0.03, true)
		state_machine.transition_to(&"Hitstun", {"info": info})


func _on_reaction_state_changed(_new_state: int, _old_state: int) -> void:
	_play_reaction_animation_for_current_state(false)


func _play_reaction_animation_for_current_state(force_restart: bool) -> void:
	if reaction_component == null:
		return
	match reaction_component.reaction_state:
		EnemyReactionComponent.ReactionState.GROUND_HITSTUN:
			play_timed_vampire_animation(&"Hitstun_Ground", maxf(0.18, reaction_component.hitstun_remaining), 0.10, true)
		EnemyReactionComponent.ReactionState.LAUNCHED:
			play_vampire_animation(&"Hitstun_Launched", 1.15, 0.11, true)
		EnemyReactionComponent.ReactionState.AIR_JUGGLE:
			play_vampire_animation(&"Hitstun_AirJuggle", 1.35, 0.09, true)
		EnemyReactionComponent.ReactionState.AIR_FALLING:
			play_vampire_animation(&"Hitstun_AirFall", 1.0, 0.14, force_restart)
		EnemyReactionComponent.ReactionState.KNOCKDOWN:
			play_timed_vampire_animation(&"Knockdown", maxf(0.25, reaction_component.knockdown_timer), 0.12, true)


func _on_poise_broken() -> void:
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("%s POISE BROKEN (DIZZY)!" % enemy_data.enemy_name)


func _on_ground_bounced(bounce_count: int) -> void:
	play_vampire_animation(&"Hitstun_AirJuggle", 1.25, 0.02, true)
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("%s GROUND BOUNCE #%d!" % [enemy_data.enemy_name, bounce_count])


func _on_air_breakaway() -> void:
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("%s AIR BREAKAWAY ESCAPE!" % enemy_data.enemy_name)


func _on_died() -> void:
	if is_dead:
		return
	is_dead = true
	set_telegraph_active(false, 0.0)
	if hitbox != null:
		hitbox.deactivate()
	if weapon_trail != null:
		weapon_trail.emitting = false
	if death_ragdoll != null:
		death_ragdoll.trigger_death(_last_damage_dir, 7.0)
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("%s slain! Auto-respawning in Combat Gym." % enemy_data.enemy_name)
	# Brief delay to showcase death animation + ragdoll collapse before respawn
	var timer: SceneTreeTimer = get_tree().create_timer(1.55)
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
		for anim_name: StringName in [&"Idle", &"Patrol_Walk", &"Strafe", &"Dizzy", &"Hitstun_AirFall"]:
			if model_anim_player.has_animation(anim_name):
				var anim: Animation = model_anim_player.get_animation(anim_name)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
		play_vampire_animation(&"Idle", 1.0, 0.18)

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


func play_vampire_animation(anim_name: StringName, custom_speed: float = 1.0, blend_time: float = 0.14, force_restart: bool = false) -> void:
	if model_anim_player == null:
		return
	if not model_anim_player.has_animation(anim_name):
		return
	_active_anim_speed = custom_speed
	var effective_speed: float = custom_speed * get_world_time_scale()
	if reaction_component != null and reaction_component.is_in_hitstop():
		effective_speed = 0.0
	var effective_blend: float = maxf(blend_time, 0.08)
	var target_name: String = String(anim_name)
	if model_anim_player.current_animation != target_name:
		# Never call stop() before play() so Godot crossfades smoothly from the previous pose!
		model_anim_player.play(anim_name, effective_blend, effective_speed)
	elif force_restart:
		model_anim_player.seek(0.0, true)
		model_anim_player.play(anim_name, effective_blend, effective_speed)
	else:
		model_anim_player.speed_scale = effective_speed


func play_timed_vampire_animation(anim_name: StringName, target_duration: float, blend_time: float = 0.05, force_restart: bool = true) -> void:
	var speed_scale: float = 1.0
	if model_anim_player != null and model_anim_player.has_animation(anim_name) and target_duration > 0.04:
		var anim_len: float = model_anim_player.get_animation(anim_name).length
		if anim_len > 0.01:
			speed_scale = clampf(anim_len / target_duration, 0.35, 3.5)
	play_vampire_animation(anim_name, speed_scale, blend_time, force_restart)

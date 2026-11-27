class_name EnemyReactionComponent
extends Node
## Modular, scalable enemy combat reaction & air-juggle physics component
## following Bayonetta 2 / PlatinumGames Character Action architecture:
## - 6-state Kinematic Reaction FSM (COMBAT_ACTIVE, GROUND_HITSTUN, LAUNCHED, AIR_JUGGLE, AIR_FALLING, KNOCKDOWN)
## - Poise (Super Armor) & DIZZY state before heavy Launch
## - Hitstop Freeze Frames pausing gravity & velocity completely
## - Vertical Velocity Stall + Progressive Gravity Scaling (1.05^N) & Hitstun Decay (0.95^N)
## - Tethering / Hit-Magnetism matching attacker forward velocity
## - Ground Bounce -> Air Juggle or Grounded Recovery (invulnerable)
## - Anti-infinite Air Breakaway / Escape roll for non-dizzy enemies
## - Directional procedural additive hit reactions (spring-damper on visual_root)

enum ReactionState {
	COMBAT_ACTIVE,
	GROUND_HITSTUN,
	LAUNCHED,
	AIR_JUGGLE,
	AIR_FALLING,
	KNOCKDOWN,
}

signal reaction_state_changed(new_state: ReactionState, old_state: ReactionState)
signal poise_broken()
signal ground_bounced(bounce_count: int)
signal air_breakaway_triggered()
signal hit_reaction_applied(local_impact_dir: Vector3, intensity: float)

var owner_body: CharacterBody3D = null
var visual_root: Node3D = null
var health: HealthComponent = null
var enemy_data: EnemyData = null
var base_gravity: float = 24.5

var reaction_state: ReactionState = ReactionState.COMBAT_ACTIVE
var current_poise: float = 65.0
var is_dizzy: bool = false
var dizzy_timer: float = 0.0
var time_since_last_hit: float = 0.0
## Hook for Witch Time / temporal slowdown (< 0.95 bypasses Poise & Air Breakaway).
var time_slow_multiplier: float = 1.0

var combo_hit_count: int = 0
var ground_bounces_used: int = 0
var hitstun_remaining: float = 0.0
var knockdown_timer: float = 0.0
var is_grounded_recovery: bool = false
var hitstop_remaining: float = 0.0
var pending_force_state: StringName = &""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _additive_rot_deg: Vector3 = Vector3.ZERO
var _additive_rot_vel: Vector3 = Vector3.ZERO
var _additive_offset: Vector3 = Vector3.ZERO
var _additive_offset_vel: Vector3 = Vector3.ZERO
var _last_step_elapsed: float = 0.0


func configure(
	body: CharacterBody3D,
	vis_root: Node3D,
	health_comp: HealthComponent,
	data: EnemyData,
	gravity_val: float = 24.5
) -> void:
	owner_body = body
	visual_root = vis_root
	health = health_comp
	enemy_data = data
	base_gravity = gravity_val
	_rng.randomize()
	reset()


func reset() -> void:
	var prev: ReactionState = reaction_state
	reaction_state = ReactionState.COMBAT_ACTIVE
	current_poise = enemy_data.max_poise if enemy_data != null else 65.0
	is_dizzy = false
	dizzy_timer = 0.0
	time_since_last_hit = 0.0
	combo_hit_count = 0
	ground_bounces_used = 0
	hitstun_remaining = 0.0
	knockdown_timer = 0.0
	is_grounded_recovery = false
	hitstop_remaining = 0.0
	pending_force_state = &""
	_last_step_elapsed = 0.0
	_additive_rot_deg = Vector3.ZERO
	_additive_rot_vel = Vector3.ZERO
	_additive_offset = Vector3.ZERO
	_additive_offset_vel = Vector3.ZERO
	if health != null:
		health.is_invulnerable = false
	if visual_root != null:
		visual_root.rotation.x = 0.0
		visual_root.rotation.z = 0.0
		visual_root.position = Vector3.ZERO
	if prev != reaction_state:
		reaction_state_changed.emit(reaction_state, prev)


func get_state_name() -> String:
	match reaction_state:
		ReactionState.COMBAT_ACTIVE:
			return "DIZZY" if is_dizzy else "COMBAT_ACTIVE"
		ReactionState.GROUND_HITSTUN:
			return "GROUND_HITSTUN"
		ReactionState.LAUNCHED:
			return "LAUNCHED (RISING)"
		ReactionState.AIR_JUGGLE:
			return "AIR_JUGGLE (N=%d)" % combo_hit_count
		ReactionState.AIR_FALLING:
			return "AIR_FALLING"
		ReactionState.KNOCKDOWN:
			return "GROUNDED_RECOVERY" if is_grounded_recovery else "KNOCKDOWN"
	return "UNKNOWN"


func is_in_reaction() -> bool:
	return reaction_state != ReactionState.COMBAT_ACTIVE


func is_in_hitstop() -> bool:
	return hitstop_remaining > 0.0


func get_current_hitstun_multiplier() -> float:
	var decay: float = enemy_data.hitstun_decay_factor if enemy_data != null else 0.95
	return pow(clampf(decay, 0.5, 1.0), float(combo_hit_count))


func get_current_juggle_gravity_scale() -> float:
	var base_scale: float = enemy_data.gravity_scale_when_juggled if enemy_data != null else 0.22
	var growth: float = enemy_data.gravity_scaling_factor if enemy_data != null else 1.05
	return base_scale * pow(maxf(1.0, growth), float(combo_hit_count))


func tick_passive(delta: float) -> void:
	time_since_last_hit += delta

	if is_dizzy:
		dizzy_timer -= delta
		if dizzy_timer <= 0.0:
			is_dizzy = false
			current_poise = enemy_data.max_poise if enemy_data != null else 65.0

	if reaction_state == ReactionState.COMBAT_ACTIVE and not is_dizzy and enemy_data != null:
		if time_since_last_hit >= enemy_data.poise_regen_delay and current_poise < enemy_data.max_poise:
			current_poise = minf(enemy_data.max_poise, current_poise + enemy_data.poise_regen_rate * delta)

	_update_procedural_hit_reaction(delta)


func process_hit(info: DamageInfo, allow_breakaway_roll: bool = true) -> Dictionary:
	if owner_body == null or enemy_data == null or info == null:
		return {"entered_reaction": false, "poise_broken": false, "breakaway": false, "reaction_state": reaction_state}

	time_since_last_hit = 0.0
	_last_step_elapsed = 0.0

	# 1) Hitstop freeze frames (3-6 frames standard at 60 FPS)
	hitstop_remaining = maxf(hitstop_remaining, info.get_effective_hitstop_duration())

	# 2) Directional additive procedural hit reaction (always runs immediately without restarting animations)
	_apply_directional_impulse(info)

	# 3) Poise / Super Armor damage
	var did_break_poise: bool = false
	if current_poise > 0.0:
		current_poise = maxf(0.0, current_poise - info.stagger_power)
		if current_poise <= 0.0:
			is_dizzy = true
			dizzy_timer = enemy_data.dizzy_duration
			did_break_poise = true
			poise_broken.emit()

	# 4) Bayonetta 2 Rule #1: Super Armor / Poise Resistance in COMBAT_ACTIVE
	var has_super_armor: bool = (
		reaction_state == ReactionState.COMBAT_ACTIVE
		and current_poise > 0.0
		and not is_dizzy
		and time_slow_multiplier >= 0.95
		and not info.is_counter
	)
	if has_super_armor:
		return {
			"entered_reaction": false,
			"poise_broken": false,
			"breakaway": false,
			"reaction_state": reaction_state,
		}

	# 5) Bayonetta 2 Rule #2: Anti-infinite Air Breakaway / Escape for non-dizzy airborne enemies
	var is_air_combo_state: bool = (reaction_state == ReactionState.LAUNCHED or reaction_state == ReactionState.AIR_JUGGLE)
	if (
		is_air_combo_state
		and not is_dizzy
		and time_slow_multiplier >= 0.95
		and combo_hit_count >= enemy_data.air_breakaway_hit_threshold
		and allow_breakaway_roll
	):
		if _rng.randf() <= enemy_data.air_breakaway_chance:
			combo_hit_count = 0
			ground_bounces_used = 0
			pending_force_state = &""
			current_poise = enemy_data.max_poise * 0.65
			hitstop_remaining = 0.0
			_set_reaction_state(ReactionState.COMBAT_ACTIVE)
			air_breakaway_triggered.emit()
			return {
				"entered_reaction": false,
				"poise_broken": did_break_poise,
				"breakaway": true,
				"reaction_state": reaction_state,
			}

	# 6) Resolve Kinematic Physics & State Transition
	var launch_vec: Vector3 = info.get_resolved_launch_vector()
	var kb_scale: float = 1.0 - clampf(enemy_data.knockback_resistance, 0.0, 0.85)
	var base_hitstun: float = info.hitstun_duration if info.hitstun_duration > 0.0 else enemy_data.hitstun_duration
	var horiz_kb: Vector3 = Vector3(launch_vec.x, 0.0, launch_vec.z) * kb_scale
	var is_currently_airborne: bool = (
		not owner_body.is_on_floor()
		or reaction_state == ReactionState.LAUNCHED
		or reaction_state == ReactionState.AIR_JUGGLE
		or reaction_state == ReactionState.AIR_FALLING
	)

	# Case A: Forced Spike / Ground Bounce Slam
	if info.force_state == DamageInfo.FORCE_STATE_GROUND_BOUNCE or launch_vec.y < -4.0:
		owner_body.velocity.x = horiz_kb.x
		owner_body.velocity.z = horiz_kb.z
		owner_body.velocity.y = minf(launch_vec.y, -12.0)
		pending_force_state = DamageInfo.FORCE_STATE_GROUND_BOUNCE
		hitstun_remaining = maxf(0.25, base_hitstun * get_current_hitstun_multiplier())
		_set_reaction_state(ReactionState.AIR_FALLING)

	# Case B: Launcher (Force.y > 0 / is_launcher)
	elif info.is_launcher or launch_vec.y > 4.0:
		if is_currently_airborne:
			combo_hit_count += 1
		else:
			combo_hit_count = 0
			ground_bounces_used = 0
		owner_body.velocity.x = horiz_kb.x
		owner_body.velocity.z = horiz_kb.z
		owner_body.velocity.y = launch_vec.y
		hitstun_remaining = maxf(0.28, base_hitstun * get_current_hitstun_multiplier())
		_set_reaction_state(ReactionState.LAUNCHED)

	# Case C: Aerial Juggle Follow-up (Vertical Velocity Stall + Tethering + Progressive Decay)
	elif is_currently_airborne:
		combo_hit_count += 1
		# Vertical Velocity Stall: reset V.y = 0 then apply micro upward hover impulse
		owner_body.velocity.y = 0.0
		var decay_mult: float = get_current_hitstun_multiplier()
		var hover: float = maxf(1.0, enemy_data.air_juggle_hover_impulse * decay_mult)
		if launch_vec.y > 0.0:
			hover = maxf(hover, launch_vec.y * decay_mult)
		owner_body.velocity.y = hover

		# Tethering / Hit-Magnetism: align horizontal knockback with attacker's forward displacement
		if info.attacker_forward_velocity.length_squared() > 0.01:
			var tether: float = clampf(enemy_data.air_tether_strength, 0.0, 1.0)
			var tethered_horiz: Vector3 = horiz_kb.lerp(info.attacker_forward_velocity, tether)
			owner_body.velocity.x = tethered_horiz.x
			owner_body.velocity.z = tethered_horiz.z
		else:
			owner_body.velocity.x = horiz_kb.x
			owner_body.velocity.z = horiz_kb.z

		hitstun_remaining = maxf(0.14, base_hitstun * decay_mult)
		_set_reaction_state(ReactionState.AIR_JUGGLE)

	# Case D: Grounded Hitstun or Forced Knockdown / Spin Blowback
	else:
		combo_hit_count = 0
		ground_bounces_used = 0
		owner_body.velocity.x = horiz_kb.x
		owner_body.velocity.z = horiz_kb.z
		owner_body.velocity.y = maxf(0.0, launch_vec.y)
		if info.force_state == DamageInfo.FORCE_STATE_KNOCKDOWN:
			is_grounded_recovery = true
			knockdown_timer = enemy_data.knockdown_recovery_duration
			if health != null:
				health.is_invulnerable = true
			_set_reaction_state(ReactionState.KNOCKDOWN)
		else:
			hitstun_remaining = base_hitstun
			_set_reaction_state(ReactionState.GROUND_HITSTUN)

	return {
		"entered_reaction": true,
		"poise_broken": did_break_poise,
		"breakaway": false,
		"reaction_state": reaction_state,
	}


func step_physics(delta: float) -> void:
	if owner_body == null or enemy_data == null:
		return

	# Hitstop Freeze Frames: pause gravity & velocity completely (V = 0 displacement)
	if hitstop_remaining > 0.0:
		var wall_delta: float = delta / maxf(Engine.time_scale, 0.01)
		hitstop_remaining = maxf(0.0, hitstop_remaining - wall_delta)
		if visual_root != null:
			var jitter: float = 0.035 * clampf(hitstop_remaining * 20.0, 0.2, 1.0)
			visual_root.position.x = _rng.randf_range(-jitter, jitter)
			visual_root.position.z = _rng.randf_range(-jitter, jitter)
		if hitstop_remaining <= 0.0 and visual_root != null:
			visual_root.position.x = _additive_offset.x
			visual_root.position.z = _additive_offset.z
		return

	_last_step_elapsed += delta
	var pre_move_vy: float = owner_body.velocity.y

	match reaction_state:
		ReactionState.GROUND_HITSTUN:
			owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, 18.0 * delta)
			owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, 18.0 * delta)
			if owner_body.is_on_floor():
				owner_body.velocity.y = -1.0
			else:
				owner_body.velocity.y -= base_gravity * delta
			owner_body.move_and_slide()
			hitstun_remaining -= delta
			if hitstun_remaining <= 0.0:
				_set_reaction_state(ReactionState.COMBAT_ACTIVE)

		ReactionState.LAUNCHED:
			owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, 4.5 * delta)
			owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, 4.5 * delta)
			owner_body.velocity.y -= base_gravity * 0.85 * delta
			owner_body.move_and_slide()
			hitstun_remaining -= delta
			if owner_body.is_on_floor() and _last_step_elapsed > 0.08:
				_handle_ground_impact(pre_move_vy)
			elif owner_body.velocity.y <= 1.2:
				if hitstun_remaining > 0.0:
					_set_reaction_state(ReactionState.AIR_JUGGLE)
				else:
					_set_reaction_state(ReactionState.AIR_FALLING)

		ReactionState.AIR_JUGGLE:
			owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, 5.2 * delta)
			owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, 5.2 * delta)
			var juggle_g_scale: float = get_current_juggle_gravity_scale()
			owner_body.velocity.y -= base_gravity * juggle_g_scale * delta
			owner_body.move_and_slide()
			hitstun_remaining -= delta
			if owner_body.is_on_floor() and _last_step_elapsed > 0.06:
				_handle_ground_impact(pre_move_vy)
			elif hitstun_remaining <= 0.0:
				_set_reaction_state(ReactionState.AIR_FALLING)

		ReactionState.AIR_FALLING:
			owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, 4.0 * delta)
			owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, 4.0 * delta)
			owner_body.velocity.y -= base_gravity * delta
			owner_body.move_and_slide()
			if owner_body.is_on_floor():
				_handle_ground_impact(pre_move_vy)

		ReactionState.KNOCKDOWN:
			owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, 22.0 * delta)
			owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, 22.0 * delta)
			owner_body.velocity.y = -1.0 if owner_body.is_on_floor() else owner_body.velocity.y - base_gravity * delta
			owner_body.move_and_slide()
			knockdown_timer -= delta
			if knockdown_timer <= 0.0:
				is_grounded_recovery = false
				if health != null:
					health.is_invulnerable = false
				combo_hit_count = 0
				ground_bounces_used = 0
				pending_force_state = &""
				current_poise = enemy_data.max_poise
				is_dizzy = false
				_set_reaction_state(ReactionState.COMBAT_ACTIVE)

		ReactionState.COMBAT_ACTIVE:
			pass


func _handle_ground_impact(pre_impact_vy: float) -> void:
	var wants_bounce: bool = (pending_force_state == DamageInfo.FORCE_STATE_GROUND_BOUNCE or pre_impact_vy < -9.0)
	if wants_bounce and ground_bounces_used < enemy_data.max_ground_bounces:
		ground_bounces_used += 1
		pending_force_state = &""
		owner_body.velocity.y = enemy_data.ground_bounce_velocity
		hitstun_remaining = maxf(0.38, enemy_data.hitstun_duration * get_current_hitstun_multiplier())
		_set_reaction_state(ReactionState.AIR_JUGGLE)
		ground_bounced.emit(ground_bounces_used)
		return

	pending_force_state = &""
	is_grounded_recovery = true
	knockdown_timer = enemy_data.knockdown_recovery_duration
	if health != null:
		health.is_invulnerable = true
	_set_reaction_state(ReactionState.KNOCKDOWN)


func _set_reaction_state(next_state: ReactionState) -> void:
	if next_state == reaction_state:
		return
	var old_state: ReactionState = reaction_state
	reaction_state = next_state
	_last_step_elapsed = 0.0
	reaction_state_changed.emit(next_state, old_state)


func _apply_directional_impulse(info: DamageInfo) -> void:
	var world_dir: Vector3 = info.impact_direction
	if world_dir.length_squared() < 0.001:
		world_dir = info.knockback_vector
	if world_dir.length_squared() < 0.001:
		world_dir = Vector3.FORWARD
	else:
		world_dir = world_dir.normalized()

	var local_dir: Vector3 = world_dir
	if visual_root != null:
		local_dir = (visual_root.global_transform.basis.inverse() * world_dir).normalized()

	# Tilt torso/visuals away from impact direction (left/right roll + front/back pitch)
	var intensity: float = clampf(info.amount / 25.0, 0.75, 1.8)
	_additive_rot_vel.x += local_dir.z * 260.0 * intensity - local_dir.y * 140.0 * intensity
	_additive_rot_vel.z += -local_dir.x * 280.0 * intensity
	_additive_offset_vel += local_dir * 1.4 * intensity
	hit_reaction_applied.emit(local_dir, intensity)


func _update_procedural_hit_reaction(delta: float) -> void:
	if visual_root == null:
		return
	# Critically damped spring returning additive hit pose to neutral without interrupting FSM animations
	var stiffness: float = 190.0
	var damping: float = 18.0
	var rot_accel: Vector3 = (-stiffness * _additive_rot_deg) - (damping * _additive_rot_vel)
	_additive_rot_vel += rot_accel * delta
	_additive_rot_deg += _additive_rot_vel * delta
	_additive_rot_deg = _additive_rot_deg.clamp(Vector3(-28.0, 0.0, -28.0), Vector3(28.0, 0.0, 28.0))

	var off_accel: Vector3 = (-stiffness * _additive_offset) - (damping * _additive_offset_vel)
	_additive_offset_vel += off_accel * delta
	_additive_offset += _additive_offset_vel * delta
	_additive_offset = _additive_offset.clamp(Vector3(-0.18, -0.12, -0.18), Vector3(0.18, 0.12, 0.18))

	# Preserve visual_root.rotation.y owned by face_direction(); apply pitch/roll additively
	visual_root.rotation.x = deg_to_rad(_additive_rot_deg.x)
	visual_root.rotation.z = deg_to_rad(_additive_rot_deg.z)
	if hitstop_remaining <= 0.0:
		visual_root.position = _additive_offset

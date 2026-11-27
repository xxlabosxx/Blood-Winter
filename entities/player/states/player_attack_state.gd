class_name PlayerAttackState
extends PlayerState
## Bayonetta 2 / PlatinumGames-inspired melee combo state supporting:
## - 4-phase frame data (Startup -> Active + Hit-Confirm -> Recovery + Buffer -> Cancel Windows)
## - Anytime Dodge Cancel (configurable via ComboStepData.allow_anytime_dodge_cancel)
## - Soft Lock-On & Attack Magnetism (gap closing without passing through enemy capsule)
## - Air Attack Hover (V.y = 0 + 10%-20% gravity) & Automatic Jump Follow-up on Launcher
## - Directional Command Attacks: Launcher, Stinger (Gap Closer), and Air Slam (Ground Bounce)

var _mode: StringName = &"ground"
var _step_index: int = 0
var _step: ComboStepData = null
var _elapsed: float = 0.0
var _speed_mult: float = 1.0
var _hitbox_started: bool = false
var _hitbox_finished: bool = false
var _hit_confirmed_this_step: bool = false
var _lift_applied: bool = false
var _forward_dir: Vector3 = Vector3.FORWARD
var _combat_target: Node3D = null


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_mode = data.get("mode", &"ground") as StringName
	_step_index = int(data.get("index", 0))
	_elapsed = 0.0
	_hitbox_started = false
	_hitbox_finished = false
	_hit_confirmed_this_step = false
	_lift_applied = false

	var weapon: WeaponData = player.current_weapon
	if weapon == null:
		request_transition(&"Idle")
		return

	if player.combat_comp != null:
		player.combat_comp.on_attack_performed()

	_speed_mult = maxf(0.2, player.get_effective_attack_speed(weapon.attack_speed))
	_step = _resolve_step(weapon, _mode, _step_index)
	if _step == null:
		request_transition(&"Idle" if player.is_on_floor() else &"Air")
		return

	if player.hitbox != null and not player.hitbox.hit_confirmed.is_connected(_on_step_hit_confirmed):
		player.hitbox.hit_confirmed.connect(_on_step_hit_confirmed)

	# Soft Lock-On / Hard Lock-On target resolution & instant frame-1 facing
	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	_combat_target = player.get_active_combat_target(move_dir)
	if _combat_target != null and is_instance_valid(_combat_target):
		var to_t: Vector3 = _combat_target.global_position - player.global_position
		to_t.y = 0.0
		if to_t.length_squared() > 0.01:
			player.visual_root.rotation.y = wrapf(atan2(-to_t.x, -to_t.z) - player.global_rotation.y, -PI, PI)
	else:
		player.face_locked_or_input_immediately()

	_forward_dir = player.get_facing_direction()

	# Forward momentum + Attack Magnetism (assisted gap-closing without clipping capsule)
	var preserve_speed: float = float(data.get("preserve_speed", 0.0))
	var impulse: float = maxf(_step.forward_impulse, preserve_speed)
	var mag_vel: Vector3 = Vector3.ZERO
	if player.combat_comp != null and _combat_target != null and _mode != &"stinger":
		mag_vel = player.combat_comp.compute_attack_magnetism_velocity(player.global_position, _combat_target)

	if mag_vel.length_squared() > impulse * impulse:
		player.velocity.x = mag_vel.x
		player.velocity.z = mag_vel.z
	else:
		player.velocity.x = _forward_dir.x * impulse
		player.velocity.z = _forward_dir.z * impulse

	# Bayonetta 2 Air Attack Hover / Air Slam Dive
	if _mode == &"air_slam" or _step.is_air_slam:
		player.velocity.y = minf(-16.0, _step.attacker_air_lift)
		player.air_combo_used = true
	elif _step.is_aerial:
		# Reset V.y = 0 then apply micro upward hover impulse to match enemy AIR_JUGGLE height
		player.velocity.y = 0.0
		var hover: float = player.combat_comp.air_attack_hover_impulse if player.combat_comp != null else 2.6
		player.velocity.y = maxf(hover, _step.attacker_air_lift * 0.65)
		if _step_index >= weapon.air_combo.size() - 1:
			player.air_combo_used = true

	player.set_combo_debug_label(_step.step_name)
	player.cancel_window_status = "Startup"
	player.reset_weapon_pose()
	player.play_attack_animation_for_step(_mode, _step_index, _step.get_total_duration(_speed_mult))


func exit() -> void:
	if player != null:
		if player.hitbox != null:
			if player.hitbox.hit_confirmed.is_connected(_on_step_hit_confirmed):
				player.hitbox.hit_confirmed.disconnect(_on_step_hit_confirmed)
			player.hitbox.deactivate()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false
		player.cancel_window_status = "-"


func physics_update(delta: float) -> void:
	if _step == null:
		request_transition(&"Idle")
		return

	_elapsed += delta
	if _combat_target != null and is_instance_valid(_combat_target):
		player.face_direction(_combat_target.global_position - player.global_position, 14.0, delta)
	else:
		player.face_locked_target(12.0, delta)

	var startup: float = _step.get_scaled_startup(_speed_mult)
	var active: float = _step.get_scaled_active(_speed_mult)
	var total: float = _step.get_total_duration(_speed_mult)

	# 1) Animation Canceling checks (Dodge Cancel has top priority on ANY frame when enabled)
	var cancel_tags: PackedStringArray = PackedStringArray()
	if _step.can_cancel_with_dodge(_elapsed, _speed_mult):
		cancel_tags.append("DODGE")
		if player.can_dodge() and player.consume_buffered_action(&"dodge"):
			player.last_cancel_note = "Cancelled %s -> DODGE" % _step.step_name
			if GameFeelManager != null:
				GameFeelManager.log_combat_event(player.last_cancel_note)
			request_transition(&"Dodge")
			return

	if _step.can_cancel_with_skill(_elapsed, _speed_mult):
		cancel_tags.append("SKILL")
		if player.can_use_skill() and player.consume_buffered_action(&"class_skill"):
			player.last_cancel_note = "Cancelled %s -> SKILL" % _step.step_name
			if GameFeelManager != null:
				GameFeelManager.log_combat_event(player.last_cancel_note)
			request_transition(&"Skill")
			return

	var can_jump_here: bool = player.combat_comp.can_jump(player.is_on_floor()) if player.combat_comp != null else player.is_on_floor()
	if _step.can_cancel_with_jump(_elapsed, _speed_mult) and can_jump_here:
		cancel_tags.append("JUMP")
		if player.consume_buffered_action(&"jump"):
			if player.combat_comp != null:
				player.combat_comp.consume_jump(player.is_on_floor())
			player.last_cancel_note = "Cancelled %s -> JUMP" % _step.step_name
			if GameFeelManager != null:
				GameFeelManager.log_combat_event(player.last_cancel_note)
			player.velocity.y = player.class_data.jump_velocity
			request_transition(&"Air")
			return

	if cancel_tags.is_empty():
		player.cancel_window_status = "Active" if _hitbox_started and not _hitbox_finished else "Startup"
	else:
		player.cancel_window_status = "CANCEL: " + "/".join(cancel_tags)

	# 2) Combo Chaining (opens at combo_window_start OR immediately on Hit-Confirm during Active/Recovery)
	var chain_open: bool = _step.can_chain_at(_elapsed, _speed_mult) or (_hit_confirmed_this_step and _elapsed >= startup)
	if chain_open:
		var weapon: WeaponData = player.current_weapon
		var move_dir: Vector3 = player.get_camera_relative_move_direction()
		if _mode == &"ground" or _mode == &"stinger":
			if player.consume_buffered_action(&"attack_launcher") and weapon.launcher_step != null:
				request_transition(&"Attack", {"mode": &"launcher", "index": 0})
				return
			if player.consume_buffered_action(&"attack_light"):
				var cmd: StringName = &"ground"
				if player.combat_comp != null:
					cmd = player.combat_comp.resolve_attack_command(true, _combat_target, move_dir, _forward_dir, false, player.get_horizontal_speed(), player.get_effective_move_speed(), player.global_position)
				if cmd == &"launcher" and weapon.launcher_step != null:
					request_transition(&"Attack", {"mode": &"launcher", "index": 0})
					return
				if (_step_index + 1) < weapon.ground_combo.size() and _mode == &"ground":
					request_transition(&"Attack", {"mode": &"ground", "index": _step_index + 1})
					return
				elif _mode == &"stinger" and not weapon.ground_combo.is_empty():
					request_transition(&"Attack", {"mode": &"ground", "index": 1 if weapon.ground_combo.size() > 1 else 0})
					return
		elif _mode == &"launcher":
			if player.consume_buffered_action(&"attack_light") and not weapon.air_combo.is_empty():
				request_transition(&"Attack", {"mode": &"air", "index": 0})
				return
		elif _mode == &"air":
			if player.consume_buffered_action(&"attack_launcher") and weapon.air_slam_step != null:
				request_transition(&"Attack", {"mode": &"air_slam", "index": 0})
				return
			if player.consume_buffered_action(&"attack_light"):
				var air_cmd: StringName = &"air"
				if player.combat_comp != null:
					air_cmd = player.combat_comp.resolve_attack_command(false, _combat_target, move_dir, _forward_dir, false, player.get_horizontal_speed(), player.get_effective_move_speed(), player.global_position)
				if air_cmd == &"air_slam" and weapon.air_slam_step != null:
					request_transition(&"Attack", {"mode": &"air_slam", "index": 0})
					return
				if (_step_index + 1) < weapon.air_combo.size():
					request_transition(&"Attack", {"mode": &"air", "index": _step_index + 1})
					return

	# 3) Hitbox Activation, Weapon Trail, and Launcher Automatic Jump Follow-up
	if not _hitbox_started and _elapsed >= startup:
		_hitbox_started = true
		_activate_step_hitbox()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = true
		if _step.is_launcher and not _lift_applied:
			_lift_applied = true
			var hold_follow_up: bool = Input.is_action_pressed(&"attack_launcher") or Input.is_action_pressed(&"attack_light")
			if hold_follow_up and _step.attacker_air_lift > 0.0:
				if player.combat_comp != null:
					player.combat_comp.consume_jump(true)
				player.velocity.y = _step.attacker_air_lift
				if GameFeelManager != null:
					GameFeelManager.log_combat_event("LAUNCHER FOLLOW-UP! (Rising with target)")

	if _hitbox_started and not _hitbox_finished and _elapsed >= (startup + active):
		_hitbox_finished = true
		if player.hitbox != null:
			player.hitbox.deactivate()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false

	# 4) Procedural Weapon Swing Arc (fallback only when no skeletal CharacterModel is attached)
	if player.character_model == null:
		var swing_t: float = clampf((_elapsed - startup * 0.5) / maxf(0.05, active + startup * 0.7), 0.0, 1.0)
		var eased_t: float = 1.0 - pow(1.0 - swing_t, 3.0)
		var yaw_deg: float = lerpf(_step.swing_start_angle_deg, _step.swing_end_angle_deg, eased_t)
		var pitch_deg: float = lerpf(-32.0, 44.0, eased_t) if _step.is_launcher else lerpf(12.0, -8.0, eased_t)
		player.set_weapon_swing_pose(yaw_deg, pitch_deg, _step.swing_tilt_deg)

	# 5) Movement Friction, Magnetism Capsule Clamp, & Bayonetta Air Attack Hover Gravity
	var horiz_drag: float = 10.0 if _mode == &"stinger" else 18.0
	player.velocity.x = move_toward(player.velocity.x, 0.0, horiz_drag * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, horiz_drag * delta)

	# Prevent passing through locked/soft-locked enemy capsule during magnetism pull
	if _combat_target != null and is_instance_valid(_combat_target):
		var dist_flat: float = Vector2(
			_combat_target.global_position.x - player.global_position.x,
			_combat_target.global_position.z - player.global_position.z
		).length()
		var min_cap: float = player.combat_comp.magnetism_min_dist if player.combat_comp != null else 1.25
		if dist_flat <= min_cap and _mode != &"stinger":
			player.velocity.x *= 0.25
			player.velocity.z *= 0.25

	if _mode == &"air_slam" or _step.is_air_slam:
		player.velocity.y -= Player.GRAVITY * 1.45 * delta
	elif _step.is_aerial:
		# Bayonetta 2 Air Attack Hover: 10%-20% of normal gravity during air combos
		var hover_scale: float = player.combat_comp.air_attack_gravity_scale if player.combat_comp != null else 0.15
		player.velocity.y -= Player.GRAVITY * hover_scale * delta
	elif _step.is_launcher and _lift_applied and not player.is_on_floor():
		player.velocity.y -= Player.GRAVITY * 0.55 * delta
	else:
		if not player.is_on_floor():
			player.velocity.y -= Player.GRAVITY * delta
		else:
			player.velocity.y = -1.0

	player.move_and_slide()

	# Landed during aerial plunge / air slam
	if _step.is_aerial and _elapsed > (startup + active) and player.is_on_floor():
		request_transition(&"Idle")
		return

	# 6) Step Completion
	if _elapsed >= total:
		if not player.is_on_floor():
			request_transition(&"Air")
		elif player.get_camera_relative_move_direction().length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")


func _on_step_hit_confirmed(_target_entity: Node3D, _info: DamageInfo) -> void:
	_hit_confirmed_this_step = true


func _resolve_step(weapon: WeaponData, mode: StringName, index: int) -> ComboStepData:
	match mode:
		&"ground":
			return weapon.get_ground_step(index)
		&"launcher":
			return weapon.launcher_step
		&"stinger":
			return weapon.stinger_step if weapon.stinger_step != null else weapon.get_ground_step(0)
		&"air":
			return weapon.get_air_step(index)
		&"air_slam":
			if weapon.air_slam_step != null:
				return weapon.air_slam_step
			if not weapon.air_combo.is_empty():
				return weapon.air_combo[weapon.air_combo.size() - 1]
	return null


func _activate_step_hitbox() -> void:
	if player.hitbox == null or player.current_weapon == null or _step == null:
		return
	var dmg_mult: float = player.get_effective_damage_multiplier()
	var poise_mult: float = player.modifiers.get_multiplier(&"poise_damage_mult") if player.modifiers != null else 1.0

	var info: DamageInfo = DamageInfo.new()
	info.amount = player.current_weapon.base_damage * _step.damage_multiplier * dmg_mult
	info.source = player
	info.knockback_vector = _forward_dir * _step.knockback_force
	info.launch_force = _step.vertical_launch_force
	info.launch_vector = Vector3(_forward_dir.x * _step.knockback_force, _step.vertical_launch_force, _forward_dir.z * _step.knockback_force)
	info.hitstun_duration = _step.hitstun_duration
	info.stagger_power = _step.stagger_power * poise_mult
	info.hitstop_frames = _step.hitstop_frames
	info.hitstop_duration = _step.hitstop_duration
	info.screen_shake = _step.screen_shake_intensity
	info.is_launcher = _step.is_launcher
	info.is_aerial = _step.is_aerial
	info.force_state = DamageInfo.FORCE_STATE_GROUND_BOUNCE if (_mode == &"air_slam" or _step.is_air_slam) else _step.force_reaction_state
	info.attacker_forward_velocity = Vector3(player.velocity.x, 0.0, player.velocity.z)

	var right_dir: Vector3 = Vector3.UP.cross(_forward_dir).normalized()
	var swing_delta: float = _step.swing_end_angle_deg - _step.swing_start_angle_deg
	var lateral_sign: float = 1.0 if swing_delta >= 0.0 else -1.0
	var vertical_bias: float = 0.65 if _step.is_launcher else (-0.75 if _step.vertical_launch_force < -4.0 else 0.1)
	info.impact_direction = (_forward_dir + right_dir * (lateral_sign * 0.7) + Vector3.UP * vertical_bias).normalized()

	player.hitbox.activate(info, _step.hitbox_size, _step.hitbox_offset)

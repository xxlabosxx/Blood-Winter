class_name PlayerAttackState
extends PlayerState
## Resource-driven melee combo state supporting Ground Combos, Launchers,
## Air Juggle Combos, and explicit Animation Canceling windows.

var _mode: StringName = &"ground"
var _step_index: int = 0
var _step: ComboStepData = null
var _elapsed: float = 0.0
var _speed_mult: float = 1.0
var _hitbox_started: bool = false
var _hitbox_finished: bool = false
var _lift_applied: bool = false
var _forward_dir: Vector3 = Vector3.FORWARD


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_mode = data.get("mode", &"ground") as StringName
	_step_index = int(data.get("index", 0))
	_elapsed = 0.0
	_hitbox_started = false
	_hitbox_finished = false
	_lift_applied = false

	var weapon: WeaponData = player.current_weapon
	if weapon == null:
		request_transition(&"Idle")
		return

	_speed_mult = maxf(0.2, weapon.attack_speed)
	_step = _resolve_step(weapon, _mode, _step_index)
	if _step == null:
		request_transition(&"Idle" if player.is_on_floor() else &"Air")
		return

	player.face_locked_or_input_immediately()
	_forward_dir = player.get_facing_direction()

	# Forward momentum burst
	player.velocity.x = _forward_dir.x * _step.forward_impulse
	player.velocity.z = _forward_dir.z * _step.forward_impulse

	# Aerial suspension impulse on air combo attacks
	if _step.is_aerial:
		if _step.attacker_air_lift >= 0.0:
			player.velocity.y = maxf(player.velocity.y * 0.25, _step.attacker_air_lift)
		else:
			player.velocity.y = _step.attacker_air_lift
		if _step_index >= weapon.air_combo.size() - 1:
			player.air_combo_used = true

	player.set_combo_debug_label(_step.step_name)
	player.cancel_window_status = "Startup"
	player.set_weapon_swing_pose(_step.swing_start_angle_deg, 10.0, _step.swing_tilt_deg)


func exit() -> void:
	if player != null:
		if player.hitbox != null:
			player.hitbox.deactivate()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false
		player.cancel_window_status = "-"


func physics_update(delta: float) -> void:
	if _step == null:
		request_transition(&"Idle")
		return

	_elapsed += delta
	var startup: float = _step.get_scaled_startup(_speed_mult)
	var active: float = _step.get_scaled_active(_speed_mult)
	var total: float = _step.get_total_duration(_speed_mult)

	# 1) Animation Canceling checks (explicitly governed by ComboStepData)
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

	if _step.can_cancel_with_jump(_elapsed, _speed_mult):
		cancel_tags.append("JUMP")
		if player.is_on_floor() and player.consume_buffered_action(&"jump"):
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

	# 2) Combo Chaining checks (Ground -> Ground, Ground -> Launcher, Launcher -> Air, Air -> Air)
	if _step.can_chain_at(_elapsed, _speed_mult):
		var weapon: WeaponData = player.current_weapon
		if _mode == &"ground":
			if player.consume_buffered_action(&"attack_launcher") and weapon.launcher_step != null:
				request_transition(&"Attack", {"mode": &"launcher", "index": 0})
				return
			if player.consume_buffered_action(&"attack_light") and (_step_index + 1) < weapon.ground_combo.size():
				request_transition(&"Attack", {"mode": &"ground", "index": _step_index + 1})
				return
		elif _mode == &"launcher":
			if player.consume_buffered_action(&"attack_light") and not weapon.air_combo.is_empty():
				request_transition(&"Attack", {"mode": &"air", "index": 0})
				return
		elif _mode == &"air":
			if player.consume_buffered_action(&"attack_light") and (_step_index + 1) < weapon.air_combo.size():
				request_transition(&"Attack", {"mode": &"air", "index": _step_index + 1})
				return

	# 3) Hitbox Activation, Weapon Trail, and Launcher Air Lift
	if not _hitbox_started and _elapsed >= startup:
		_hitbox_started = true
		_activate_step_hitbox()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = true
		if _step.is_launcher and not _lift_applied:
			_lift_applied = true
			if _step.attacker_air_lift > 0.0:
				player.velocity.y = _step.attacker_air_lift

	if _hitbox_started and not _hitbox_finished and _elapsed >= (startup + active):
		_hitbox_finished = true
		if player.hitbox != null:
			player.hitbox.deactivate()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false

	# 4) Procedural Weapon Swing Arc
	var swing_t: float = clampf((_elapsed - startup * 0.5) / maxf(0.05, active + startup * 0.7), 0.0, 1.0)
	var eased_t: float = 1.0 - pow(1.0 - swing_t, 3.0)
	var yaw_deg: float = lerpf(_step.swing_start_angle_deg, _step.swing_end_angle_deg, eased_t)
	var pitch_deg: float = lerpf(-32.0, 44.0, eased_t) if _step.is_launcher else lerpf(12.0, -8.0, eased_t)
	player.set_weapon_swing_pose(yaw_deg, pitch_deg, _step.swing_tilt_deg)

	# 5) Movement Friction & Aerial Gravity Suspension
	player.velocity.x = move_toward(player.velocity.x, 0.0, 18.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, 18.0 * delta)

	if _step.is_aerial:
		# Reduced gravity during aerial slashes keeps player suspended like DMC/Bayonetta
		var grav_scale: float = 0.24 if _step.attacker_air_lift >= 0.0 else 1.15
		player.velocity.y -= Player.GRAVITY * grav_scale * delta
	elif _step.is_launcher and _lift_applied:
		player.velocity.y -= Player.GRAVITY * 0.65 * delta
	else:
		if not player.is_on_floor():
			player.velocity.y -= Player.GRAVITY * delta
		else:
			player.velocity.y = -1.0

	player.move_and_slide()

	# Landed early during aerial plunge
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


func _resolve_step(weapon: WeaponData, mode: StringName, index: int) -> ComboStepData:
	match mode:
		&"ground":
			return weapon.get_ground_step(index)
		&"launcher":
			return weapon.launcher_step
		&"air":
			return weapon.get_air_step(index)
	return null


func _activate_step_hitbox() -> void:
	if player.hitbox == null or player.current_weapon == null or _step == null:
		return
	var info: DamageInfo = DamageInfo.new()
	info.amount = player.current_weapon.base_damage * _step.damage_multiplier
	info.source = player
	info.knockback_vector = _forward_dir * _step.knockback_force
	info.launch_force = _step.vertical_launch_force
	info.hitstop_duration = _step.hitstop_duration
	info.screen_shake = _step.screen_shake_intensity
	info.is_launcher = _step.is_launcher
	info.is_aerial = _step.is_aerial
	player.hitbox.activate(info, _step.hitbox_size, _step.hitbox_offset)

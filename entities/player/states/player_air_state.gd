class_name PlayerAirState
extends PlayerState


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	player.set_combo_debug_label("Airborne")
	player.cancel_window_status = "-"
	player.reset_weapon_pose()
	player.play_character_animation(&"Jump", 1.0, 0.14)


func physics_update(delta: float) -> void:
	if try_consume_common_actions(false):
		return

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	var air_speed: float = player.get_effective_move_speed() * 0.92
	var horiz_vel: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var cur_speed: float = horiz_vel.length()

	# Bayonetta 2 Double Jump: resets V.y = 0, applies jump impulse, and redirects horizontal momentum
	if player.combat_comp != null and player.consume_buffered_action(&"jump") and player.combat_comp.consume_jump(false):
		player.velocity.y = 0.0
		player.velocity.y = player.class_data.jump_velocity
		if move_dir.length_squared() > 0.01:
			var dj_speed: float = maxf(air_speed, cur_speed * 0.92)
			player.velocity.x = move_dir.x * dj_speed
			player.velocity.z = move_dir.z * dj_speed
			player.face_direction(move_dir, 100.0, 1.0)
		player.play_character_animation(&"Jump", 1.15, 0.10, true)
		player.spawn_dodge_ghost(Color(0.75, 0.90, 1.0, 0.45), 0.20)
		player.set_combo_debug_label("Double Jump")
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("DOUBLE JUMP!")
	elif move_dir.length_squared() > 0.01:
		if cur_speed > air_speed:
			# Preserve aerial momentum from Dash-Jumps and Slide-Hops (minimal air drag)
			var preserved_speed: float = maxf(air_speed, cur_speed - 1.15 * delta)
			var steer_dir: Vector3 = horiz_vel.normalized().slerp(move_dir, clampf(4.8 * delta, 0.0, 1.0)).normalized()
			player.velocity.x = steer_dir.x * preserved_speed
			player.velocity.z = steer_dir.z * preserved_speed
		else:
			player.velocity.x = move_toward(player.velocity.x, move_dir.x * air_speed, 65.0 * delta)
			player.velocity.z = move_toward(player.velocity.z, move_dir.z * air_speed, 65.0 * delta)
		if not player.face_locked_target(14.0, delta):
			player.face_direction(move_dir, 10.0, delta)
	else:
		# Very gentle air drag so jumps keep forward carry
		var drag: float = 2.4 if cur_speed > air_speed else 7.5
		player.velocity.x = move_toward(player.velocity.x, 0.0, drag * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, drag * delta)
		player.face_locked_target(14.0, delta)

	# Variable Jump Height: releasing jump early before apex cuts upward arc cleanly
	var jump_cut_mult: float = 1.0
	if player.velocity.y > 0.0 and not Input.is_action_pressed(&"jump"):
		jump_cut_mult = player.combat_comp.jump_cut_gravity_multiplier if player.combat_comp != null else 2.5
	player.velocity.y -= Player.GRAVITY * jump_cut_mult * delta
	player.move_and_slide()

	if player.is_on_floor():
		# Deadlock Slide-Hop / Dash-Jump-Slide: holding CTRL on landing chains straight into Slide!
		if (player.is_holding_slide() or player.consume_buffered_action(&"slide")) and player.can_slide():
			request_transition(&"Slide")
			return
		if move_dir.length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")

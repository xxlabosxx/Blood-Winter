class_name PlayerMoveState
extends PlayerState


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	player.set_combo_debug_label("Moving")
	player.cancel_window_status = "-"
	player.reset_weapon_pose()
	player.play_character_animation(&"Run", 1.15, 0.16)


func physics_update(delta: float) -> void:
	if try_consume_common_actions(true):
		return

	if not player.is_on_floor():
		request_transition(&"Air")
		return

	if player.consume_buffered_action(&"slide") and player.can_slide():
		request_transition(&"Slide")
		return

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	if move_dir.length_squared() < 0.01:
		request_transition(&"Idle")
		return

	var cls: HunterClassData = player.class_data
	var base_speed: float = player.get_effective_move_speed()
	var sprint_speed: float = cls.sprint_momentum_speed * (base_speed / maxf(0.1, cls.move_speed))
	var horiz_vel: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var cur_speed: float = horiz_vel.length()

	var target_speed: float = base_speed
	# Bayonetta 2 Hybrid: instantaneous (1-3 frames) acceleration up to base_speed,
	# then Deadlock momentum buildup & preservation above base_speed.
	var accel: float = 220.0

	if cur_speed >= base_speed - 0.15:
		var alignment: float = horiz_vel.normalized().dot(move_dir) if cur_speed > 0.05 else 1.0
		if alignment > 0.55:
			if cur_speed > sprint_speed:
				# Preserve excess momentum from dashes, slides, or air drops with gentle decay
				target_speed = sprint_speed
				accel = cls.momentum_ground_decay
			else:
				# Build up sprint momentum continuously until slide threshold is reached
				target_speed = sprint_speed
				accel = cls.momentum_buildup_rate
		else:
			# Sharp turn sheds excess speed for crisp directional control
			target_speed = base_speed
			accel = 140.0

	var new_speed: float = move_toward(cur_speed, target_speed, accel * delta)
	var desired_dir: Vector3 = move_dir
	if cur_speed > base_speed + 0.5:
		desired_dir = horiz_vel.normalized().slerp(move_dir, clampf(10.0 * delta, 0.0, 1.0)).normalized()

	player.velocity.x = desired_dir.x * new_speed
	player.velocity.z = desired_dir.z * new_speed
	player.velocity.y = 0.0

	if player.camera_rig != null and player.camera_rig.locked_target != null and is_instance_valid(player.camera_rig.locked_target):
		var to_enemy: Vector3 = player.camera_rig.locked_target.global_position - player.global_position
		player.face_direction(to_enemy, 14.0, delta)
	else:
		player.face_direction(move_dir, 15.0, delta)

	player.move_and_slide()

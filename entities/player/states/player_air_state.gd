class_name PlayerAirState
extends PlayerState


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	player.set_combo_debug_label("Airborne")
	player.cancel_window_status = "-"
	player.reset_weapon_pose()


func physics_update(delta: float) -> void:
	if try_consume_common_actions(false):
		return

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	var air_speed: float = player.class_data.move_speed * 0.9
	if move_dir.length_squared() > 0.01:
		player.velocity.x = move_toward(player.velocity.x, move_dir.x * air_speed, 22.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, move_dir.z * air_speed, 22.0 * delta)
		player.face_direction(move_dir, 10.0, delta)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, 8.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 8.0 * delta)

	player.velocity.y -= Player.GRAVITY * delta
	player.move_and_slide()

	if player.is_on_floor():
		if move_dir.length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")

class_name PlayerMoveState
extends PlayerState


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	player.set_combo_debug_label("Moving")
	player.cancel_window_status = "-"
	player.reset_weapon_pose()


func physics_update(delta: float) -> void:
	if try_consume_common_actions(true):
		return

	if not player.is_on_floor():
		request_transition(&"Air")
		return

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	if move_dir.length_squared() < 0.01:
		request_transition(&"Idle")
		return

	var target_speed: float = player.class_data.move_speed
	player.velocity.x = move_toward(player.velocity.x, move_dir.x * target_speed, 38.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, move_dir.z * target_speed, 38.0 * delta)
	player.velocity.y = 0.0

	if player.camera_rig != null and player.camera_rig.locked_target != null and is_instance_valid(player.camera_rig.locked_target):
		var to_enemy: Vector3 = player.camera_rig.locked_target.global_position - player.global_position
		player.face_direction(to_enemy, 14.0, delta)
	else:
		player.face_direction(move_dir, 15.0, delta)

	player.move_and_slide()

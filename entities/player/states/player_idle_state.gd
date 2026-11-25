class_name PlayerIdleState
extends PlayerState


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	player.set_combo_debug_label("Idle")
	player.cancel_window_status = "-"
	player.reset_weapon_pose()


func physics_update(delta: float) -> void:
	if try_consume_common_actions(true):
		return

	if not player.is_on_floor():
		request_transition(&"Air")
		return

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	if move_dir.length_squared() > 0.01:
		request_transition(&"Move")
		return

	player.velocity.x = move_toward(player.velocity.x, 0.0, 28.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, 28.0 * delta)
	player.velocity.y = 0.0
	player.move_and_slide()

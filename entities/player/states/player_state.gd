class_name PlayerState
extends State
## Typed base state for the Player's finite state machine.

var player: Player = null


func enter(_previous_state: StringName, _data: Dictionary = {}) -> void:
	player = actor as Player


func try_consume_common_actions(allow_jump: bool = true) -> bool:
	if player == null:
		return false
	if player.consume_buffered_action(&"dodge") and player.can_dodge():
		request_transition(&"Dodge")
		return true
	if player.consume_buffered_action(&"class_skill") and player.can_use_skill():
		request_transition(&"Skill")
		return true
	if allow_jump and player.is_on_floor() and player.consume_buffered_action(&"jump"):
		if player.combat_comp != null:
			player.combat_comp.consume_jump(true)
		player.velocity.y = player.class_data.jump_velocity
		request_transition(&"Air")
		return true

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	var target: Node3D = player.get_active_combat_target(move_dir)

	if player.current_weapon != null and player.consume_buffered_action(&"attack_launcher"):
		var cmd: StringName = &"launcher" if player.is_on_floor() else &"air_slam"
		if player.combat_comp != null:
			cmd = player.combat_comp.resolve_attack_command(
				player.is_on_floor(),
				target,
				move_dir,
				player.get_facing_direction(),
				true,
				player.get_horizontal_speed(),
				player.get_effective_move_speed(),
				player.global_position
			)
		if player.is_on_floor() or not player.air_combo_used or cmd == &"air_slam":
			request_transition(&"Attack", {"mode": cmd, "index": 0})
			return true

	if player.current_weapon != null and player.consume_buffered_action(&"attack_light"):
		var cmd_light: StringName = &"ground" if player.is_on_floor() else &"air"
		if player.combat_comp != null:
			cmd_light = player.combat_comp.resolve_attack_command(
				player.is_on_floor(),
				target,
				move_dir,
				player.get_facing_direction(),
				false,
				player.get_horizontal_speed(),
				player.get_effective_move_speed(),
				player.global_position
			)
		if player.is_on_floor() or not player.air_combo_used or cmd_light == &"air_slam":
			request_transition(&"Attack", {"mode": cmd_light, "index": 0})
			return true

	return false

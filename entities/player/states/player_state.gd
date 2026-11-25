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
		player.velocity.y = player.class_data.jump_velocity
		request_transition(&"Air")
		return true
	if player.consume_buffered_action(&"attack_launcher"):
		if player.is_on_floor():
			request_transition(&"Attack", {"mode": &"launcher", "index": 0})
		else:
			request_transition(&"Attack", {"mode": &"air", "index": 0})
		return true
	if player.consume_buffered_action(&"attack_light"):
		if player.is_on_floor():
			request_transition(&"Attack", {"mode": &"ground", "index": 0})
		elif not player.air_combo_used:
			request_transition(&"Attack", {"mode": &"air", "index": 0})
		return true
	return false

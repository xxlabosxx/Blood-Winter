class_name State
extends Node
## Base class for explicit, strongly-typed finite state machine states.

signal transition_requested(target_state: StringName, data: Dictionary)

var state_machine: StateMachine = null
var actor: Node = null


func enter(_previous_state: StringName, _data: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func request_transition(target_state: StringName, data: Dictionary = {}) -> void:
	transition_requested.emit(target_state, data)

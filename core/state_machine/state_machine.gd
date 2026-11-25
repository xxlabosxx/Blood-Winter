class_name StateMachine
extends Node
## Explicit State Machine managing child State nodes with strict transitions.

signal state_changed(previous_state: StringName, current_state: StringName)

@export var initial_state: State = null

var current_state: State = null
var _states: Dictionary = {}


func initialize(target_actor: Node) -> void:
	_states.clear()
	for child: Node in get_children():
		if child is State:
			var state_node: State = child as State
			var key: StringName = StringName(state_node.name)
			_states[key] = state_node
			state_node.state_machine = self
			state_node.actor = target_actor
			if not state_node.transition_requested.is_connected(_on_state_transition_requested):
				state_node.transition_requested.connect(_on_state_transition_requested)

	if initial_state != null:
		transition_to(StringName(initial_state.name))
	elif not _states.is_empty():
		var first_key: StringName = _states.keys()[0]
		transition_to(first_key)


func transition_to(target_state_name: StringName, data: Dictionary = {}) -> void:
	if not _states.has(target_state_name):
		push_warning("StateMachine: Unknown target state '%s'." % String(target_state_name))
		return

	var next_state: State = _states[target_state_name] as State
	var previous_name: StringName = &""
	if current_state != null:
		previous_name = StringName(current_state.name)
		current_state.exit()

	current_state = next_state
	current_state.enter(previous_name, data)
	state_changed.emit(previous_name, target_state_name)


func get_current_state_name() -> StringName:
	if current_state == null:
		return &"None"
	return StringName(current_state.name)


func handle_input(event: InputEvent) -> void:
	if current_state != null:
		current_state.handle_input(event)


func update(delta: float) -> void:
	if current_state != null:
		current_state.update(delta)


func physics_update(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


func _on_state_transition_requested(target_state: StringName, data: Dictionary) -> void:
	transition_to(target_state, data)

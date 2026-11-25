class_name VampireState
extends State
## Typed base state for the Vampire Duelist AI.

var vampire: VampireDuelist = null


func enter(_previous_state: StringName, _data: Dictionary = {}) -> void:
	vampire = actor as VampireDuelist

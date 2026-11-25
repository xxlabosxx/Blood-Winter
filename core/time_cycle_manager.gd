extends Node
## Day/Night cycle state machine: DAY -> DUSK -> NIGHT -> DAWN.
## Paused by default in the Combat Gym for isolated combat testing.

enum Phase {
	DAY,
	DUSK,
	NIGHT,
	DAWN,
}

signal phase_changed(new_phase: Phase, day_number: int)
signal day_completed(completed_day: int)
signal pause_changed(is_paused: bool)

@export var phase_durations: Dictionary = {
	Phase.DAY: 180.0,
	Phase.DUSK: 45.0,
	Phase.NIGHT: 150.0,
	Phase.DAWN: 30.0,
}

var current_phase: Phase = Phase.NIGHT
var day_number: int = 1
var phase_elapsed: float = 0.0
var is_paused: bool = true


func _process(delta: float) -> void:
	if is_paused:
		return

	var duration: float = get_current_phase_duration()
	phase_elapsed += delta
	if phase_elapsed >= duration:
		phase_elapsed = 0.0
		advance_phase()


func get_current_phase_duration() -> float:
	return float(phase_durations.get(current_phase, 60.0))


func get_phase_progress() -> float:
	var duration: float = maxf(0.01, get_current_phase_duration())
	return clampf(phase_elapsed / duration, 0.0, 1.0)


func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	pause_changed.emit(is_paused)


func toggle_pause() -> bool:
	set_paused(not is_paused)
	return is_paused


func set_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_elapsed = 0.0
	phase_changed.emit(current_phase, day_number)


func advance_phase() -> Phase:
	var next_index: int = (int(current_phase) + 1) % Phase.size()
	if next_index == int(Phase.DAY):
		var finished_day: int = day_number
		day_number += 1
		if SeedManager != null:
			SeedManager.set_current_day(day_number)
		day_completed.emit(finished_day)
	current_phase = next_index as Phase
	phase_elapsed = 0.0
	phase_changed.emit(current_phase, day_number)
	return current_phase


func reset_cycle(start_phase: Phase = Phase.NIGHT, paused: bool = true) -> void:
	day_number = 1
	current_phase = start_phase
	phase_elapsed = 0.0
	is_paused = paused
	if SeedManager != null:
		SeedManager.set_current_day(day_number)
	phase_changed.emit(current_phase, day_number)
	pause_changed.emit(is_paused)


func get_phase_name(phase: Phase = current_phase) -> String:
	match phase:
		Phase.DAY:
			return "DAY"
		Phase.DUSK:
			return "DUSK"
		Phase.NIGHT:
			return "NIGHT"
		Phase.DAWN:
			return "DAWN"
	return "UNKNOWN"

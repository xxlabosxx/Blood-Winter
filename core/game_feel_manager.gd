extends Node
## Coordinates combat game feel: micro hitstop freezes and camera screen shake.

signal screen_shake_requested(intensity: float, duration: float)
signal combat_event_logged(message: String)

var _hitstop_token: int = 0
var _is_in_hitstop: bool = false


func trigger_hitstop(duration: float, time_scale_value: float = 0.04) -> void:
	if duration <= 0.001:
		return
	_hitstop_token += 1
	var my_token: int = _hitstop_token
	_is_in_hitstop = true
	Engine.time_scale = clampf(time_scale_value, 0.01, 0.5)

	# ignore_time_scale = true guarantees recovery in real wall-clock seconds.
	var timer: SceneTreeTimer = get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	if my_token == _hitstop_token:
		Engine.time_scale = 1.0
		_is_in_hitstop = false


func request_screen_shake(intensity: float, duration: float = 0.14) -> void:
	if intensity <= 0.001:
		return
	screen_shake_requested.emit(intensity, duration)


func log_combat_event(message: String) -> void:
	combat_event_logged.emit(message)


func reset_time_scale() -> void:
	_hitstop_token += 1
	_is_in_hitstop = false
	Engine.time_scale = 1.0

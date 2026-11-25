class_name TorchFlicker
extends OmniLight3D
## Subtle organic crimson/ember flicker for gothic arena torches.

@export var base_energy: float = 4.2
@export var flicker_amplitude: float = 0.85
@export var flicker_speed: float = 7.5

var _phase_offset: float = 0.0


func _ready() -> void:
	_phase_offset = float(get_instance_id() % 997) * 0.13


func _process(_delta: float) -> void:
	var t: float = (Time.get_ticks_msec() / 1000.0) * flicker_speed + _phase_offset
	var wave: float = sin(t) * 0.55 + sin(t * 2.37) * 0.30 + cos(t * 4.11) * 0.15
	light_energy = maxf(0.5, base_energy + wave * flicker_amplitude)

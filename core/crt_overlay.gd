extends CanvasLayer
## Global Analog / CRT post-processing overlay with runtime toggle.

signal crt_toggled(enabled: bool)

@onready var _crt_rect: ColorRect = $CRTRect

var crt_enabled: bool = true


func _ready() -> void:
	set_crt_enabled(crt_enabled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crt"):
		toggle_crt()
		get_viewport().set_input_as_handled()


func set_crt_enabled(enabled: bool) -> void:
	crt_enabled = enabled
	if _crt_rect != null:
		_crt_rect.visible = crt_enabled
	crt_toggled.emit(crt_enabled)


func toggle_crt() -> bool:
	set_crt_enabled(not crt_enabled)
	return crt_enabled

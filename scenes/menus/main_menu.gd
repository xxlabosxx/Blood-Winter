class_name MainMenu
extends Control
## Blood Winter initial gothic title HUD with Jogar, Arena de Combate Debug, and Sair.
## Includes lightweight procedural winter snowfall backdrop and clean scene transitions.

const DEBUG_ARENA_SCENE: String = "res://scenes/test_arena/combat_gym.tscn"
const SNOW_COUNT: int = 72

## Future main gameplay scene path (e.g. Base Hub / Procedural Day-Night World).
## Leave empty while under construction to display an inline notice.
@export_file("*.tscn") var play_scene_path: String = ""

@onready var _play_button: Button = %PlayButton
@onready var _debug_arena_button: Button = %DebugArenaButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel

var _snowflakes: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Engine.time_scale = 1.0
	var tdm: Node = get_tree().root.get_node_or_null("TimeDilationManager")
	if tdm != null and tdm.has_method("cancel_witch_time"):
		tdm.call("cancel_witch_time")

	_rng.randomize()
	_init_snowflakes()

	if _status_label != null:
		_status_label.text = ""
	if _play_button != null:
		_play_button.grab_focus()


func _process(delta: float) -> void:
	var vp: Vector2 = size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	for flake: Dictionary in _snowflakes:
		var pos: Vector2 = flake["pos"] as Vector2
		var spd: float = float(flake["speed"])
		var drift: float = float(flake["drift"])
		var phase: float = float(flake["phase"]) + delta * 1.4
		flake["phase"] = phase
		pos.y += spd * delta
		pos.x += (drift + sin(phase) * 14.0) * delta
		if pos.y > vp.y + 8.0:
			pos.y = -8.0
			pos.x = _rng.randf_range(0.0, vp.x)
		if pos.x < -12.0:
			pos.x = vp.x + 12.0
		elif pos.x > vp.x + 12.0:
			pos.x = -12.0
		flake["pos"] = pos
	queue_redraw()


func _draw() -> void:
	var vp: Vector2 = size
	# Subtle gothic crimson moon halo behind the title card
	var moon_center: Vector2 = Vector2(vp.x * 0.5, vp.y * 0.28)
	draw_circle(moon_center, 190.0, Color(0.55, 0.04, 0.10, 0.08))
	draw_circle(moon_center, 110.0, Color(0.75, 0.06, 0.14, 0.10))
	draw_circle(moon_center, 46.0, Color(0.92, 0.12, 0.20, 0.16))

	# Procedural winter snowfall
	for flake: Dictionary in _snowflakes:
		var pos: Vector2 = flake["pos"] as Vector2
		var r: float = float(flake["radius"])
		var alpha: float = float(flake["alpha"])
		draw_circle(pos, r, Color(0.86, 0.92, 1.0, alpha))


func _init_snowflakes() -> void:
	_snowflakes.clear()
	var vp: Vector2 = Vector2(1280.0, 720.0)
	if size.x > 10.0 and size.y > 10.0:
		vp = size
	for _i: int in range(SNOW_COUNT):
		_snowflakes.append({
			"pos": Vector2(_rng.randf_range(0.0, vp.x), _rng.randf_range(0.0, vp.y)),
			"radius": _rng.randf_range(1.2, 2.8),
			"speed": _rng.randf_range(28.0, 76.0),
			"drift": _rng.randf_range(-18.0, -4.0),
			"alpha": _rng.randf_range(0.18, 0.62),
			"phase": _rng.randf_range(0.0, TAU),
		})


func _on_play_button_pressed() -> void:
	if not play_scene_path.is_empty() and ResourceLoader.exists(play_scene_path):
		get_tree().change_scene_to_file(play_scene_path)
		return
	if _status_label != null:
		_status_label.text = "Modo Principal em construção — use 'Arena de Combate Debug' para testar o combate."


func _on_debug_arena_button_pressed() -> void:
	get_tree().change_scene_to_file(DEBUG_ARENA_SCENE)


func _on_quit_button_pressed() -> void:
	get_tree().quit()

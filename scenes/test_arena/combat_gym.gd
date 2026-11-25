class_name CombatGymController
extends Node3D
## Orchestrates the Combat Gym Vertical Slice:
## class switching, arena resets, seed testing, and TimeCycle atmosphere previews.

@export var available_classes: Array[HunterClassData] = []

@onready var _player: Player = $Player
@onready var _vampire: VampireDuelist = $VampireDuelist
@onready var _camera_rig: CombatCameraRig = $CombatCameraRig
@onready var _debug_hud: DebugHUD = $DebugHUD
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun_light: DirectionalLight3D = $DirectionalLight3D

var _current_class_index: int = 0


func _ready() -> void:
	if available_classes.is_empty():
		var vanguard: HunterClassData = load("res://data/classes/vanguard_inquisitor.tres") as HunterClassData
		var stalker: HunterClassData = load("res://data/classes/night_stalker.tres") as HunterClassData
		if vanguard != null:
			available_classes.append(vanguard)
		if stalker != null:
			available_classes.append(stalker)

	if _debug_hud != null:
		_debug_hud.bind_actors(_player, _vampire, _camera_rig)
		_debug_hud.switch_class_requested.connect(_cycle_hunter_class)
		_debug_hud.reset_arena_requested.connect(_reset_arena)
		_debug_hud.reroll_seed_requested.connect(_reroll_seed)
		_debug_hud.advance_day_requested.connect(_advance_day)

	if TimeCycleManager != null:
		TimeCycleManager.reset_cycle(TimeCycleManager.Phase.NIGHT, true)
		if not TimeCycleManager.phase_changed.is_connected(_on_time_phase_changed):
			TimeCycleManager.phase_changed.connect(_on_time_phase_changed)
		_apply_phase_atmosphere(TimeCycleManager.current_phase)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_class"):
		_cycle_hunter_class()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_arena"):
		_reset_arena()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reroll_seed"):
		_reroll_seed()
		get_viewport().set_input_as_handled()


func _cycle_hunter_class() -> void:
	if available_classes.is_empty() or _player == null:
		return
	_current_class_index = (_current_class_index + 1) % available_classes.size()
	var next_class: HunterClassData = available_classes[_current_class_index]
	_player.apply_class_data(next_class)
	if GameFeelManager != null:
		GameFeelManager.log_combat_event("Switched class -> %s (%s)" % [next_class.class_name_display, next_class.special_skill_name])


func _reset_arena() -> void:
	if GameFeelManager != null:
		GameFeelManager.reset_time_scale()
		GameFeelManager.log_combat_event("Arena reset.")
	if _player != null:
		_player.reset_for_gym()
	if _vampire != null:
		_vampire.reset_for_gym()


func _reroll_seed() -> void:
	if SeedManager != null:
		var new_seed: int = SeedManager.initialize_run()
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("New Run Seed -> #%d" % new_seed)


func _advance_day() -> void:
	if SeedManager != null:
		var day: int = SeedManager.advance_day()
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("Simulated Day %d sub-seeds derived." % day)


func _on_time_phase_changed(new_phase: int, _day_number: int) -> void:
	_apply_phase_atmosphere(new_phase)


func _apply_phase_atmosphere(phase: int) -> void:
	if _world_env == null or _world_env.environment == null or _sun_light == null:
		return
	var env: Environment = _world_env.environment
	match phase:
		TimeCycleManager.Phase.DAY:
			env.fog_light_color = Color(0.62, 0.72, 0.84, 1.0)
			env.ambient_light_color = Color(0.55, 0.66, 0.80, 1.0)
			env.ambient_light_energy = 0.72
			_sun_light.light_color = Color(0.88, 0.94, 1.0, 1.0)
			_sun_light.light_energy = 1.55
		TimeCycleManager.Phase.DUSK:
			env.fog_light_color = Color(0.36, 0.22, 0.28, 1.0)
			env.ambient_light_color = Color(0.45, 0.28, 0.34, 1.0)
			env.ambient_light_energy = 0.55
			_sun_light.light_color = Color(0.95, 0.45, 0.42, 1.0)
			_sun_light.light_energy = 1.15
		TimeCycleManager.Phase.NIGHT:
			env.fog_light_color = Color(0.16, 0.22, 0.32, 1.0)
			env.ambient_light_color = Color(0.28, 0.38, 0.52, 1.0)
			env.ambient_light_energy = 0.48
			_sun_light.light_color = Color(0.76, 0.86, 1.0, 1.0)
			_sun_light.light_energy = 1.25
		TimeCycleManager.Phase.DAWN:
			env.fog_light_color = Color(0.46, 0.54, 0.68, 1.0)
			env.ambient_light_color = Color(0.46, 0.52, 0.66, 1.0)
			env.ambient_light_energy = 0.60
			_sun_light.light_color = Color(0.94, 0.80, 0.78, 1.0)
			_sun_light.light_energy = 1.30

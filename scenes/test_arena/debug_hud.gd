class_name DebugHUD
extends CanvasLayer
## Live Combat Gym diagnostic HUD displaying state machine telemetry, combos,
## Animation Canceling windows, height/airborne status, seeds, time cycle,
## hunter class switcher, and CRT filter toggle.

signal switch_class_requested()
signal reset_arena_requested()
signal reroll_seed_requested()
signal advance_day_requested()

@onready var _player_info_label: RichTextLabel = %PlayerInfoLabel
@onready var _enemy_info_label: RichTextLabel = %EnemyInfoLabel
@onready var _world_info_label: RichTextLabel = %WorldInfoLabel
@onready var _event_log_label: RichTextLabel = %EventLogLabel
@onready var _controls_panel: PanelContainer = %ControlsPanel
@onready var _crt_button: Button = %CRTButton
@onready var _class_button: Button = %ClassButton
@onready var _time_pause_button: Button = %TimePauseButton

var player_ref: Player = null
var enemy_ref: VampireDuelist = null
var camera_ref: CombatCameraRig = null

var _event_lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	if GameFeelManager != null and not GameFeelManager.combat_event_logged.is_connected(_on_combat_event_logged):
		GameFeelManager.combat_event_logged.connect(_on_combat_event_logged)
	if CRTOverlay != null and not CRTOverlay.crt_toggled.is_connected(_on_crt_toggled):
		CRTOverlay.crt_toggled.connect(_on_crt_toggled)
	_refresh_button_labels()


func bind_actors(player: Player, enemy: VampireDuelist, cam: CombatCameraRig) -> void:
	player_ref = player
	enemy_ref = enemy
	camera_ref = cam
	_refresh_button_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud_help"):
		if _controls_panel != null:
			_controls_panel.visible = not _controls_panel.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_update_player_panel()
	_update_enemy_panel()
	_update_world_panel()
	_refresh_button_labels()


func _update_player_panel() -> void:
	if _player_info_label == null or player_ref == null:
		return

	var cls: HunterClassData = player_ref.class_data
	var wpn: WeaponData = player_ref.current_weapon
	var state_name: String = String(player_ref.state_machine.get_current_state_name())
	var height: float = player_ref.get_height_above_ground()
	var air_str: String = "[color=#7fd4ff]AIRBORNE (%.2fm)[/color]" % height if not player_ref.is_on_floor() else "[color=#d8e4f0]GROUNDED (%.2fm)[/color]" % height
	var iframe_str: String = " [color=#ff4d6d][I-FRAMES][/color]" if (player_ref.health != null and player_ref.health.is_invulnerable) else ""
	var lock_str: String = "[color=#ff3b5c]LOCKED[/color]" if (camera_ref != null and camera_ref.locked_target != null) else "Free"
	var skill_cd: String = "READY" if player_ref.skill_cooldown_remaining <= 0.01 else "%.1fs" % player_ref.skill_cooldown_remaining
	var hp_cur: float = player_ref.health.current_health if player_ref.health != null else 0.0
	var hp_max: float = player_ref.health.max_health if player_ref.health != null else 1.0

	var cancel_color: String = "#ffbe3b" if player_ref.cancel_window_status.begins_with("CANCEL") else "#a6b5c8"

	var text: String = ""
	text += "[b][color=#ff2e4c]BLOOD WINTER // COMBAT GYM[/color][/b]\n"
	text += "Class: [b]%s[/b]  |  Weapon: [b]%s[/b]\n" % [
		cls.class_name_display if cls != null else "None",
		wpn.weapon_name if wpn != null else "None",
	]
	if cls != null:
		text += "Skill: [color=#ff6680]%s[/color] (%s)  |  Loot x%.2f  ID +%.0f%%\n" % [
			cls.special_skill_name,
			skill_cd,
			cls.loot_bonus_multiplier,
			cls.identification_bonus * 100.0,
		]
	text += "HP: [b]%.0f / %.0f[/b]  |  Target: %s\n" % [hp_cur, hp_max, lock_str]
	text += "State: [b][color=#eef6ff]%s[/color][/b]%s\n" % [state_name, iframe_str]
	text += "Combo Step: [b][color=#ff6b81]%s[/color][/b]\n" % player_ref.current_combo_label
	text += "Window: [color=%s]%s[/color]\n" % [cancel_color, player_ref.cancel_window_status]
	text += "Air/Height: %s" % air_str
	_player_info_label.text = text


func _update_enemy_panel() -> void:
	if _enemy_info_label == null or enemy_ref == null:
		return

	var e_state: String = String(enemy_ref.state_machine.get_current_state_name())
	var hp_cur: float = enemy_ref.health.current_health if enemy_ref.health != null else 0.0
	var hp_max: float = enemy_ref.health.max_health if enemy_ref.health != null else 1.0
	var air_badge: String = " [color=#7fd4ff][JUGGLED %.2fm][/color]" % enemy_ref.get_height_above_ground() if enemy_ref.is_juggled_in_air else ""
	var tele_badge: String = " [color=#ff1f3d][b]!! TELEGRAPH !![/b][/color]" if enemy_ref.is_telegraphing else ""

	var text: String = "[b][color=#e8edf5]TARGET: %s[/color][/b]\n" % (enemy_ref.enemy_data.enemy_name if enemy_ref.enemy_data != null else "Vampire")
	text += "HP: [b]%.0f / %.0f[/b]  |  State: [b]%s[/b]%s%s" % [hp_cur, hp_max, e_state, tele_badge, air_badge]
	_enemy_info_label.text = text


func _update_world_panel() -> void:
	if _world_info_label == null:
		return
	var seed_str: String = SeedManager.get_debug_summary() if SeedManager != null else "SeedManager N/A"
	var phase_str: String = TimeCycleManager.get_phase_name() if TimeCycleManager != null else "N/A"
	var pause_str: String = "PAUSED" if (TimeCycleManager != null and TimeCycleManager.is_paused) else "RUNNING"
	var mouse_str: String = "CAPTURED (Esc = Cursor)" if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else "FREE CURSOR (Esc = Capture)"

	var text: String = "[b][color=#a8c5e5]WORLD & DETERMINISM[/color][/b]\n"
	text += "%s\n" % seed_str
	text += "Time Cycle: [b]%s[/b] (%s)\n" % [phase_str, pause_str]
	text += "Mouse: [color=#b4c2d4]%s[/color]" % mouse_str
	_world_info_label.text = text


func _refresh_button_labels() -> void:
	if _crt_button != null and CRTOverlay != null:
		_crt_button.text = "[F1] CRT Filter: %s" % ("ON" if CRTOverlay.crt_enabled else "OFF")
	if _class_button != null and player_ref != null and player_ref.class_data != null:
		_class_button.text = "[C] Switch Class (%s)" % player_ref.class_data.class_name_display
	if _time_pause_button != null and TimeCycleManager != null:
		_time_pause_button.text = "Time: %s" % ("Resume" if TimeCycleManager.is_paused else "Pause")


func _on_combat_event_logged(message: String) -> void:
	_event_lines.append("> " + message)
	while _event_lines.size() > 5:
		_event_lines.remove_at(0)
	if _event_log_label != null:
		_event_log_label.text = "\n".join(_event_lines)


func _on_crt_toggled(_enabled: bool) -> void:
	_refresh_button_labels()


func _on_class_button_pressed() -> void:
	switch_class_requested.emit()


func _on_crt_button_pressed() -> void:
	if CRTOverlay != null:
		CRTOverlay.toggle_crt()


func _on_seed_button_pressed() -> void:
	reroll_seed_requested.emit()


func _on_next_day_button_pressed() -> void:
	advance_day_requested.emit()


func _on_time_pause_button_pressed() -> void:
	if TimeCycleManager != null:
		TimeCycleManager.toggle_pause()
	_refresh_button_labels()


func _on_phase_button_pressed() -> void:
	if TimeCycleManager != null:
		TimeCycleManager.advance_phase()


func _on_reset_button_pressed() -> void:
	reset_arena_requested.emit()

class_name DebugHUD
extends CanvasLayer
## Live Combat Gym HUD displaying permanent gameplay elements (top-center 0-100 HP bar,
## crimson Parry cooldown circle, bottom-center 1-9 Hotbar) and toggleable diagnostic
## debug telemetry panels via the persistent Debug button or F2.

signal switch_class_requested()
signal reset_arena_requested()
signal reroll_seed_requested()
signal advance_day_requested()

@onready var _top_left_column: Control = %TopLeftColumn
@onready var _top_right_column: Control = %TopRightColumn
@onready var _bottom_left_panel: Control = %BottomLeftPanel
@onready var _controls_panel: PanelContainer = %ControlsPanel
@onready var _debug_toggle_button: Button = %DebugToggleButton

@onready var _player_info_label: RichTextLabel = %PlayerInfoLabel
@onready var _enemy_info_label: RichTextLabel = %EnemyInfoLabel
@onready var _world_info_label: RichTextLabel = %WorldInfoLabel
@onready var _event_log_label: RichTextLabel = %EventLogLabel
@onready var _crt_button: Button = %CRTButton
@onready var _class_button: Button = %ClassButton
@onready var _time_pause_button: Button = %TimePauseButton

@onready var _player_hp_header_label: Label = %PlayerHPHeaderLabel
@onready var _player_hp_delay_bar: ProgressBar = %PlayerHPDelayBar
@onready var _player_hp_bar: ProgressBar = %PlayerHPBar
@onready var _player_hp_value_label: Label = %PlayerHPValueLabel
@onready var _parry_cooldown_circle: CooldownCircleIndicator = %ParryCooldownCircle
@onready var _hotbar_equipped_label: Label = %HotbarEquippedLabel
@onready var _hotbar_slots_row: HBoxContainer = %HotbarSlotsRow

var player_ref: Player = null
var enemy_ref: VampireDuelist = null
var camera_ref: CombatCameraRig = null

var _event_lines: PackedStringArray = PackedStringArray()
var _displayed_hp_delay: float = 100.0
var _debug_visible: bool = true
var _bound_inventory: InventoryComponent = null
var _hotbar_slot_views: Array[Dictionary] = []


func _ready() -> void:
	if GameFeelManager != null and not GameFeelManager.combat_event_logged.is_connected(_on_combat_event_logged):
		GameFeelManager.combat_event_logged.connect(_on_combat_event_logged)
	if CRTOverlay != null and not CRTOverlay.crt_toggled.is_connected(_on_crt_toggled):
		CRTOverlay.crt_toggled.connect(_on_crt_toggled)
	_build_hotbar_slots()
	_set_debug_visible(true)
	_refresh_button_labels()


func bind_actors(player: Player, enemy: VampireDuelist, cam: CombatCameraRig) -> void:
	if _bound_inventory != null and is_instance_valid(_bound_inventory):
		if _bound_inventory.inventory_updated.is_connected(_on_inventory_updated):
			_bound_inventory.inventory_updated.disconnect(_on_inventory_updated)
		if _bound_inventory.selected_slot_changed.is_connected(_on_selected_slot_changed):
			_bound_inventory.selected_slot_changed.disconnect(_on_selected_slot_changed)
	_bound_inventory = null

	player_ref = player
	enemy_ref = enemy
	camera_ref = cam

	if player_ref != null and player_ref.inventory != null:
		_bound_inventory = player_ref.inventory
		_bound_inventory.inventory_updated.connect(_on_inventory_updated)
		_bound_inventory.selected_slot_changed.connect(_on_selected_slot_changed)

	_refresh_hotbar()
	_refresh_button_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud_help"):
		_set_debug_visible(not _debug_visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_top_health_bar(delta)
	_update_parry_cooldown()
	if _debug_visible:
		_update_player_panel()
		_update_enemy_panel()
		_update_world_panel()
		_refresh_button_labels()


func _set_debug_visible(visible_state: bool) -> void:
	_debug_visible = visible_state
	if _top_left_column != null:
		_top_left_column.visible = _debug_visible
	if _top_right_column != null:
		_top_right_column.visible = _debug_visible
	if _bottom_left_panel != null:
		_bottom_left_panel.visible = _debug_visible
	if _controls_panel != null:
		_controls_panel.visible = _debug_visible
	if _debug_toggle_button != null:
		_debug_toggle_button.text = "[F2] Debug: %s" % ("ON" if _debug_visible else "OFF")


func _update_top_health_bar(delta: float) -> void:
	if player_ref == null or player_ref.health == null:
		return
	var hp_cur: float = clampf(player_ref.health.current_health, 0.0, 100.0)
	var hp_max: float = maxf(1.0, player_ref.health.max_health)
	var hp_scaled: float = clampf((hp_cur / hp_max) * 100.0, 0.0, 100.0)
	if _displayed_hp_delay < hp_scaled:
		_displayed_hp_delay = hp_scaled
	else:
		_displayed_hp_delay = move_toward(_displayed_hp_delay, hp_scaled, 38.0 * delta)

	if _player_hp_bar != null:
		_player_hp_bar.value = hp_scaled
	if _player_hp_delay_bar != null:
		_player_hp_delay_bar.value = _displayed_hp_delay
	if _player_hp_value_label != null:
		_player_hp_value_label.text = "%d / 100" % int(round(hp_scaled))
	if _player_hp_header_label != null:
		var cls_name: String = player_ref.class_data.class_name_display.to_upper() if player_ref.class_data != null else "HUNTER"
		_player_hp_header_label.text = "%s" % cls_name


func _update_parry_cooldown() -> void:
	if _parry_cooldown_circle == null or player_ref == null:
		return
	var cd_total: float = player_ref.class_data.special_skill_cooldown if player_ref.class_data != null else 3.0
	_parry_cooldown_circle.set_cooldown_state(player_ref.skill_cooldown_remaining, cd_total)


func _build_hotbar_slots() -> void:
	if _hotbar_slots_row == null:
		return
	_hotbar_slot_views.clear()
	for i: int in range(9):
		var slot_btn: Button = Button.new()
		slot_btn.custom_minimum_size = Vector2(46, 46)
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.clip_contents = true

		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.07, 0.10, 0.88)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.28, 0.32, 0.42, 0.75)
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_right = 3
		style.corner_radius_bottom_left = 3

		var hover_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.11, 0.12, 0.16, 0.92)
		slot_btn.add_theme_stylebox_override("normal", style)
		slot_btn.add_theme_stylebox_override("hover", hover_style)
		slot_btn.add_theme_stylebox_override("pressed", hover_style)

		var num_lbl: Label = Label.new()
		num_lbl.text = str(i + 1)
		num_lbl.position = Vector2(4, 2)
		num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num_lbl.add_theme_font_size_override("font_size", 10)
		num_lbl.add_theme_color_override("font_color", Color(0.68, 0.74, 0.84, 0.85))
		slot_btn.add_child(num_lbl)

		var tag_lbl: Label = Label.new()
		tag_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_lbl.add_theme_font_size_override("font_size", 11)
		tag_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
		slot_btn.add_child(tag_lbl)

		var qty_lbl: Label = Label.new()
		qty_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty_lbl.offset_left = -22
		qty_lbl.offset_top = -16
		qty_lbl.offset_right = -3
		qty_lbl.offset_bottom = -3
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_lbl.add_theme_font_size_override("font_size", 10)
		qty_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.65, 1.0))
		slot_btn.add_child(qty_lbl)

		var accent_bar: ColorRect = ColorRect.new()
		accent_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		accent_bar.offset_top = -4
		accent_bar.offset_left = 2
		accent_bar.offset_right = -2
		accent_bar.offset_bottom = -1
		accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		accent_bar.color = Color(0, 0, 0, 0)
		slot_btn.add_child(accent_bar)

		slot_btn.pressed.connect(_on_hotbar_slot_clicked.bind(i))
		_hotbar_slots_row.add_child(slot_btn)

		_hotbar_slot_views.append({
			"button": slot_btn,
			"style": style,
			"hover_style": hover_style,
			"num_label": num_lbl,
			"tag_label": tag_lbl,
			"qty_label": qty_lbl,
			"accent_bar": accent_bar,
		})


func _refresh_hotbar() -> void:
	if _bound_inventory == null or _hotbar_slot_views.is_empty():
		return
	var selected_idx: int = _bound_inventory.selected_hotbar_index
	for i: int in range(mini(9, _hotbar_slot_views.size())):
		var view: Dictionary = _hotbar_slot_views[i]
		var slot: InventorySlotData = _bound_inventory.get_hotbar_slot(i)
		var is_sel: bool = (i == selected_idx)
		var style: StyleBoxFlat = view["style"] as StyleBoxFlat
		var hover_style: StyleBoxFlat = view["hover_style"] as StyleBoxFlat
		var tag_lbl: Label = view["tag_label"] as Label
		var qty_lbl: Label = view["qty_label"] as Label
		var num_lbl: Label = view["num_label"] as Label
		var accent_bar: ColorRect = view["accent_bar"] as ColorRect

		if is_sel:
			style.bg_color = Color(0.16, 0.06, 0.09, 0.95)
			style.border_color = Color(0.95, 0.16, 0.26, 1.0)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			num_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.52, 1.0))
		else:
			style.bg_color = Color(0.06, 0.07, 0.10, 0.86)
			style.border_color = Color(0.28, 0.32, 0.42, 0.72)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			num_lbl.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78, 0.78))
		hover_style.border_color = style.border_color

		if slot != null and not slot.is_empty():
			tag_lbl.text = slot.item.short_tag
			tag_lbl.add_theme_color_override("font_color", Color(0.98, 0.96, 0.98, 1.0))
			accent_bar.color = slot.item.accent_color
			qty_lbl.text = str(slot.quantity) if slot.quantity > 1 else ""
		else:
			tag_lbl.text = ""
			accent_bar.color = Color(0, 0, 0, 0)
			qty_lbl.text = ""

	if _hotbar_equipped_label != null:
		var sel_slot: InventorySlotData = _bound_inventory.get_selected_slot()
		var item_str: String = sel_slot.item.display_name if (sel_slot != null and not sel_slot.is_empty()) else "Empty Hand"
		_hotbar_equipped_label.text = "%d // %s" % [selected_idx + 1, item_str]


func _on_hotbar_slot_clicked(index: int) -> void:
	if _bound_inventory != null:
		_bound_inventory.select_hotbar_slot(index)


func _on_inventory_updated() -> void:
	_refresh_hotbar()


func _on_selected_slot_changed(_slot_index: int, _slot: InventorySlotData) -> void:
	_refresh_hotbar()


func _update_player_panel() -> void:
	if _player_info_label == null or player_ref == null:
		return

	var cls: HunterClassData = player_ref.class_data
	var wpn: WeaponData = player_ref.current_weapon
	var state_name: String = "DEAD" if player_ref.is_dead else String(player_ref.state_machine.get_current_state_name())
	var height: float = player_ref.get_height_above_ground()
	var h_speed: float = player_ref.get_horizontal_speed()
	var slide_thresh: float = cls.slide_min_speed if cls != null else 8.4
	var speed_badge: String = ""
	if player_ref.is_sliding:
		speed_badge = " [color=#56e0ff][SLIDING][/color]"
	elif player_ref.is_backflip_dodge:
		speed_badge = " [color=#ff4d88][BACKFLIP][/color]"
	elif player_ref.can_slide():
		speed_badge = " [color=#6bff95][SLIDE READY - CTRL][/color]"
	else:
		speed_badge = " [color=#7d8da3](Slide >= %.1f)[/color]" % slide_thresh
	var air_str: String = "[color=#7fd4ff]AIRBORNE (%.2fm)[/color]" % height if not player_ref.is_on_floor() else "[color=#d8e4f0]GROUNDED (%.2fm)[/color]" % height
	var iframe_str: String = " [color=#ff4d6d][I-FRAMES][/color]" if (player_ref.health != null and player_ref.health.is_invulnerable) else ""
	var lock_str: String = "[color=#ff3b5c]LOCKED[/color]" if (camera_ref != null and camera_ref.locked_target != null) else "Free"
	var skill_cd: String = "READY" if player_ref.skill_cooldown_remaining <= 0.01 else "%.1fs" % player_ref.skill_cooldown_remaining
	var hp_cur: float = player_ref.health.current_health if player_ref.health != null else 0.0
	var hp_max: float = player_ref.health.max_health if player_ref.health != null else 1.0

	var cancel_color: String = "#ffbe3b" if player_ref.cancel_window_status.begins_with("CANCEL") else "#a6b5c8"
	var jumps_used: int = player_ref.combat_comp.jumps_used if player_ref.combat_comp != null else 0
	var max_jumps: int = player_ref.combat_comp.max_jumps if player_ref.combat_comp != null else 2
	var dodge_chain: int = player_ref.combat_comp.consecutive_dodges if player_ref.combat_comp != null else 0
	var dodge_limit: int = player_ref.combat_comp.dodge_spam_limit if player_ref.combat_comp != null else 5
	var buff_count: int = player_ref.modifiers.get_active_count() if player_ref.modifiers != null else 0
	var tdm: Node = get_tree().root.get_node_or_null("TimeDilationManager")
	var wt_active: bool = tdm != null and bool(tdm.get("is_witch_time_active"))
	var wt_str: String = "[color=#c57bff][b]WITCH TIME %.1fs (%.2fx)[/b][/color]" % [float(tdm.get("witch_time_remaining")), float(tdm.get("world_time_scale"))] if wt_active else "Normal (1.00x)"

	var text: String = ""
	text += "[b][color=#ff2e4c]BLOOD WINTER // COMBAT GYM[/color][/b]\n"
	text += "Class: [b]%s[/b]  |  Weapon: [b]%s[/b]\n" % [
		cls.class_name_display if cls != null else "None",
		wpn.weapon_name if wpn != null else "Unarmed",
	]
	if cls != null:
		text += "Skill [F]: [color=#ff6680]%s[/color] (%s)  |  Loot x%.2f  ID +%.0f%%\n" % [
			cls.special_skill_name,
			skill_cd,
			cls.loot_bonus_multiplier,
			cls.identification_bonus * 100.0,
		]
	text += "HP: [b]%.0f / %.0f[/b]  |  Target: %s\n" % [hp_cur, hp_max, lock_str]
	text += "State: [b][color=#eef6ff]%s[/color][/b]%s  |  World: %s\n" % [state_name, iframe_str, wt_str]
	text += "Speed: [b]%.1f m/s[/b]%s\n" % [h_speed, speed_badge]
	text += "Jumps: [b]%d/%d[/b]  |  Dodge Chain: [b]%d/%d[/b]  |  Buffs: [b]%d[/b]\n" % [jumps_used, max_jumps, dodge_chain, dodge_limit, buff_count]
	text += "Combo Step: [b][color=#ff6b81]%s[/color][/b]\n" % player_ref.current_combo_label
	text += "Window: [color=%s]%s[/color]\n" % [cancel_color, player_ref.cancel_window_status]
	text += "Air/Height: %s" % air_str
	_player_info_label.text = text


func _update_enemy_panel() -> void:
	if _enemy_info_label == null or enemy_ref == null:
		return

	var e_state: String = "DEAD" if enemy_ref.is_dead else String(enemy_ref.state_machine.get_current_state_name())
	var hp_cur: float = enemy_ref.health.current_health if enemy_ref.health != null else 0.0
	var hp_max: float = enemy_ref.health.max_health if enemy_ref.health != null else 1.0
	var air_badge: String = " [color=#7fd4ff][JUGGLED %.2fm][/color]" % enemy_ref.get_height_above_ground() if enemy_ref.is_juggled_in_air else ""
	var tele_badge: String = " [color=#ff1f3d][b]!! TELEGRAPH !![/b][/color]" if enemy_ref.is_telegraphing else ""

	var text: String = "[b][color=#e8edf5]TARGET: %s[/color][/b]\n" % (enemy_ref.enemy_data.enemy_name if enemy_ref.enemy_data != null else "Vampire")
	text += "HP: [b]%.0f / %.0f[/b]  |  State: [b]%s[/b]%s%s\n" % [hp_cur, hp_max, e_state, tele_badge, air_badge]
	if enemy_ref.reaction_component != null:
		var rc: EnemyReactionComponent = enemy_ref.reaction_component
		var max_poise: float = enemy_ref.enemy_data.max_poise if enemy_ref.enemy_data != null else 65.0
		var poise_str: String = "[color=#ffbe3b][DIZZY][/color]" if rc.is_dizzy else "%.0f/%.0f" % [rc.current_poise, max_poise]
		text += "Reaction: [b]%s[/b]  |  Poise: %s\n" % [rc.get_state_name(), poise_str]
		text += "Juggle N: [b]%d[/b]  |  Grav: %.2fx  |  Decay: %.0f%%" % [
			rc.combo_hit_count,
			rc.get_current_juggle_gravity_scale(),
			rc.get_current_hitstun_multiplier() * 100.0,
		]
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


func _on_debug_toggle_button_pressed() -> void:
	_set_debug_visible(not _debug_visible)


func _on_main_menu_button_pressed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")


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

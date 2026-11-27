class_name PlayerDodgeState
extends PlayerState
## Primary defensive tool: rapid burst dash with true i-frames and fading ghost trail.

var _elapsed: float = 0.0
var _ghost_timer: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD
var _started_in_air: bool = false
var _is_backflip: bool = false
var _is_stumble: bool = false
var _effective_duration: float = 0.26
var _effective_iframe_dur: float = 0.22


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_ghost_timer = 0.0
	_started_in_air = not player.is_on_floor()
	if _started_in_air:
		player.air_dodge_used = true

	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	if move_dir.length_squared() > 0.01:
		_dash_dir = move_dir
	else:
		_dash_dir = player.get_facing_direction()

	_is_stumble = player.combat_comp.register_dodge() if player.combat_comp != null else false

	if _is_stumble:
		# Anti-Mash Penalty (5 consecutive dodges without attacking): unmistakable stumble/trip without i-frames
		_is_backflip = false
		player.is_backflip_dodge = false
		player.face_direction(_dash_dir, 100.0, 1.0)
		player.health.is_invulnerable = false
		_effective_iframe_dur = 0.0
		var base_stumble: float = player.combat_comp.dodge_stumble_duration if player.combat_comp != null else 0.72
		_effective_duration = maxf(base_stumble, 0.72)
		player.dodge_cooldown_remaining = player.class_data.dodge_cooldown * 1.6
		player.set_combo_debug_label("DODGE STUMBLE (No i-frames!)")
		player.cancel_window_status = "SPAM PENALTY (STUMBLE)"
		var stumble_speed: float = 1.15
		if player.model_anim_player != null and player.model_anim_player.has_animation(&"Dodge_Stumble"):
			var stumble_len: float = player.model_anim_player.get_animation(&"Dodge_Stumble").length
			if stumble_len > 0.05:
				stumble_speed = clampf(stumble_len / _effective_duration, 0.85, 1.35)
		player.play_character_animation(&"Dodge_Stumble", stumble_speed, 0.08, true)
		if GameFeelManager != null:
			GameFeelManager.request_screen_shake(0.16, 0.14)
			GameFeelManager.log_combat_event("DODGE SPAM PENALTY (5x) -> Tripped / Stumbled (No i-frames)!")
		return

	_is_backflip = player.should_backflip_dodge(_dash_dir)
	player.is_backflip_dodge = _is_backflip
	_effective_duration = maxf(player.class_data.dodge_duration * 1.75, 0.46) if _is_backflip else player.class_data.dodge_duration
	var bonus_iframes: float = player.modifiers.get_additive(&"dodge_iframe_bonus") if player.modifiers != null else 0.0
	_effective_iframe_dur = player.class_data.dodge_iframe_duration + bonus_iframes
	if _is_backflip:
		_effective_iframe_dur = maxf(_effective_iframe_dur, _effective_duration * 0.68)

	if _is_backflip:
		if not player.face_locked_target(100.0, 1.0):
			player.face_direction(-_dash_dir, 100.0, 1.0)
	else:
		player.face_direction(_dash_dir, 100.0, 1.0)
		if player.camera_rig != null and player.camera_rig.locked_target != null and is_instance_valid(player.camera_rig.locked_target):
			player.face_locked_or_input_immediately()

	player.health.is_invulnerable = true
	player.dodge_cooldown_remaining = player.class_data.dodge_cooldown
	player.set_combo_debug_label("Backflip Dodge (i-frames)" if _is_backflip else "Dodge (i-frames)")
	player.cancel_window_status = "BACKFLIP I-FRAMES" if _is_backflip else "I-FRAMES"

	# Check Perfect Dodge Witch Time trigger against enemies in their telegraph/parry window
	if player.combat_comp != null:
		player.combat_comp.try_trigger_witch_time(
			player.global_position,
			player.get_tree().get_nodes_in_group("enemies"),
			player.modifiers,
			false
		)

	if _is_backflip:
		var anim_speed: float = 1.45
		if player.model_anim_player != null and player.model_anim_player.has_animation(&"Slide_Backflip"):
			var anim_len: float = player.model_anim_player.get_animation(&"Slide_Backflip").length
			if anim_len > 0.05:
				anim_speed = clampf(anim_len / _effective_duration, 1.0, 1.65)
		player.play_character_animation(&"Slide_Backflip", anim_speed, 0.09, true)
	else:
		player.play_character_animation(&"Dodge", 1.25, 0.10, true)
	player.spawn_dodge_ghost(Color(0.95, 0.14, 0.24, 0.60), 0.24)
	if player.weapon_trail != null:
		player.weapon_trail.emitting = true


func exit() -> void:
	if player != null:
		player.is_backflip_dodge = false
		if player.combat_comp != null:
			player.combat_comp.is_stumbling = false
		player.health.is_invulnerable = false
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false


func physics_update(delta: float) -> void:
	_elapsed += delta
	_ghost_timer += delta

	if _is_stumble:
		var stumble_speed: float = player.get_effective_move_speed() * 0.45 * (1.0 - clampf(_elapsed / _effective_duration, 0.0, 1.0))
		player.velocity.x = _dash_dir.x * stumble_speed
		player.velocity.z = _dash_dir.z * stumble_speed
		player.velocity.y = -2.0 if player.is_on_floor() else player.velocity.y - Player.GRAVITY * delta
		player.move_and_slide()
		if _elapsed >= _effective_duration:
			request_transition(&"Idle" if player.is_on_floor() else &"Air")
		return

	# Disable i-frames once the configured window expires
	if _elapsed >= _effective_iframe_dur:
		player.health.is_invulnerable = false
		player.cancel_window_status = "Recovery"

	if _ghost_timer >= 0.065:
		_ghost_timer = 0.0
		player.spawn_dodge_ghost(Color(0.85, 0.12, 0.22, 0.42), 0.20)

	var dash_speed: float = player.get_effective_move_speed() * player.class_data.dodge_speed_multiplier
	# Preserve healthy exit momentum so Dodge chains naturally into Move, Dash-Jump, or Dash-Slide
	var t: float = clampf(_elapsed / maxf(0.05, _effective_duration), 0.0, 1.0)
	var current_speed: float = dash_speed * lerpf(1.12, 0.78, t * t)

	player.velocity.x = _dash_dir.x * current_speed
	player.velocity.z = _dash_dir.z * current_speed
	if _started_in_air:
		player.velocity.y = move_toward(player.velocity.y, 0.0, 18.0 * delta)
	else:
		player.velocity.y = -2.0

	player.move_and_slide()

	# Deadlock-style Dash-Jump: jump mid-dash to launch forward with preserved dash speed
	if t >= 0.32 and t <= 0.92 and player.is_on_floor() and player.consume_buffered_action(&"jump"):
		if player.combat_comp != null:
			player.combat_comp.consume_jump(true)
		var carry_speed: float = minf(dash_speed * 0.96, player.class_data.slide_max_speed)
		player.velocity.x = _dash_dir.x * carry_speed
		player.velocity.z = _dash_dir.z * carry_speed
		player.velocity.y = player.class_data.jump_velocity
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("DASH-JUMP! (%.1f m/s momentum)" % carry_speed)
		request_transition(&"Air")
		return

	# Deadlock-style Dash-Slide: press/hold CTRL to convert dash burst into a low-friction slide
	if t >= 0.42 and player.is_on_floor():
		if player.consume_buffered_action(&"slide") or (t >= 0.72 and player.is_holding_slide()):
			var slide_carry: float = maxf(current_speed, dash_speed * 0.90)
			request_transition(&"Slide", {"direction": _dash_dir, "speed": slide_carry})
			return

	# Allow crisp attack cancel out of the final 25% of dodge recovery
	if t >= 0.72 and player.current_weapon != null:
		if player.consume_buffered_action(&"attack_launcher") and player.is_on_floor():
			request_transition(&"Attack", {"mode": &"launcher", "index": 0, "preserve_speed": current_speed * 0.65})
			return
		if player.consume_buffered_action(&"attack_light"):
			if player.is_on_floor():
				request_transition(&"Attack", {"mode": &"ground", "index": 0, "preserve_speed": current_speed * 0.65})
			elif not player.air_combo_used:
				request_transition(&"Attack", {"mode": &"air", "index": 0})
			return

	if _elapsed >= _effective_duration:
		if not player.is_on_floor():
			request_transition(&"Air")
		elif player.is_holding_slide() and player.can_slide(current_speed):
			request_transition(&"Slide", {"direction": _dash_dir, "speed": current_speed})
		elif player.get_camera_relative_move_direction().length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")

class_name PlayerSlideState
extends PlayerState
## Deadlock-inspired momentum-preserving ground slide (CTRL).
## - Always plays the consistent low-profile `Slide` animation in every direction.
## - Requires horizontal speed >= slide_min_speed on flat ground, OR any slope.
## - Preserves speed with minimal friction for `slide_preserve_duration` (~0.75s),
##   then ramps up friction on flat ground. Downhill slopes accelerate and refresh preservation.
## - Supports Slide-Jump (Slide-Hop), Slide-Attack, Dodge-Cancel, and Skill-Cancel.

var _elapsed: float = 0.0
var _flat_slide_timer: float = 0.0
var _slide_dir: Vector3 = Vector3.FORWARD
var _slide_speed: float = 0.0
var _ghost_timer: float = 0.0


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_flat_slide_timer = 0.0
	_ghost_timer = 0.0

	var horiz_vel: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var entry_speed: float = horiz_vel.length()

	if data.has("direction") and (data["direction"] as Vector3).length_squared() > 0.01:
		_slide_dir = (data["direction"] as Vector3).normalized()
	elif entry_speed > 0.25:
		_slide_dir = horiz_vel.normalized()
	else:
		var move_dir: Vector3 = player.get_camera_relative_move_direction()
		_slide_dir = move_dir if move_dir.length_squared() > 0.01 else player.get_facing_direction()

	if data.has("speed"):
		entry_speed = maxf(entry_speed, float(data["speed"]))

	var cls: HunterClassData = player.class_data
	var min_spd: float = cls.slide_min_speed if cls != null else 8.4
	var max_spd: float = cls.slide_max_speed if cls != null else 20.5
	var boost: float = cls.slide_entry_boost if cls != null else 1.08

	if entry_speed <= min_spd * 1.25:
		_slide_speed = clampf(maxf(entry_speed, min_spd) * boost, min_spd, max_spd)
	else:
		_slide_speed = clampf(entry_speed, min_spd, max_spd)

	player.is_sliding = true
	if not player.face_locked_target(100.0, 1.0):
		player.face_direction(_slide_dir, 100.0, 1.0)

	player.set_combo_debug_label("Ground Slide (Momentum)")
	player.cancel_window_status = "SLIDE PRESERVE"
	player.play_character_animation(&"Slide", 1.0, 0.14, true)

	player.velocity.x = _slide_dir.x * _slide_speed
	player.velocity.z = _slide_dir.z * _slide_speed
	player.spawn_dodge_ghost(Color(0.55, 0.85, 1.0, 0.45), 0.20)


func exit() -> void:
	if player != null:
		player.is_sliding = false
		var cls: HunterClassData = player.class_data
		player.slide_cooldown_remaining = cls.slide_cooldown if cls != null else 0.14
		player.cancel_window_status = "-"


func physics_update(delta: float) -> void:
	_elapsed += delta
	_ghost_timer += delta

	var cls: HunterClassData = player.class_data
	var preserve_dur: float = cls.slide_preserve_duration if cls != null else 0.75
	var low_fric: float = cls.slide_low_friction if cls != null else 1.35
	var high_fric: float = cls.slide_high_friction if cls != null else 13.5
	var slope_accel: float = cls.slide_slope_accel if cls != null else 24.0
	var exit_spd: float = cls.slide_exit_speed if cls != null else 4.2
	var max_spd: float = cls.slide_max_speed if cls != null else 20.5

	# 1) Responsive Cancellations (Preserving full horizontal momentum!)
	if player.consume_buffered_action(&"jump") and player.is_on_floor():
		var hop_speed: float = clampf(_slide_speed * 1.04, cls.move_speed, max_spd)
		player.velocity.x = _slide_dir.x * hop_speed
		player.velocity.z = _slide_dir.z * hop_speed
		player.velocity.y = cls.jump_velocity
		if GameFeelManager != null:
			GameFeelManager.log_combat_event("SLIDE-HOP! (%.1f m/s preserved)" % hop_speed)
		request_transition(&"Air")
		return

	if player.consume_buffered_action(&"dodge") and player.can_dodge():
		request_transition(&"Dodge")
		return

	if player.consume_buffered_action(&"class_skill") and player.can_use_skill():
		request_transition(&"Skill")
		return

	if player.current_weapon != null and player.consume_buffered_action(&"attack_launcher"):
		request_transition(&"Attack", {"mode": &"launcher", "index": 0, "preserve_speed": _slide_speed * 0.70})
		return

	if player.current_weapon != null and player.consume_buffered_action(&"attack_light"):
		request_transition(&"Attack", {"mode": &"ground", "index": 0, "preserve_speed": _slide_speed * 0.72})
		return

	# 2) Subtle steering control while sliding
	var move_dir: Vector3 = player.get_camera_relative_move_direction()
	if move_dir.length_squared() > 0.01:
		_slide_dir = _slide_dir.slerp(move_dir, clampf(1.65 * delta, 0.0, 1.0)).normalized()

	# 3) Slope gravity interaction & Deadlock friction curve
	var on_floor: bool = player.is_on_floor()
	var slope_dot: float = 0.0
	if on_floor:
		var floor_normal: Vector3 = player.get_floor_normal()
		var downhill_vec: Vector3 = Vector3(floor_normal.x, 0.0, floor_normal.z)
		var slope_steepness: float = downhill_vec.length()
		if slope_steepness > 0.05:
			slope_dot = downhill_vec.normalized().dot(_slide_dir) * slope_steepness

	if slope_dot > 0.04:
		_slide_speed = minf(max_spd, _slide_speed + slope_accel * slope_dot * delta)
		_flat_slide_timer = maxf(0.0, _flat_slide_timer - delta * 1.5)
		player.cancel_window_status = "SLOPE BOOST (%.1f m/s)" % _slide_speed
	else:
		_flat_slide_timer += delta
		var uphill_penalty: float = maxf(0.0, -slope_dot) * slope_accel * 1.4
		if _flat_slide_timer <= preserve_dur:
			_slide_speed = maxf(0.0, _slide_speed - (low_fric + uphill_penalty) * delta)
			player.cancel_window_status = "PRESERVE %.1f m/s" % _slide_speed
		else:
			var ramp_t: float = clampf((_flat_slide_timer - preserve_dur) / 0.45, 0.0, 1.0)
			var friction: float = lerpf(low_fric, high_fric, ramp_t) + uphill_penalty
			_slide_speed = maxf(0.0, _slide_speed - friction * delta)
			player.cancel_window_status = "FRICTION %.1f m/s" % _slide_speed

	# 4) Apply velocity & facing
	player.velocity.x = _slide_dir.x * _slide_speed
	player.velocity.z = _slide_dir.z * _slide_speed
	if on_floor:
		player.velocity.y = -3.0
	else:
		player.velocity.y -= Player.GRAVITY * delta

	if not player.face_locked_target(16.0, delta):
		player.face_direction(_slide_dir, 12.0, delta)

	player.move_and_slide()

	if _slide_speed >= 10.5 and _ghost_timer >= 0.085:
		_ghost_timer = 0.0
		player.spawn_dodge_ghost(Color(0.65, 0.88, 1.0, 0.34), 0.18)

	# 5) Exit conditions
	if not player.is_on_floor() and _elapsed > 0.08:
		request_transition(&"Air")
		return

	var holding_ctrl: bool = player.is_holding_slide()
	if _slide_speed <= exit_spd or (_elapsed >= 0.18 and not holding_ctrl):
		if move_dir.length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")

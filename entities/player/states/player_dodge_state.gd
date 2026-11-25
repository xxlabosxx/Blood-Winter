class_name PlayerDodgeState
extends PlayerState
## Primary defensive tool: rapid burst dash with true i-frames and fading ghost trail.

var _elapsed: float = 0.0
var _ghost_timer: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD
var _started_in_air: bool = false


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

	player.face_direction(_dash_dir, 100.0, 1.0)
	player.health.is_invulnerable = true
	player.dodge_cooldown_remaining = player.class_data.dodge_cooldown
	player.set_combo_debug_label("Dodge (i-frames)")
	player.cancel_window_status = "I-FRAMES"
	player.spawn_dodge_ghost(Color(0.95, 0.14, 0.24, 0.60), 0.24)
	if player.weapon_trail != null:
		player.weapon_trail.emitting = true


func exit() -> void:
	if player != null:
		player.health.is_invulnerable = false
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false


func physics_update(delta: float) -> void:
	_elapsed += delta
	_ghost_timer += delta

	# Disable i-frames once the configured window expires
	if _elapsed >= player.class_data.dodge_iframe_duration:
		player.health.is_invulnerable = false
		player.cancel_window_status = "Recovery"

	if _ghost_timer >= 0.065:
		_ghost_timer = 0.0
		player.spawn_dodge_ghost(Color(0.85, 0.12, 0.22, 0.42), 0.20)

	var dash_speed: float = player.class_data.move_speed * player.class_data.dodge_speed_multiplier
	# Slight ease-out near end of dodge for snappy control
	var t: float = clampf(_elapsed / maxf(0.05, player.class_data.dodge_duration), 0.0, 1.0)
	var current_speed: float = dash_speed * lerpf(1.12, 0.55, t * t)

	player.velocity.x = _dash_dir.x * current_speed
	player.velocity.z = _dash_dir.z * current_speed
	if _started_in_air:
		player.velocity.y = move_toward(player.velocity.y, 0.0, 18.0 * delta)
	else:
		player.velocity.y = -2.0

	player.move_and_slide()

	# Allow crisp attack cancel out of the final 25% of dodge recovery
	if t >= 0.72:
		if player.consume_buffered_action(&"attack_launcher") and player.is_on_floor():
			request_transition(&"Attack", {"mode": &"launcher", "index": 0})
			return
		if player.consume_buffered_action(&"attack_light"):
			if player.is_on_floor():
				request_transition(&"Attack", {"mode": &"ground", "index": 0})
			elif not player.air_combo_used:
				request_transition(&"Attack", {"mode": &"air", "index": 0})
			return

	if _elapsed >= player.class_data.dodge_duration:
		if not player.is_on_floor():
			request_transition(&"Air")
		elif player.get_camera_relative_move_direction().length_squared() > 0.01:
			request_transition(&"Move")
		else:
			request_transition(&"Idle")

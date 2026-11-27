class_name PlayerHitstunState
extends PlayerState

var _elapsed: float = 0.0
var _duration: float = 0.28
var _is_heavy_blowback: bool = false


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_duration = 0.28
	_is_heavy_blowback = false

	var info: DamageInfo = data.get("info", null) as DamageInfo
	if info != null:
		if info.hitstun_duration > 0.0:
			_duration = info.hitstun_duration
		player.velocity.x = info.knockback_vector.x
		player.velocity.z = info.knockback_vector.z
		if info.launch_force > 0.0:
			player.velocity.y = info.launch_force
		_is_heavy_blowback = info.is_launcher or info.launch_force >= 5.0 or info.knockback_vector.length() >= 11.0
		if _is_heavy_blowback:
			_duration = maxf(_duration, 0.48)

	player.set_combo_debug_label("Launched!" if _is_heavy_blowback else "Hitstun")
	player.cancel_window_status = "BLOWBACK" if _is_heavy_blowback else "Staggered"
	player.play_character_animation(&"Hitstun", 0.9 if _is_heavy_blowback else 1.1, 0.10, true)


func physics_update(delta: float) -> void:
	_elapsed += delta
	var airborne: bool = not player.is_on_floor()
	var drag: float = 3.2 if (airborne or _is_heavy_blowback) else 20.0
	player.velocity.x = move_toward(player.velocity.x, 0.0, drag * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, drag * delta)
	if airborne:
		player.velocity.y -= Player.GRAVITY * delta
	elif player.velocity.y < 0.0:
		player.velocity.y = -1.0
	player.move_and_slide()

	# Allow panic dodge cancel late in hitstun
	if _elapsed >= _duration * 0.72 and player.can_dodge() and player.consume_buffered_action(&"dodge"):
		request_transition(&"Dodge")
		return

	if _elapsed >= _duration:
		request_transition(&"Idle" if player.is_on_floor() else &"Air")

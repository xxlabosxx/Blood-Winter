class_name VampireEvadeState
extends VampireState
## Sharp tactical lateral/backstep evade with crimson afterimages.

var _elapsed: float = 0.0
var _ghost_timer: float = 0.0
var _evade_dir: Vector3 = Vector3.BACK


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_ghost_timer = 0.0
	vampire.evade_cooldown_remaining = vampire.enemy_data.evade_cooldown
	vampire.set_telegraph_active(false, 0.0)

	var to_player: Vector3 = vampire.get_direction_to_player_flat()
	var strafe_sign: float = float(data.get("strafe_sign", 1.0))
	var right_dir: Vector3 = Vector3(-to_player.z, 0.0, to_player.x) * strafe_sign
	_evade_dir = (right_dir * 0.8 - to_player * 0.6).normalized()
	vampire.play_timed_vampire_animation(&"Evade", vampire.enemy_data.evade_duration, 0.10, true)
	vampire.spawn_evade_ghost()


func physics_update(delta: float) -> void:
	_elapsed += delta
	_ghost_timer += delta
	if _ghost_timer >= 0.06:
		_ghost_timer = 0.0
		vampire.spawn_evade_ghost()

	var to_player: Vector3 = vampire.get_direction_to_player_flat()
	vampire.face_direction(to_player, 14.0, delta)

	vampire.velocity.x = _evade_dir.x * vampire.enemy_data.evade_speed
	vampire.velocity.z = _evade_dir.z * vampire.enemy_data.evade_speed
	if not vampire.is_on_floor():
		vampire.velocity.y -= VampireDuelist.GRAVITY * delta
	else:
		vampire.velocity.y = -1.0

	vampire.move_and_slide()

	if _elapsed >= vampire.enemy_data.evade_duration:
		# Immediately threaten with a counter-lunge if cooldown allows
		if vampire.attack_cooldown_remaining <= 0.0 and vampire.get_distance_to_player() <= vampire.enemy_data.attack_range * 1.45:
			request_transition(&"Attack")
		else:
			request_transition(&"Strafe")

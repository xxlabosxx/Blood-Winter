class_name VampireHitstunState
extends VampireState
## Handles grounded stagger, knockback, vertical launch, and airborne juggle suspension.

var _elapsed: float = 0.0
var _duration: float = 0.36
var _airborne_juggle: bool = false


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_duration = vampire.enemy_data.hitstun_duration
	vampire.set_telegraph_active(false, 0.0)
	if vampire.hitbox != null:
		vampire.hitbox.deactivate()
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = false

	var info: DamageInfo = data.get("info", null) as DamageInfo
	if info != null:
		var kb_scale: float = 1.0 - clampf(vampire.enemy_data.knockback_resistance, 0.0, 0.85)
		vampire.velocity.x = info.knockback_vector.x * kb_scale
		vampire.velocity.z = info.knockback_vector.z * kb_scale

		if info.is_launcher or info.launch_force > 4.0:
			vampire.velocity.y = info.launch_force
			_airborne_juggle = true
			_duration = maxf(_duration, 0.55)
		elif info.is_aerial:
			if info.launch_force < 0.0:
				# Aerial slam finisher (Helmbreaker / Eclipse Plunge)
				vampire.velocity.y = info.launch_force
				_airborne_juggle = false
			else:
				# Keep vampire briefly suspended mid-air during player aerial combos!
				vampire.velocity.y = maxf(vampire.velocity.y * 0.25, vampire.enemy_data.air_juggle_hover_impulse)
				_airborne_juggle = true
				_duration = maxf(_duration, 0.45)
		elif not vampire.is_on_floor():
			vampire.velocity.y = maxf(vampire.velocity.y, vampire.enemy_data.air_juggle_hover_impulse * 0.75)
			_airborne_juggle = true
		elif info.launch_force > 0.0:
			vampire.velocity.y = info.launch_force

	vampire.is_juggled_in_air = _airborne_juggle or not vampire.is_on_floor()


func exit() -> void:
	if vampire != null:
		vampire.is_juggled_in_air = false


func physics_update(delta: float) -> void:
	_elapsed += delta
	var drag: float = 6.5 if not vampire.is_on_floor() else 18.0
	vampire.velocity.x = move_toward(vampire.velocity.x, 0.0, drag * delta)
	vampire.velocity.z = move_toward(vampire.velocity.z, 0.0, drag * delta)

	if not vampire.is_on_floor():
		var grav_scale: float = vampire.enemy_data.gravity_scale_when_juggled if (_airborne_juggle and vampire.velocity.y < 3.5) else 1.0
		vampire.velocity.y -= VampireDuelist.GRAVITY * grav_scale * delta
	else:
		if _airborne_juggle and _elapsed > 0.12:
			_airborne_juggle = false
		vampire.velocity.y = -1.0

	vampire.is_juggled_in_air = not vampire.is_on_floor()
	vampire.move_and_slide()

	if vampire.is_on_floor() and _elapsed >= _duration:
		# Tactical wake-up evade if hunter stays right on top of the vampire
		if vampire.evade_cooldown_remaining <= 0.0 and vampire.get_distance_to_player() < 2.6 and vampire.roll_chance(0.55):
			request_transition(&"Evade")
		else:
			request_transition(&"Strafe")

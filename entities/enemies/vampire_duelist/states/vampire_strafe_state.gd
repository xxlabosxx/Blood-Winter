class_name VampireStrafeState
extends VampireState
## Tactical spacing state: circles the Hunter, closes distance, evades pressure,
## and commits to telegraphed lethal lunges.

var _strafe_sign: float = 1.0
var _rethink_timer: float = 0.0


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_strafe_sign = -1.0 if vampire.roll_chance(0.5) else 1.0
	_rethink_timer = vampire.randf_range_val(0.65, 1.35)
	vampire.set_telegraph_active(false, 0.0)
	vampire.reset_weapon_pose()


func physics_update(delta: float) -> void:
	var dist: float = vampire.get_distance_to_player()
	if dist > vampire.enemy_data.detection_range * 1.35:
		request_transition(&"Patrol")
		return

	_rethink_timer -= delta
	if _rethink_timer <= 0.0:
		_rethink_timer = vampire.randf_range_val(0.7, 1.4)
		_strafe_sign *= -1.0

	var to_player: Vector3 = vampire.get_direction_to_player_flat()
	vampire.face_direction(to_player, 11.0, delta)

	# Reactively sidestep if the player is swinging at close range
	var player_ref: Player = vampire.target_player as Player
	if player_ref != null and vampire.evade_cooldown_remaining <= 0.0:
		var player_state_name: StringName = player_ref.state_machine.get_current_state_name()
		if player_state_name == &"Attack" and dist < vampire.enemy_data.attack_range * 1.15:
			if vampire.roll_chance(vampire.enemy_data.evade_chance):
				request_transition(&"Evade", {"strafe_sign": _strafe_sign})
				return

	# Commit to lethal telegraphed lunge when in striking distance
	if dist <= vampire.enemy_data.attack_range and vampire.attack_cooldown_remaining <= 0.0:
		request_transition(&"Attack")
		return

	# Tactical approach / strafe blend
	var right_dir: Vector3 = Vector3(-to_player.z, 0.0, to_player.x) * _strafe_sign
	var desired_velocity: Vector3 = Vector3.ZERO
	if dist > vampire.enemy_data.preferred_combat_distance + 0.8:
		desired_velocity = (to_player * vampire.enemy_data.chase_speed) + (right_dir * vampire.enemy_data.strafe_speed * 0.35)
	elif dist < vampire.enemy_data.preferred_combat_distance - 0.9:
		desired_velocity = (-to_player * vampire.enemy_data.strafe_speed * 0.65) + (right_dir * vampire.enemy_data.strafe_speed)
	else:
		desired_velocity = (to_player * 1.4) + (right_dir * vampire.enemy_data.strafe_speed)

	vampire.velocity.x = move_toward(vampire.velocity.x, desired_velocity.x, 20.0 * delta)
	vampire.velocity.z = move_toward(vampire.velocity.z, desired_velocity.z, 20.0 * delta)

	if not vampire.is_on_floor():
		vampire.velocity.y -= VampireDuelist.GRAVITY * delta
	else:
		vampire.velocity.y = -1.0

	vampire.move_and_slide()

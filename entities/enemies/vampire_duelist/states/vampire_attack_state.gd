class_name VampireAttackState
extends VampireState
## Multi-hit Hack-and-Slash Vampire combo kit (similar to the Player's):
## 1) Opening red telegraph (player reaction window for dodge/parry)
## 2) Up to 3 rapid combo slashes (`Attack_Combo1` -> `Attack_Combo2` -> `Attack_Combo3`, 10 DMG each)
## 3) Heavy Finisher telegraph + explosive knockback/launch blow (`Attack_Finisher`, 10 DMG + throws Hunter away)
## 4) Punishable recovery opening (`Attack_Recovery`)

enum SubPhase {
	TELEGRAPH,
	COMBO_ACTIVE,
	COMBO_LINK,
	FINISHER_TELEGRAPH,
	FINISHER_ACTIVE,
	RECOVERY,
}

var _sub_phase: SubPhase = SubPhase.TELEGRAPH
var _elapsed: float = 0.0
var _lunge_dir: Vector3 = Vector3.FORWARD
var _combo_step_index: int = 0
var _target_combo_hits: int = 3


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_sub_phase = SubPhase.TELEGRAPH
	_elapsed = 0.0
	_combo_step_index = 0
	var max_hits: int = maxi(1, vampire.enemy_data.combo_max_hits)
	# Randomly execute 1..3 combo slashes + 1 heavy knockback finisher (biased toward 2-3 hit chains)
	_target_combo_hits = clampi(2 if max_hits >= 2 and vampire.roll_chance(0.25) else max_hits, 1, max_hits)
	_lunge_dir = vampire.get_direction_to_player_flat()
	vampire.set_telegraph_active(true, 0.0)
	vampire.reset_weapon_pose()
	vampire.play_timed_vampire_animation(&"Attack_Telegraph", vampire.enemy_data.telegraph_duration, 0.12, true)


func exit() -> void:
	if vampire != null:
		vampire.set_telegraph_active(false, 0.0)
		vampire.attack_cooldown_remaining = vampire.enemy_data.attack_cooldown
		if vampire.hitbox != null:
			vampire.hitbox.deactivate()
		if vampire.weapon_trail != null:
			vampire.weapon_trail.emitting = false


func physics_update(delta: float) -> void:
	_elapsed += delta

	match _sub_phase:
		SubPhase.TELEGRAPH:
			var t: float = clampf(_elapsed / maxf(0.05, vampire.enemy_data.telegraph_duration), 0.0, 1.0)
			if t < 0.65:
				_lunge_dir = vampire.get_direction_to_player_flat()
				vampire.face_direction(_lunge_dir, 14.0, delta)
			vampire.set_telegraph_active(true, t)
			_apply_damped_ground_motion(24.0, delta)
			if _elapsed >= vampire.enemy_data.telegraph_duration:
				_begin_combo_strike(0)

		SubPhase.COMBO_ACTIVE:
			vampire.velocity.x = _lunge_dir.x * vampire.enemy_data.combo_step_lunge_speed
			vampire.velocity.z = _lunge_dir.z * vampire.enemy_data.combo_step_lunge_speed
			_apply_vertical_and_slide(delta)
			if _elapsed >= vampire.enemy_data.combo_step_active_duration:
				_on_combo_strike_finished()

		SubPhase.COMBO_LINK:
			var t: float = clampf(_elapsed / maxf(0.04, vampire.enemy_data.combo_step_telegraph_duration), 0.0, 1.0)
			_lunge_dir = vampire.get_direction_to_player_flat()
			vampire.face_direction(_lunge_dir, 15.0, delta)
			_apply_damped_ground_motion(22.0, delta)
			if _elapsed >= vampire.enemy_data.combo_step_telegraph_duration:
				if vampire.get_distance_to_player() > vampire.enemy_data.combo_chase_range:
					_begin_recovery()
				else:
					_begin_combo_strike(_combo_step_index)

		SubPhase.FINISHER_TELEGRAPH:
			var t: float = clampf(_elapsed / maxf(0.05, vampire.enemy_data.finisher_telegraph_duration), 0.0, 1.0)
			if t < 0.60:
				_lunge_dir = vampire.get_direction_to_player_flat()
				vampire.face_direction(_lunge_dir, 14.0, delta)
			vampire.set_telegraph_active(true, 0.45 + 0.55 * t)
			_apply_damped_ground_motion(24.0, delta)
			if _elapsed >= vampire.enemy_data.finisher_telegraph_duration:
				_begin_finisher_strike()

		SubPhase.FINISHER_ACTIVE:
			vampire.velocity.x = _lunge_dir.x * vampire.enemy_data.finisher_lunge_speed
			vampire.velocity.z = _lunge_dir.z * vampire.enemy_data.finisher_lunge_speed
			_apply_vertical_and_slide(delta)
			if _elapsed >= vampire.enemy_data.finisher_active_duration:
				_begin_recovery()

		SubPhase.RECOVERY:
			_apply_damped_ground_motion(22.0, delta)
			if _elapsed >= vampire.enemy_data.attack_recovery_duration:
				request_transition(&"Strafe")


func _begin_combo_strike(step_idx: int) -> void:
	_sub_phase = SubPhase.COMBO_ACTIVE
	_elapsed = 0.0
	_combo_step_index = step_idx
	vampire.set_telegraph_active(false, 0.0)

	var anim_name: StringName = &"Attack_Combo1"
	if step_idx == 1:
		anim_name = &"Attack_Combo2"
	elif step_idx >= 2:
		anim_name = &"Attack_Combo3"
	var clip_dur: float = vampire.enemy_data.combo_step_active_duration + 0.14
	vampire.play_timed_vampire_animation(anim_name, clip_dur, 0.10, true)

	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = true

	var info: DamageInfo = DamageInfo.new()
	info.amount = vampire.enemy_data.attack_damage
	info.source = vampire
	info.knockback_vector = _lunge_dir * 4.5
	info.launch_force = 0.0
	info.hitstun_duration = 0.24
	info.hitstop_duration = 0.035
	info.screen_shake = 0.14
	if vampire.hitbox != null:
		vampire.hitbox.activate(info, Vector3(2.15, 1.5, 2.55), Vector3(0.0, 1.05, -1.4))


func _on_combo_strike_finished() -> void:
	if vampire.hitbox != null:
		vampire.hitbox.deactivate()
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = false

	_combo_step_index += 1
	if _combo_step_index < _target_combo_hits:
		if vampire.get_distance_to_player() > vampire.enemy_data.combo_chase_range:
			_begin_recovery()
			return
		_sub_phase = SubPhase.COMBO_LINK
		_elapsed = 0.0
	else:
		if vampire.get_distance_to_player() > vampire.enemy_data.combo_chase_range * 1.15:
			_begin_recovery()
			return
		_begin_finisher_telegraph()


func _begin_finisher_telegraph() -> void:
	_sub_phase = SubPhase.FINISHER_TELEGRAPH
	_elapsed = 0.0
	vampire.set_telegraph_active(true, 0.35)
	vampire.play_timed_vampire_animation(&"Attack_Finisher_Telegraph", vampire.enemy_data.finisher_telegraph_duration, 0.12, true)


func _begin_finisher_strike() -> void:
	_sub_phase = SubPhase.FINISHER_ACTIVE
	_elapsed = 0.0
	vampire.set_telegraph_active(false, 0.0)
	vampire.play_timed_vampire_animation(&"Attack_Finisher", vampire.enemy_data.finisher_active_duration + 0.18, 0.09, true)
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = true

	var info: DamageInfo = DamageInfo.new()
	info.amount = vampire.enemy_data.attack_damage
	info.source = vampire
	info.knockback_vector = _lunge_dir * vampire.enemy_data.finisher_knockback_force
	info.launch_force = vampire.enemy_data.finisher_launch_force
	info.launch_vector = Vector3(
		_lunge_dir.x * vampire.enemy_data.finisher_knockback_force,
		vampire.enemy_data.finisher_launch_force,
		_lunge_dir.z * vampire.enemy_data.finisher_knockback_force
	)
	info.hitstun_duration = vampire.enemy_data.finisher_hitstun_duration
	info.hitstop_duration = 0.075
	info.screen_shake = 0.32
	info.is_launcher = true
	if vampire.hitbox != null:
		vampire.hitbox.activate(info, Vector3(2.45, 1.7, 2.85), Vector3(0.0, 1.05, -1.5))


func _begin_recovery() -> void:
	_sub_phase = SubPhase.RECOVERY
	_elapsed = 0.0
	vampire.set_telegraph_active(false, 0.0)
	vampire.play_timed_vampire_animation(&"Attack_Recovery", vampire.enemy_data.attack_recovery_duration, 0.14, true)
	if vampire.hitbox != null:
		vampire.hitbox.deactivate()
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = false


func _apply_damped_ground_motion(drag: float, delta: float) -> void:
	vampire.velocity.x = move_toward(vampire.velocity.x, 0.0, drag * delta)
	vampire.velocity.z = move_toward(vampire.velocity.z, 0.0, drag * delta)
	_apply_vertical_and_slide(delta)


func _apply_vertical_and_slide(delta: float) -> void:
	if not vampire.is_on_floor():
		vampire.velocity.y -= VampireDuelist.GRAVITY * delta
	else:
		vampire.velocity.y = -1.0
	vampire.move_and_slide()


func is_in_witch_time_window() -> bool:
	if (_sub_phase == SubPhase.TELEGRAPH or _sub_phase == SubPhase.FINISHER_TELEGRAPH) and vampire != null and vampire.enemy_data != null:
		var dur: float = vampire.enemy_data.finisher_telegraph_duration if _sub_phase == SubPhase.FINISHER_TELEGRAPH else vampire.enemy_data.telegraph_duration
		var t: float = _elapsed / maxf(0.05, dur)
		return t >= 0.50
	if _sub_phase == SubPhase.COMBO_ACTIVE or _sub_phase == SubPhase.FINISHER_ACTIVE:
		return _elapsed <= 0.10
	return false

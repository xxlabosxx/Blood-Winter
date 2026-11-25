class_name VampireAttackState
extends VampireState
## Lethal 3-phase Vampire strike:
## 1) Unmistakable crimson telegraph (player reaction window for dodge or parry)
## 2) High-speed lunge slash with crimson weapon trail
## 3) Punishable recovery opening

enum SubPhase {
	TELEGRAPH,
	ACTIVE,
	RECOVERY,
}

var _sub_phase: SubPhase = SubPhase.TELEGRAPH
var _elapsed: float = 0.0
var _lunge_dir: Vector3 = Vector3.FORWARD


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_sub_phase = SubPhase.TELEGRAPH
	_elapsed = 0.0
	_lunge_dir = vampire.get_direction_to_player_flat()
	vampire.set_telegraph_active(true, 0.0)
	vampire.set_weapon_pose(-105.0, -20.0, 28.0)


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
			# Track player for first 60% of windup, then lock direction so sidestepping works cleanly
			if t < 0.60:
				_lunge_dir = vampire.get_direction_to_player_flat()
				vampire.face_direction(_lunge_dir, 14.0, delta)
			vampire.set_telegraph_active(true, t)
			vampire.set_weapon_pose(lerpf(-75.0, -128.0, t), lerpf(-8.0, -28.0, t), 32.0)

			vampire.velocity.x = move_toward(vampire.velocity.x, 0.0, 24.0 * delta)
			vampire.velocity.z = move_toward(vampire.velocity.z, 0.0, 24.0 * delta)
			if not vampire.is_on_floor():
				vampire.velocity.y -= VampireDuelist.GRAVITY * delta
			vampire.move_and_slide()

			if _elapsed >= vampire.enemy_data.telegraph_duration:
				_begin_active_lunge()

		SubPhase.ACTIVE:
			var t: float = clampf(_elapsed / maxf(0.04, vampire.enemy_data.attack_active_duration), 0.0, 1.0)
			vampire.set_weapon_pose(lerpf(-120.0, 108.0, t), lerpf(-18.0, 12.0, t), 12.0)
			vampire.velocity.x = _lunge_dir.x * vampire.enemy_data.attack_lunge_speed
			vampire.velocity.z = _lunge_dir.z * vampire.enemy_data.attack_lunge_speed
			if not vampire.is_on_floor():
				vampire.velocity.y -= VampireDuelist.GRAVITY * delta
			else:
				vampire.velocity.y = -1.0
			vampire.move_and_slide()

			if _elapsed >= vampire.enemy_data.attack_active_duration:
				_begin_recovery()

		SubPhase.RECOVERY:
			vampire.velocity.x = move_toward(vampire.velocity.x, 0.0, 22.0 * delta)
			vampire.velocity.z = move_toward(vampire.velocity.z, 0.0, 22.0 * delta)
			if not vampire.is_on_floor():
				vampire.velocity.y -= VampireDuelist.GRAVITY * delta
			vampire.move_and_slide()

			if _elapsed >= vampire.enemy_data.attack_recovery_duration:
				request_transition(&"Strafe")


func _begin_active_lunge() -> void:
	_sub_phase = SubPhase.ACTIVE
	_elapsed = 0.0
	vampire.set_telegraph_active(false, 0.0)
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = true

	var info: DamageInfo = DamageInfo.new()
	info.amount = vampire.enemy_data.attack_damage
	info.source = vampire
	info.knockback_vector = _lunge_dir * 7.5
	info.launch_force = 2.0
	info.hitstop_duration = 0.055
	info.screen_shake = 0.22
	if vampire.hitbox != null:
		vampire.hitbox.activate(info, Vector3(2.1, 1.5, 2.5), Vector3(0.0, 1.05, -1.4))


func _begin_recovery() -> void:
	_sub_phase = SubPhase.RECOVERY
	_elapsed = 0.0
	if vampire.hitbox != null:
		vampire.hitbox.deactivate()
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = false

class_name PlayerSkillState
extends PlayerState
## Executes the active HunterClassData's optional special skill:
## - CRIMSON_PARRY: reactive guard window -> high-damage counter-slash (no posture bar).
## - SHADOW_DASH: invulnerable dark-crimson blink-slash through foes.

var _skill_type: HunterClassData.SpecialSkillType = HunterClassData.SpecialSkillType.NONE
var _elapsed: float = 0.0
var _counter_phase: bool = false
var _counter_elapsed: float = 0.0
var _ghost_timer: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_counter_phase = false
	_counter_elapsed = 0.0
	_ghost_timer = 0.0
	_skill_type = player.class_data.special_skill
	player.skill_cooldown_remaining = player.class_data.special_skill_cooldown
	player.parry_counter_triggered = false
	player.last_parried_attacker = null
	player.face_locked_or_input_immediately()
	_dash_dir = player.get_facing_direction()

	match _skill_type:
		HunterClassData.SpecialSkillType.CRIMSON_PARRY:
			player.is_parry_window_active = true
			player.set_parry_aura_visible(true)
			player.set_combo_debug_label("Skill: Crimson Parry")
			player.cancel_window_status = "PARRY WINDOW"
			player.set_weapon_swing_pose(-15.0, -35.0, 48.0)
		HunterClassData.SpecialSkillType.SHADOW_DASH:
			player.health.is_invulnerable = true
			player.set_combo_debug_label("Skill: Shadow Dash")
			player.cancel_window_status = "SHADOW BLINK"
			player.spawn_dodge_ghost(Color(0.25, 0.04, 0.12, 0.78), 0.34)
			if player.weapon_trail != null:
				player.weapon_trail.emitting = true
			_activate_shadow_dash_hitbox()
		_:
			request_transition(&"Idle")


func exit() -> void:
	if player != null:
		player.is_parry_window_active = false
		player.parry_counter_triggered = false
		player.health.is_invulnerable = false
		player.set_parry_aura_visible(false)
		if player.hitbox != null:
			player.hitbox.deactivate()
		if player.weapon_trail != null:
			player.weapon_trail.emitting = false
		player.cancel_window_status = "-"


func physics_update(delta: float) -> void:
	match _skill_type:
		HunterClassData.SpecialSkillType.CRIMSON_PARRY:
			_update_crimson_parry(delta)
		HunterClassData.SpecialSkillType.SHADOW_DASH:
			_update_shadow_dash(delta)
		_:
			request_transition(&"Idle")


func _update_crimson_parry(delta: float) -> void:
	if not _counter_phase:
		_elapsed += delta
		player.velocity.x = move_toward(player.velocity.x, 0.0, 26.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 26.0 * delta)
		if not player.is_on_floor():
			player.velocity.y -= Player.GRAVITY * 0.45 * delta
		player.move_and_slide()

		if player.parry_counter_triggered:
			_begin_parry_counter()
			return

		if _elapsed >= player.class_data.parry_window:
			player.is_parry_window_active = false
			player.set_parry_aura_visible(false)
			player.cancel_window_status = "Parry Recovery"
			if player.can_dodge() and player.consume_buffered_action(&"dodge"):
				request_transition(&"Dodge")
				return
			if _elapsed >= player.class_data.parry_window + 0.16:
				request_transition(&"Idle" if player.is_on_floor() else &"Air")
	else:
		_counter_elapsed += delta
		var swing_t: float = clampf(_counter_elapsed / 0.16, 0.0, 1.0)
		player.set_weapon_swing_pose(lerpf(-120.0, 125.0, swing_t), 0.0, 20.0)
		player.velocity.x = move_toward(player.velocity.x, 0.0, 22.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, 0.0, 22.0 * delta)
		player.move_and_slide()

		if _counter_elapsed >= 0.16 and player.hitbox != null:
			player.hitbox.deactivate()
		if _counter_elapsed >= 0.28:
			request_transition(&"Idle" if player.is_on_floor() else &"Air")


func _begin_parry_counter() -> void:
	_counter_phase = true
	_counter_elapsed = 0.0
	player.is_parry_window_active = false
	player.health.is_invulnerable = true
	player.set_parry_aura_visible(false)
	player.set_combo_debug_label("COUNTER: Crimson Riposte!")
	player.cancel_window_status = "COUNTER-SLASH"

	if player.last_parried_attacker != null and is_instance_valid(player.last_parried_attacker):
		var to_attacker: Vector3 = player.last_parried_attacker.global_position - player.global_position
		player.face_direction(to_attacker, 100.0, 1.0)
	_dash_dir = player.get_facing_direction()
	player.velocity = _dash_dir * 7.5
	if player.weapon_trail != null:
		player.weapon_trail.emitting = true

	var base_dmg: float = player.current_weapon.base_damage if player.current_weapon != null else 25.0
	var info: DamageInfo = DamageInfo.new()
	info.amount = base_dmg * player.class_data.parry_counter_damage_multiplier
	info.source = player
	info.knockback_vector = _dash_dir * 10.5
	info.launch_force = 7.2
	info.hitstop_duration = 0.09
	info.screen_shake = 0.28
	info.is_launcher = true
	info.is_counter = true
	if player.hitbox != null:
		player.hitbox.activate(info, Vector3(3.4, 2.2, 3.4), Vector3(0.0, 1.0, -1.6))


func _update_shadow_dash(delta: float) -> void:
	_elapsed += delta
	_ghost_timer += delta
	var duration: float = 0.24

	if _ghost_timer >= 0.04:
		_ghost_timer = 0.0
		player.spawn_dodge_ghost(Color(0.95, 0.08, 0.22, 0.55), 0.30)

	var dash_speed: float = player.class_data.move_speed * player.class_data.shadow_dash_distance_multiplier
	player.velocity.x = _dash_dir.x * dash_speed
	player.velocity.z = _dash_dir.z * dash_speed
	player.velocity.y = 0.0
	player.set_weapon_swing_pose(lerpf(-110.0, 115.0, clampf(_elapsed / duration, 0.0, 1.0)), 6.0, -14.0)
	player.move_and_slide()

	if _elapsed >= duration:
		player.velocity *= 0.35
		request_transition(&"Idle" if player.is_on_floor() else &"Air")


func _activate_shadow_dash_hitbox() -> void:
	if player.hitbox == null:
		return
	var base_dmg: float = player.current_weapon.base_damage if player.current_weapon != null else 20.0
	var info: DamageInfo = DamageInfo.new()
	info.amount = base_dmg * 1.45
	info.source = player
	info.knockback_vector = _dash_dir * 6.5
	info.launch_force = 5.5
	info.hitstop_duration = 0.055
	info.screen_shake = 0.18
	info.is_counter = true
	player.hitbox.activate(info, Vector3(2.4, 1.8, 2.8), Vector3(0.0, 1.0, -0.8))

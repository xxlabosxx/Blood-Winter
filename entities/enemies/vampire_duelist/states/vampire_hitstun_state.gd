class_name VampireHitstunState
extends VampireState
## Delegates kinematic reaction & air-juggle physics (Hitstop freeze frames,
## gravity scaling, progressive decay, Ground Bounce & Knockdown Recovery)
## to the modular EnemyReactionComponent.


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	vampire.set_telegraph_active(false, 0.0)
	if vampire.hitbox != null:
		vampire.hitbox.deactivate()
	if vampire.weapon_trail != null:
		vampire.weapon_trail.emitting = false
	vampire.is_juggled_in_air = not vampire.is_on_floor()


func exit() -> void:
	if vampire != null:
		vampire.is_juggled_in_air = false


func physics_update(delta: float) -> void:
	if vampire.reaction_component == null:
		request_transition(&"Strafe")
		return

	vampire.reaction_component.step_physics(delta)
	vampire.is_juggled_in_air = not vampire.is_on_floor()

	if not vampire.reaction_component.is_in_reaction():
		if vampire.evade_cooldown_remaining <= 0.0 and vampire.get_distance_to_player() < 2.6 and vampire.roll_chance(0.55):
			request_transition(&"Evade")
		else:
			request_transition(&"Strafe")

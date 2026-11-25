class_name PlayerHitstunState
extends PlayerState

var _elapsed: float = 0.0
var _duration: float = 0.28


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_elapsed = 0.0
	_duration = 0.28
	player.set_combo_debug_label("Hitstun")
	player.cancel_window_status = "Staggered"

	var info: DamageInfo = data.get("info", null) as DamageInfo
	if info != null:
		player.velocity.x = info.knockback_vector.x
		player.velocity.z = info.knockback_vector.z
		if info.launch_force > 0.0:
			player.velocity.y = info.launch_force * 0.5


func physics_update(delta: float) -> void:
	_elapsed += delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, 22.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, 0.0, 22.0 * delta)
	if not player.is_on_floor():
		player.velocity.y -= Player.GRAVITY * delta
	player.move_and_slide()

	# Allow panic dodge cancel late in hitstun
	if _elapsed >= _duration * 0.72 and player.can_dodge() and player.consume_buffered_action(&"dodge"):
		request_transition(&"Dodge")
		return

	if _elapsed >= _duration:
		request_transition(&"Idle" if player.is_on_floor() else &"Air")

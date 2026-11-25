class_name VampirePatrolState
extends VampireState
## Stalks an anchor radius until the Hunter enters combat awareness range.

var _anchor_pos: Vector3 = Vector3.ZERO
var _orbit_angle: float = 0.0


func enter(previous_state: StringName, data: Dictionary = {}) -> void:
	super.enter(previous_state, data)
	_anchor_pos = vampire.global_position
	vampire.set_telegraph_active(false, 0.0)
	vampire.reset_weapon_pose()


func physics_update(delta: float) -> void:
	var dist: float = vampire.get_distance_to_player()
	if dist <= vampire.enemy_data.detection_range:
		request_transition(&"Strafe")
		return

	_orbit_angle += delta * 0.55
	var desired: Vector3 = _anchor_pos + Vector3(cos(_orbit_angle) * 3.0, 0.0, sin(_orbit_angle) * 3.0)
	var to_desired: Vector3 = desired - vampire.global_position
	to_desired.y = 0.0
	if to_desired.length() > 0.25:
		var dir: Vector3 = to_desired.normalized()
		vampire.velocity.x = dir.x * vampire.enemy_data.patrol_speed
		vampire.velocity.z = dir.z * vampire.enemy_data.patrol_speed
		vampire.face_direction(dir, 6.0, delta)
	else:
		vampire.velocity.x = 0.0
		vampire.velocity.z = 0.0

	if not vampire.is_on_floor():
		vampire.velocity.y -= VampireDuelist.GRAVITY * delta
	else:
		vampire.velocity.y = -1.0

	vampire.move_and_slide()

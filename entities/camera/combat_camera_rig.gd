class_name CombatCameraRig
extends Node3D
## Stylized close third-person camera with Lock-on framing and combat screen shake.

signal lock_on_changed(target: Node3D)

@export var target_path: NodePath = NodePath()
@export var follow_speed: float = 11.0
@export var mouse_sensitivity: float = 0.0028
@export var min_pitch_deg: float = -48.0
@export var max_pitch_deg: float = 28.0
@export var lock_on_range: float = 24.0
@export var pivot_height_offset: float = 1.65

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D
@onready var _lock_marker: MeshInstance3D = $LockOnMarker

var target_node: Node3D = null
var locked_target: Node3D = null

var _yaw: float = 0.0
var _pitch: float = -0.22
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_elapsed: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if not target_path.is_empty():
		target_node = get_node_or_null(target_path) as Node3D
	if _lock_marker != null:
		_lock_marker.top_level = true
		_lock_marker.visible = false
	if GameFeelManager != null and not GameFeelManager.screen_shake_requested.is_connected(_on_screen_shake_requested):
		GameFeelManager.screen_shake_requested.connect(_on_screen_shake_requested)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mouse_capture"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("lock_on"):
		toggle_lock_on()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if locked_target == null:
			var motion: InputEventMouseMotion = event as InputEventMouseMotion
			_yaw -= motion.relative.x * mouse_sensitivity
			_pitch = clampf(
				_pitch - motion.relative.y * mouse_sensitivity,
				deg_to_rad(min_pitch_deg),
				deg_to_rad(max_pitch_deg)
			)


func _process(delta: float) -> void:
	if target_node == null:
		return

	# Validate locked target
	if locked_target != null:
		if not is_instance_valid(locked_target) or not locked_target.is_inside_tree():
			clear_lock_on()
		elif target_node.global_position.distance_to(locked_target.global_position) > lock_on_range * 1.25:
			clear_lock_on()

	# Smoothly track player position
	var desired_pos: Vector3 = target_node.global_position + Vector3(0.0, pivot_height_offset, 0.0)
	global_position = global_position.lerp(desired_pos, clampf(follow_speed * delta, 0.0, 1.0))

	# Smoothly orient toward locked enemy if active
	if locked_target != null:
		var to_enemy: Vector3 = (locked_target.global_position + Vector3(0.0, 1.1, 0.0)) - global_position
		var horizontal: Vector3 = Vector3(to_enemy.x, 0.0, to_enemy.z)
		if horizontal.length_squared() > 0.01:
			var target_yaw: float = atan2(-horizontal.x, -horizontal.z)
			_yaw = lerp_angle(_yaw, target_yaw, clampf(8.5 * delta, 0.0, 1.0))
			var desired_pitch: float = clampf(
				atan2(to_enemy.y - 0.5, horizontal.length()) - 0.12,
				deg_to_rad(-34.0),
				deg_to_rad(18.0)
			)
			_pitch = lerpf(_pitch, desired_pitch, clampf(6.0 * delta, 0.0, 1.0))

		if _lock_marker != null:
			_lock_marker.visible = true
			_lock_marker.global_position = locked_target.global_position + Vector3(0.0, 2.35, 0.0)
			_lock_marker.rotate_y(delta * 3.8)
	elif _lock_marker != null:
		_lock_marker.visible = false

	rotation = Vector3(_pitch, _yaw, 0.0)
	_update_screen_shake(delta)


func toggle_lock_on() -> void:
	if locked_target != null:
		clear_lock_on()
		return
	var best: Node3D = _find_nearest_enemy()
	if best != null:
		locked_target = best
		lock_on_changed.emit(locked_target)


func clear_lock_on() -> void:
	if locked_target != null:
		locked_target = null
		lock_on_changed.emit(null)


func get_horizontal_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


func _find_nearest_enemy() -> Node3D:
	if target_node == null:
		return null
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var closest: Node3D = null
	var closest_dist: float = lock_on_range
	for node: Node in enemies:
		if node is Node3D:
			var enemy_node: Node3D = node as Node3D
			var dist: float = target_node.global_position.distance_to(enemy_node.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = enemy_node
	return closest


func _on_screen_shake_requested(intensity: float, duration: float) -> void:
	if intensity >= _shake_intensity or _shake_elapsed >= _shake_duration:
		_shake_intensity = intensity
		_shake_duration = maxf(0.04, duration)
		_shake_elapsed = 0.0


func _update_screen_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_elapsed < _shake_duration and _shake_intensity > 0.001:
		_shake_elapsed += delta
		var decay: float = clampf(1.0 - (_shake_elapsed / maxf(0.01, _shake_duration)), 0.0, 1.0)
		var mag: float = _shake_intensity * decay * decay
		_camera.h_offset = _rng.randf_range(-mag, mag)
		_camera.v_offset = _rng.randf_range(-mag, mag)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_shake_intensity = 0.0

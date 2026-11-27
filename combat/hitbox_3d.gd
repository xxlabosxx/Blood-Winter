class_name Hitbox3D
extends Area3D
## Melee hitbox that checks overlapping Hurtbox3D nodes during active frames.
## Uses an internal active flag (instead of toggling monitoring) to avoid physics flush errors.

signal hit_confirmed(target_entity: Node3D, info: DamageInfo)

@export var owner_entity: Node3D = null
@export var shape_node: CollisionShape3D = null

var _is_active: bool = false
var _current_info: DamageInfo = null
var _already_hit: Array[Node] = []


func _ready() -> void:
	monitoring = true
	monitorable = false
	if shape_node == null:
		shape_node = get_node_or_null("CollisionShape3D") as CollisionShape3D
	area_entered.connect(_on_area_entered)


func activate(info: DamageInfo, box_size: Vector3 = Vector3.ZERO, local_offset: Vector3 = Vector3.ZERO) -> void:
	_current_info = info
	_already_hit.clear()
	if shape_node != null:
		if box_size != Vector3.ZERO and shape_node.shape is BoxShape3D:
			(shape_node.shape as BoxShape3D).size = box_size
		if local_offset != Vector3.ZERO:
			position = local_offset
	_is_active = true
	_scan_overlaps()


func deactivate() -> void:
	_is_active = false
	_current_info = null
	_already_hit.clear()


func is_hitbox_active() -> bool:
	return _is_active


func _physics_process(_delta: float) -> void:
	if _is_active:
		_scan_overlaps()


func _scan_overlaps() -> void:
	if not _is_active or _current_info == null:
		return
	for area: Area3D in get_overlapping_areas():
		_try_hit_area(area)


func _on_area_entered(area: Area3D) -> void:
	if _is_active:
		_try_hit_area(area)


func _try_hit_area(area: Area3D) -> void:
	if not (area is Hurtbox3D):
		return
	var hurtbox: Hurtbox3D = area as Hurtbox3D
	var target: Node3D = hurtbox.owner_entity if hurtbox.owner_entity != null else hurtbox.get_parent() as Node3D
	if target == null or target == owner_entity:
		return
	if _already_hit.has(target):
		return

	_already_hit.append(target)
	var payload: DamageInfo = _clone_info(_current_info)
	payload.hit_position = hurtbox.global_position
	hurtbox.receive_hit(payload)
	hit_confirmed.emit(target, payload)


func _clone_info(src: DamageInfo) -> DamageInfo:
	var copy: DamageInfo = DamageInfo.new()
	copy.amount = src.amount
	copy.source = src.source
	copy.knockback_vector = src.knockback_vector
	copy.launch_force = src.launch_force
	copy.launch_vector = src.launch_vector
	copy.hitstun_duration = src.hitstun_duration
	copy.stagger_power = src.stagger_power
	copy.hitstop_frames = src.hitstop_frames
	copy.hitstop_duration = src.hitstop_duration
	copy.screen_shake = src.screen_shake
	copy.is_launcher = src.is_launcher
	copy.is_aerial = src.is_aerial
	copy.is_counter = src.is_counter
	copy.force_state = src.force_state
	copy.attacker_forward_velocity = src.attacker_forward_velocity
	copy.impact_direction = src.impact_direction
	copy.hit_position = src.hit_position
	return copy

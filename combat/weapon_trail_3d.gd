class_name WeaponTrail3D
extends MeshInstance3D
## Stylized crimson ribbon weapon trail rendered with ImmediateMesh in world space.

@export var base_marker: Node3D = null
@export var tip_marker: Node3D = null
@export var trail_color: Color = Color(0.95, 0.08, 0.16, 0.92)
@export var trail_lifetime: float = 0.18
@export var min_sample_distance: float = 0.04
@export var max_points: int = 36

var emitting: bool = false

var _immediate_mesh: ImmediateMesh = null
var _material: StandardMaterial3D = null
var _points: Array[Dictionary] = []


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_immediate_mesh = ImmediateMesh.new()
	mesh = _immediate_mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.no_depth_test = false
	material_override = _material


func set_trail_color(new_color: Color) -> void:
	trail_color = new_color


func clear_trail() -> void:
	_points.clear()
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()


func _process(delta: float) -> void:
	# Age existing ribbon segments
	var idx: int = _points.size() - 1
	while idx >= 0:
		var pt: Dictionary = _points[idx]
		pt["age"] = float(pt["age"]) + delta
		if float(pt["age"]) >= trail_lifetime:
			_points.remove_at(idx)
		idx -= 1

	# Sample new segment from weapon markers
	if emitting and base_marker != null and tip_marker != null:
		var base_pos: Vector3 = base_marker.global_position
		var tip_pos: Vector3 = tip_marker.global_position
		var should_add: bool = _points.is_empty()
		if not should_add:
			var last_tip: Vector3 = _points[_points.size() - 1]["tip"] as Vector3
			if last_tip.distance_to(tip_pos) >= min_sample_distance:
				should_add = true
		if should_add:
			_points.append({
				"base": base_pos,
				"tip": tip_pos,
				"age": 0.0,
			})
			if _points.size() > max_points:
				_points.remove_at(0)

	_rebuild_mesh()


func _rebuild_mesh() -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()
	if _points.size() < 2:
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in range(_points.size()):
		var pt: Dictionary = _points[i]
		var age_ratio: float = clampf(1.0 - (float(pt["age"]) / maxf(0.01, trail_lifetime)), 0.0, 1.0)
		var alpha: float = age_ratio * age_ratio * trail_color.a
		var tip_col: Color = Color(trail_color.r, trail_color.g, trail_color.b, alpha)
		var base_col: Color = Color(trail_color.r * 0.55, trail_color.g * 0.2, trail_color.b * 0.25, alpha * 0.35)

		_immediate_mesh.surface_set_color(base_col)
		_immediate_mesh.surface_add_vertex(pt["base"] as Vector3)

		_immediate_mesh.surface_set_color(tip_col)
		_immediate_mesh.surface_add_vertex(pt["tip"] as Vector3)
	_immediate_mesh.surface_end()

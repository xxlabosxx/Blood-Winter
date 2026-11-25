class_name DodgeAfterimage
extends MeshInstance3D
## Short-lived translucent silhouette ghost spawned during dodges and Shadow Dash.

var _lifetime: float = 0.26
var _elapsed: float = 0.0
var _material: StandardMaterial3D = null
var _initial_alpha: float = 0.55


static func spawn(parent: Node, world_transform: Transform3D, ghost_color: Color, height: float = 1.65, radius: float = 0.36, duration: float = 0.24) -> DodgeAfterimage:
	var ghost: DodgeAfterimage = DodgeAfterimage.new()
	ghost._lifetime = maxf(0.05, duration)
	ghost._initial_alpha = ghost_color.a

	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = radius
	cap.height = height
	cap.radial_segments = 8
	cap.rings = 2
	ghost.mesh = cap
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = ghost_color
	ghost._material = mat
	ghost.material_override = mat

	parent.add_child(ghost)
	ghost.global_transform = world_transform
	return ghost


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(1.0 - (_elapsed / _lifetime), 0.0, 1.0)
	if _material != null:
		var c: Color = _material.albedo_color
		c.a = _initial_alpha * t * t
		_material.albedo_color = c
	scale = Vector3.ONE * lerpf(0.86, 1.02, t)
	if _elapsed >= _lifetime:
		queue_free()

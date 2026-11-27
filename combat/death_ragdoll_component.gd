class_name DeathRagdollComponent
extends Node
## Reusable Death + Lightweight Physics Ragdoll Collapse component for Blood Winter humanoids.
## Combines the skeletal `Death` collapse animation with a real physics knockback slide,
## ground-impact bounce, and procedural damped-spring limb flop on Skeleton3D bones —
## guaranteeing dramatic, readable deaths with 100% clean reset on respawn!

const RAGDOLL_BONES: Array[String] = [
	"Head", "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R",
	"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"
]

var owner_body: CharacterBody3D = null
var visual_root: Node3D = null
var skeleton: Skeleton3D = null
var anim_player: AnimationPlayer = null
var gravity: float = 24.5

var is_active: bool = false
var _elapsed: float = 0.0
var _bounced: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bone_indices: PackedInt32Array = PackedInt32Array()
var _bone_flop_angles: Array[Vector3] = []
var _bone_flop_vels: Array[Vector3] = []
var _root_roll_deg: float = 0.0
var _root_roll_vel: float = 0.0


func configure(body: CharacterBody3D, vis_root: Node3D, skel: Skeleton3D, anim_p: AnimationPlayer, grav: float = 24.5) -> void:
	owner_body = body
	visual_root = vis_root
	skeleton = skel
	anim_player = anim_p
	gravity = grav
	_rng.randomize()
	_cache_bones()


func _cache_bones() -> void:
	_bone_indices.clear()
	_bone_flop_angles.clear()
	_bone_flop_vels.clear()
	if skeleton == null:
		return
	for bname: String in RAGDOLL_BONES:
		var idx: int = skeleton.find_bone(bname)
		if idx != -1:
			_bone_indices.append(idx)
			_bone_flop_angles.append(Vector3.ZERO)
			_bone_flop_vels.append(Vector3.ZERO)


func trigger_death(knockback_dir: Vector3 = Vector3.BACK, impulse_speed: float = 6.5) -> void:
	if is_active:
		return
	is_active = true
	_elapsed = 0.0
	_bounced = false
	_root_roll_deg = 0.0
	_root_roll_vel = _rng.randf_range(-140.0, 140.0)

	if _bone_indices.is_empty() and skeleton != null:
		_cache_bones()

	# Seed lively ragdoll limb angular velocities
	for i: int in range(_bone_indices.size()):
		_bone_flop_angles[i] = Vector3.ZERO
		_bone_flop_vels[i] = Vector3(
			_rng.randf_range(-210.0, 210.0),
			_rng.randf_range(-130.0, 130.0),
			_rng.randf_range(-180.0, 180.0)
		)

	if anim_player != null and anim_player.has_animation(&"Death"):
		anim_player.speed_scale = 1.0
		anim_player.play(&"Death", 0.12, 1.05)

	if owner_body != null:
		var flat: Vector3 = Vector3(knockback_dir.x, 0.0, knockback_dir.z)
		if flat.length_squared() < 0.01:
			flat = -visual_root.global_transform.basis.z if visual_root != null else Vector3.BACK
			flat = -flat
		flat = flat.normalized()
		owner_body.velocity.x = flat.x * impulse_speed
		owner_body.velocity.z = flat.z * impulse_speed
		owner_body.velocity.y = maxf(owner_body.velocity.y, 3.4)


func step_physics(delta: float) -> void:
	if not is_active or owner_body == null:
		return
	_elapsed += delta

	var on_floor: bool = owner_body.is_on_floor()
	var drag: float = 9.5 if on_floor else 2.2
	owner_body.velocity.x = move_toward(owner_body.velocity.x, 0.0, drag * delta)
	owner_body.velocity.z = move_toward(owner_body.velocity.z, 0.0, drag * delta)

	if not on_floor:
		owner_body.velocity.y -= gravity * delta
	elif not _bounced and _elapsed > 0.18:
		# Subtle ragdoll impact bounce when body slams into the snow
		_bounced = true
		owner_body.velocity.y = 2.1
		_root_roll_vel *= 0.65
		for i: int in range(_bone_flop_vels.size()):
			_bone_flop_vels[i] += Vector3(
				_rng.randf_range(-90.0, 90.0),
				_rng.randf_range(-60.0, 60.0),
				_rng.randf_range(-90.0, 90.0)
			)
	else:
		owner_body.velocity.y = -1.0

	owner_body.move_and_slide()

	# Damped ragdoll roll on visual_root
	if visual_root != null:
		var settle_target: float = clampf(_root_roll_deg, -18.0, 18.0)
		var roll_accel: float = (-28.0 * (_root_roll_deg - settle_target)) - (6.5 * _root_roll_vel)
		_root_roll_vel += roll_accel * delta
		_root_roll_deg = clampf(_root_roll_deg + _root_roll_vel * delta, -24.0, 24.0)
		visual_root.rotation.z = deg_to_rad(_root_roll_deg)

	# Procedural damped-spring ragdoll flop layered on top of the Death skeleton pose
	if skeleton != null and _elapsed >= 0.15:
		var ragdoll_weight: float = clampf((_elapsed - 0.15) / 0.35, 0.0, 1.0)
		for i: int in range(_bone_indices.size()):
			var ang: Vector3 = _bone_flop_angles[i]
			var vel: Vector3 = _bone_flop_vels[i]
			var accel: Vector3 = (-24.0 * ang) - (5.8 * vel)
			vel += accel * delta
			ang = (ang + vel * delta).clamp(Vector3(-34.0, -24.0, -34.0), Vector3(34.0, 24.0, 34.0))
			_bone_flop_angles[i] = ang
			_bone_flop_vels[i] = vel

			var b_idx: int = _bone_indices[i]
			var base_rot: Quaternion = skeleton.get_bone_pose_rotation(b_idx)
			var flop_q: Quaternion = Quaternion.from_euler(Vector3(
				deg_to_rad(ang.x * ragdoll_weight),
				deg_to_rad(ang.y * ragdoll_weight),
				deg_to_rad(ang.z * ragdoll_weight)
			))
			skeleton.set_bone_pose_rotation(b_idx, (base_rot * flop_q).normalized())


func reset_ragdoll() -> void:
	is_active = false
	_elapsed = 0.0
	_bounced = false
	_root_roll_deg = 0.0
	_root_roll_vel = 0.0
	for i: int in range(_bone_flop_angles.size()):
		_bone_flop_angles[i] = Vector3.ZERO
		_bone_flop_vels[i] = Vector3.ZERO
	if visual_root != null:
		visual_root.rotation.x = 0.0
		visual_root.rotation.z = 0.0
	if skeleton != null:
		skeleton.reset_bone_poses()

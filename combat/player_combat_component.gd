class_name PlayerCombatComponent
extends Node
## Modular, reusable Bayonetta 2 / PlatinumGames combat controller component
## shared across all playable character archetypes:
## - Double Jump & Variable Jump Height multiplier
## - Air Attack Hover (10%-20% gravity + V.y reset)
## - Dodge Spam Penalty (5 consecutive dodges -> Stumble without i-frames)
## - Perfect Dodge Witch Time trigger (via TimeDilationManager)
## - Soft Lock-On cone detection & Attack Magnetism (gap-closing without capsule clipping)
## - Directional Command Inputs (Launcher, Stinger, Air Slam)

signal perfect_dodge_witch_time(duration: float)
signal dodge_spam_stumbled()
signal double_jump_executed()

@export_group("Jump & Aerial Combat")
@export var max_jumps: int = 2
@export var jump_cut_gravity_multiplier: float = 2.5
@export var air_attack_gravity_scale: float = 0.15
@export var air_attack_hover_impulse: float = 2.6

@export_group("Dodge & Anti-Mash")
@export var dodge_spam_limit: int = 5
@export var dodge_spam_window: float = 1.8
@export var dodge_stumble_duration: float = 0.56

@export_group("Witch Time (Unlockable Skill)")
@export var witch_time_enabled: bool = false
@export var witch_time_base_duration: float = 2.6
@export var witch_time_world_scale: float = 0.25
@export var witch_time_trigger_range: float = 5.4

@export_group("Soft Lock-On & Attack Magnetism")
@export var soft_lock_range: float = 8.5
@export var soft_lock_cone_cos: float = 0.30
@export var magnetism_min_dist: float = 1.25
@export var magnetism_max_dist: float = 4.2
@export var magnetism_pull_speed: float = 14.0

var jumps_used: int = 0
var consecutive_dodges: int = 0
var dodge_chain_timer: float = 0.0
var is_stumbling: bool = false
var soft_lock_target: Node3D = null


func reset() -> void:
	jumps_used = 0
	consecutive_dodges = 0
	dodge_chain_timer = 0.0
	is_stumbling = false
	soft_lock_target = null


func reset_air_jumps() -> void:
	jumps_used = 0


func can_jump(is_on_floor: bool) -> bool:
	return is_on_floor or jumps_used < max_jumps


func consume_jump(is_on_floor: bool) -> bool:
	if is_on_floor:
		jumps_used = 1
		return true
	if jumps_used < max_jumps:
		jumps_used += 1
		double_jump_executed.emit()
		return true
	return false


func tick(delta: float) -> void:
	if dodge_chain_timer > 0.0:
		dodge_chain_timer -= delta
		if dodge_chain_timer <= 0.0:
			dodge_chain_timer = 0.0
			consecutive_dodges = 0


func on_attack_performed() -> void:
	consecutive_dodges = 0
	dodge_chain_timer = 0.0


func register_dodge() -> bool:
	consecutive_dodges += 1
	dodge_chain_timer = dodge_spam_window
	if consecutive_dodges >= dodge_spam_limit:
		is_stumbling = true
		consecutive_dodges = 0
		dodge_chain_timer = 0.0
		dodge_spam_stumbled.emit()
		return true
	return false


func try_trigger_witch_time(
	player_pos: Vector3,
	enemies: Array,
	mod_comp: CombatModifierComponent = null,
	force_trigger: bool = false,
	tdm_override: Node = null
) -> bool:
	var unlocked_by_skill: bool = mod_comp != null and mod_comp.get_additive(&"witch_time_unlocked") > 0.0
	if not witch_time_enabled and not unlocked_by_skill:
		return false

	var should_trigger: bool = force_trigger
	if not should_trigger:
		for node: Variant in enemies:
			if node is Node3D:
				var enemy_node: Node3D = node as Node3D
				if not is_instance_valid(enemy_node):
					continue
				if player_pos.distance_to(enemy_node.global_position) <= witch_time_trigger_range:
					if enemy_node.has_method("is_in_witch_time_window") and bool(enemy_node.call("is_in_witch_time_window")):
						should_trigger = true
						break
	if not should_trigger:
		return false

	var dur_mult: float = mod_comp.get_multiplier(&"witch_time_duration_mult") if mod_comp != null else 1.0
	var final_dur: float = witch_time_base_duration * dur_mult
	var tdm: Node = tdm_override
	if tdm == null and is_inside_tree():
		tdm = get_tree().root.get_node_or_null("TimeDilationManager")
	if tdm != null and tdm.has_method("trigger_witch_time"):
		tdm.call("trigger_witch_time", final_dur, witch_time_world_scale)
	perfect_dodge_witch_time.emit(final_dur)
	return true


func find_soft_lock_target(origin: Vector3, search_dir: Vector3, enemies: Array) -> Node3D:
	var flat_dir: Vector3 = Vector3(search_dir.x, 0.0, search_dir.z)
	if flat_dir.length_squared() < 0.001:
		flat_dir = Vector3.FORWARD
	else:
		flat_dir = flat_dir.normalized()

	var best_target: Node3D = null
	var best_score: float = 9999.0
	for node: Variant in enemies:
		if node is Node3D:
			var enemy_node: Node3D = node as Node3D
			if not is_instance_valid(enemy_node):
				continue
			var to_enemy: Vector3 = enemy_node.global_position - origin
			var flat_to: Vector3 = Vector3(to_enemy.x, 0.0, to_enemy.z)
			var dist: float = flat_to.length()
			if dist > soft_lock_range or dist < 0.01:
				continue
			var alignment: float = flat_dir.dot(flat_to / dist)
			if alignment < soft_lock_cone_cos:
				continue
			var score: float = dist - (alignment * 2.5)
			if score < best_score:
				best_score = score
				best_target = enemy_node

	soft_lock_target = best_target
	return best_target


func compute_attack_magnetism_velocity(origin: Vector3, target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var to_target: Vector3 = target.global_position - origin
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist <= magnetism_min_dist or dist > magnetism_max_dist:
		return Vector3.ZERO
	var pull: float = minf(magnetism_pull_speed, (dist - magnetism_min_dist) * 8.5)
	return (to_target / dist) * pull


func resolve_attack_command(
	is_on_floor: bool,
	target: Node3D,
	move_dir: Vector3,
	facing_dir: Vector3,
	is_launcher_btn: bool,
	horiz_speed: float,
	base_move_speed: float,
	origin: Vector3
) -> StringName:
	if not is_on_floor:
		if is_launcher_btn:
			return &"air_slam"
		if move_dir.length_squared() > 0.1:
			var ref_dir: Vector3 = facing_dir
			if target != null and is_instance_valid(target):
				var to_t: Vector3 = target.global_position - origin
				to_t.y = 0.0
				if to_t.length_squared() > 0.01:
					ref_dir = to_t.normalized()
			if move_dir.normalized().dot(ref_dir.normalized()) < -0.55:
				return &"air_slam"
		return &"air"

	if is_launcher_btn:
		return &"launcher"

	if target != null and is_instance_valid(target) and move_dir.length_squared() > 0.1:
		var to_target: Vector3 = target.global_position - origin
		to_target.y = 0.0
		var dist: float = to_target.length()
		if dist > 0.01:
			var dot: float = move_dir.normalized().dot(to_target / dist)
			if dot < -0.60:
				return &"launcher"
			if dot > 0.70 and dist >= 2.6 and dist <= 7.5:
				return &"stinger"

	if move_dir.length_squared() > 0.1 and horiz_speed >= base_move_speed * 1.08:
		return &"stinger"

	return &"ground"

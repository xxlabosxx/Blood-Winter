class_name DamageInfo
extends RefCounted
## Immutable-style HitData payload describing a single combat hit,
## aligned with Character Action (Bayonetta 2 / PlatinumGames) reaction architecture.

const FORCE_STATE_NONE: StringName = &""
const FORCE_STATE_GROUND_BOUNCE: StringName = &"GROUND_BOUNCE"
const FORCE_STATE_SPIN_BLOWBACK: StringName = &"SPIN_BLOWBACK"
const FORCE_STATE_KNOCKDOWN: StringName = &"KNOCKDOWN"

var amount: float = 0.0
var source: Node3D = null
var knockback_vector: Vector3 = Vector3.ZERO
var launch_force: float = 0.0
## Explicit 3D launch/impulse vector in world space (e.g., (0, 12, 0) launch, (0, -20, 0) spike).
## When non-zero, EnemyReactionComponent prioritizes launch_vector over legacy launch_force/knockback_vector.
var launch_vector: Vector3 = Vector3.ZERO
## Hitstun duration in seconds (-1.0 falls back to target's EnemyData default).
var hitstun_duration: float = -1.0
## Subtracted from the target's invisible Poise (Super Armor) pool.
var stagger_power: float = 35.0
## Exact freeze frames at 60 FPS (3-6 frames standard). Overrides hitstop_duration when > 0.
var hitstop_frames: int = 4
var hitstop_duration: float = 0.04
var screen_shake: float = 0.10
var is_launcher: bool = false
var is_aerial: bool = false
var is_counter: bool = false
## Optional forced reaction state (e.g., GROUND_BOUNCE, SPIN_BLOWBACK, KNOCKDOWN).
var force_state: StringName = FORCE_STATE_NONE
## Attacker's horizontal movement velocity for aerial Tethering / Hit-Magnetism.
var attacker_forward_velocity: Vector3 = Vector3.ZERO
## Normalized world-space strike direction (left/right/up/down) for directional hit reactions.
var impact_direction: Vector3 = Vector3.FORWARD
var hit_position: Vector3 = Vector3.ZERO


func get_effective_hitstop_duration() -> float:
	if hitstop_frames > 0:
		return float(hitstop_frames) / 60.0
	return hitstop_duration


func get_resolved_launch_vector() -> Vector3:
	if launch_vector != Vector3.ZERO:
		return launch_vector
	return Vector3(knockback_vector.x, launch_force, knockback_vector.z)

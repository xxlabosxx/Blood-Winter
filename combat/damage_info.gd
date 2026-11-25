class_name DamageInfo
extends RefCounted
## Immutable-style payload describing a single combat hit.

var amount: float = 0.0
var source: Node3D = null
var knockback_vector: Vector3 = Vector3.ZERO
var launch_force: float = 0.0
var hitstop_duration: float = 0.04
var screen_shake: float = 0.10
var is_launcher: bool = false
var is_aerial: bool = false
var is_counter: bool = false
var hit_position: Vector3 = Vector3.ZERO

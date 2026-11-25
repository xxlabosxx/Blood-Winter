class_name ComboStepData
extends Resource
## Resource defining a single melee attack step, including aerial launch impulses
## and explicit Animation Canceling timing windows.

@export var step_name: String = "Slash"
@export var is_aerial: bool = false
@export var is_launcher: bool = false

@export_group("Damage & Timing")
@export var damage_multiplier: float = 1.0
@export var startup_time: float = 0.10
@export var active_time: float = 0.11
@export var recovery_time: float = 0.24
@export var combo_window_start: float = 0.17

@export_group("Animation Canceling Windows")
## Earliest elapsed time (before attack_speed scaling) at which Dodge can cancel this attack.
@export var cancel_dodge_time: float = 0.14
## Earliest elapsed time at which Jump can cancel this attack.
@export var cancel_jump_time: float = 0.20
## Earliest elapsed time at which the Hunter Class Skill can cancel this attack.
@export var cancel_skill_time: float = 0.12

@export_group("Motion & Launch Forces")
@export var forward_impulse: float = 4.5
@export var vertical_launch_force: float = 0.0
@export var attacker_air_lift: float = 0.0
@export var knockback_force: float = 4.0

@export_group("Game Feel & Hitbox")
@export var hitstop_duration: float = 0.045
@export var screen_shake_intensity: float = 0.12
@export var hitbox_size: Vector3 = Vector3(1.8, 1.4, 2.2)
@export var hitbox_offset: Vector3 = Vector3(0.0, 1.0, -1.35)

@export_group("Stylized Procedural Swing")
@export var swing_start_angle_deg: float = -75.0
@export var swing_end_angle_deg: float = 85.0
@export var swing_tilt_deg: float = 18.0


func get_scaled_startup(speed_mult: float = 1.0) -> float:
	return startup_time / maxf(0.1, speed_mult)


func get_scaled_active(speed_mult: float = 1.0) -> float:
	return active_time / maxf(0.1, speed_mult)


func get_scaled_recovery(speed_mult: float = 1.0) -> float:
	return recovery_time / maxf(0.1, speed_mult)


func get_total_duration(speed_mult: float = 1.0) -> float:
	return (startup_time + active_time + recovery_time) / maxf(0.1, speed_mult)


func is_hitbox_active_at(elapsed: float, speed_mult: float = 1.0) -> bool:
	var start: float = get_scaled_startup(speed_mult)
	var stop: float = start + get_scaled_active(speed_mult)
	return elapsed >= start and elapsed <= stop


func can_chain_at(elapsed: float, speed_mult: float = 1.0) -> bool:
	return elapsed >= (combo_window_start / maxf(0.1, speed_mult))


func can_cancel_with_dodge(elapsed: float, speed_mult: float = 1.0) -> bool:
	return cancel_dodge_time >= 0.0 and elapsed >= (cancel_dodge_time / maxf(0.1, speed_mult))


func can_cancel_with_jump(elapsed: float, speed_mult: float = 1.0) -> bool:
	return cancel_jump_time >= 0.0 and elapsed >= (cancel_jump_time / maxf(0.1, speed_mult))


func can_cancel_with_skill(elapsed: float, speed_mult: float = 1.0) -> bool:
	return cancel_skill_time >= 0.0 and elapsed >= (cancel_skill_time / maxf(0.1, speed_mult))

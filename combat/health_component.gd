class_name HealthComponent
extends Node
## Reusable health pool with invulnerability flag and clean signals.

signal health_changed(current: float, maximum: float)
signal damaged(info: DamageInfo, final_damage: float)
signal died()

@export var max_health: float = 100.0

var current_health: float = 100.0
var is_invulnerable: bool = false


func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func configure_max_health(new_max: float, refill: bool = true) -> void:
	max_health = maxf(1.0, new_max)
	if refill:
		current_health = max_health
	else:
		current_health = minf(current_health, max_health)
	health_changed.emit(current_health, max_health)


func reset_health() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func apply_damage(info: DamageInfo) -> float:
	if is_invulnerable or current_health <= 0.0:
		return 0.0
	var final_damage: float = maxf(0.0, info.amount)
	current_health = maxf(0.0, current_health - final_damage)
	health_changed.emit(current_health, max_health)
	damaged.emit(info, final_damage)
	if current_health <= 0.0:
		died.emit()
	return final_damage


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)


func get_health_ratio() -> float:
	return clampf(current_health / maxf(1.0, max_health), 0.0, 1.0)

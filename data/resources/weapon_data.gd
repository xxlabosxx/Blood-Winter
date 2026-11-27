class_name WeaponData
extends Resource
## Resource describing a weapon's core stats and full ground/launcher/air combo chains.

@export var weapon_name: String = "Crimson Claymore"
@export var base_damage: float = 24.0
@export var attack_range: float = 2.4
@export var attack_speed: float = 1.0
@export var blade_length: float = 1.65
@export var blade_color: Color = Color(0.76, 0.82, 0.90, 1.0)
@export var trail_color: Color = Color(0.95, 0.08, 0.16, 1.0)

@export_group("Combo Chains")
@export var ground_combo: Array[ComboStepData] = []
@export var launcher_step: ComboStepData = null
@export var stinger_step: ComboStepData = null
@export var air_combo: Array[ComboStepData] = []
@export var air_slam_step: ComboStepData = null


func get_ground_step(index: int) -> ComboStepData:
	if index < 0 or index >= ground_combo.size():
		return null
	return ground_combo[index]


func get_air_step(index: int) -> ComboStepData:
	if index < 0 or index >= air_combo.size():
		return null
	return air_combo[index]

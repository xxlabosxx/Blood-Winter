class_name HunterClassData
extends Resource
## Resource defining a playable Vampire Hunter class archetype:
## base mobility, dodge performance, loot/identification perks, and optional class skill.

enum SpecialSkillType {
	NONE,
	CRIMSON_PARRY,
	SHADOW_DASH,
}

@export var class_name_display: String = "Vanguard Inquisitor"
@export_multiline var description: String = "Balanced frontline slayer with a reactive Crimson Parry counter-slash."

@export_group("Base Attributes")
@export var max_health: float = 120.0
@export var move_speed: float = 7.6
@export var jump_velocity: float = 9.4

@export_group("Dodge / Primary Defense")
@export var dodge_speed_multiplier: float = 2.15
@export var dodge_duration: float = 0.26
@export var dodge_iframe_duration: float = 0.22
@export var dodge_cooldown: float = 0.24

@export_group("Exploration & Loot Perks")
@export var loot_bonus_multiplier: float = 1.0
@export var identification_bonus: float = 0.15

@export_group("Class Special Skill (Optional)")
@export var special_skill: SpecialSkillType = SpecialSkillType.CRIMSON_PARRY
@export var special_skill_name: String = "Crimson Parry"
@export var special_skill_cooldown: float = 1.35
## Active guard window for Crimson Parry (no Sekiro posture bar — direct counter-slash).
@export var parry_window: float = 0.28
@export var parry_counter_damage_multiplier: float = 2.0
## Speed/reach multiplier for Shadow Dash blink-slash.
@export var shadow_dash_distance_multiplier: float = 2.9

@export_group("Visual Identity & Gear")
@export var cloak_color: Color = Color(0.09, 0.09, 0.12, 1.0)
@export var accent_color: Color = Color(0.86, 0.10, 0.18, 1.0)
@export var default_weapon: WeaponData = null

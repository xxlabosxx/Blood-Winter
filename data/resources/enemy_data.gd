class_name EnemyData
extends Resource
## Resource defining a lethal enemy's stats, tactical AI timings, and air-juggle physics.

@export var enemy_name: String = "Crimson Duelist"
@export var max_health: float = 160.0

@export_group("Tactical Movement")
@export var patrol_speed: float = 3.2
@export var chase_speed: float = 6.2
@export var strafe_speed: float = 4.6
@export var detection_range: float = 18.0
@export var preferred_combat_distance: float = 3.6
@export var attack_range: float = 2.9

@export_group("Lethal Strike & Telegraph")
@export var attack_damage: float = 28.0
@export var telegraph_duration: float = 0.48
@export var attack_active_duration: float = 0.14
@export var attack_recovery_duration: float = 0.56
@export var attack_lunge_speed: float = 13.5
@export var attack_cooldown: float = 1.15

@export_group("Tactical Evasion")
@export var evade_chance: float = 0.42
@export var evade_speed: float = 12.0
@export var evade_duration: float = 0.24
@export var evade_cooldown: float = 2.2

@export_group("Reaction & Air Juggle Physics")
@export var hitstun_duration: float = 0.34
@export var knockback_resistance: float = 0.15
@export var gravity_scale_when_juggled: float = 0.36
@export var air_juggle_hover_impulse: float = 4.4

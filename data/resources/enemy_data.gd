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
@export var attack_damage: float = 10.0
@export var telegraph_duration: float = 0.44
@export var attack_active_duration: float = 0.14
@export var attack_recovery_duration: float = 0.58
@export var attack_lunge_speed: float = 13.5
@export var attack_cooldown: float = 1.15

@export_group("Combo & Heavy Knockback Finisher")
@export var combo_max_hits: int = 3
@export var combo_step_telegraph_duration: float = 0.17
@export var combo_step_active_duration: float = 0.13
@export var combo_step_lunge_speed: float = 10.5
@export var combo_chase_range: float = 4.3
@export var finisher_telegraph_duration: float = 0.42
@export var finisher_active_duration: float = 0.18
@export var finisher_lunge_speed: float = 15.5
@export var finisher_knockback_force: float = 17.5
@export var finisher_launch_force: float = 8.4
@export var finisher_hitstun_duration: float = 0.62

@export_group("Tactical Evasion")
@export var evade_chance: float = 0.42
@export var evade_speed: float = 12.0
@export var evade_duration: float = 0.24
@export var evade_cooldown: float = 2.2

@export_group("Reaction & Air Juggle Physics")
@export var hitstun_duration: float = 0.36
@export var knockback_resistance: float = 0.15
## Base gravity multiplier while suspended in AIR_JUGGLE (15%-30% of base gravity per Bayonetta 2 spec).
@export var gravity_scale_when_juggled: float = 0.22
## Vertical micro-impulse applied on each air hit after stalling V.y to 0.
@export var air_juggle_hover_impulse: float = 3.2

@export_group("Poise / Super Armor & Anti-Infinite Rules")
## Invisible Poise pool. While > 0 in COMBAT_ACTIVE, heavy/elite enemies resist Launch until staggered.
@export var max_poise: float = 65.0
## Seconds after last hit before Poise begins regenerating.
@export var poise_regen_delay: float = 2.6
## Poise recovered per second once regeneration starts.
@export var poise_regen_rate: float = 24.0
## Duration of the vulnerable DIZZY / STAGGER window after Poise breaks (allows guaranteed Launch).
@export var dizzy_duration: float = 2.4
## Progressive Hitstun Decay per consecutive air hit: HitstunAtual = HitstunBase * (decay ^ N).
@export var hitstun_decay_factor: float = 0.95
## Progressive Gravity Scaling per consecutive air hit: GravidadeAtual = G_juggle * (scaling ^ N).
@export var gravity_scaling_factor: float = 1.05
## Maximum number of Ground Bounces allowed within a single combo before forcing Knockdown.
@export var max_ground_bounces: int = 1
## Upward velocity applied when a Ground Bounce triggers.
@export var ground_bounce_velocity: float = 8.4
## Invulnerable recovery duration on the ground after Knockdown.
@export var knockdown_recovery_duration: float = 0.55
## Consecutive air hits before an elite (non-Dizzy) enemy can trigger an Air Breakaway / Escape.
@export var air_breakaway_hit_threshold: int = 5
## Probability [0..1] of executing an Air Breakaway on each hit at or beyond threshold.
@export var air_breakaway_chance: float = 0.45
## Horizontal tether strength [0..1] matching attacker forward displacement during air combos.
@export var air_tether_strength: float = 0.85

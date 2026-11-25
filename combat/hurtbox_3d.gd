class_name Hurtbox3D
extends Area3D
## Receives combat hits from Hitbox3D areas and forwards them to the owning entity.
## Keeping reception decoupled lets the owner intercept hits for i-frames or Crimson Parry.

signal hit_received(info: DamageInfo)

@export var owner_entity: Node3D = null


func receive_hit(info: DamageInfo) -> void:
	hit_received.emit(info)

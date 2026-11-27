extends Node
## Global separated time-dilation controller (Bayonetta 2 Witch Time architecture).
## Modulates `world_time_scale` for enemies, projectiles, and hazards while keeping
## `player_time_scale` at 1.0 so the player retains full combat speed.

signal witch_time_started(duration: float, world_scale: float)
signal witch_time_ended()

var world_time_scale: float = 1.0
var player_time_scale: float = 1.0
var is_witch_time_active: bool = false
var witch_time_remaining: float = 0.0


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not is_witch_time_active:
		return
	var real_delta: float = delta / maxf(Engine.time_scale, 0.01)
	witch_time_remaining -= real_delta
	if witch_time_remaining <= 0.0:
		cancel_witch_time()


func trigger_witch_time(duration: float = 2.6, world_scale: float = 0.25) -> void:
	if duration <= 0.01:
		return
	var was_active: bool = is_witch_time_active
	world_time_scale = clampf(world_scale, 0.05, 1.0)
	witch_time_remaining = maxf(witch_time_remaining, duration)
	is_witch_time_active = true
	if not was_active:
		var gfm: Node = get_tree().root.get_node_or_null("GameFeelManager") if is_inside_tree() else null
		if gfm != null and gfm.has_method("log_combat_event"):
			gfm.call("log_combat_event", "WITCH TIME ACTIVATED! (%.2fx for %.1fs)" % [world_time_scale, witch_time_remaining])
	witch_time_started.emit(witch_time_remaining, world_time_scale)


func cancel_witch_time() -> void:
	if not is_witch_time_active and is_equal_approx(world_time_scale, 1.0):
		return
	world_time_scale = 1.0
	witch_time_remaining = 0.0
	is_witch_time_active = false
	witch_time_ended.emit()


func get_enemy_delta(delta: float) -> float:
	return delta * world_time_scale


func get_player_delta(delta: float) -> float:
	return delta * player_time_scale

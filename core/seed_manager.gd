extends Node
## Deterministic seed orchestration for Blood Winter.
## Supports the "Fixed Anchor (Base) + Daily Procedural Rings/Zones" architecture.

signal run_seed_changed(new_seed: int)
signal day_changed(new_day: int)

const DOMAIN_MAP: StringName = &"map"
const DOMAIN_LOOT: StringName = &"loot"
const DOMAIN_ENEMIES: StringName = &"enemies"
const DOMAIN_EVENTS: StringName = &"events"

var run_seed: int = 0
var current_day: int = 1


func _ready() -> void:
	initialize_run()


func initialize_run(custom_seed: int = -1) -> int:
	if custom_seed < 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		run_seed = abs(rng.randi())
	else:
		run_seed = abs(custom_seed)
	current_day = 1
	run_seed_changed.emit(run_seed)
	day_changed.emit(current_day)
	return run_seed


func set_current_day(day: int) -> void:
	current_day = maxi(1, day)
	day_changed.emit(current_day)


func advance_day() -> int:
	current_day += 1
	day_changed.emit(current_day)
	return current_day


## Derives a stable, deterministic sub-seed from (run_seed, day, domain).
func get_daily_seed(day: int, domain: StringName) -> int:
	var key: String = "%d|%d|%s" % [run_seed, day, String(domain)]
	var h: int = 2166136261
	var utf8: PackedByteArray = key.to_utf8_buffer()
	for b: int in utf8:
		h = (h ^ b) & 0x7FFFFFFF
		h = (h * 16777619) & 0x7FFFFFFF
	# Mix bits for better distribution across adjacent days
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0x7FFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return h


func create_rng_for_day(day: int, domain: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = get_daily_seed(day, domain)
	return rng


func get_debug_summary() -> String:
	return "Run #%d | Day %d (Map:%d Loot:%d Mob:%d)" % [
		run_seed,
		current_day,
		get_daily_seed(current_day, DOMAIN_MAP) % 100000,
		get_daily_seed(current_day, DOMAIN_LOOT) % 100000,
		get_daily_seed(current_day, DOMAIN_ENEMIES) % 100000,
	]

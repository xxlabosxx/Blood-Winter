class_name CombatModifierComponent
extends Node
## Scalable stat-modifier & buff/debuff container for any entity.
## Future skills, relics, passives, and temporary buffs register named modifiers
## that cleanly stack multiplicatively or additively without hardcoding class checks.

enum ModMode {
	MULTIPLY,
	ADD,
}

signal modifier_added(id: StringName)
signal modifier_removed(id: StringName)
signal modifiers_changed()

# { id: { "stat_key": StringName, "value": float, "mode": ModMode, "remaining": float } }
var _modifiers: Dictionary = {}


func add_modifier(
	id: StringName,
	stat_key: StringName,
	value: float,
	duration: float = -1.0,
	mode: ModMode = ModMode.MULTIPLY
) -> void:
	_modifiers[id] = {
		"stat_key": stat_key,
		"value": value,
		"mode": mode,
		"remaining": duration,
	}
	modifier_added.emit(id)
	modifiers_changed.emit()


func remove_modifier(id: StringName) -> void:
	if _modifiers.erase(id):
		modifier_removed.emit(id)
		modifiers_changed.emit()


func clear_all() -> void:
	if _modifiers.is_empty():
		return
	_modifiers.clear()
	modifiers_changed.emit()


func get_multiplier(stat_key: StringName, default_val: float = 1.0) -> float:
	var result: float = default_val
	for id: StringName in _modifiers.keys():
		var entry: Dictionary = _modifiers[id]
		if entry["stat_key"] == stat_key and int(entry["mode"]) == ModMode.MULTIPLY:
			result *= float(entry["value"])
	return result


func get_additive(stat_key: StringName, default_val: float = 0.0) -> float:
	var result: float = default_val
	for id: StringName in _modifiers.keys():
		var entry: Dictionary = _modifiers[id]
		if entry["stat_key"] == stat_key and int(entry["mode"]) == ModMode.ADD:
			result += float(entry["value"])
	return result


func get_active_count() -> int:
	return _modifiers.size()


func tick(delta: float) -> void:
	if _modifiers.is_empty():
		return
	var expired: Array[StringName] = []
	for id: StringName in _modifiers.keys():
		var entry: Dictionary = _modifiers[id]
		var rem: float = float(entry["remaining"])
		if rem > 0.0:
			rem -= delta
			if rem <= 0.0:
				expired.append(id)
			else:
				entry["remaining"] = rem
	if not expired.is_empty():
		for id: StringName in expired:
			_modifiers.erase(id)
			modifier_removed.emit(id)
		modifiers_changed.emit()

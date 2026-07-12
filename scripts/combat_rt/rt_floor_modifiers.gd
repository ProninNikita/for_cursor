class_name RTFloorModifiers
extends RefCounted

var values: Dictionary = {}

static func with_defaults(defaults: Dictionary, raw_modifiers):
	var modifiers := new()
	modifiers.values = defaults.duplicate(true)
	if raw_modifiers is Dictionary:
		for key in raw_modifiers.keys():
			modifiers.values[key] = raw_modifiers[key]
	return modifiers

func to_dictionary() -> Dictionary:
	return values.duplicate(true)

func get_float(key: String, fallback: float = 0.0) -> float:
	return float(values.get(key, fallback))

func get_bool(key: String, fallback: bool = false) -> bool:
	return bool(values.get(key, fallback))

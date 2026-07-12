class_name RTBrainClassBehavior
extends RefCounted

func apply_personality_envelope(unit, values: Dictionary) -> Dictionary:
	var result := values.duplicate(true)
	var class_id := _unit_class_id(unit)
	var personality := _personality(unit)
	match class_id:
		"berserker":
			_clamp_value(result, "caution", 0.0, 0.58)
			_clamp_value(result, "aggression", 0.54, 1.0)
			_clamp_value(result, "self_preserve", 0.0, 0.68)
		"healer":
			_clamp_value(result, "teamwork", 0.5, 1.0)
			_clamp_value(result, "aggression", 0.0, 0.72)
		"assassin", "scout":
			_clamp_value(result, "cover_usage", 0.35, 1.0)
			_clamp_value(result, "skill_patience", 0.32, 1.0)
		"defender":
			_clamp_value(result, "teamwork", 0.42, 1.0)
			_clamp_value(result, "self_preserve", 0.28, 1.0)
		_:
			pass
	if personality.contains("агрессив") or personality.contains("храбр"):
		_clamp_value(result, "aggression", 0.45, 1.0)
		_clamp_value(result, "caution", 0.0, 0.76)
	elif personality.contains("осторож") or personality.contains("расч"):
		_clamp_value(result, "caution", 0.38, 1.0)
		_clamp_value(result, "skill_patience", 0.34, 1.0)
	elif personality.contains("одиноч"):
		_clamp_value(result, "teamwork", 0.0, 0.7)
		_clamp_value(result, "cover_usage", 0.32, 1.0)
	return result

func _clamp_value(values: Dictionary, key: String, low: float, high: float) -> void:
	values[key] = clampf(float(values.get(key, 0.5)), low, high)

func _unit_class_id(unit) -> String:
	if unit != null and unit.character_data != null:
		return str(unit.character_data.character_class).to_lower()
	return ""

func _personality(unit) -> String:
	if unit != null and unit.character_data != null:
		return str(unit.character_data.personality_trait).to_lower()
	return ""

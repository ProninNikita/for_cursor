class_name RTBrainAbilityTargeting
extends RefCounted

func friendly_fire_penalty_multiplier(unit) -> float:
	if unit == null:
		return 1.0
	var caution: float = unit.brain_value("caution")
	var teamwork: float = unit.brain_value("teamwork")
	var aggression: float = unit.brain_value("aggression")
	return clampf(0.85 + caution * 0.35 + teamwork * 0.32 - aggression * 0.18, 0.7, 1.55)

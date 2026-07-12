class_name RTBrainSurvival
extends RefCounted

func panic_score(
	unit,
	hp: float,
	self_preserve: float,
	pain_fear: float,
	alone_fear: float,
	threat_fear: float,
	visibility_fear: float
) -> float:
	var value: float = (1.0 - hp) * self_preserve
	value += unit.fear * 0.7
	value += pain_fear + alone_fear + threat_fear + visibility_fear
	value -= unit.morale * 0.45
	return clampf(value, 0.0, 1.0)

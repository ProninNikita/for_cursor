class_name RTBrainCombat
extends RefCounted

func attack_score(unit, enemy, aggression: float, focus_fire: float, panic: float, is_focus_target: bool) -> float:
	var score: float = aggression * 1.35
	if enemy != null:
		score += focus_fire * (1.0 - enemy.hp_ratio())
	if is_focus_target:
		score += focus_fire * 0.55 + unit.brain_value("teamwork") * 0.18
	score -= panic * 0.7
	return score

class_name RTBrainFormation
extends RefCounted

func choke_point_intent(unit, enemy, battlefield, teamwork: float, caution: float, panic: float) -> Dictionary:
	if unit == null or enemy == null or battlefield == null:
		return {}
	if not _is_guard(unit):
		return {}
	var best: Vector2i = unit.grid_pos
	var best_score: float = -INF
	for candidate in battlefield.get_neighbors(unit.grid_pos):
		if battlefield.is_occupied(candidate, unit.unit_id):
			continue
		if not _is_choke_tile(candidate, battlefield):
			continue
		if not battlefield.has_line_of_sight(candidate, enemy.grid_pos):
			continue
		var enemy_distance: float = Vector2(candidate - enemy.grid_pos).length()
		var score: float = 0.62 + teamwork * 0.45 + caution * 0.28 - panic * 0.25
		score += maxf(0.0, 4.0 - enemy_distance) * 0.08
		if score > best_score:
			best = candidate
			best_score = score
	if best == unit.grid_pos:
		return {}
	return {
		"type": "hold_choke",
		"reason": "держит узкий проход",
		"destination": best,
		"score": best_score,
		"raw_score": best_score,
		"target": enemy,
		"ability": null,
		"targets": []
	}

func _is_guard(unit) -> bool:
	if unit.character_data != null:
		var class_id := str(unit.character_data.character_class).to_lower()
		if class_id in ["defender", "warrior"]:
			return true
	return unit.battle_unit != null and unit.battle_unit.def >= 6

func _is_choke_tile(pos: Vector2i, battlefield) -> bool:
	if battlefield.is_narrow(pos) or battlefield.is_door(pos):
		return true
	var walkable_neighbors := 0
	for neighbor in battlefield.get_neighbors(pos):
		if battlefield.is_walkable(neighbor):
			walkable_neighbors += 1
	return walkable_neighbors <= 2

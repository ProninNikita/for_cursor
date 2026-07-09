class_name RTUtilityBrain
extends RefCounted

func choose_intent(unit, units: Array, battlefield, rng: RandomNumberGenerator) -> Dictionary:
	if not unit.is_alive():
		return _intent("dead", "не может действовать")

	var allies: Array = _living_allies(unit, units)
	var unseen_enemies: Array = _living_enemies(unit, units)
	var visible_enemies: Array = unit.visible_enemies
	var nearest_enemy = _nearest_unit(unit, visible_enemies)
	var nearest_ally = _nearest_unit(unit, allies)
	var nearest_unseen_enemy = _nearest_unit(unit, unseen_enemies)
	var hp: float = unit.hp_ratio()
	var aggression: float = unit.brain_value("aggression")
	var caution: float = unit.brain_value("caution")
	var teamwork: float = unit.brain_value("teamwork")
	var self_preserve: float = unit.brain_value("self_preserve")
	var cover_usage: float = unit.brain_value("cover_usage")
	var focus_fire: float = unit.brain_value("focus_fire")
	var pain_fear: float = _pain_fear(unit)
	var alone_fear: float = _alone_fear(unit, nearest_ally)
	var threat_fear: float = _threat_fear(unit, visible_enemies)
	var panic: float = clampf((1.0 - hp) * self_preserve + unit.fear * 0.7 + pain_fear + alone_fear + threat_fear - unit.morale * 0.45, 0.0, 1.0)

	var best: Dictionary = _intent("hold", "оценивает поле боя", unit.grid_pos, -999.0)

	if nearest_enemy != null:
		var enemy_distance: float = _grid_distance(unit.grid_pos, nearest_enemy.grid_pos)
		var attack_score: float = aggression * 1.35 + focus_fire * (1.0 - nearest_enemy.hp_ratio()) - panic * 0.7
		if enemy_distance <= unit.attack_range_tiles:
			best = _pick_better(best, _intent("attack", "видит цель и готов атаковать", unit.grid_pos, attack_score + 0.9, nearest_enemy))
		else:
			var chase_score: float = attack_score - enemy_distance * 0.08
			best = _pick_better(best, _intent("chase", "двигается к замеченному врагу", nearest_enemy.grid_pos, chase_score, nearest_enemy))

		var cover_pos: Vector2i = battlefield.find_nearest_cover(unit.grid_pos, nearest_enemy.grid_pos)
		if cover_pos != unit.grid_pos:
			var cover_score: float = caution * 0.55 + cover_usage * 0.65 + panic * 1.35 - aggression * 0.45 - hp * 0.2
			best = _pick_better(best, _intent("take_cover", "ищет укрытие от видимого врага", cover_pos, cover_score, nearest_enemy))

		var retreat_pos: Vector2i = _retreat_position(unit, nearest_enemy, battlefield)
		var retreat_score: float = panic * 1.8 + (1.0 - hp) * 0.9 - aggression * 0.45
		best = _pick_better(best, _intent("retreat", "страх и раны заставляют отступать", retreat_pos, retreat_score, nearest_enemy))

		if unit.side == BattleUnit.UnitSide.ALLY and (unit.battle_unit != null and unit.battle_unit.atk >= 9):
			var ambush_pos: Vector2i = battlefield.find_nearest_cover(unit.grid_pos, nearest_enemy.grid_pos, 5)
			var ambush_score: float = caution * 0.55 + focus_fire * 0.45 - panic * 0.15
			best = _pick_better(best, _intent("ambush", "готовит засаду из укрытия", ambush_pos, ambush_score, nearest_enemy))

	elif nearest_ally != null:
		var follow_pos: Vector2i = battlefield.find_position_near(unit.grid_pos, nearest_ally.grid_pos, 1)
		var follow_score: float = teamwork * 0.8 + alone_fear * 1.2 + caution * 0.25
		best = _pick_better(best, _intent("follow", "держится ближе к союзникам", follow_pos, follow_score, nearest_ally))

		var scout_score: float = 0.95 + aggression * 0.45 + unit.brain_value("skill_patience") * 0.2 - alone_fear * 0.25
		var patrol_pos: Vector2i = _patrol_position(unit, battlefield, rng)
		var scout_reason := "прочёсывает область и ищет контакт"
		if nearest_unseen_enemy != null:
			patrol_pos = _advance_position_towards(unit, nearest_unseen_enemy.grid_pos, battlefield)
			scout_score += 0.35
			scout_reason = "двигается на шум и признаки врага"
		best = _pick_better(best, _intent("patrol", scout_reason, patrol_pos, scout_score))
	else:
		var lonely_patrol_pos := _patrol_position(unit, battlefield, rng)
		if nearest_unseen_enemy != null:
			lonely_patrol_pos = _advance_position_towards(unit, nearest_unseen_enemy.grid_pos, battlefield)
		best = _pick_better(best, _intent("patrol", "один на поле и осторожно двигается", lonely_patrol_pos, 0.8))

	if best["score"] < 0.15:
		return _intent("hold", "не видит надёжного действия", unit.grid_pos, best["score"])
	return best

func _intent(type: String, reason: String, destination: Vector2i = Vector2i.ZERO, score: float = 0.0, target = null) -> Dictionary:
	return {
		"type": type,
		"reason": reason,
		"destination": destination,
		"score": score,
		"target": target
	}

func _pick_better(current: Dictionary, candidate: Dictionary) -> Dictionary:
	if float(candidate.get("score", 0.0)) > float(current.get("score", 0.0)):
		return candidate
	return current

func _living_allies(unit, units: Array) -> Array:
	var result: Array = []
	for other in units:
		if other != unit and other.is_alive() and other.side == unit.side:
			result.append(other)
	return result

func _living_enemies(unit, units: Array) -> Array:
	var result: Array = []
	for other in units:
		if other != unit and other.is_alive() and other.side != unit.side:
			result.append(other)
	return result

func _nearest_unit(unit, candidates: Array):
	var best = null
	var best_distance: float = INF
	for candidate in candidates:
		var distance: float = _grid_distance(unit.grid_pos, candidate.grid_pos)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _pain_fear(unit) -> float:
	var near_deaths: int = 0
	if unit.character_data != null:
		near_deaths = int(unit.character_data.combat_brain.get("near_deaths", 0))
	return minf(0.22, float(near_deaths) * 0.035)

func _alone_fear(unit, nearest_ally) -> float:
	if nearest_ally == null:
		return unit.brain_value("teamwork") * 0.28
	var distance: float = _grid_distance(unit.grid_pos, nearest_ally.grid_pos)
	if distance <= 3.0:
		return 0.0
	return clampf((distance - 3.0) * 0.06 * unit.brain_value("teamwork"), 0.0, 0.24)

func _threat_fear(unit, enemies: Array) -> float:
	var fear: float = 0.0
	for enemy in enemies:
		if enemy.battle_unit != null and unit.battle_unit != null and enemy.battle_unit.max_hp > unit.battle_unit.max_hp * 1.25:
			fear += 0.08
		if _grid_distance(unit.grid_pos, enemy.grid_pos) <= 2.0:
			fear += 0.06
	return clampf(fear, 0.0, 0.28)

func _retreat_position(unit, enemy, battlefield) -> Vector2i:
	var away: Vector2 = Vector2(unit.grid_pos - enemy.grid_pos)
	if away.length() <= 0.01:
		away = Vector2.RIGHT if unit.side == BattleUnit.UnitSide.ALLY else Vector2.LEFT
	var desired: Vector2i = unit.grid_pos + Vector2i(roundi(away.normalized().x * 4.0), roundi(away.normalized().y * 4.0))
	desired.x = clampi(desired.x, 1, battlefield.width - 2)
	desired.y = clampi(desired.y, 1, battlefield.height - 2)
	if battlefield.is_walkable(desired):
		return desired
	return battlefield.find_nearest_cover(unit.grid_pos, enemy.grid_pos)

func _patrol_position(unit, battlefield, rng: RandomNumberGenerator) -> Vector2i:
	var bias: Vector2i = Vector2i.RIGHT if unit.side == BattleUnit.UnitSide.ALLY else Vector2i.LEFT
	var forward: Vector2i = unit.grid_pos + Vector2i(4 * bias.x, rng.randi_range(-2, 2))
	forward.x = clampi(forward.x, 1, battlefield.width - 2)
	forward.y = clampi(forward.y, 1, battlefield.height - 2)
	if battlefield.is_walkable(forward):
		return forward
	for _i in 8:
		var offset: Vector2i = Vector2i(rng.randi_range(-2, 4) * bias.x, rng.randi_range(-3, 3))
		var candidate: Vector2i = unit.grid_pos + offset
		candidate.x = clampi(candidate.x, 1, battlefield.width - 2)
		candidate.y = clampi(candidate.y, 1, battlefield.height - 2)
		if battlefield.is_walkable(candidate):
			return candidate
	return unit.grid_pos

func _advance_position_towards(unit, target_pos: Vector2i, battlefield) -> Vector2i:
	if battlefield.is_walkable(target_pos):
		return target_pos
	var best: Vector2i = unit.grid_pos
	var best_score: float = INF
	for neighbor in battlefield.get_neighbors(target_pos):
		var score: float = _grid_distance(unit.grid_pos, neighbor)
		if score < best_score:
			best = neighbor
			best_score = score
	return best

func _grid_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

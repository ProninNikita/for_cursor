class_name RTUtilityBrain
extends RefCounted

func choose_intent(unit, units: Array, battlefield, rng: RandomNumberGenerator) -> Dictionary:
	if not unit.is_alive():
		return _intent("dead", "не может действовать")

	var candidates: Array[Dictionary] = []
	var allies: Array = _living_allies(unit, units)
	var visible_enemies: Array = unit.visible_enemies
	var nearest_enemy = _nearest_unit(unit, visible_enemies)
	var nearest_ally = _nearest_unit(unit, allies)
	var last_contact: Dictionary = _last_known_contact(unit)
	var has_last_contact := not last_contact.is_empty()
	var last_contact_pos: Vector2i = last_contact.get("pos", unit.grid_pos)
	var has_noise_contact: bool = unit.heard_noise_timer > 0.0
	var hp: float = unit.hp_ratio()
	var aggression: float = unit.brain_value("aggression")
	var caution: float = unit.brain_value("caution")
	var teamwork: float = unit.brain_value("teamwork")
	var self_preserve: float = unit.brain_value("self_preserve")
	var cover_usage: float = unit.brain_value("cover_usage")
	var focus_fire: float = unit.brain_value("focus_fire")
	match unit.squad_style:
		"aggressive":
			aggression = clampf(aggression + 0.12, 0.0, 1.0)
			focus_fire = clampf(focus_fire + 0.08, 0.0, 1.0)
		"cautious":
			caution = clampf(caution + 0.12, 0.0, 1.0)
			self_preserve = clampf(self_preserve + 0.08, 0.0, 1.0)
		"cohesive":
			teamwork = clampf(teamwork + 0.14, 0.0, 1.0)
			cover_usage = clampf(cover_usage + 0.05, 0.0, 1.0)
		_:
			pass
	var pain_fear: float = _pain_fear(unit)
	var alone_fear: float = _alone_fear(unit, nearest_ally)
	var threat_fear: float = _threat_fear(unit, visible_enemies)
	var visibility_fear: float = _visibility_fear(unit, nearest_ally)
	var panic: float = clampf((1.0 - hp) * self_preserve + unit.fear * 0.7 + pain_fear + alone_fear + threat_fear + visibility_fear - unit.morale * 0.45, 0.0, 1.0)
	var squad_focus = _squad_focus_target(unit, visible_enemies)
	if squad_focus != null:
		nearest_enemy = squad_focus
	var class_id: String = _unit_class_id(unit)

	var best: Dictionary = _consider_intent(unit, _intent("hold", "оценивает поле боя", unit.grid_pos, -999.0), candidates)
	best = _pick_better(best, _consider_intent(unit, _best_ability_intent(unit, allies, visible_enemies, battlefield, panic, rng), candidates))

	if nearest_enemy != null:
		var enemy_distance: float = _grid_distance(unit.grid_pos, nearest_enemy.grid_pos)
		var attack_score: float = aggression * 1.35 + focus_fire * (1.0 - nearest_enemy.hp_ratio()) - panic * 0.7
		var is_focus_target: bool = unit.squad_focus_target_id != "" and nearest_enemy.unit_id == unit.squad_focus_target_id
		if is_focus_target:
			attack_score += focus_fire * 0.55 + teamwork * 0.18

		var class_combat_intent: Dictionary = _class_combat_intent(unit, class_id, nearest_enemy, nearest_ally, allies, battlefield, aggression, caution, teamwork, panic, alone_fear, visibility_fear)
		if not class_combat_intent.is_empty():
			best = _pick_better(best, _consider_intent(unit, class_combat_intent, candidates))

		if _is_ranged_unit(unit):
			var preferred_min_range: float = _preferred_min_range(unit)
			if enemy_distance < preferred_min_range:
				var keep_pos: Vector2i = _ranged_position(unit, nearest_enemy, battlefield, true)
				if keep_pos != unit.grid_pos:
					var pressure: float = clampf((preferred_min_range - enemy_distance) / preferred_min_range, 0.0, 1.0)
					var keep_score: float = 1.15 + pressure * 1.35 + caution * 0.55 + panic * 0.45 + unit.brain_value("skill_patience") * 0.25 - aggression * 0.15
					best = _pick_better(best, _consider_intent(unit, _intent("keep_distance", "держит дистанцию для дальнего боя", keep_pos, keep_score, nearest_enemy), candidates))
		if enemy_distance <= unit.attack_range_tiles:
			var attack_reason: String = "фокусирует цель отряда" if is_focus_target else "видит цель и готов атаковать"
			best = _pick_better(best, _consider_intent(unit, _intent("attack", attack_reason, unit.grid_pos, attack_score + 0.9, nearest_enemy), candidates))
		else:
			var chase_score: float = attack_score - enemy_distance * 0.08
			var chase_destination: Vector2i = nearest_enemy.grid_pos
			var chase_reason := "двигается к замеченному врагу"
			if _is_ranged_unit(unit):
				chase_destination = _ranged_position(unit, nearest_enemy, battlefield, false)
				chase_reason = "выходит на дистанцию атаки"
			if is_focus_target:
				chase_reason = "сближается с целью отряда"
			best = _pick_better(best, _consider_intent(unit, _intent("chase", chase_reason, chase_destination, chase_score, nearest_enemy), candidates))

		if not _is_ranged_unit(unit) and enemy_distance > unit.attack_range_tiles:
			var flank_pos: Vector2i = _flank_position(unit, nearest_enemy, battlefield)
			if flank_pos != unit.grid_pos:
				var flank_score: float = attack_score + focus_fire * 0.45 + unit.brain_value("skill_patience") * 0.25 - panic * 0.25
				best = _pick_better(best, _consider_intent(unit, _intent("flank", "ищет боковой заход", flank_pos, flank_score, nearest_enemy), candidates))

		var cover_pos: Vector2i = battlefield.find_nearest_cover(unit.grid_pos, nearest_enemy.grid_pos)
		if cover_pos != unit.grid_pos:
			var cover_score: float = caution * 0.55 + cover_usage * 0.65 + panic * 1.35 + visibility_fear * 0.45 - aggression * 0.45 - hp * 0.2
			best = _pick_better(best, _consider_intent(unit, _intent("take_cover", "ищет укрытие от видимого врага", cover_pos, cover_score, nearest_enemy), candidates))

		var retreat_pos: Vector2i = _retreat_position(unit, nearest_enemy, battlefield)
		var retreat_score: float = panic * 1.8 + (1.0 - hp) * 0.9 - aggression * 0.45
		best = _pick_better(best, _consider_intent(unit, _intent("retreat", "страх и раны заставляют отступать", retreat_pos, retreat_score, nearest_enemy), candidates))

		var collapse_pressure: float = _team_collapse_pressure(unit, allies)
		if collapse_pressure > 0.45:
			var group_retreat_score: float = collapse_pressure * 1.45 + teamwork * 0.55 + self_preserve * 0.35 - aggression * 0.28
			best = _pick_better(best, _consider_intent(unit, _intent("group_retreat", "отходит вместе с проседающим отрядом", retreat_pos, group_retreat_score, nearest_enemy), candidates))

		if _is_guard_role(unit) and _guard_needed(unit, nearest_enemy, allies):
			var guard_pos: Vector2i = _guard_position(unit, nearest_enemy, allies, battlefield)
			if guard_pos != unit.grid_pos:
				var guard_score: float = teamwork * 0.55 + caution * 0.28 + unit.brain_value("leader_trust") * 0.18 + collapse_pressure * 0.45 - panic * 0.18
				best = _pick_better(best, _consider_intent(unit, _intent("guard_ally", "прикрывает слабую линию", guard_pos, guard_score, nearest_enemy), candidates))

		if _is_support_role(unit) and _support_reposition_needed(unit, nearest_enemy):
			var support_pos: Vector2i = _support_backline_position(unit, nearest_enemy, allies, battlefield)
			if support_pos != unit.grid_pos:
				var support_score: float = teamwork * 0.38 + caution * 0.42 + self_preserve * 0.24 + panic * 0.18 - aggression * 0.22
				best = _pick_better(best, _consider_intent(unit, _intent("support_backline", "держится за спинами союзников", support_pos, support_score, nearest_enemy), candidates))

		if unit.side == BattleUnit.UnitSide.ALLY and (unit.stealth_rating > 0.0 or (unit.battle_unit != null and unit.battle_unit.atk >= 9)):
			var ambush_pos: Vector2i = _ambush_position(unit, nearest_enemy, battlefield)
			if ambush_pos != unit.grid_pos:
				var ambush_score: float = caution * 0.55 + focus_fire * 0.45 + unit.stealth_rating * 1.15 - panic * 0.15
				best = _pick_better(best, _consider_intent(unit, _intent("ambush", "готовит засаду из укрытия", ambush_pos, ambush_score, nearest_enemy), candidates))

	elif unit.squad_focus_target_id != "" and unit.squad_focus_target_pos != Vector2i.ZERO:
		var assist_pos: Vector2i = _advance_position_towards(unit, unit.squad_focus_target_pos, battlefield)
		var assist_score: float = 1.05 + teamwork * 0.38 + focus_fire * 0.25 - alone_fear * 0.12
		best = _pick_better(best, _consider_intent(unit, _intent("chase", "идёт к цели отряда", assist_pos, assist_score), candidates))

	elif nearest_ally != null:
		var formation_intent: Dictionary = _formation_intent(unit, battlefield, teamwork, caution, alone_fear)
		if not formation_intent.is_empty():
			best = _pick_better(best, _consider_intent(unit, formation_intent, candidates))

		if _should_rally_to_leader(unit):
			var rally_pos: Vector2i = _rally_leader_position(unit, battlefield)
			var rally_score: float = teamwork * 0.95 + unit.brain_value("leader_trust") * 0.45 + alone_fear * 0.9 + visibility_fear * 0.55
			best = _pick_better(best, _consider_intent(unit, _intent("rally_leader", "собирается у лидера", rally_pos, rally_score), candidates))

		var follow_pos: Vector2i = battlefield.find_position_near(unit.grid_pos, nearest_ally.grid_pos, 1)
		var follow_score: float = teamwork * 0.8 + alone_fear * 1.2 + caution * 0.25 + visibility_fear * 0.5
		best = _pick_better(best, _consider_intent(unit, _intent("follow", "держится ближе к союзникам", follow_pos, follow_score, nearest_ally), candidates))

		var scout_probe_intent: Dictionary = _scout_probe_intent(unit, class_id, nearest_ally, battlefield, rng, aggression, alone_fear, visibility_fear)
		if not scout_probe_intent.is_empty():
			best = _pick_better(best, _consider_intent(unit, scout_probe_intent, candidates))

		var scout_score: float = 0.95 + aggression * 0.45 + unit.brain_value("skill_patience") * 0.2 - alone_fear * 0.25 - visibility_fear * 0.45
		var patrol_pos: Vector2i = _patrol_position(unit, battlefield, rng)
		var scout_reason := "прочёсывает область и ищет контакт"
		if has_last_contact:
			patrol_pos = _advance_position_towards(unit, last_contact_pos, battlefield)
			scout_score += 0.35
			scout_reason = "идёт к последнему контакту"
		elif has_noise_contact:
			patrol_pos = _advance_position_towards(unit, unit.heard_noise_pos, battlefield)
			scout_score += 0.18
			scout_reason = "проверяет услышанный шум"
		best = _pick_better(best, _consider_intent(unit, _intent("patrol", scout_reason, patrol_pos, scout_score), candidates))
	else:
		var solo_formation_intent: Dictionary = _formation_intent(unit, battlefield, teamwork, caution, alone_fear)
		if not solo_formation_intent.is_empty():
			best = _pick_better(best, _consider_intent(unit, solo_formation_intent, candidates))

		var lonely_patrol_pos := _patrol_position(unit, battlefield, rng)
		if has_last_contact:
			lonely_patrol_pos = _advance_position_towards(unit, last_contact_pos, battlefield)
		elif has_noise_contact:
			lonely_patrol_pos = _advance_position_towards(unit, unit.heard_noise_pos, battlefield)
		best = _pick_better(best, _consider_intent(unit, _intent("patrol", "один на поле и осторожно двигается", lonely_patrol_pos, 0.8), candidates))

	if best["score"] < 0.15:
		var hold_intent := _consider_intent(unit, _intent("hold", "не видит надёжного действия", unit.grid_pos, best["score"]), candidates)
		return _finalize_intent(unit, hold_intent, candidates, panic, rng)
	return _finalize_intent(unit, best, candidates, panic, rng)

func _intent(type: String, reason: String, destination: Vector2i = Vector2i.ZERO, score: float = 0.0, target = null, ability: AbilityData = null, targets: Array = []) -> Dictionary:
	return {
		"type": type,
		"reason": reason,
		"destination": destination,
		"score": score,
		"raw_score": score,
		"target": target,
		"ability": ability,
		"targets": targets
	}

func _consider_intent(unit, candidate: Dictionary, candidates: Array[Dictionary]) -> Dictionary:
	var weighted := _with_behavior_weights(unit, candidate)
	candidates.append(weighted)
	return weighted

func _with_behavior_weights(unit, intent: Dictionary) -> Dictionary:
	var weighted: Dictionary = intent.duplicate(true)
	var score := float(weighted.get("score", 0.0))
	score += _class_intent_bonus(unit, weighted)
	score += _ability_fit_bonus(unit, weighted)
	weighted["score"] = score
	return weighted

func _finalize_intent(unit, preferred: Dictionary, candidates: Array[Dictionary], panic: float, rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty():
		return _intent("hold", "не видит надёжного действия", unit.grid_pos, 0.0)

	var sorted: Array[Dictionary] = candidates.duplicate(true)
	sorted.sort_custom(Callable(self, "_sort_intent_scores_desc"))
	var confidence: float = _decision_confidence(unit, sorted, panic)
	var mistake_chance: float = _decision_mistake_chance(unit, confidence, panic)
	var final_intent := _apply_hysteresis(unit, preferred, sorted, confidence)
	final_intent = _apply_decision_mistake(unit, final_intent, sorted, confidence, mistake_chance, rng)
	return _decorate_decision(final_intent, sorted, confidence, mistake_chance)

func _sort_intent_scores_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("score", -INF)) > float(b.get("score", -INF))

func _decision_confidence(unit, sorted: Array[Dictionary], panic: float) -> float:
	if sorted.size() <= 1:
		return 0.82
	var top: float = float(sorted[0].get("score", 0.0))
	var second: float = float(sorted[1].get("score", 0.0))
	var margin: float = top - second
	var patience: float = unit.brain_value("skill_patience")
	var confidence: float = 0.18 + margin * 0.42 + patience * 0.2 + unit.morale * 0.18 - panic * 0.3
	return clampf(confidence, 0.0, 1.0)

func _decision_mistake_chance(unit, confidence: float, panic: float) -> float:
	var patience: float = unit.brain_value("skill_patience")
	var chance: float = (1.0 - confidence) * 0.1 + panic * 0.12 + (1.0 - patience) * 0.04
	if unit.intent in ["retreat", "keep_distance"]:
		chance *= 0.65
	match _unit_class_id(unit):
		"tactician":
			chance *= 0.72
		"scout":
			chance *= 0.9
		"berserker":
			chance *= 1.16
		_:
			pass
	return clampf(chance, 0.0, 0.24)

func _apply_hysteresis(unit, preferred: Dictionary, sorted: Array[Dictionary], confidence: float) -> Dictionary:
	if unit.decision_lock_timer <= 0.0:
		return preferred
	if unit.intent in ["", "idle", "dead"]:
		return preferred
	if str(preferred.get("type", "")) == unit.intent:
		return preferred

	var current_candidate := _candidate_for_current_intent(unit, sorted)
	if current_candidate.is_empty():
		return preferred
	var current_score: float = float(current_candidate.get("score", -INF))
	if current_score < 0.05:
		return preferred

	var margin: float = float(preferred.get("score", 0.0)) - current_score
	var switch_threshold: float = 0.2 + unit.brain_value("skill_patience") * 0.28 + confidence * 0.14
	if margin >= switch_threshold:
		var switched: Dictionary = preferred.duplicate(true)
		switched["shifted"] = true
		return switched

	var kept: Dictionary = current_candidate.duplicate(true)
	kept["hysteresis"] = true
	kept["reason"] = "%s, но держит план" % str(kept.get("reason", "оценивает ситуацию"))
	return kept

func _candidate_for_current_intent(unit, sorted: Array[Dictionary]) -> Dictionary:
	for candidate in sorted:
		if str(candidate.get("type", "")) == unit.intent:
			return candidate
	return {}

func _apply_decision_mistake(unit, chosen: Dictionary, sorted: Array[Dictionary], confidence: float, mistake_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	if sorted.size() <= 1 or mistake_chance <= 0.0:
		return chosen
	if rng.randf() >= mistake_chance:
		return chosen

	var max_index := mini(3, sorted.size() - 1)
	if max_index < 1:
		return chosen
	var mistake_index := rng.randi_range(1, max_index)
	var mistaken: Dictionary = sorted[mistake_index].duplicate(true)
	if float(mistaken.get("score", -INF)) < 0.05:
		return chosen
	mistaken["mistake"] = true
	mistaken["confidence_before_mistake"] = confidence
	mistaken["reason"] = "%s, но ошибается под давлением" % str(mistaken.get("reason", "оценивает ситуацию"))
	return mistaken

func _decorate_decision(intent: Dictionary, sorted: Array[Dictionary], confidence: float, mistake_chance: float) -> Dictionary:
	var decorated: Dictionary = intent.duplicate(true)
	var top_score := float(sorted[0].get("score", 0.0)) if not sorted.is_empty() else float(decorated.get("score", 0.0))
	var second_score := top_score
	if sorted.size() > 1:
		second_score = float(sorted[1].get("score", 0.0))
	decorated["confidence"] = confidence
	decorated["score_margin"] = top_score - second_score
	decorated["mistake_chance"] = mistake_chance
	decorated["scores"] = _decision_score_snapshots(sorted)
	return decorated

func _decision_score_snapshots(sorted: Array[Dictionary]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var limit := mini(6, sorted.size())
	for i in range(limit):
		var candidate := sorted[i]
		var ability: AbilityData = candidate.get("ability", null)
		snapshots.append({
			"type": str(candidate.get("type", "")),
			"reason": str(candidate.get("reason", "")),
			"score": float(candidate.get("score", 0.0)),
			"raw_score": float(candidate.get("raw_score", candidate.get("score", 0.0))),
			"ability": ability.name if ability != null else ""
		})
	return snapshots

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

func _best_ability_intent(unit, allies: Array, visible_enemies: Array, battlefield, panic: float, rng: RandomNumberGenerator) -> Dictionary:
	var best: Dictionary = _intent("hold", "не видит подходящей способности", unit.grid_pos, -999.0)
	if unit.battle_unit == null:
		return best
	for ability in unit.battle_unit.abilities:
		if ability == null or not unit.can_use_ability(ability):
			continue
		if ability.id == "basic_attack":
			continue
		var candidate: Dictionary = _score_ability(unit, ability, allies, visible_enemies, battlefield, panic, rng)
		best = _pick_better(best, candidate)
	return best

func _score_ability(unit, ability: AbilityData, allies: Array, visible_enemies: Array, battlefield, panic: float, rng: RandomNumberGenerator) -> Dictionary:
	var targets: Array = _targets_for_ability(unit, ability, allies, visible_enemies, battlefield)
	if targets.is_empty():
		return _intent("hold", "нет целей для способности", unit.grid_pos, -999.0)

	var primary = targets[0]
	var destination: Vector2i = primary.grid_pos if primary != null else unit.grid_pos
	var score: float = rng.randf() * 0.08 + ability.power * 0.35 + ability.rt_priority - ability.rt_cast_time * 0.08
	var reason: String = "использует %s" % ability.name
	if ability.rt_radius_tiles > 0.0 and targets.size() > 1:
		reason = "накрывает область: %s x%d" % [ability.name, targets.size()]

	match ability.type:
		AbilityData.AbilityType.DAMAGE:
			score += unit.brain_value("aggression") * 0.9 + unit.brain_value("focus_fire") * 0.55
			if primary != null:
				score += (1.0 - primary.hp_ratio()) * 0.85
			if ability.target_type == AbilityData.TargetType.ALL_ENEMIES:
				score += float(targets.size()) * 0.35
			if ability.rt_radius_tiles > 0.0:
				score += minf(0.45, ability.rt_radius_tiles * 0.18)
			score -= panic * 0.25
		AbilityData.AbilityType.HEAL:
			var missing: float = 1.0 - primary.hp_ratio()
			score += missing * 2.4 + unit.brain_value("teamwork") * 0.8 + unit.brain_value("caution") * 0.35
			if missing < 0.18:
				score -= 2.0
		AbilityData.AbilityType.BUFF:
			score += unit.brain_value("teamwork") * 0.45 + unit.brain_value("skill_patience") * 0.5
			if visible_enemies.is_empty():
				score -= 0.75
		AbilityData.AbilityType.DEBUFF:
			score += unit.brain_value("focus_fire") * 0.65 + unit.brain_value("skill_patience") * 0.35
			if primary != null:
				score += (1.0 - primary.hp_ratio()) * 0.35
		AbilityData.AbilityType.SPECIAL:
			score += unit.brain_value("skill_patience") * 0.5 + unit.brain_value("teamwork") * 0.35
			if visible_enemies.is_empty() and ability.target_type == AbilityData.TargetType.SELF:
				score -= 0.5
		_:
			score -= 1.0

	score += _class_ability_score_bonus(unit, ability, primary, targets, visible_enemies, panic)
	return _intent("ability", reason, destination, score, primary, ability, targets)

func _targets_for_ability(unit, ability: AbilityData, allies: Array, visible_enemies: Array, battlefield) -> Array:
	var result: Array = []
	match ability.target_type:
		AbilityData.TargetType.SELF:
			result.append(unit)
		AbilityData.TargetType.SINGLE_ALLY:
			var candidates: Array = allies.duplicate()
			candidates.append(unit)
			var best = _weakest_in_range(unit, candidates, ability, battlefield)
			if best != null:
				result.append(best)
		AbilityData.TargetType.ALL_ALLIES:
			var all_allies: Array = allies.duplicate()
			all_allies.append(unit)
			for ally in all_allies:
				if ability.type != AbilityData.AbilityType.HEAL or ally.hp_ratio() < 0.92:
					result.append(ally)
		AbilityData.TargetType.SINGLE_ENEMY:
			var enemy = _weakest_in_range(unit, visible_enemies, ability, battlefield)
			if enemy != null:
				if _offensive_area_ability(ability):
					result = _best_enemy_area_targets(unit, visible_enemies, ability, battlefield, enemy)
				else:
					result.append(enemy)
		AbilityData.TargetType.ALL_ENEMIES:
			if _offensive_area_ability(ability):
				result = _best_enemy_area_targets(unit, visible_enemies, ability, battlefield)
			else:
				for enemy in visible_enemies:
					if _target_in_ability_range(unit, enemy, ability, battlefield):
						result.append(enemy)
		_:
			pass
	return result

func _offensive_area_ability(ability: AbilityData) -> bool:
	return ability.rt_radius_tiles > 0.0 and ability.type in [
		AbilityData.AbilityType.DAMAGE,
		AbilityData.AbilityType.DEBUFF,
		AbilityData.AbilityType.SPECIAL
	]

func _best_enemy_area_targets(unit, visible_enemies: Array, ability: AbilityData, battlefield, preferred_center = null) -> Array:
	var best_targets: Array = []
	var best_score: float = -INF
	var centers: Array = []
	if preferred_center != null:
		centers.append(preferred_center)
	for enemy in visible_enemies:
		if enemy != preferred_center:
			centers.append(enemy)

	for center in centers:
		if center == null or not center.is_alive():
			continue
		if not _target_in_ability_range(unit, center, ability, battlefield):
			continue
		var cluster: Array = [center]
		var cluster_score: float = 1.0 + (1.0 - center.hp_ratio()) * 0.45
		for enemy in visible_enemies:
			if enemy == center or not enemy.is_alive():
				continue
			if _grid_distance(center.grid_pos, enemy.grid_pos) > ability.rt_radius_tiles:
				continue
			if not battlefield.has_line_of_sight(center.grid_pos, enemy.grid_pos):
				continue
			cluster.append(enemy)
			cluster_score += 1.0 + (1.0 - enemy.hp_ratio()) * 0.45
		if cluster_score > best_score:
			best_targets = cluster
			best_score = cluster_score
	return best_targets

func _weakest_in_range(unit, candidates: Array, ability: AbilityData, battlefield):
	var best = null
	for candidate in candidates:
		if not candidate.is_alive():
			continue
		if ability.target_type != AbilityData.TargetType.SELF and not _target_in_ability_range(unit, candidate, ability, battlefield):
			continue
		if best == null or candidate.hp_ratio() < best.hp_ratio():
			best = candidate
	return best

func _target_in_ability_range(unit, target, ability: AbilityData, battlefield) -> bool:
	if target == unit:
		return true
	var range_tiles: float = unit.ability_range_tiles(ability)
	if _grid_distance(unit.grid_pos, target.grid_pos) > range_tiles:
		return false
	if target.side != unit.side and not battlefield.has_line_of_sight(unit.grid_pos, target.grid_pos):
		return false
	return true

func _class_intent_bonus(unit, intent: Dictionary) -> float:
	var class_id := _unit_class_id(unit)
	var intent_type := str(intent.get("type", "hold"))
	var ability: AbilityData = intent.get("ability", null)
	var target = intent.get("target", null)
	var bonus := 0.0

	match class_id:
		"warrior":
			if intent_type in ["attack", "chase", "press_attack"]:
				bonus += 0.18
			elif intent_type == "guard_ally":
				bonus += 0.12
			elif intent_type == "flank":
				bonus += 0.08
			elif intent_type == "retreat":
				bonus -= 0.08
		"mage":
			if intent_type == "ability" and ability != null and ability.stat_used == "magic":
				bonus += 0.26
			elif intent_type in ["keep_distance", "safe_los"]:
				bonus += 0.2
			elif intent_type == "take_cover":
				bonus += 0.12
			elif intent_type == "attack":
				bonus -= 0.08
		"healer":
			if intent_type == "ability" and ability != null and ability.type in [AbilityData.AbilityType.HEAL, AbilityData.AbilityType.BUFF]:
				bonus += 0.34
			elif intent_type in ["follow", "panic_seek_ally"]:
				bonus += 0.18
			elif intent_type in ["take_cover", "keep_distance"]:
				bonus += 0.1
			elif intent_type in ["attack", "chase"]:
				bonus -= 0.16
		"scout":
			if intent_type in ["patrol", "flank", "scout_probe", "scout_flank"]:
				bonus += 0.2
			elif intent_type == "ambush":
				bonus += 0.22
			elif intent_type == "keep_distance":
				bonus += 0.08
		"defender":
			if intent_type in ["follow", "take_cover", "hold_line", "guard_ally"]:
				bonus += 0.18
			elif intent_type == "ability" and ability != null and ability.stat_used == "def":
				bonus += 0.18
			elif intent_type == "chase":
				bonus -= 0.08
		"berserker":
			if intent_type in ["attack", "chase", "berserk_charge"]:
				bonus += 0.32
			elif intent_type == "ability" and ability != null and ability.type == AbilityData.AbilityType.DAMAGE:
				bonus += 0.22
			elif intent_type in ["retreat", "take_cover", "keep_distance"]:
				bonus -= 0.24
		"tactician":
			if intent_type == "ability" and ability != null and ability.type in [AbilityData.AbilityType.BUFF, AbilityData.AbilityType.DEBUFF]:
				bonus += 0.24
			elif intent_type in ["flank", "follow", "tactical_position"]:
				bonus += 0.14
			elif intent_type == "patrol":
				bonus += 0.06
		"assassin":
			if intent_type in ["ambush", "flank", "assassin_pickoff"]:
				bonus += 0.3
			elif intent_type == "attack" and target != null and target.hp_ratio() < 0.45:
				bonus += 0.22
			elif intent_type in ["take_cover", "break_contact"]:
				bonus += 0.08
		"ranged":
			if intent_type == "keep_distance":
				bonus += 0.18
			elif intent_type == "chase":
				bonus -= 0.08
		"guard":
			if intent_type in ["take_cover", "follow"]:
				bonus += 0.12
		_:
			pass

	return bonus

func _ability_fit_bonus(unit, intent: Dictionary) -> float:
	var intent_type := str(intent.get("type", "hold"))
	var ability: AbilityData = intent.get("ability", null)
	var targets: Array = intent.get("targets", [])
	var bonus := 0.0

	if _is_ranged_unit(unit):
		if intent_type == "keep_distance":
			bonus += 0.12
		elif intent_type == "chase":
			bonus -= 0.06
	elif intent_type in ["attack", "chase"] and unit.attack_range_tiles <= 1.5:
		bonus += 0.05

	if unit.stealth_rating > 0.0 and intent_type in ["ambush", "flank", "take_cover"]:
		bonus += unit.stealth_rating * 0.22

	if ability == null:
		return bonus

	var best_stat: int = maxi(unit.get_stat("atk"), maxi(unit.get_stat("magic"), unit.get_stat("def")))
	var ability_stat: int = unit.get_stat(ability.stat_used)
	if best_stat > 0:
		bonus += clampf(float(ability_stat - best_stat) * 0.025, -0.12, 0.12)
	if ability.rt_radius_tiles > 0.0 and targets.size() > 1:
		bonus += 0.12 + minf(0.18, float(targets.size() - 1) * 0.06)

	match ability.type:
		AbilityData.AbilityType.HEAL:
			bonus += unit.brain_value("teamwork") * 0.16
		AbilityData.AbilityType.BUFF:
			bonus += unit.brain_value("skill_patience") * 0.12
		AbilityData.AbilityType.DEBUFF:
			bonus += unit.brain_value("focus_fire") * 0.12
		AbilityData.AbilityType.DAMAGE:
			bonus += unit.brain_value("aggression") * 0.1
		_:
			pass

	return bonus

func _unit_class_id(unit) -> String:
	if unit.character_data != null:
		return str(unit.character_data.character_class).to_lower()
	if _is_ranged_unit(unit):
		return "ranged"
	if unit.battle_unit != null and unit.battle_unit.def >= 5:
		return "guard"
	return "fighter"

func _squad_focus_target(unit, visible_enemies: Array):
	if unit.squad_focus_target_id == "":
		return null
	for enemy in visible_enemies:
		if enemy != null and enemy.is_alive() and enemy.unit_id == unit.squad_focus_target_id:
			return enemy
	return null

func _formation_intent(unit, battlefield, teamwork: float, caution: float, alone_fear: float) -> Dictionary:
	if unit.is_leader:
		return {}
	if unit.formation_slot == Vector2i.ZERO or unit.formation_slot == unit.grid_pos:
		return {}
	if unit.squad_focus_target_id != "" and not unit.visible_enemies.is_empty():
		return {}
	var distance: float = _grid_distance(unit.grid_pos, unit.formation_slot)
	if distance < 1.5:
		return {}
	if not battlefield.in_bounds(unit.formation_slot) or not battlefield.is_walkable(unit.formation_slot):
		return {}
	if battlefield.is_occupied(unit.formation_slot, unit.unit_id):
		return {}
	if battlefield.find_path(unit.grid_pos, unit.formation_slot, unit.unit_id, false).is_empty():
		return {}
	var score: float = 0.42 + teamwork * 0.45 + caution * 0.18 + alone_fear * 0.22
	if unit.squad_style == "cohesive":
		score += 0.3
	elif unit.squad_style == "cautious" and unit.formation_role == "backline":
		score += 0.18
	elif unit.squad_style == "aggressive" and unit.formation_role == "front":
		score += 0.12
	score += minf(0.28, distance * 0.045)
	return _intent("formation", "занимает позицию в строю", unit.formation_slot, score)

func _class_combat_intent(
	unit,
	class_id: String,
	enemy,
	nearest_ally,
	allies: Array,
	battlefield,
	aggression: float,
	caution: float,
	teamwork: float,
	panic: float,
	alone_fear: float,
	visibility_fear: float
) -> Dictionary:
	if enemy == null:
		return {}
	var enemy_distance: float = _grid_distance(unit.grid_pos, enemy.grid_pos)
	match class_id:
		"warrior":
			if enemy_distance > unit.attack_range_tiles:
				var press_pos := _engage_position(unit, enemy, battlefield)
				if press_pos == unit.grid_pos:
					press_pos = enemy.grid_pos
				var score: float = 0.82 + aggression * 0.75 + unit.morale * 0.25 - panic * 0.28 - enemy_distance * 0.04
				return _intent("press_attack", "уверенно сближается", press_pos, score, enemy)
		"defender":
			var line_pos := _line_hold_position(unit, enemy, allies, battlefield)
			var line_score: float = 0.72 + teamwork * 0.55 + caution * 0.42 + unit.brain_value("leader_trust") * 0.18 - panic * 0.12
			if _team_collapse_pressure(unit, allies) > 0.25:
				line_score += 0.22
			return _intent("hold_line", "держит линию между врагом и отрядом", line_pos, line_score, enemy)
		"healer":
			if nearest_ally != null and (alone_fear >= 0.1 or visibility_fear >= 0.08 or panic >= 0.38):
				var panic_pos: Vector2i = battlefield.find_position_near(unit.grid_pos, nearest_ally.grid_pos, 1, 4)
				if panic_pos != unit.grid_pos:
					var panic_score: float = 0.48 + alone_fear * 1.65 + visibility_fear * 0.8 + panic * 0.55
					return _intent("panic_seek_ally", "панически ищет союзника", panic_pos, panic_score, nearest_ally)
		"mage":
			var safe_pos := _safe_los_position(unit, enemy, battlefield)
			if safe_pos != unit.grid_pos:
				var safe_score: float = 0.72 + caution * 0.45 + unit.brain_value("skill_patience") * 0.36 + visibility_fear * 0.2 - aggression * 0.08
				return _intent("safe_los", "ищет безопасную линию огня", safe_pos, safe_score, enemy)
		"scout":
			if enemy_distance > unit.attack_range_tiles:
				var scout_pos := _scout_flank_position(unit, enemy, battlefield)
				if scout_pos != unit.grid_pos:
					var scout_score: float = 0.68 + aggression * 0.25 + unit.stealth_rating * 0.75 + unit.brain_value("skill_patience") * 0.18 - panic * 0.2
					return _intent("scout_flank", "использует траву и фланг", scout_pos, scout_score, enemy)
		"assassin":
			if _should_break_open_fight(unit, enemy, panic):
				var break_pos := _break_contact_position(unit, enemy, battlefield)
				if break_pos != unit.grid_pos:
					var break_score: float = 0.68 + panic * 0.72 + caution * 0.38 + unit.stealth_rating * 0.45
					return _intent("break_contact", "разрывает открытую драку", break_pos, break_score, enemy)
			if enemy_distance > unit.attack_range_tiles or enemy.hp_ratio() <= 0.55:
				var kill_pos := _scout_flank_position(unit, enemy, battlefield)
				if kill_pos != unit.grid_pos:
					var kill_score: float = 0.74 + aggression * 0.45 + (1.0 - enemy.hp_ratio()) * 0.65 + unit.stealth_rating * 0.55 - panic * 0.22
					return _intent("assassin_pickoff", "ищет слабое место цели", kill_pos, kill_score, enemy)
		"berserker":
			if enemy_distance > unit.attack_range_tiles:
				var charge_pos := _engage_position(unit, enemy, battlefield)
				if charge_pos == unit.grid_pos:
					charge_pos = enemy.grid_pos
				var charge_score: float = 0.98 + aggression * 0.95 + (1.0 - unit.hp_ratio()) * 0.18 - panic * 0.18 - enemy_distance * 0.025
				return _intent("berserk_charge", "рвётся в ближний бой", charge_pos, charge_score, enemy)
		"tactician":
			if enemy.unit_id == unit.squad_focus_target_id:
				var focus_pos := _tactician_focus_position(unit, enemy, allies, battlefield)
				if focus_pos != unit.grid_pos:
					var focus_score: float = 0.58 + teamwork * 0.5 + unit.brain_value("focus_fire") * 0.35 + unit.brain_value("skill_patience") * 0.32
					return _intent("tactical_position", "выбирает точку для фокуса", focus_pos, focus_score, enemy)
		_:
			pass
	return {}

func _scout_probe_intent(
	unit,
	class_id: String,
	nearest_ally,
	battlefield,
	rng: RandomNumberGenerator,
	aggression: float,
	alone_fear: float,
	visibility_fear: float
) -> Dictionary:
	if class_id != "scout":
		return {}
	var destination := _scout_probe_position(unit, nearest_ally, battlefield, rng)
	if destination == unit.grid_pos:
		return {}
	var score: float = 1.08 + aggression * 0.24 + unit.brain_value("skill_patience") * 0.22 + unit.stealth_rating * 0.22 - alone_fear * 0.32 - visibility_fear * 0.2
	return _intent("scout_probe", "быстро открывает карту", destination, score)

func _class_ability_score_bonus(unit, ability: AbilityData, primary, targets: Array, visible_enemies: Array, panic: float) -> float:
	var class_id := _unit_class_id(unit)
	var bonus := 0.0
	match class_id:
		"warrior":
			if ability.id == "heavy_strike" and primary != null:
				if primary.unit_id == unit.squad_focus_target_id:
					bonus += 0.34
				if primary.hp_ratio() <= 0.58 or primary.get_stat("def") >= 6:
					bonus += 0.28
			elif ability.id == "guard":
				bonus += clampf(panic, 0.0, 0.22)
		"defender":
			if ability.id == "taunt" and visible_enemies.size() >= 2:
				bonus += 0.42
			elif ability.id in ["fortify", "taunt"]:
				bonus += 0.22 + panic * 0.18
			elif ability.id == "shield_bash" and primary != null and _grid_distance(unit.grid_pos, primary.grid_pos) <= 1.5:
				bonus += 0.22
		"healer":
			if ability.type == AbilityData.AbilityType.HEAL and primary != null and primary.hp_ratio() <= 0.5:
				bonus += 0.36
			elif ability.id == "blessing" and not visible_enemies.is_empty():
				bonus += 0.18
		"mage":
			if ability.id == "fireball" and targets.size() >= 2:
				bonus += 0.42 + minf(0.22, float(targets.size() - 2) * 0.08)
			elif ability.id == "barrier" and primary != null and primary.hp_ratio() <= 0.72:
				bonus += 0.2
		"scout":
			if ability.id == "mark_target" and primary != null:
				bonus += 0.28 + (1.0 - primary.hp_ratio()) * 0.24
			elif ability.id == "evade" and panic > 0.25:
				bonus += 0.22
		"assassin":
			if ability.id in ["backstab", "poison_blade", "shadow_step"] and primary != null:
				bonus += (1.0 - primary.hp_ratio()) * 0.52
				if primary.unit_id == unit.squad_focus_target_id:
					bonus += 0.18
		"berserker":
			if ability.id == "bloodlust" and unit.hp_ratio() <= 0.72:
				bonus += 0.35
			elif ability.id == "reckless_charge" and unit.hp_ratio() >= 0.42:
				bonus += 0.34
			elif ability.id == "frenzy" and targets.size() >= 2:
				bonus += 0.38
		"tactician":
			if ability.id in ["command", "rally"]:
				bonus += 0.28 + unit.brain_value("teamwork") * 0.2
			elif ability.id == "tactical_strike" and primary != null and primary.unit_id == unit.squad_focus_target_id:
				bonus += 0.32
		_:
			pass
	return bonus

func _engage_position(unit, enemy, battlefield) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score: float = -INF
	for candidate in battlefield.get_neighbors(enemy.grid_pos):
		if not _reachable_combat_tile(unit, candidate, battlefield):
			continue
		var score: float = -_grid_distance(unit.grid_pos, candidate) * 0.22
		if battlefield.is_cover(candidate):
			score += 0.12
		if score > best_score:
			best = candidate
			best_score = score
	return best

func _line_hold_position(unit, enemy, allies: Array, battlefield) -> Vector2i:
	var anchor := _protected_anchor_position(unit, allies)
	var direction := Vector2(enemy.grid_pos - anchor)
	if direction.length() <= 0.01:
		return unit.grid_pos
	var ideal := anchor + Vector2i(roundi(direction.normalized().x * 2.0), roundi(direction.normalized().y * 2.0))
	ideal.x = clampi(ideal.x, 1, battlefield.width - 2)
	ideal.y = clampi(ideal.y, 1, battlefield.height - 2)
	return _best_reachable_near(unit, ideal, battlefield, 3, enemy.grid_pos)

func _protected_anchor_position(unit, allies: Array) -> Vector2i:
	var weakest = _weakest_ally_for_guard(unit, allies)
	if weakest != null:
		return weakest.grid_pos
	if unit.squad_anchor != Vector2i.ZERO:
		return unit.squad_anchor
	return unit.grid_pos

func _safe_los_position(unit, enemy, battlefield) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score: float = _safe_los_score(unit, unit.grid_pos, enemy, battlefield)
	var search_radius: int = ceili(unit.attack_range_tiles) + 2
	for y in range(maxi(1, unit.grid_pos.y - search_radius), mini(battlefield.height - 1, unit.grid_pos.y + search_radius + 1)):
		for x in range(maxi(1, unit.grid_pos.x - search_radius), mini(battlefield.width - 1, unit.grid_pos.x + search_radius + 1)):
			var candidate := Vector2i(x, y)
			if not _reachable_combat_tile(unit, candidate, battlefield):
				continue
			var score := _safe_los_score(unit, candidate, enemy, battlefield)
			if score > best_score:
				best = candidate
				best_score = score
	return best

func _safe_los_score(unit, pos: Vector2i, enemy, battlefield) -> float:
	var enemy_distance: float = _grid_distance(pos, enemy.grid_pos)
	if enemy_distance > unit.attack_range_tiles or enemy_distance < _preferred_min_range(unit) * 0.85:
		return -INF
	if not battlefield.has_line_of_sight(pos, enemy.grid_pos):
		return -INF
	var score: float = -absf(enemy_distance - _preferred_max_range(unit)) * 0.34 - _grid_distance(unit.grid_pos, pos) * 0.14
	if battlefield.is_cover(pos):
		score += 0.42
	elif battlefield.is_grass(pos):
		score += 0.16
	if enemy_distance >= _preferred_min_range(unit):
		score += 0.18
	return score

func _scout_flank_position(unit, enemy, battlefield) -> Vector2i:
	var ambush_pos := _ambush_position(unit, enemy, battlefield)
	if ambush_pos != unit.grid_pos:
		return ambush_pos
	return _flank_position(unit, enemy, battlefield)

func _should_break_open_fight(unit, enemy, panic: float) -> bool:
	if unit.hidden or unit.ambush_ready:
		return false
	if _grid_distance(unit.grid_pos, enemy.grid_pos) > unit.attack_range_tiles + 0.5:
		return false
	if enemy.hp_ratio() <= 0.42:
		return false
	if unit.hp_ratio() <= 0.62:
		return true
	return panic >= 0.36 and unit.stealth_rating > 0.0

func _break_contact_position(unit, enemy, battlefield) -> Vector2i:
	var cover: Vector2i = battlefield.find_nearest_cover(unit.grid_pos, enemy.grid_pos, 6)
	if cover != unit.grid_pos and _reachable_combat_tile(unit, cover, battlefield):
		return cover
	var ambush_pos := _ambush_position(unit, enemy, battlefield)
	if ambush_pos != unit.grid_pos:
		return ambush_pos
	return _retreat_position(unit, enemy, battlefield)

func _tactician_focus_position(unit, enemy, allies: Array, battlefield) -> Vector2i:
	if _is_ranged_unit(unit):
		return _ranged_position(unit, enemy, battlefield, false)
	var anchor = _frontline_anchor(unit, allies)
	if anchor != null:
		return battlefield.find_position_near(unit.grid_pos, anchor.grid_pos, 2, 4)
	return unit.grid_pos

func _scout_probe_position(unit, nearest_ally, battlefield, rng: RandomNumberGenerator) -> Vector2i:
	var bias := 1 if unit.side == BattleUnit.UnitSide.ALLY else -1
	var best: Vector2i = unit.grid_pos
	var best_score: float = -INF
	var search_radius := 6
	for y in range(maxi(1, unit.grid_pos.y - search_radius), mini(battlefield.height - 1, unit.grid_pos.y + search_radius + 1)):
		for x in range(maxi(1, unit.grid_pos.x - search_radius), mini(battlefield.width - 1, unit.grid_pos.x + search_radius + 1)):
			var candidate := Vector2i(x, y)
			if not _reachable_combat_tile(unit, candidate, battlefield):
				continue
			var forward_progress := float((candidate.x - unit.grid_pos.x) * bias)
			if forward_progress < 1.0:
				continue
			var score: float = forward_progress * 0.3 - _grid_distance(unit.grid_pos, candidate) * 0.08 + rng.randf_range(0.0, 0.12)
			if battlefield.is_grass(candidate):
				score += 0.32
			elif battlefield.is_cover(candidate):
				score += 0.18
			if nearest_ally != null:
				var ally_distance: float = _grid_distance(candidate, nearest_ally.grid_pos)
				if ally_distance > 7.0:
					score -= (ally_distance - 7.0) * 0.18
			if score > best_score:
				best = candidate
				best_score = score
	return best

func _best_reachable_near(unit, ideal: Vector2i, battlefield, radius: int, threat_pos: Vector2i) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score: float = INF
	for y in range(ideal.y - radius, ideal.y + radius + 1):
		for x in range(ideal.x - radius, ideal.x + radius + 1):
			var candidate := Vector2i(x, y)
			if not _reachable_combat_tile(unit, candidate, battlefield):
				continue
			var score: float = _grid_distance(candidate, ideal) + _grid_distance(unit.grid_pos, candidate) * 0.12
			if battlefield.is_cover(candidate):
				score -= 0.15
			if _grid_distance(candidate, threat_pos) <= 1.5:
				score += 0.12
			if score < best_score:
				best = candidate
				best_score = score
	return best

func _reachable_combat_tile(unit, candidate: Vector2i, battlefield) -> bool:
	if not battlefield.in_bounds(candidate) or not battlefield.is_walkable(candidate):
		return false
	if battlefield.is_occupied(candidate, unit.unit_id):
		return false
	if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
		return false
	return true

func _is_guard_role(unit) -> bool:
	var class_id: String = _unit_class_id(unit)
	return class_id in ["defender", "warrior"] or (unit.battle_unit != null and unit.battle_unit.def >= 6)

func _is_support_role(unit) -> bool:
	var class_id: String = _unit_class_id(unit)
	return class_id in ["healer", "mage", "tactician"] or _is_ranged_unit(unit)

func _guard_needed(unit, enemy, allies: Array) -> bool:
	var protected = _weakest_ally_for_guard(unit, allies)
	if protected == null:
		return false
	if protected.hp_ratio() <= 0.68:
		return true
	if enemy != null and _grid_distance(protected.grid_pos, enemy.grid_pos) <= 3.0:
		return true
	return unit.squad_style == "cohesive" and protected.hp_ratio() <= 0.82 and unit.brain_value("teamwork") >= 0.62

func _support_reposition_needed(unit, enemy) -> bool:
	if enemy == null:
		return false
	var distance: float = _grid_distance(unit.grid_pos, enemy.grid_pos)
	if distance > unit.attack_range_tiles:
		return false
	if unit.hp_ratio() <= 0.58:
		return true
	if _is_ranged_unit(unit) and distance < _preferred_min_range(unit) + 0.7:
		return true
	var class_id: String = _unit_class_id(unit)
	return class_id == "healer" and distance <= 3.2

func _team_collapse_pressure(unit, allies: Array) -> float:
	var pressure: float = 0.0
	var total: int = 1
	if unit.hp_ratio() <= 0.35:
		pressure += 0.45
	for ally in allies:
		total += 1
		if ally.hp_ratio() <= 0.35:
			pressure += 0.35
		elif ally.fear >= 0.65:
			pressure += 0.16
	return clampf(pressure / float(total) * 2.0, 0.0, 1.0)

func _weakest_ally_for_guard(unit, allies: Array):
	var best = null
	var best_score: float = INF
	for ally in allies:
		if ally == null or not ally.is_alive():
			continue
		if _is_guard_role(ally):
			continue
		var score: float = ally.hp_ratio() + _grid_distance(unit.grid_pos, ally.grid_pos) * 0.04
		if score < best_score:
			best = ally
			best_score = score
	return best

func _guard_position(unit, enemy, allies: Array, battlefield) -> Vector2i:
	var protected = _weakest_ally_for_guard(unit, allies)
	if protected == null:
		return unit.grid_pos
	var best: Vector2i = unit.grid_pos
	var best_score: float = -INF
	var candidates: Array[Vector2i] = battlefield.get_neighbors(protected.grid_pos)
	candidates.append(protected.grid_pos)
	for candidate in candidates:
		if not battlefield.is_walkable(candidate):
			continue
		if battlefield.is_occupied(candidate, unit.unit_id):
			continue
		if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
			continue
		var protected_distance: float = _grid_distance(candidate, protected.grid_pos)
		var enemy_distance: float = _grid_distance(candidate, enemy.grid_pos)
		var protected_enemy_distance: float = _grid_distance(protected.grid_pos, enemy.grid_pos)
		var score: float = -protected_distance * 0.55 - _grid_distance(unit.grid_pos, candidate) * 0.16
		if enemy_distance < protected_enemy_distance:
			score += 0.65
		if battlefield.is_cover(candidate):
			score += 0.18
		if score > best_score:
			best = candidate
			best_score = score
	return best

func _support_backline_position(unit, enemy, allies: Array, battlefield) -> Vector2i:
	var anchor = _frontline_anchor(unit, allies)
	if anchor == null:
		return _ranged_position(unit, enemy, battlefield, true)
	var best: Vector2i = unit.grid_pos
	var best_score: float = -INF
	var search_radius: int = 5
	for y in range(maxi(1, anchor.grid_pos.y - search_radius), mini(battlefield.height - 1, anchor.grid_pos.y + search_radius + 1)):
		for x in range(maxi(1, anchor.grid_pos.x - search_radius), mini(battlefield.width - 1, anchor.grid_pos.x + search_radius + 1)):
			var candidate := Vector2i(x, y)
			if not battlefield.is_walkable(candidate):
				continue
			if battlefield.is_occupied(candidate, unit.unit_id):
				continue
			if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
				continue
			var enemy_distance: float = _grid_distance(candidate, enemy.grid_pos)
			var anchor_distance: float = _grid_distance(candidate, anchor.grid_pos)
			if enemy_distance < anchor_distance:
				continue
			var score: float = -absf(anchor_distance - 2.0) * 0.38 + enemy_distance * 0.1 - _grid_distance(unit.grid_pos, candidate) * 0.14
			if _is_ranged_unit(unit) and enemy_distance <= unit.attack_range_tiles and battlefield.has_line_of_sight(candidate, enemy.grid_pos):
				score += 0.35
			if battlefield.is_cover(candidate):
				score += 0.24
			elif battlefield.is_grass(candidate):
				score += 0.12
			if score > best_score:
				best = candidate
				best_score = score
	return best

func _frontline_anchor(unit, allies: Array):
	var best = null
	var best_score: float = -INF
	for ally in allies:
		if ally == null or not ally.is_alive():
			continue
		var score: float = float(ally.get_stat("def")) * 0.12 + ally.hp_ratio() * 0.35
		if _is_guard_role(ally):
			score += 0.55
		if score > best_score:
			best = ally
			best_score = score
	return best

func _should_rally_to_leader(unit) -> bool:
	if unit.leader_unit_id == "" or unit.is_leader:
		return false
	if unit.squad_anchor == Vector2i.ZERO:
		return false
	if unit.last_seen_enemies.is_empty() and unit.heard_noise_timer <= 0.0 and unit.lost_target_timer <= 0.0:
		return false
	var distance: float = _grid_distance(unit.grid_pos, unit.squad_anchor)
	if unit.squad_style == "cohesive":
		return distance >= 3.0
	return distance >= 5.0 and unit.brain_value("teamwork") >= 0.42

func _rally_leader_position(unit, battlefield) -> Vector2i:
	if not battlefield.in_bounds(unit.squad_anchor):
		return unit.grid_pos
	if _grid_distance(unit.grid_pos, unit.squad_anchor) <= 1.5:
		return unit.grid_pos
	return battlefield.find_position_near(unit.grid_pos, unit.squad_anchor, 1, 4)

func _nearest_unit(unit, candidates: Array):
	var best = null
	var best_distance: float = INF
	for candidate in candidates:
		var distance: float = _grid_distance(unit.grid_pos, candidate.grid_pos)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _last_known_contact(unit) -> Dictionary:
	var best: Dictionary = {}
	var best_age: int = 12001
	var now: int = Time.get_ticks_msec()
	for memory_value in unit.last_seen_enemies.values():
		if not (memory_value is Dictionary):
			continue
		var memory: Dictionary = memory_value
		var age: int = now - int(memory.get("time", 0))
		if age > 12000 or age >= best_age:
			continue
		var raw_pos = memory.get("pos", unit.grid_pos)
		if not (raw_pos is Vector2i):
			continue
		best = {
			"pos": raw_pos,
			"age": age
		}
		best_age = age
	return best

func _pain_fear(unit) -> float:
	var near_deaths: int = 0
	if unit.character_data != null:
		near_deaths = int(unit.character_data.combat_brain.get("near_deaths", 0))
	var wound_pressure: float = 1.0 - unit.hp_ratio()
	var learned_fear: float = unit.brain_value("pain_fear") * wound_pressure * 0.24
	var fear: float = float(near_deaths) * 0.035 + learned_fear
	if _unit_class_id(unit) == "berserker":
		fear *= 0.58
	return clampf(fear, 0.0, 0.28)

func _alone_fear(unit, nearest_ally) -> float:
	var solitude_fear: float = unit.brain_value("solitude_fear")
	if nearest_ally == null:
		return clampf(unit.brain_value("teamwork") * 0.18 + solitude_fear * 0.18, 0.0, 0.34)
	var distance: float = _grid_distance(unit.grid_pos, nearest_ally.grid_pos)
	if distance <= 3.0:
		return 0.0
	var distance_pressure: float = (distance - 3.0) * 0.055
	var fear_weight: float = unit.brain_value("teamwork") * 0.55 + solitude_fear * 0.85
	return clampf(distance_pressure * fear_weight, 0.0, 0.3)

func _threat_fear(unit, enemies: Array) -> float:
	var fear: float = 0.0
	var close_enemies: int = 0
	var strong_enemy_fear: float = unit.brain_value("strong_enemy_fear")
	var surround_fear: float = unit.brain_value("surround_fear")
	for enemy in enemies:
		if enemy.battle_unit != null and unit.battle_unit != null and enemy.battle_unit.max_hp > unit.battle_unit.max_hp * 1.25:
			fear += 0.05 + strong_enemy_fear * 0.09
		if _grid_distance(unit.grid_pos, enemy.grid_pos) <= 2.0:
			close_enemies += 1
			fear += 0.035 + surround_fear * 0.045
	if enemies.size() >= 2:
		fear += float(enemies.size() - 1) * surround_fear * 0.025
	if close_enemies >= 2:
		fear += float(close_enemies - 1) * surround_fear * 0.07
	return clampf(fear, 0.0, 0.36)

func _visibility_fear(unit, nearest_ally) -> float:
	if unit.visibility_stress <= 0.0:
		return 0.0
	var fear: float = unit.visibility_stress * unit.brain_value("darkness_fear") * 0.38
	if unit.is_leader:
		fear *= 0.78
	elif nearest_ally != null and _grid_distance(unit.grid_pos, nearest_ally.grid_pos) <= 3.0:
		fear *= 0.68
	return clampf(fear, 0.0, 0.32)

func _is_ranged_unit(unit) -> bool:
	if unit.attack_range_tiles > 2.25:
		return true
	if unit.battle_unit == null:
		return false
	return unit.battle_unit.magic > unit.battle_unit.atk

func _preferred_min_range(unit) -> float:
	if unit.attack_range_tiles <= 2.25:
		return 1.35
	return minf(unit.attack_range_tiles - 0.75, maxf(2.0, unit.attack_range_tiles * 0.58))

func _preferred_max_range(unit) -> float:
	return maxf(_preferred_min_range(unit) + 0.6, unit.attack_range_tiles * 0.9)

func _ranged_position(unit, enemy, battlefield, defensive: bool) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score := -INF
	var min_range: float = _preferred_min_range(unit)
	var desired_range: float = _preferred_max_range(unit)
	var search_radius: int = ceili(unit.attack_range_tiles) + 3
	var center: Vector2i = unit.grid_pos if defensive else enemy.grid_pos
	for y in range(maxi(1, center.y - search_radius), mini(battlefield.height - 1, center.y + search_radius + 1)):
		for x in range(maxi(1, center.x - search_radius), mini(battlefield.width - 1, center.x + search_radius + 1)):
			var candidate := Vector2i(x, y)
			if not battlefield.is_walkable(candidate):
				continue
			if battlefield.is_occupied(candidate, unit.unit_id):
				continue
			var enemy_distance: float = _grid_distance(candidate, enemy.grid_pos)
			if enemy_distance < min_range or enemy_distance > unit.attack_range_tiles:
				continue
			if not battlefield.has_line_of_sight(candidate, enemy.grid_pos):
				continue
			if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
				continue
			var score: float = -absf(enemy_distance - desired_range) * 0.8 - _grid_distance(unit.grid_pos, candidate) * 0.22
			if defensive:
				score += maxf(0.0, enemy_distance - _grid_distance(unit.grid_pos, enemy.grid_pos)) * 0.45
			if battlefield.is_cover(candidate):
				score += 0.55
			elif battlefield.is_grass(candidate):
				score += 0.2
			if score > best_score:
				best = candidate
				best_score = score
	return best

func _flank_position(unit, enemy, battlefield) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score := -INF
	var approach: Vector2 = Vector2(enemy.grid_pos - unit.grid_pos)
	if approach.length() <= 0.01:
		approach = Vector2.RIGHT
	approach = approach.normalized()
	for candidate in battlefield.get_neighbors(enemy.grid_pos):
		if battlefield.is_occupied(candidate, unit.unit_id):
			continue
		if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
			continue
		var offset: Vector2 = Vector2(candidate - enemy.grid_pos)
		if offset.length() <= 0.01:
			continue
		offset = offset.normalized()
		var side_score: float = 1.0 - absf(approach.dot(offset))
		var behind_score: float = 0.0
		if enemy.facing.length() > 0.01:
			behind_score = maxf(0.0, -enemy.facing.normalized().dot(offset))
		var score: float = side_score * 0.8 + behind_score * 0.45 - _grid_distance(unit.grid_pos, candidate) * 0.12
		if battlefield.is_cover(candidate):
			score += 0.25
		if score > best_score:
			best = candidate
			best_score = score
	return best

func _ambush_position(unit, enemy, battlefield) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score := -INF
	var search_radius := 6
	for y in range(maxi(1, unit.grid_pos.y - search_radius), mini(battlefield.height - 1, unit.grid_pos.y + search_radius + 1)):
		for x in range(maxi(1, unit.grid_pos.x - search_radius), mini(battlefield.width - 1, unit.grid_pos.x + search_radius + 1)):
			var candidate := Vector2i(x, y)
			if not battlefield.is_walkable(candidate):
				continue
			if battlefield.is_occupied(candidate, unit.unit_id):
				continue
			if not _is_hiding_spot(candidate, battlefield):
				continue
			if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
				continue
			var enemy_distance: float = _grid_distance(candidate, enemy.grid_pos)
			var stealth_score := 0.0
			if battlefield.is_grass(candidate):
				stealth_score += 0.8
			if battlefield.is_cover(candidate):
				stealth_score += 0.55
			if not battlefield.has_line_of_sight(enemy.grid_pos, candidate):
				stealth_score += 0.75
			if enemy_distance <= unit.attack_range_tiles + 1.0:
				stealth_score += 0.45
			var score: float = stealth_score - _grid_distance(unit.grid_pos, candidate) * 0.12 - absf(enemy_distance - maxf(1.5, unit.attack_range_tiles)) * 0.1
			if score > best_score:
				best = candidate
				best_score = score
	if best == unit.grid_pos:
		return battlefield.find_nearest_cover(unit.grid_pos, enemy.grid_pos, 5)
	return best

func _is_hiding_spot(pos: Vector2i, battlefield) -> bool:
	if battlefield.is_grass(pos) or battlefield.is_cover(pos):
		return true
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var nearby: Vector2i = pos + offset
		if not battlefield.in_bounds(nearby) or battlefield.blocks_vision(nearby):
			return true
	return false

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
	if _valid_patrol_destination(unit, unit.patrol_destination, battlefield):
		return unit.patrol_destination

	var bias: Vector2i = Vector2i.RIGHT if unit.side == BattleUnit.UnitSide.ALLY else Vector2i.LEFT
	var forward: Vector2i = unit.grid_pos + Vector2i(4 * bias.x, rng.randi_range(-2, 2))
	forward.x = clampi(forward.x, 1, battlefield.width - 2)
	forward.y = clampi(forward.y, 1, battlefield.height - 2)
	if battlefield.is_walkable(forward):
		return _remember_patrol_destination(unit, forward, rng)
	for _i in 8:
		var offset: Vector2i = Vector2i(rng.randi_range(-2, 4) * bias.x, rng.randi_range(-3, 3))
		var candidate: Vector2i = unit.grid_pos + offset
		candidate.x = clampi(candidate.x, 1, battlefield.width - 2)
		candidate.y = clampi(candidate.y, 1, battlefield.height - 2)
		if battlefield.is_walkable(candidate):
			return _remember_patrol_destination(unit, candidate, rng)
	return unit.grid_pos

func _valid_patrol_destination(unit, destination: Vector2i, battlefield) -> bool:
	if unit.patrol_rethink_timer <= 0.0:
		return false
	if destination == unit.grid_pos:
		return false
	if not battlefield.in_bounds(destination) or not battlefield.is_walkable(destination):
		return false
	if battlefield.is_occupied(destination, unit.unit_id):
		return false
	return not battlefield.find_path(unit.grid_pos, destination, unit.unit_id, false).is_empty()

func _remember_patrol_destination(unit, destination: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	unit.patrol_destination = destination
	unit.patrol_rethink_timer = rng.randf_range(1.8, 3.4)
	return destination

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

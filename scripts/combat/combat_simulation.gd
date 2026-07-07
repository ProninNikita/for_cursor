class_name CombatSimulation
extends RefCounted

enum BattleOutcome { NONE, VICTORY, DEFEAT }

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var all_units: Array[BattleUnit] = []
var turn_order: Array[BattleUnit] = []
var turn_ptr: int = 0
var battle_start_hp: Dictionary = {}
var battle_damage_dealt: Dictionary = {}
var battle_healing_done: Dictionary = {}

func setup(squad: Array[CharacterData]) -> void:
	all_units.clear()
	turn_order.clear()
	turn_ptr = 0
	battle_start_hp.clear()
	battle_damage_dealt.clear()
	battle_healing_done.clear()

	for cd in squad:
		cd.ensure_combat_brain()
		var unit := BattleUnit.from_hero(cd, rng)
		all_units.append(unit)
		battle_start_hp[cd.id] = unit.current_hp
		battle_damage_dealt[cd.id] = 0
		battle_healing_done[cd.id] = 0

	for i in 3:
		all_units.append(BattleUnit.goblin(i, rng))

	build_turn_order()

func build_turn_order() -> void:
	turn_order = all_units.duplicate()
	turn_order.sort_custom(_compare_initiative)

func living_enemies() -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in all_units:
		if unit.side == BattleUnit.UnitSide.ENEMY and unit.is_alive():
			result.append(unit)
	return result

func living_allies() -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for unit in all_units:
		if unit.side == BattleUnit.UnitSide.ALLY and unit.is_alive():
			result.append(unit)
	return result

func get_outcome() -> BattleOutcome:
	if living_enemies().is_empty():
		return BattleOutcome.VICTORY
	if living_allies().is_empty():
		return BattleOutcome.DEFEAT
	return BattleOutcome.NONE

func next_alive_actor() -> BattleUnit:
	var count := turn_order.size()
	if count == 0:
		return null

	var tried := 0
	while tried < count:
		var unit := turn_order[turn_ptr]
		turn_ptr = (turn_ptr + 1) % count
		if unit.is_alive():
			return unit
		tried += 1
	return null

func peek_next_alive_actor() -> BattleUnit:
	var count := turn_order.size()
	if count == 0:
		return null

	var ptr := turn_ptr
	var tried := 0
	while tried < count:
		var unit := turn_order[ptr]
		ptr = (ptr + 1) % count
		if unit.is_alive():
			return unit
		tried += 1
	return null

func targets_for_ability(user: BattleUnit, ability: AbilityData) -> Array[BattleUnit]:
	match ability.target_type:
		AbilityData.TargetType.SELF:
			return [user]
		AbilityData.TargetType.SINGLE_ENEMY:
			return living_enemies() if user.side == BattleUnit.UnitSide.ALLY else living_allies()
		AbilityData.TargetType.SINGLE_ALLY:
			return living_allies() if user.side == BattleUnit.UnitSide.ALLY else living_enemies()
		AbilityData.TargetType.ALL_ENEMIES:
			return living_enemies() if user.side == BattleUnit.UnitSide.ALLY else living_allies()
		AbilityData.TargetType.ALL_ALLIES:
			return living_allies() if user.side == BattleUnit.UnitSide.ALLY else living_enemies()
		_:
			return []

func choose_ally_decision(actor: BattleUnit) -> Dictionary:
	var best = {
		"score": -9999.0,
		"ability": null,
		"target": null,
		"targets": [],
		"all_targets": false,
		"reason": ""
	}

	for ability in actor.abilities:
		if not ability.can_use():
			continue
		var targets := targets_for_ability(actor, ability)
		if targets.is_empty():
			continue

		var targets_all := ability.target_type == AbilityData.TargetType.ALL_ALLIES or ability.target_type == AbilityData.TargetType.ALL_ENEMIES
		if targets_all:
			var score := score_ally_action(actor, ability, null, targets)
			if score > best["score"]:
				best = {
					"score": score,
					"ability": ability,
					"target": null,
					"targets": targets,
					"all_targets": true,
					"reason": describe_ally_decision(ability, null)
				}
		else:
			for target in targets:
				var score := score_ally_action(actor, ability, target, [])
				if score > best["score"]:
					best = {
						"score": score,
						"ability": ability,
						"target": target,
						"targets": [],
						"all_targets": false,
						"reason": describe_ally_decision(ability, target)
					}

	if best["ability"] == null:
		return {}

	var patience := brain_value(actor, "skill_patience")
	var threshold := 0.55 + patience * 0.25
	if best["score"] < threshold:
		return {}
	return best

func score_ally_action(actor: BattleUnit, ability: AbilityData, target: BattleUnit, targets: Array[BattleUnit]) -> float:
	var aggression := brain_value(actor, "aggression")
	var caution := brain_value(actor, "caution")
	var teamwork := brain_value(actor, "teamwork")
	var self_preserve := brain_value(actor, "self_preserve")
	var focus_fire := brain_value(actor, "focus_fire")
	var skill_patience := brain_value(actor, "skill_patience")
	var actor_hp_ratio := hp_ratio(actor)
	var cooldown_cost := float(ability.cooldown_max) * skill_patience * 0.08
	var score := rng.randf() * 0.08

	match ability.type:
		AbilityData.AbilityType.DAMAGE:
			if target == null:
				return -9999.0
			var target_hp_ratio := hp_ratio(target)
			score += 0.65 + ability.power + aggression * 0.7 + focus_fire * (1.0 - target_hp_ratio) * 1.25
			if actor_hp_ratio < 0.35:
				score -= caution * self_preserve * 0.3
			score -= cooldown_cost
		AbilityData.AbilityType.HEAL:
			if target == null:
				return -9999.0
			var missing := 1.0 - hp_ratio(target)
			score += missing * 3.0 + teamwork * 0.85 + caution * 0.35
			if target == actor:
				score += self_preserve * 0.5
			score -= cooldown_cost
		AbilityData.AbilityType.BUFF:
			score += 0.35 + teamwork * 0.75 + skill_patience * 0.45
			if target == actor and actor_hp_ratio < 0.45:
				score += caution * self_preserve * 0.6
			if not targets.is_empty():
				score += float(targets.size()) * 0.08
			score -= cooldown_cost
		AbilityData.AbilityType.DEBUFF:
			if target == null:
				return -9999.0
			score += 0.55 + aggression * 0.35 + skill_patience * 0.25 + focus_fire * (1.0 - hp_ratio(target))
			score -= cooldown_cost
		AbilityData.AbilityType.SPECIAL:
			score += 0.45 + aggression * 0.3 + teamwork * 0.3 + skill_patience * 0.2
			score -= cooldown_cost
		_:
			score += 0.25

	return score

func describe_ally_decision(ability: AbilityData, target: BattleUnit) -> String:
	if target == null:
		return "использовать %s для группы" % ability.name
	return "использовать %s на %s" % [ability.name, target.display_name]

func choose_enemy_ability(enemy: BattleUnit) -> AbilityData:
	if enemy.abilities.is_empty():
		return null

	var available_abilities: Array[AbilityData] = []
	for ability in enemy.abilities:
		if ability.can_use():
			available_abilities.append(ability)

	if available_abilities.is_empty():
		return null

	var lowest_hp_ally: BattleUnit = null
	for ally in living_allies():
		if lowest_hp_ally == null or ally.current_hp < lowest_hp_ally.current_hp:
			lowest_hp_ally = ally

	if lowest_hp_ally != null and lowest_hp_ally.current_hp < lowest_hp_ally.max_hp * 0.3:
		for ability in available_abilities:
			if ability.type == AbilityData.AbilityType.DAMAGE:
				return ability

	for ability in available_abilities:
		if ability.type == AbilityData.AbilityType.HEAL:
			if lowest_hp_ally != null and lowest_hp_ally.current_hp < lowest_hp_ally.max_hp * 0.5:
				continue
		return ability

	return available_abilities[0]

func choose_target_for_ability(user: BattleUnit, ability: AbilityData) -> BattleUnit:
	match ability.target_type:
		AbilityData.TargetType.SELF:
			return user
		AbilityData.TargetType.SINGLE_ENEMY:
			var enemies := living_enemies() if user.side == BattleUnit.UnitSide.ALLY else living_allies()
			if enemies.is_empty():
				return null
			return _pick_weakest(enemies)
		AbilityData.TargetType.SINGLE_ALLY:
			var allies := living_allies() if user.side == BattleUnit.UnitSide.ALLY else living_enemies()
			if allies.is_empty():
				return null
			return _pick_weakest(allies)
		AbilityData.TargetType.ALL_ENEMIES:
			return null
		AbilityData.TargetType.ALL_ALLIES:
			return null
		_:
			return null

func calc_damage(attacker: BattleUnit, defender: BattleUnit) -> int:
	var raw := attacker.atk - defender.def / 2
	return maxi(1, raw)

func pick_weakest_enemy(enemies: Array[BattleUnit]) -> BattleUnit:
	return _pick_weakest(enemies)

func pick_weakest_ally(allies: Array[BattleUnit]) -> BattleUnit:
	return _pick_weakest(allies)

func record_damage_dealt(user: BattleUnit, amount: int) -> void:
	if amount <= 0 or user.character_data == null:
		return
	var char_id := user.character_data.id
	battle_damage_dealt[char_id] = int(battle_damage_dealt.get(char_id, 0)) + amount

func record_healing_done(user: BattleUnit, amount: int) -> void:
	if amount <= 0 or user.character_data == null:
		return
	var char_id := user.character_data.id
	battle_healing_done[char_id] = int(battle_healing_done.get(char_id, 0)) + amount

func record_damage_taken(target: BattleUnit, amount: int) -> void:
	if amount <= 0 or target.character_data == null:
		return
	target.character_data.record_damage_taken(amount, target.max_hp)

func sync_roster_hp(roster: Roster) -> void:
	for unit in all_units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		roster.apply_hp_from_battle(unit.character_data.id, unit.current_hp)

func update_combat_brains(victory: bool) -> void:
	for unit in all_units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null or not unit.is_alive():
			continue
		var char_id := unit.character_data.id
		var start_hp := int(battle_start_hp.get(char_id, unit.max_hp))
		var damage_taken_ratio := 0.0
		if unit.max_hp > 0:
			damage_taken_ratio = float(maxi(0, start_hp - unit.current_hp)) / float(unit.max_hp)
		var damage_dealt := int(battle_damage_dealt.get(char_id, 0))
		var healing_done := int(battle_healing_done.get(char_id, 0))
		unit.character_data.record_combat_result(victory, hp_ratio(unit), damage_taken_ratio, damage_dealt, healing_done)

func hp_ratio(unit: BattleUnit) -> float:
	if unit.max_hp <= 0:
		return 0.0
	return float(unit.current_hp) / float(unit.max_hp)

func brain_value(unit: BattleUnit, key: String) -> float:
	if unit.character_data == null:
		return 0.5
	return unit.character_data.get_brain_value(key)

static func _compare_initiative(a: BattleUnit, b: BattleUnit) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	return a.tie_breaker > b.tie_breaker

func _pick_weakest(units: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for unit in units:
		if best == null or unit.current_hp < best.current_hp:
			best = unit
		elif unit.current_hp == best.current_hp and rng.randf() < 0.5:
			best = unit
	return best

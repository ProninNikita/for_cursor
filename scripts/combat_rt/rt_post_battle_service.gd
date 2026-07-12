class_name RTPostBattleService
extends RefCounted

const ENEMY_REWARD_GOLD_PER_WEIGHT := 4.0
const ENEMY_REWARD_LOOTBOX_WEIGHT := 8.0

func apply(
	victory: bool,
	context,
	units: Array,
	duration_seconds: float = 0.0,
	seed_label: String = "random"
) -> Dictionary:
	var state = _game_state()
	if state == null:
		push_error("RTPostBattleService: GameState not found")
		return {}
	_record_fallen_heroes(victory, context, units, duration_seconds, seed_label)
	_sync_roster_hp(units)
	var reward_data: Dictionary = _reward_data_for_result(victory, context, units)

	var applied_rewards: Dictionary = {}
	if victory:
		if context != null and context.is_tower():
			applied_rewards = state.apply_rewards(reward_data)
			state.tower_elevation.register_victory(context.tower_floor)
			state.tower_elevation.advance_to_next_floor()
		elif context != null and context.is_raid():
			_sync_active_raid_hp(units)
			_sync_active_raid_reward_data(reward_data)
			state.finish_raid_combat(true)
			if state.active_raid != null:
				state.active_raid.complete_combat_event(true)
		else:
			applied_rewards = state.apply_rewards(reward_data)
	elif context != null and context.is_raid():
		_sync_active_raid_hp(units)
		state.finish_raid_combat(false)
		if state.active_raid != null:
			state.active_raid.complete_combat_event(false)

	_clear_pending_combat_state()
	return applied_rewards

func _reward_data_for_result(victory: bool, context, units: Array) -> Dictionary:
	var reward_data: Dictionary = {}
	if context != null:
		reward_data = context.reward_data.duplicate(true)
	else:
		reward_data = {"lootboxes": 1}

	var metrics := _enemy_reward_metrics(units)
	var bonus: Dictionary = {}
	if victory:
		bonus = _enemy_reward_bonus(metrics)
		reward_data = _merge_rewards(reward_data, bonus)
		reward_data = _apply_reward_multiplier(reward_data, context)

	if context != null:
		context.set_enemy_reward_summary(metrics, bonus)
		context.reward_data = reward_data.duplicate(true)

	return reward_data

func _apply_reward_multiplier(reward_data: Dictionary, context) -> Dictionary:
	if context == null:
		return reward_data
	var multiplier: float = context.modifier_float("reward_multiplier", 1.0)
	if is_equal_approx(multiplier, 1.0):
		return reward_data
	var result := reward_data.duplicate(true)
	for key in result.keys():
		if not (result[key] is int or result[key] is float):
			continue
		if key == "lootboxes":
			result[key] = maxi(0, int(round(float(result[key]) * multiplier)))
		else:
			result[key] = maxi(0, int(round(float(result[key]) * multiplier)))
	return result

func _enemy_reward_metrics(units: Array) -> Dictionary:
	var metrics := {
		"total_danger": 0.0,
		"defeated_danger": 0.0,
		"total_reward_weight": 0.0,
		"defeated_reward_weight": 0.0
	}
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ENEMY:
			continue
		var danger := maxf(0.0, float(unit.enemy_danger))
		var reward_weight := maxf(0.0, float(unit.enemy_reward_weight))
		metrics["total_danger"] = float(metrics["total_danger"]) + danger
		metrics["total_reward_weight"] = float(metrics["total_reward_weight"]) + reward_weight
		if not unit.is_alive():
			metrics["defeated_danger"] = float(metrics["defeated_danger"]) + danger
			metrics["defeated_reward_weight"] = float(metrics["defeated_reward_weight"]) + reward_weight
	return metrics

func _enemy_reward_bonus(metrics: Dictionary) -> Dictionary:
	var defeated_weight := float(metrics.get("defeated_reward_weight", 0.0))
	var bonus: Dictionary = {}
	var gold_bonus := roundi(defeated_weight * ENEMY_REWARD_GOLD_PER_WEIGHT)
	if gold_bonus > 0:
		bonus["gold"] = gold_bonus
	var lootbox_bonus := floori(defeated_weight / ENEMY_REWARD_LOOTBOX_WEIGHT)
	if lootbox_bonus > 0:
		bonus["lootboxes"] = lootbox_bonus
	return bonus

func _merge_rewards(base_rewards: Dictionary, bonus_rewards: Dictionary) -> Dictionary:
	var result := base_rewards.duplicate(true)
	for key in bonus_rewards:
		if bonus_rewards[key] is int or bonus_rewards[key] is float:
			result[key] = int(result.get(key, 0)) + int(bonus_rewards[key])
		else:
			result[key] = bonus_rewards[key]
	return result

func _sync_roster_hp(units: Array) -> void:
	var state = _game_state()
	if state == null or state.roster == null:
		return
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		state.roster.apply_hp_from_battle(unit.character_data.id, unit.battle_unit.current_hp)

func _record_fallen_heroes(
	victory: bool,
	context,
	units: Array,
	duration_seconds: float,
	seed_label: String
) -> void:
	var state = _game_state()
	if state == null:
		return
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null or unit.is_alive():
			continue
		state.record_fallen_hero(_fallen_hero_record(unit, victory, context, duration_seconds, seed_label))

func _fallen_hero_record(
	unit,
	victory: bool,
	context,
	duration_seconds: float,
	seed_label: String
) -> Dictionary:
	var hero: CharacterData = unit.character_data
	var combat_type := "training"
	var floor_num := 0
	var floor_name := ""
	var encounter_id := ""
	var raid_event: Dictionary = {}
	if context != null:
		encounter_id = str(context.encounter_id)
		if context.is_tower():
			combat_type = "tower"
			floor_num = int(context.tower_floor)
			floor_name = str(context.floor_name)
		elif context.is_raid():
			combat_type = "raid"
			raid_event = context.raid_event.duplicate(true)
		else:
			combat_type = "training"
	return {
		"hero_id": hero.id,
		"name": hero.display_name,
		"class": hero.character_class,
		"class_display": hero.character_class_display_name,
		"stats": hero.stats.duplicate(true),
		"level": int(hero.stats.get("level", 1)),
		"battle": {
			"victory": victory,
			"combat_type": combat_type,
			"encounter_id": encounter_id,
			"floor": floor_num,
			"floor_name": floor_name,
			"raid_event": raid_event,
			"duration_seconds": duration_seconds,
			"seed": seed_label
		},
		"cause": unit.last_damage_cause,
		"killer": unit.last_damage_source_name,
		"killer_side": unit.last_damage_source_side,
		"ability": unit.last_damage_ability_name,
		"timestamp": Time.get_unix_time_from_system()
	}

func _sync_active_raid_hp(units: Array) -> void:
	var state = _game_state()
	if state == null or state.active_raid == null:
		return
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		var char_id: String = unit.character_data.id
		if state.active_raid.character_states.has(char_id):
			state.active_raid.character_states[char_id]["hp"] = unit.battle_unit.current_hp

func _sync_active_raid_reward_data(reward_data: Dictionary) -> void:
	var state = _game_state()
	if state == null or state.active_raid == null:
		return
	if state.active_raid.pending_combat_event.is_empty():
		return
	state.active_raid.pending_combat_event["rewards"] = reward_data.duplicate(true)

func _clear_pending_combat_state() -> void:
	var state = _game_state()
	if state == null:
		return
	state.clear_pending_combat()
	state.is_tower_elevation = false
	state.pending_tower_floor = 0
	state.pending_raid_event.clear()

func _game_state():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")

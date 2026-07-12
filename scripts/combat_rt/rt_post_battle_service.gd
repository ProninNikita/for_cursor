class_name RTPostBattleService
extends RefCounted

const ENEMY_REWARD_GOLD_PER_WEIGHT := 4.0
const ENEMY_REWARD_LOOTBOX_WEIGHT := 8.0

func apply(victory: bool, context, units: Array) -> Dictionary:
	_sync_roster_hp(units)
	var reward_data: Dictionary = _reward_data_for_result(victory, context, units)

	var applied_rewards: Dictionary = {}
	if victory:
		if context != null and context.is_tower():
			applied_rewards = GameState.apply_rewards(reward_data)
			GameState.tower_elevation.register_victory(context.tower_floor)
			GameState.tower_elevation.advance_to_next_floor()
		elif context != null and context.is_raid():
			_sync_active_raid_hp(units)
			_sync_active_raid_reward_data(reward_data)
			GameState.finish_raid_combat(true)
			if GameState.active_raid != null:
				GameState.active_raid.complete_combat_event(true)
		else:
			applied_rewards = GameState.apply_rewards(reward_data)
	elif context != null and context.is_raid():
		_sync_active_raid_hp(units)
		GameState.finish_raid_combat(false)
		if GameState.active_raid != null:
			GameState.active_raid.complete_combat_event(false)

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
	if GameState.roster == null:
		return
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		GameState.roster.apply_hp_from_battle(unit.character_data.id, unit.battle_unit.current_hp)

func _sync_active_raid_hp(units: Array) -> void:
	if GameState.active_raid == null:
		return
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		var char_id: String = unit.character_data.id
		if GameState.active_raid.character_states.has(char_id):
			GameState.active_raid.character_states[char_id]["hp"] = unit.battle_unit.current_hp

func _sync_active_raid_reward_data(reward_data: Dictionary) -> void:
	if GameState.active_raid == null:
		return
	if GameState.active_raid.pending_combat_event.is_empty():
		return
	GameState.active_raid.pending_combat_event["rewards"] = reward_data.duplicate(true)

func _clear_pending_combat_state() -> void:
	GameState.clear_pending_combat()
	GameState.is_tower_elevation = false
	GameState.pending_tower_floor = 0
	GameState.pending_raid_event.clear()

class_name RTBattleResultData
extends RefCounted

var values: Dictionary = {}

static func from_result(result):
	var data := new()
	if result == null:
		return data
	data.values = {
		"timestamp": Time.get_unix_time_from_system(),
		"combat_type": result.combat_type,
		"seed": result.seed_label,
		"victory": result.victory,
		"elapsed_seconds": result.elapsed_seconds,
		"allies_alive": result.allies_alive,
		"allies_total": result.allies_total,
		"allies_dead": result.allies_dead,
		"enemies_alive": result.enemies_alive,
		"enemies_total": result.enemies_total,
		"enemies_defeated": result.enemies_defeated,
		"damage_dealt": result.damage_dealt,
		"healing_done": result.healing_done,
		"ability_usage": result.ability_usage.duplicate(true),
		"decision_usage": result.decision_usage.duplicate(true),
		"applied_rewards": result.applied_rewards.duplicate(true),
		"enemy_total_danger": result.enemy_total_danger,
		"enemy_defeated_danger": result.enemy_defeated_danger,
		"enemy_reward_bonus": result.enemy_reward_bonus.duplicate(true),
		"allies": result.ally_summaries.duplicate(true),
		"fallen_allies": result.fallen_allies.duplicate(true),
		"finish_reason": result.finish_reason,
		"finish_detail": result.finish_detail,
		"timeline": result.timeline.duplicate(true),
		"max_tick_ms": result.max_tick_ms
	}
	return data

func to_dictionary() -> Dictionary:
	return values.duplicate(true)

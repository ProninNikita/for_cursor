class_name RTCombatResult
extends RefCounted

var victory: bool = false
var combat_type: String = "demo"
var seed_label: String = "random"
var elapsed_seconds: float = 0.0
var allies_alive: int = 0
var allies_total: int = 0
var enemies_alive: int = 0
var enemies_total: int = 0
var enemies_defeated: int = 0
var damage_dealt: int = 0
var healing_done: int = 0
var ability_usage: Dictionary = {}
var decision_usage: Dictionary = {}
var applied_rewards: Dictionary = {}
var enemy_total_danger: float = 0.0
var enemy_defeated_danger: float = 0.0
var enemy_reward_bonus: Dictionary = {}
var ally_summaries: Array[Dictionary] = []

func setup_from_battle(
	victory_value: bool,
	context,
	config,
	units: Array,
	damage_by_character: Dictionary,
	healing_by_character: Dictionary,
	ability_usage_counts: Dictionary,
	decision_usage_counts: Dictionary,
	rewards: Dictionary,
	duration_seconds: float
) -> void:
	victory = victory_value
	elapsed_seconds = duration_seconds
	applied_rewards = rewards.duplicate(true)
	ability_usage = ability_usage_counts.duplicate(true)
	decision_usage = decision_usage_counts.duplicate(true)
	damage_dealt = _sum_dictionary_int(damage_by_character)
	healing_done = _sum_dictionary_int(healing_by_character)
	combat_type = _combat_type_label(context)
	seed_label = config.seed_label() if config != null else "random"
	if context != null:
		enemy_total_danger = float(context.enemy_total_danger)
		enemy_defeated_danger = float(context.enemy_defeated_danger)
		enemy_reward_bonus = context.enemy_reward_bonus.duplicate(true)
	_collect_unit_counts(units)

func stats_text() -> String:
	var text := "Статистика: время %s, союзники %d/%d, враги повержены %d/%d, урон %d, лечение %d." % [
		format_duration(elapsed_seconds),
		allies_alive,
		allies_total,
		enemies_defeated,
		enemies_total,
		damage_dealt,
		healing_done
	]
	if enemy_total_danger > 0.0:
		text += "\nОпасность врагов: %.1f/%.1f, бонус за врагов: %s." % [
			enemy_defeated_danger,
			enemy_total_danger,
			_format_rewards(enemy_reward_bonus)
		]
	return text

func summary_line() -> String:
	return "Итог боя: %s, %s, seed %s, союзники %d/%d, враги %d/%d, урон %d, лечение %d, способности: %s, решения: %s." % [
		"победа" if victory else "поражение",
		format_duration(elapsed_seconds),
		seed_label,
		allies_alive,
		allies_total,
		enemies_defeated,
		enemies_total,
		damage_dealt,
		healing_done,
		_format_ability_usage(),
		_format_decision_usage()
	]

func to_balance_record() -> Dictionary:
	return {
		"timestamp": Time.get_unix_time_from_system(),
		"combat_type": combat_type,
		"seed": seed_label,
		"victory": victory,
		"elapsed_seconds": elapsed_seconds,
		"allies_alive": allies_alive,
		"allies_total": allies_total,
		"enemies_alive": enemies_alive,
		"enemies_total": enemies_total,
		"enemies_defeated": enemies_defeated,
		"damage_dealt": damage_dealt,
		"healing_done": healing_done,
		"ability_usage": ability_usage.duplicate(true),
		"decision_usage": decision_usage.duplicate(true),
		"applied_rewards": applied_rewards.duplicate(true),
		"enemy_total_danger": enemy_total_danger,
		"enemy_defeated_danger": enemy_defeated_danger,
		"enemy_reward_bonus": enemy_reward_bonus.duplicate(true),
		"allies": ally_summaries.duplicate(true)
	}

func format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(round(seconds)))
	var minutes := floori(float(total_seconds) / 60.0)
	var seconds_part := total_seconds % 60
	return "%d:%s" % [minutes, str(seconds_part).pad_zeros(2)]

func _collect_unit_counts(units: Array) -> void:
	allies_alive = 0
	allies_total = 0
	enemies_alive = 0
	enemies_total = 0
	enemies_defeated = 0
	ally_summaries.clear()

	for unit in units:
		if unit.side == BattleUnit.UnitSide.ALLY:
			allies_total += 1
			if unit.is_alive():
				allies_alive += 1
				ally_summaries.append({
					"name": unit.display_name,
					"class": str(unit.character_data.character_class) if unit.character_data != null else "",
					"hp": unit.battle_unit.current_hp,
					"max_hp": unit.battle_unit.max_hp,
					"alive": unit.is_alive()
			})
		else:
			enemies_total += 1
			if unit.is_alive():
				enemies_alive += 1
	enemies_defeated = enemies_total - enemies_alive

func _combat_type_label(context) -> String:
	if context != null:
		if context.is_tower():
			return "tower"
		if context.is_raid():
			return "raid"
	return "demo"

func _format_ability_usage() -> String:
	if ability_usage.is_empty():
		return "нет"
	var parts: PackedStringArray = []
	for ability_name in ability_usage.keys():
		parts.append("%s x%d" % [ability_name, int(ability_usage[ability_name])])
	return ", ".join(parts)

func _format_decision_usage() -> String:
	if decision_usage.is_empty():
		return "нет"
	var parts: PackedStringArray = []
	for decision_name in decision_usage.keys():
		parts.append("%s x%d" % [str(decision_name), int(decision_usage[decision_name])])
		if parts.size() >= 5:
			break
	return ", ".join(parts)

func _format_rewards(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	var lootboxes := int(rewards.get("lootboxes", 0))
	if lootboxes > 0:
		parts.append("%d лутбоксов" % lootboxes)
	var gold_amount := int(rewards.get("gold", 0))
	if gold_amount > 0:
		parts.append("%d золота" % gold_amount)
	if parts.is_empty():
		return "нет"
	return ", ".join(parts)

func _sum_dictionary_int(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total

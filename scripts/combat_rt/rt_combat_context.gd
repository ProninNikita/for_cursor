class_name RTCombatContext
extends RefCounted

const FloorModifiersScript = preload("res://scripts/combat_rt/rt_floor_modifiers.gd")

enum CombatType { DEMO, TOWER, RAID }

var combat_type: int = CombatType.DEMO
var encounter_id: String = ""
var tower_floor: int = 0
var floor_name: String = ""
var arena_id: String = "training_ruins"
var floor_data: Dictionary = {}
var raid_event: Dictionary = {}
var enemy_plan: Array = []
var reward_data: Dictionary = {}
var enemy_total_danger: float = 0.0
var enemy_defeated_danger: float = 0.0
var enemy_total_reward_weight: float = 0.0
var enemy_defeated_reward_weight: float = 0.0
var enemy_reward_bonus: Dictionary = {}
var combat_modifiers: Dictionary = {}
var victory_conditions: Dictionary = {}
var defeat_conditions: Dictionary = {}
var threat_summary: PackedStringArray = []
var consequence_summary: PackedStringArray = []

func setup_from_game_state() -> void:
	combat_type = CombatType.DEMO
	encounter_id = GameState.pending_combat_encounter
	tower_floor = 0
	floor_name = ""
	arena_id = "training_ruins"
	floor_data.clear()
	raid_event.clear()
	enemy_plan.clear()
	reward_data.clear()
	combat_modifiers.clear()
	victory_conditions.clear()
	defeat_conditions.clear()
	threat_summary.clear()
	consequence_summary.clear()
	_clear_enemy_reward_summary()

	if not GameState.pending_raid_event.is_empty():
		combat_type = CombatType.RAID
		raid_event = GameState.pending_raid_event.duplicate(true)
		arena_id = str(raid_event.get("arena_id", "training_ruins"))
		enemy_plan = _duplicate_entries(raid_event.get("enemies", []))
		reward_data = raid_event.get("rewards", {}).duplicate(true)
		_setup_raid_rules()
		return

	if GameState.is_tower_elevation and GameState.tower_elevation != null:
		combat_type = CombatType.TOWER
		tower_floor = GameState.pending_tower_floor
		floor_data = GameState.tower_elevation.get_floor_data(tower_floor).duplicate(true)
		floor_name = str(floor_data.get("name", "Этаж %d" % tower_floor))
		arena_id = str(floor_data.get("arena_id", "training_ruins"))
		enemy_plan = _duplicate_entries(floor_data.get("enemies", []))
		reward_data = floor_data.get("reward", {}).duplicate(true)
		_setup_tower_rules()
		return

	combat_type = CombatType.DEMO
	arena_id = "training_ruins"
	enemy_plan = [
		{"type": "goblin", "count": 3},
		{"type": "goblin_coward", "count": 1},
		{"type": "goblin_scout", "count": 1},
		{"type": "orc", "count": 1}
	]
	reward_data = {"lootboxes": 1}
	_setup_demo_rules()

func is_tower() -> bool:
	return combat_type == CombatType.TOWER

func is_raid() -> bool:
	return combat_type == CombatType.RAID

func is_demo() -> bool:
	return combat_type == CombatType.DEMO

func next_tower_floor() -> int:
	return tower_floor + 1

func set_enemy_reward_summary(metrics: Dictionary, bonus: Dictionary) -> void:
	enemy_total_danger = float(metrics.get("total_danger", 0.0))
	enemy_defeated_danger = float(metrics.get("defeated_danger", 0.0))
	enemy_total_reward_weight = float(metrics.get("total_reward_weight", 0.0))
	enemy_defeated_reward_weight = float(metrics.get("defeated_reward_weight", 0.0))
	enemy_reward_bonus = bonus.duplicate(true)

func modifier_float(key: String, fallback: float = 0.0) -> float:
	return float(combat_modifiers.get(key, fallback))

func modifier_bool(key: String, fallback: bool = false) -> bool:
	return bool(combat_modifiers.get(key, fallback))

func victory_string(key: String, fallback: String = "") -> String:
	return str(victory_conditions.get(key, fallback))

func victory_float(key: String, fallback: float = 0.0) -> float:
	return float(victory_conditions.get(key, fallback))

func defeat_string(key: String, fallback: String = "") -> String:
	return str(defeat_conditions.get(key, fallback))

func defeat_float(key: String, fallback: float = 0.0) -> float:
	return float(defeat_conditions.get(key, fallback))

func threat_text() -> String:
	if threat_summary.is_empty():
		return "Угрозы: стандартный бой."
	return "Угрозы: " + "; ".join(threat_summary)

func consequence_text(victory: bool) -> String:
	if victory:
		return ""
	if consequence_summary.is_empty():
		return "Последствие: выжившие сохраняют текущий HP, награда не выдаётся."
	return "Последствие: " + "; ".join(consequence_summary)

func _setup_demo_rules() -> void:
	combat_modifiers = {
		"enemy_scale": 1.58,
		"damage_taken_multiplier": 0.56,
		"reward_multiplier": 1.0,
		"trap_damage": 2.0,
		"poison_damage_multiplier": 0.9,
		"friendly_fire_multiplier": 0.5,
		"area_damage_multiplier": 0.92,
		"retreat_enabled": true,
		"heavy_loss_threshold": 0.34,
		"decision_interval": 0.36,
		"max_log_lines": 16
	}
	victory_conditions = {"type": "eliminate_enemies"}
	defeat_conditions = {"type": "collapse", "retreat_after_seconds": 16.0, "time_limit_seconds": 80.0}
	threat_summary = PackedStringArray(["учебная арена", "низкая смертность"])
	consequence_summary = PackedStringArray(["тренировочный бой не выдаёт штрафов кроме потерянного HP"])

func _setup_tower_rules() -> void:
	var floor_num: int = maxi(1, tower_floor)
	var raw_modifiers = floor_data.get("modifiers", {})
	var default_modifiers := {
		"enemy_scale": 1.0,
		"damage_taken_multiplier": 0.70,
		"reward_multiplier": 1.0,
		"trap_damage": 2.0,
		"poison_damage_multiplier": 1.0,
		"friendly_fire_multiplier": 0.55,
		"area_damage_multiplier": 1.0,
		"retreat_enabled": true,
		"heavy_loss_threshold": 0.36,
		"decision_interval": 0.38,
		"max_log_lines": 18
	}
	combat_modifiers = FloorModifiersScript.with_defaults(default_modifiers, raw_modifiers).to_dictionary()
	victory_conditions = floor_data.get("victory", {"type": "eliminate_enemies"}).duplicate(true)
	defeat_conditions = floor_data.get("defeat", {"type": "collapse", "retreat_after_seconds": 14.0}).duplicate(true)
	threat_summary = _tower_threat_summary(floor_num)
	consequence_summary = PackedStringArray(["попытка этажа засчитана", "награда не выдаётся", "выжившие возвращаются с текущим HP"])

func _setup_raid_rules() -> void:
	var difficulty := float(raid_event.get("difficulty", 1.0))
	combat_modifiers = {
		"enemy_scale": difficulty,
		"damage_taken_multiplier": clampf(0.70 + (difficulty - 1.0) * 0.12, 0.62, 1.1),
		"reward_multiplier": 1.0,
		"trap_damage": 2.0,
		"poison_damage_multiplier": 1.0,
		"friendly_fire_multiplier": 0.55,
		"area_damage_multiplier": 1.0,
		"retreat_enabled": true,
		"heavy_loss_threshold": 0.3,
		"decision_interval": 0.34,
		"max_log_lines": 18
	}
	_merge_dictionary(combat_modifiers, raid_event.get("modifiers", {}))
	victory_conditions = raid_event.get("victory", {"type": "eliminate_enemies"}).duplicate(true)
	defeat_conditions = raid_event.get("defeat", {"type": "collapse", "retreat_after_seconds": 12.0}).duplicate(true)
	threat_summary = PackedStringArray([
		str(raid_event.get("name", "боевое событие")),
		"сложность %.1fx" % difficulty
	])
	consequence_summary = PackedStringArray(["отряд получает дополнительный урон 15%", "состояние вылазки обновляется между боями"])

func _tower_threat_summary(floor: int) -> PackedStringArray:
	var result := PackedStringArray()
	result.append("этаж %d" % floor)
	result.append("масштаб врагов %.2fx" % modifier_float("enemy_scale", 1.0))
	if arena_id != "":
		result.append("арена: %s" % arena_id)
	var enemy_count := 0
	for entry in enemy_plan:
		if entry is Dictionary:
			enemy_count += int(entry.get("count", 1))
	if enemy_count > 0:
		result.append("контактов: %d" % enemy_count)
	var victory_type := victory_string("type", "eliminate_enemies")
	if victory_type != "eliminate_enemies":
		result.append("условие победы: %s" % victory_type)
	var defeat_type := defeat_string("type", "collapse")
	if defeat_type != "collapse":
		result.append("условие поражения: %s" % defeat_type)
	return result

func _merge_dictionary(target: Dictionary, source) -> void:
	if not (source is Dictionary):
		return
	for key in source.keys():
		target[key] = source[key]

func _clear_enemy_reward_summary() -> void:
	enemy_total_danger = 0.0
	enemy_defeated_danger = 0.0
	enemy_total_reward_weight = 0.0
	enemy_defeated_reward_weight = 0.0
	enemy_reward_bonus.clear()

static func _duplicate_entries(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
		else:
			result.append(entry)
	return result

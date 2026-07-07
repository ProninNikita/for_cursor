class_name CharacterData
extends Resource

## Данные персонажа — предыстория, характер, класс, статы, способности

@export var id: String = ""
@export var display_name: String = ""
@export var backstory_origin: String = ""
@export var backstory_event: String = ""
@export var backstory_motivation: String = ""
@export var personality_trait: String = ""
@export var character_class: String = ""
@export var character_class_display_name: String = ""
@export var stats: Dictionary = {}
@export var current_hp: int = -1
@export var combat_brain: Dictionary = {}
@export var ability_ids: Array[String] = []
@export var unique_ability_id: String = ""
@export var portrait_path: String = ""

## Текстовое описание для UI
func get_backstory_text() -> String:
	return "Происхождение: %s. Ключевое событие: %s. Мотивация: %s." % [backstory_origin, backstory_event, backstory_motivation]

func get_full_description() -> String:
	return "%s — %s с характером %s.\n%s" % [
		display_name,
		character_class,
		personality_trait,
		get_backstory_text()
	]

func get_initiative() -> int:
	return int(stats.get("initiative", stats.get("speed", 5)))

func get_max_hp() -> int:
	return int(stats.get("hp", 1))

func get_current_hp() -> int:
	if current_hp < 0:
		return get_max_hp()
	return mini(current_hp, get_max_hp())

func set_current_hp(value: int) -> void:
	current_hp = mini(maxi(value, 0), get_max_hp())

func ensure_combat_brain() -> void:
	var defaults = _make_default_combat_brain()
	for key in defaults:
		if not combat_brain.has(key):
			combat_brain[key] = defaults[key]

func initialize_combat_brain() -> void:
	combat_brain = _make_default_combat_brain()

func get_brain_value(key: String) -> float:
	ensure_combat_brain()
	return float(combat_brain.get(key, 0.5))

func adjust_brain_value(key: String, delta: float, use_learning_rate: bool = true) -> void:
	ensure_combat_brain()
	var rate = _get_learning_rate() if use_learning_rate else 1.0
	combat_brain[key] = _clamp01(get_brain_value(key) + delta * rate)

func remember_lesson(text: String) -> void:
	ensure_combat_brain()
	var lessons: Array = combat_brain.get("lessons", [])
	if lessons.is_empty() or lessons[lessons.size() - 1] != text:
		lessons.append(text)
	while lessons.size() > 4:
		lessons.remove_at(0)
	combat_brain["lessons"] = lessons

func record_damage_taken(amount: int, max_hp_value: int) -> void:
	if max_hp_value <= 0:
		return
	var ratio = float(amount) / float(max_hp_value)
	if ratio <= 0.0:
		return
	adjust_brain_value("caution", mini(0.025, ratio * 0.05))
	adjust_brain_value("self_preserve", mini(0.03, ratio * 0.06))
	if ratio >= 0.2:
		adjust_brain_value("aggression", -0.012)
		remember_lesson("боль учит избегать открытого риска")

func record_combat_result(victory: bool, hp_ratio: float, damage_taken_ratio: float, damage_dealt: int, healing_done: int) -> void:
	ensure_combat_brain()
	combat_brain["battle_count"] = int(combat_brain.get("battle_count", 0)) + 1
	if victory:
		combat_brain["wins"] = int(combat_brain.get("wins", 0)) + 1
		adjust_brain_value("leader_trust", 0.006)

	if hp_ratio <= 0.3 or damage_taken_ratio >= 0.45:
		combat_brain["near_deaths"] = int(combat_brain.get("near_deaths", 0)) + 1
		adjust_brain_value("caution", 0.04)
		adjust_brain_value("self_preserve", 0.045)
		adjust_brain_value("aggression", -0.02)
		remember_lesson("выживание важнее жадной атаки")
	elif victory and hp_ratio >= 0.7:
		adjust_brain_value("aggression", 0.01)

	if damage_dealt > 0 and victory:
		adjust_brain_value("focus_fire", 0.018)
		adjust_brain_value("aggression", 0.01)
		remember_lesson("добивание врагов работает")

	if healing_done > 0:
		adjust_brain_value("teamwork", 0.02)
		adjust_brain_value("skill_patience", 0.012)
		remember_lesson("поддержка союзников повышает шанс выжить")

func _make_default_combat_brain() -> Dictionary:
	var brain = {
		"aggression": 0.45,
		"caution": 0.45,
		"teamwork": 0.45,
		"self_preserve": 0.45,
		"focus_fire": 0.45,
		"cover_usage": 0.45,
		"skill_patience": 0.45,
		"leader_trust": 0.45,
		"battle_count": 0,
		"wins": 0,
		"near_deaths": 0,
		"lessons": []
	}

	match character_class:
		"warrior":
			brain["aggression"] += 0.12
			brain["focus_fire"] += 0.05
		"mage":
			brain["caution"] += 0.1
			brain["skill_patience"] += 0.15
			brain["self_preserve"] += 0.05
		"healer":
			brain["teamwork"] += 0.18
			brain["caution"] += 0.1
			brain["skill_patience"] += 0.1
		"scout":
			brain["focus_fire"] += 0.08
			brain["caution"] += 0.08
			brain["cover_usage"] += 0.1
		"defender":
			brain["teamwork"] += 0.15
			brain["self_preserve"] += 0.1
			brain["aggression"] -= 0.05
		"berserker":
			brain["aggression"] += 0.2
			brain["caution"] -= 0.1
			brain["self_preserve"] -= 0.08
			brain["skill_patience"] -= 0.08
		"tactician":
			brain["skill_patience"] += 0.15
			brain["teamwork"] += 0.12
			brain["focus_fire"] += 0.05
		"assassin":
			brain["focus_fire"] += 0.18
			brain["aggression"] += 0.1
			brain["teamwork"] -= 0.05

	match personality_trait:
		"агрессивный":
			brain["aggression"] += 0.1
		"осторожный":
			brain["caution"] += 0.12
			brain["self_preserve"] += 0.08
		"сострадательный":
			brain["teamwork"] += 0.12
		"безрассудный":
			brain["aggression"] += 0.12
			brain["caution"] -= 0.08
		"расчётливый":
			brain["skill_patience"] += 0.12
			brain["focus_fire"] += 0.06
		"одиночка":
			brain["teamwork"] -= 0.08
			brain["self_preserve"] += 0.06
		"защитник":
			brain["teamwork"] += 0.1
			brain["self_preserve"] += 0.08

	for key in ["aggression", "caution", "teamwork", "self_preserve", "focus_fire", "cover_usage", "skill_patience", "leader_trust"]:
		brain[key] = _clamp01(float(brain[key]))
	return brain

func _get_learning_rate() -> float:
	var intelligence = float(stats.get("intelligence", stats.get("magic", 0) + stats.get("initiative", 5)))
	return max(0.45, min(1.25, 0.55 + intelligence * 0.035))

func _clamp01(value: float) -> float:
	return max(0.0, min(1.0, value))

## Сериализация для сохранения
func to_dict() -> Dictionary:
	ensure_combat_brain()
	return {
		"id": id,
		"display_name": display_name,
		"backstory_origin": backstory_origin,
		"backstory_event": backstory_event,
		"backstory_motivation": backstory_motivation,
		"personality_trait": personality_trait,
		"character_class": character_class,
		"character_class_display_name": character_class_display_name,
		"stats": stats,
		"current_hp": get_current_hp(),
		"combat_brain": combat_brain,
		"ability_ids": ability_ids,
		"unique_ability_id": unique_ability_id,
		"portrait_path": portrait_path
	}

static func from_dict(data: Dictionary) -> CharacterData:
	var char_data = CharacterData.new()
	char_data.id = data.get("id", "")
	char_data.display_name = data.get("display_name", "")
	char_data.backstory_origin = data.get("backstory_origin", "")
	char_data.backstory_event = data.get("backstory_event", "")
	char_data.backstory_motivation = data.get("backstory_motivation", "")
	char_data.personality_trait = data.get("personality_trait", "")
	char_data.character_class = data.get("character_class", "")
	char_data.character_class_display_name = data.get("character_class_display_name", "")
	char_data.stats = data.get("stats", {})
	if data.has("current_hp"):
		char_data.set_current_hp(int(data.get("current_hp", char_data.get_max_hp())))
	else:
		char_data.set_current_hp(char_data.get_max_hp())
	char_data.combat_brain = data.get("combat_brain", {})
	char_data.ensure_combat_brain()
	char_data.ability_ids.clear()
	for aid in data.get("ability_ids", []):
		char_data.ability_ids.append(str(aid))
	char_data.unique_ability_id = data.get("unique_ability_id", "")
	char_data.portrait_path = data.get("portrait_path", "")
	if not char_data.stats.has("initiative"):
		char_data.stats["initiative"] = int(char_data.stats.get("speed", 5))
	return char_data

class_name CharacterGenerator
extends RefCounted

## Генерирует персонажа с нуля: предыстория -> характер -> класс -> способности

const CharacterDataScript = preload("res://scripts/core/character_data.gd")

var _rng: RandomNumberGenerator
var _backstories: Dictionary
var _personalities: Dictionary
var _classes: Dictionary
var _names: Dictionary

func _init(seed_value: int = -1) -> void:
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_load_data()

func _load_data() -> void:
	_backstories = _load_json("res://data/backstories.json")
	_personalities = _load_json("res://data/personalities.json")
	_classes = _load_json("res://data/classes.json")
	_names = _load_json("res://data/names.json")

func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Не удалось загрузить: " + path)
		return {}
	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if data == null:
		push_error("Ошибка парсинга JSON: " + path)
		return {}
	if data is Dictionary:
		return data
	return {}

func _pick_random(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[_rng.randi() % arr.size()]

## Главный метод: генерирует полного персонажа
func generate_character() -> CharacterData:
	var char_data = CharacterDataScript.new()
	char_data.id = "char_%d_%d" % [Time.get_unix_time_from_system(), _rng.randi()]
	
	# 1. Предыстория
	var origin = _pick_random(_backstories.get("origins", []))
	var event = _pick_random(_backstories.get("key_events", []))
	var motivation = _pick_random(_backstories.get("motivations", []))
	char_data.backstory_origin = str(origin)
	char_data.backstory_event = str(event)
	char_data.backstory_motivation = str(motivation)
	
	# 2. Характер (черта) - влияет на класс
	var traits = _personalities.get("traits", [])
	var selected_trait = _pick_random(traits)
	if selected_trait == null:
		selected_trait = {"name": "неизвестный", "class_weight": {}, "stat_bonus": {}}
	char_data.personality_trait = selected_trait.get("name", "неизвестный")
	
	# 3. Класс - на основе черты характера
	char_data.character_class = _pick_class_from_trait(selected_trait)
	var class_info = _classes.get("classes", {}).get(char_data.character_class, {})
	char_data.character_class_display_name = class_info.get("name", char_data.character_class)
	
	# 4. Имя
	char_data.display_name = _generate_name()
	
	# 5. Статы - базовые из класса + бонусы от черты
	var class_data = _classes.get("classes", {}).get(char_data.character_class, {})
	var base_stats = class_data.get("base_stats", {})
	char_data.stats = _apply_stat_modifiers(base_stats.duplicate(), selected_trait)
	
	# 6. Способности - базовые класса + уникальная
	char_data.ability_ids.clear()
	for aid in class_data.get("base_abilities", []):
		char_data.ability_ids.append(str(aid))
	char_data.unique_ability_id = _generate_unique_ability_id(char_data)
	
	return char_data

func _pick_class_from_trait(trait_data: Dictionary) -> String:
	var weights: Dictionary = trait_data.get("class_weight", {})
	if weights.is_empty():
		return _pick_random(["warrior", "mage", "healer"])
	
	var total_weight: int = 0
	for w in weights.values():
		total_weight += int(w)
	
	var keys_arr = Array(weights.keys())
	if total_weight <= 0 or keys_arr.is_empty():
		return _pick_random(keys_arr) if keys_arr.size() > 0 else "warrior"
	
	var roll = _rng.randi() % total_weight
	for class_id in keys_arr:
		roll -= int(weights[class_id])
		if roll < 0:
			return class_id
	
	return keys_arr[0]

func _apply_stat_modifiers(stats: Dictionary, trait_data: Dictionary) -> Dictionary:
	var bonus = trait_data.get("stat_bonus", {})
	for key in bonus.keys():
		if stats.has(key):
			stats[key] = int(stats[key]) + int(bonus[key])
		else:
			stats[key] = int(bonus[key])
		if stats[key] < 1:
			stats[key] = 1
	return stats

func _generate_name() -> String:
	var first = _pick_random(_names.get("first_names", ["Герой"]))
	var last = _pick_random(_names.get("surnames", [""]))
	if last:
		return "%s %s" % [first, last]
	return str(first)

func _generate_unique_ability_id(char_data: CharacterData) -> String:
	# Уникальная способность на основе комбинации предыстория + характер + класс
	var parts = [char_data.backstory_motivation, char_data.personality_trait, char_data.character_class]
	var combined = "_".join(parts).to_lower()
	combined = combined.replace(" ", "_")
	return "unique_%s_%d" % [combined.hash(), _rng.randi() % 1000]

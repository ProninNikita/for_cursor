class_name AbilityRegistry
extends RefCounted

static var _abilities: Dictionary = {}
static var _enemy_abilities: Dictionary = {}
static var _initialized: bool = false

static func _load_json(path: String) -> Dictionary:
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

static func initialize():
	if _initialized:
		return

	var data = _load_json("res://data/abilities.json")
	_abilities = data.get("abilities", {})
	_enemy_abilities = data.get("enemy_abilities", {})
	_initialized = true

static func get_ability(id: String):
	if not _initialized:
		initialize()

	var ability_data = _abilities.get(id, null)
	if ability_data == null:
		ability_data = _enemy_abilities.get(id, null)

	if ability_data == null:
		push_warning("Способность не найдена: " + id)
		return null

	var ability = AbilityData.from_dict(ability_data)
	ability.id = id
	return ability

static func get_all_ability_ids():
	if not _initialized:
		initialize()

	var ids: Array[String] = []
	for id in _abilities:
		ids.append(id)
	for id in _enemy_abilities:
		ids.append(id)
	return ids

static func create_basic_attack():
	return get_ability("basic_attack")

static func generate_unique_ability(motivation: String, personality_trait: String, class_id: String):
	if not _initialized:
		initialize()

	var combined_hash = (motivation + personality_trait + class_id).hash()
	var abs_hash = abs(combined_hash)

	var base_ability = _select_base_ability_for_class(class_id, abs_hash)
	if base_ability == null:
		base_ability = create_basic_attack()

	var unique_ability = base_ability.clone()
	unique_ability.id = "unique_%d" % abs_hash
	unique_ability.name = _generate_unique_name(motivation, personality_trait, class_id)
	unique_ability.description = "Уникальная способность: %s" % [motivation]
	unique_ability.power = mini(2.5, base_ability.power * 1.2)
	unique_ability.cooldown_max = maxi(1, base_ability.cooldown_max - 1)

	return unique_ability

static func _select_base_ability_for_class(class_id: String, hash_value: int):
	var class_abilities: Array[String] = []

	match class_id:
		"warrior":
			class_abilities = ["basic_attack", "heavy_strike", "guard"]
		"mage":
			class_abilities = ["fireball", "arcane_bolt", "barrier"]
		"healer":
			class_abilities = ["heal", "cure", "blessing"]
		"scout":
			class_abilities = ["quick_strike", "evade", "mark_target"]
		"defender":
			class_abilities = ["shield_bash", "taunt", "fortify"]
		"berserker":
			class_abilities = ["frenzy", "bloodlust", "reckless_charge"]
		"tactician":
			class_abilities = ["command", "tactical_strike", "rally"]
		"assassin":
			class_abilities = ["backstab", "poison_blade", "shadow_step"]
		_:
			class_abilities = ["basic_attack"]

	if class_abilities.is_empty():
		return null

	var index = hash_value % class_abilities.size()
	return get_ability(class_abilities[index])

static func _generate_unique_name(motivation: String, personality_trait: String, class_id: String) -> String:
	var prefixes = {
		"месть": ["Кровавая", "Яростная", "Мстительная"],
		"защита": ["Стальной", "Несломленная", "Верная"],
		"знание": ["Мистическая", "Древняя", "Таинственная"],
		"богатство": ["Золотая", "Алчная", "Сокровищная"],
		"искупление": ["Искупительная", "Святая", "Чистая"]
	}

	var suffixes = {
		"warrior": ["Меч", "Удар", "Ярость"],
		"mage": ["Магия", "Заклинание", "Энергия"],
		"healer": ["Благодать", "Свет", "Исцеление"],
		"scout": ["Тень", "Заря", "Шаг"],
		"defender": ["Щит", "Стена", "Крепость"],
		"berserker": ["Ярость", "Кровь", "Безумие"],
		"tactician": ["Стратегия", "Команда", "Тактика"],
		"assassin": ["Удар", "Клинок", "Смерть"]
	}

	var prefix_list = prefixes.get(motivation.to_lower(), ["Уникальная"])
	var suffix_list = suffixes.get(class_id.to_lower(), ["Способность"])

	var prefix_index = (motivation + personality_trait).hash() % prefix_list.size()
	var suffix_index = (personality_trait + class_id).hash() % suffix_list.size()

	return "%s %s" % [prefix_list[prefix_index], suffix_list[suffix_index]]

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

## Сериализация для сохранения
func to_dict() -> Dictionary:
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
	char_data.ability_ids.clear()
	for aid in data.get("ability_ids", []):
		char_data.ability_ids.append(str(aid))
	char_data.unique_ability_id = data.get("unique_ability_id", "")
	char_data.portrait_path = data.get("portrait_path", "")
	if not char_data.stats.has("initiative"):
		char_data.stats["initiative"] = int(char_data.stats.get("speed", 5))
	return char_data

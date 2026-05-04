extends Node

## Менеджер сохранений — каждый слот в отдельном файле с метаданными

const SAVE_DIR = "user://saves/"
const SAVE_SLOTS = 3
const STARTING_LOOTBOXES = 10

func _ready() -> void:
	_dir_ensure(SAVE_DIR)

func _dir_ensure(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

func get_save_path(slot: int) -> String:
	return SAVE_DIR + "save_slot_%d.json" % slot

## Загружает метаданные сохранения (без полных данных)
func get_save_info(slot: int) -> Dictionary:
	var path = get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "slot": slot}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false, "slot": slot}
	
	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return {"exists": false, "slot": slot}
	
	var meta = data.get("metadata", {})
	var tower_data = data.get("tower_elevation", {})
	return {
		"exists": true,
		"slot": slot,
		"name": meta.get("name", "Сохранение %d" % slot),
		"date": meta.get("date", ""),
		"playtime_seconds": meta.get("playtime_seconds", 0),
		"character_count": meta.get("character_count", 0),
		"lootboxes_remaining": meta.get("lootboxes_remaining", 0),
		"tower_max_floor": tower_data.get("max_floor", 1),
		"active_raid": data.get("active_raid") != null
	}

func list_saves() -> Array:
	var result: Array = []
	for slot in range(1, SAVE_SLOTS + 1):
		result.append(get_save_info(slot))
	return result

func save_game(slot: int, playtime_seconds: float = 0.0) -> bool:
	var roster = GameState.roster
	var lootboxes = GameState.lootboxes_remaining
	
	var characters_data: Array = []
	for c in roster.get_characters():
		characters_data.append(c.to_dict())
	
	var tower_max_floor = GameState.tower_elevation.max_floor if GameState.tower_elevation else 1
	var has_active_raid = GameState.active_raid != null

	var save_data = {
		"metadata": {
			"name": "Сохранение %d" % slot,
			"date": Time.get_datetime_string_from_system(),
			"playtime_seconds": int(playtime_seconds),
			"character_count": roster.get_character_count(),
			"lootboxes_remaining": lootboxes,
			"tower_max_floor": tower_max_floor,
			"active_raid": has_active_raid
		},
		"lootboxes_remaining": lootboxes,
		"characters": characters_data,
		"tower_elevation": GameState.tower_elevation.to_dict() if GameState.tower_elevation else {},
		"active_raid": GameState.active_raid.to_dict() if GameState.active_raid else null,
		"completed_raids": GameState.completed_raids
	}
	
	var path = get_save_path(slot)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось сохранить: " + path)
		return false
	
	file.store_string(JSON.stringify(save_data))
	file.close()
	return true

func load_game(slot: int) -> bool:
	var path = get_save_path(slot)
	if not FileAccess.file_exists(path):
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null or not data is Dictionary:
		return false

	GameState.lootboxes_remaining = data.get("lootboxes_remaining", 0)
	GameState.roster.clear_all()

	for char_dict in data.get("characters", []):
		var char_data = CharacterData.from_dict(char_dict)
		GameState.roster.add_character(char_data)

	# Загружаем прогресс Башни
	var tower_data = data.get("tower_elevation", {})
	if not tower_data.is_empty():
		GameState.tower_elevation.from_dict(tower_data)

	# Загружаем активную вылазку (если была)
	var raid_data = data.get("active_raid")
	if raid_data != null:
		GameState.active_raid = RaidExpedition.from_dict(raid_data)

	# Загружаем историю вылазок
	GameState.completed_raids = data.get("completed_raids", [])

	return true

func delete_save(slot: int) -> bool:
	var path = get_save_path(slot)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK

func delete_all_saves() -> void:
	for slot in range(1, SAVE_SLOTS + 1):
		delete_save(slot)

func start_new_game() -> void:
	GameState.roster.clear_all()
	GameState.lootboxes_remaining = STARTING_LOOTBOXES
	GameState.tower_elevation.reset()
	GameState.active_raid = null
	GameState.completed_raids.clear()

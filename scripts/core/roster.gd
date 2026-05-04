class_name Roster
extends RefCounted

## Ростер — хранит всех полученных персонажей

var characters: Array[CharacterData] = []
const MAX_SQUAD_SIZE: int = 5

func add_character(char_data: CharacterData) -> void:
	characters.append(char_data)

func clear_all() -> void:
	characters.clear()

func get_character_count() -> int:
	return characters.size()

func get_characters() -> Array[CharacterData]:
	return characters.duplicate()

## Выбрать отряд для миссии (до MAX_SQUAD_SIZE персонажей)
func get_squad(character_ids: Array) -> Array[CharacterData]:
	var squad: Array[CharacterData] = []
	var ids = {}
	for id in character_ids:
		ids[id] = true
	
	for c in characters:
		if c.id in ids and squad.size() < MAX_SQUAD_SIZE:
			squad.append(c)
	
	return squad

func get_by_id(char_id: String) -> CharacterData:
	for c in characters:
		if c.id == char_id:
			return c
	return null

func remove_character(char_id: String) -> void:
	for i in range(characters.size() - 1, -1, -1):
		if characters[i].id == char_id:
			characters.remove_at(i)
			return

func apply_hp_from_battle(char_id: String, hp_remaining: int) -> void:
	var c = get_by_id(char_id)
	if c == null:
		return
	if hp_remaining <= 0:
		remove_character(char_id)
	else:
		c.stats["hp"] = hp_remaining

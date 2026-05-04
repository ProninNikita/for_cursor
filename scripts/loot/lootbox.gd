class_name Lootbox
extends RefCounted

## Лутбокс — при открытии генерирует нового персонажа с нуля

var _generator: CharacterGenerator

func _init(seed_value: int = -1) -> void:
	_generator = CharacterGenerator.new(seed_value)

## Открыть лутбокс и получить нового персонажа
func open() -> CharacterData:
	return _generator.generate_character()

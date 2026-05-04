class_name TowerElevation
extends RefCounted

## Управляет прогрессом игрока в Возвышении (многоэтажная башня)

var current_floor: int = 1  ## Текущий этаж (нумерация с 1)
var max_floor: int = 1  ## Максимальный достигнутый этаж
var floor_attempts: Dictionary = {}  ## floor_num -> количество попыток
var floor_victories: Dictionary = {}  ## floor_num -> количество побед

func _init():
	_load_from_save()

## Загружает данные об этаже из JSON
func get_floor_data(floor_num: int) -> Dictionary:
	var file = FileAccess.open("res://data/tower_floors.json", FileAccess.READ)
	if file == null:
		push_error("Не удалось загрузить tower_floors.json")
		return {}

	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)

	if data == null or not data is Dictionary:
		push_error("Ошибка парсинга tower_floors.json")
		return {}

	var floors = data.get("floors", {})
	return floors.get(str(floor_num), {})

## Продвигает на следующий этаж после победы
func advance_to_next_floor() -> void:
	current_floor += 1
	if current_floor > max_floor:
		max_floor = current_floor
	_save_progress()

## Можно ли попытаться пройти этот этаж?
func can_attempt_floor(floor_num: int) -> bool:
	return floor_num <= max_floor + 1

## Регистрирует попытку прохождения этажа
func register_attempt(floor_num: int) -> void:
	floor_attempts[str(floor_num)] = floor_attempts.get(str(floor_num), 0) + 1
	_save_progress()

## Регистрирует победу на этаже
func register_victory(floor_num: int) -> void:
	floor_victories[str(floor_num)] = floor_victories.get(str(floor_num), 0) + 1
	_save_progress()

## Получает статистику этажа
func get_floor_stats(floor_num: int) -> Dictionary:
	return {
		"attempts": floor_attempts.get(str(floor_num), 0),
		"victories": floor_victories.get(str(floor_num), 0)
	}

## Сбрасывает прогресс (для новой игры)
func reset() -> void:
	current_floor = 1
	max_floor = 1
	floor_attempts.clear()
	floor_victories.clear()
	_save_progress()

## Сериализация для сохранения
func to_dict() -> Dictionary:
	return {
		"current_floor": current_floor,
		"max_floor": max_floor,
		"floor_attempts": floor_attempts,
		"floor_victories": floor_victories
	}

## Десериализация из сохранения
func from_dict(data: Dictionary) -> void:
	current_floor = data.get("current_floor", 1)
	max_floor = data.get("max_floor", 1)
	floor_attempts = data.get("floor_attempts", {})
	floor_victories = data.get("floor_victories", {})

func _load_from_save() -> void:
	# Загрузка из сохранения будет через SaveManager
	pass

func _save_progress() -> void:
	# Сохранение будет через SaveManager
	# Это просто уведомление о необходимости сохранения
	pass

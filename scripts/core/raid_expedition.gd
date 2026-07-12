class_name RaidExpedition
extends RefCounted

## Управляет активной вылазкой

enum RaidStatus { PREPARING, IN_PROGRESS, COMPLETED, FAILED }
enum RaidType { HUNT, SCOUT, CARAVAN }
enum RaidDifficulty { EASY, NORMAL, HARD }

var squad: Array[CharacterData] = []
var duration_hours: int = 0  ## Длительность в часах (реального времени)
var elapsed_hours: int = 0  ## Прошедшее время
var status: RaidStatus = RaidStatus.PREPARING
var raid_type: RaidType = RaidType.HUNT
var difficulty: RaidDifficulty = RaidDifficulty.NORMAL
var events: Array[Dictionary] = []  ## События во время вылазки
var pending_rewards: Dictionary = {}  ## Награды после завершения
var start_time: int = 0  ## Время начала (Unix timestamp)
var character_states: Dictionary = {}  ## Состояние героев {char_id: {hp, max_hp}}
var pending_combat_event: Dictionary = {}  ## Событие, требующее боя

## Создаёт новую вылазку
static func create(squad_chars: Array[CharacterData], duration: int, type: int, diff: int) -> RaidExpedition:
	var raid = RaidExpedition.new()
	raid.squad = squad_chars
	raid.duration_hours = duration
	raid.raid_type = type as RaidType
	raid.difficulty = diff as RaidDifficulty
	raid.status = RaidStatus.IN_PROGRESS
	raid.start_time = Time.get_unix_time_from_system()

	# Сохраняем начальное состояние героев
	for hero in squad_chars:
		raid.character_states[hero.id] = {
			"hp": hero.get_current_hp(),
			"max_hp": hero.get_max_hp()
		}

	return raid

## Продвигает время на указанное количество часов
func tick(hours: int) -> Array[Dictionary]:
	if status != RaidStatus.IN_PROGRESS:
		return []

	var new_events: Array[Dictionary] = []
	elapsed_hours += hours

	# Генерируем события для каждого часа
	for i in range(hours):
		if elapsed_hours >= duration_hours:
			status = RaidStatus.COMPLETED
			_calculate_final_rewards()
			break

		_apply_travel_fatigue()
		var event = _generate_random_event()
		if not event.is_empty():
			events.append(event)
			new_events.append(event)
			_process_event(event)

	return new_events

## Генерирует случайное событие
func _generate_random_event() -> Dictionary:
	var file = FileAccess.open("res://data/raid_events.json", FileAccess.READ)
	if file == null:
		return {}

	var text = file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)

	if data == null or not data is Dictionary:
		return {}

	var all_events = data.get("events", {})
	var event_keys = all_events.keys()

	if event_keys.is_empty():
		return {}

	# Шанс события: 30% каждый час
	if randf() > 0.3:
		return {}

	var random_key = event_keys.pick_random()
	var event_data = all_events[random_key].duplicate()
	event_data["hour"] = elapsed_hours + 1
	return event_data

## Обрабатывает событие
func _process_event(event: Dictionary) -> void:
	var event_type = event.get("type", "")

	match event_type:
		"combat":
			# Сохраняем событие для обработки через combat scene
			pending_combat_event = event.duplicate()
		"reward":
			var rewards = event.get("rewards", {})
			for key in rewards:
				pending_rewards[key] = pending_rewards.get(key, 0) + rewards[key]
		"heal":
			var heal_percent = event.get("heal_percent", 0)
			for char_id in character_states:
				var state = character_states[char_id]
				var heal_amount = int(state["max_hp"] * heal_percent / 100.0)
				state["hp"] = mini(state["max_hp"], state["hp"] + heal_amount)
				state["fatigue"] = maxf(0.0, float(state.get("fatigue", 0.0)) - 0.12)
		"damage":
			var damage_percent = event.get("damage_percent", 0)
			for char_id in character_states:
				var state = character_states[char_id]
				var damage_amount = int(state["max_hp"] * damage_percent / 100.0)
				state["hp"] = maxi(0, state["hp"] - damage_amount)

				# Проверка на смерть
				if state["hp"] <= 0:
					status = RaidStatus.FAILED
		_:
			# Другие типы событий можно добавить позже
			pass

## Вычисляет финальные награды
func _calculate_final_rewards() -> void:
	# Базовые награды за длительность
	var base_lootboxes = 1
	var base_gold = 25

	match duration_hours:
		2:
			base_lootboxes = 1
			base_gold = 25
		6:
			base_lootboxes = 2
			base_gold = 75
		12:
			base_lootboxes = 3
			base_gold = 150
		24:
			base_lootboxes = 5
			base_gold = 300

	# Множитель сложности
	var difficulty_mult = 1.0
	match difficulty:
		RaidDifficulty.EASY:
			difficulty_mult = 0.8
		RaidDifficulty.NORMAL:
			difficulty_mult = 1.0
		RaidDifficulty.HARD:
			difficulty_mult = 1.5

	# Множитель типа вылазки
	var type_mult = 1.0
	match raid_type:
		RaidType.HUNT:
			type_mult = 1.2  # Больше ресурсов
		RaidType.SCOUT:
			type_mult = 0.8  # Меньше ресурсов, но больше информации
		RaidType.CARAVAN:
			type_mult = 1.0  # Баланс

	pending_rewards["lootboxes"] = pending_rewards.get("lootboxes", 0) + int(base_lootboxes * difficulty_mult * type_mult)
	pending_rewards["gold"] = pending_rewards.get("gold", 0) + int(base_gold * difficulty_mult * type_mult)

func _apply_travel_fatigue() -> void:
	if duration_hours < 6:
		return
	var difficulty_pressure := 1.0
	match difficulty:
		RaidDifficulty.EASY:
			difficulty_pressure = 0.65
		RaidDifficulty.NORMAL:
			difficulty_pressure = 1.0
		RaidDifficulty.HARD:
			difficulty_pressure = 1.35
	for char_id in character_states:
		var state = character_states[char_id]
		var fatigue := clampf(float(state.get("fatigue", 0.0)) + 0.045 * difficulty_pressure, 0.0, 0.7)
		state["fatigue"] = fatigue
		if fatigue < 0.18:
			continue
		var damage_percent := 0.01 + fatigue * 0.018
		var damage_amount := maxi(1, int(round(float(state["max_hp"]) * damage_percent)))
		state["hp"] = maxi(1, int(state["hp"]) - damage_amount)

## Завершена ли вылазка?
func is_complete() -> bool:
	return elapsed_hours >= duration_hours or status == RaidStatus.COMPLETED or status == RaidStatus.FAILED

## Получает прогресс (0.0 - 1.0)
func get_progress() -> float:
	if duration_hours == 0:
		return 0.0
	return float(elapsed_hours) / float(duration_hours)

## Получает оставшееся время в часах
func get_remaining_hours() -> int:
	return maxi(0, duration_hours - elapsed_hours)

## Есть ли незавершённый бой?
func has_pending_combat() -> bool:
	return not pending_combat_event.is_empty()

## Получает событие, требующее боя
func get_pending_combat_event() -> Dictionary:
	return pending_combat_event.duplicate()

## Завершает бой в вылазке
func complete_combat_event(victory: bool) -> void:
	if pending_combat_event.is_empty():
		return

	if victory:
		# Награда за победу в бою
		var combat_reward = pending_combat_event.get("rewards", {})
		for key in combat_reward:
			pending_rewards[key] = pending_rewards.get(key, 0) + combat_reward[key]
	else:
		# Штраф за поражение - дополнительный урон отряду
		var damage_percent = 15  # 15% урона всем при поражении
		for char_id in character_states:
			var state = character_states[char_id]
			var damage_amount = int(state["max_hp"] * damage_percent / 100.0)
			state["hp"] = maxi(0, state["hp"] - damage_amount)

			# Проверка на смерть
			if state["hp"] <= 0:
				status = RaidStatus.FAILED

	pending_combat_event.clear()

## Обновляет состояние героев в ростере после завершения
func update_roster_states() -> void:
	for hero in squad:
		if hero.id in character_states:
			var state = character_states[hero.id]
			hero.set_current_hp(state["hp"])

			# Если герой умер, удаляем его из ростера
			if state["hp"] <= 0:
				GameState.roster.remove_character(hero.id)

## Сериализация для сохранения
func to_dict() -> Dictionary:
	var squad_ids = []
	for hero in squad:
		squad_ids.append(hero.id)

	return {
		"squad_ids": squad_ids,
		"duration_hours": duration_hours,
		"elapsed_hours": elapsed_hours,
		"status": status,
		"raid_type": raid_type,
		"difficulty": difficulty,
		"events": events,
		"pending_rewards": pending_rewards,
		"start_time": start_time,
		"character_states": character_states
	}

## Десериализация из сохранения
static func from_dict(data: Dictionary) -> RaidExpedition:
	var raid = RaidExpedition.new()
	raid.duration_hours = data.get("duration_hours", 0)
	raid.elapsed_hours = data.get("elapsed_hours", 0)
	raid.status = data.get("status", RaidStatus.IN_PROGRESS)
	raid.raid_type = data.get("raid_type", RaidType.HUNT)
	raid.difficulty = data.get("difficulty", RaidDifficulty.NORMAL)
	raid.events = data.get("events", [])
	raid.pending_rewards = data.get("pending_rewards", {})
	raid.start_time = data.get("start_time", 0)
	raid.character_states = data.get("character_states", {})

	# Восстанавливаем отряд из ID
	var squad_ids = data.get("squad_ids", [])
	raid.squad = []
	for char_id in squad_ids:
		var hero = GameState.roster.get_by_id(char_id)
		if hero != null:
			raid.squad.append(hero)

	return raid

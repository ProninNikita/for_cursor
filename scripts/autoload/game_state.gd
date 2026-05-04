extends Node

## Глобальное состояние игры — ростер и лутбокс сохраняются между сценами

var roster: Roster
var lootbox: Lootbox
var lootboxes_remaining: int = 0  ## Неоткрытые лутбоксы

## Временные данные перед сценой боя (очищаются после боя)
var pending_combat_squad: Array[CharacterData] = []
var pending_combat_encounter: String = ""
var pending_tower_floor: int = 1  ## Выбранный этаж для Возвышения
var is_tower_elevation: bool = false  ## Это бой в Возвышении?

## Прогресс Башни
var tower_elevation: TowerElevation = null  ## Прогресс Возвышения
var active_raid: RaidExpedition = null  ## Текущая вылазка (если есть)
var completed_raids: Array[Dictionary] = []  ## История завершённых вылазок

## Текущее событие вылазки (для боёв)
var pending_raid_event: Dictionary = {}  ## Событие вылазки, которое требует боя

func _ready() -> void:
	roster = Roster.new()
	lootbox = Lootbox.new()
	tower_elevation = TowerElevation.new()

func begin_combat(squad: Array[CharacterData], encounter_id: String) -> void:
	pending_combat_squad.clear()
	for c in squad:
		pending_combat_squad.append(c)
	pending_combat_encounter = encounter_id

func clear_pending_combat() -> void:
	pending_combat_squad.clear()
	pending_combat_encounter = ""

## Начинает бой в Башне (для Возвышения)
func begin_tower_combat(squad: Array[CharacterData], floor_num: int) -> void:
	begin_combat(squad, "tower_floor_" + str(floor_num))

## Начинает вылазку
func begin_raid(squad: Array[CharacterData], duration_hours: int, raid_type: int, difficulty: int) -> void:
	active_raid = RaidExpedition.create(squad, duration_hours, raid_type, difficulty)

## Завершает вылазку и выдаёт награды
func complete_raid() -> Dictionary:
	if active_raid == null:
		return {}

	var rewards = active_raid.pending_rewards.duplicate()
	var duration = active_raid.duration_hours

	active_raid.update_roster_states()

	# Сохраняем в историю
	completed_raids.append({
		"duration": duration,
		"rewards": rewards,
		"timestamp": Time.get_unix_time_from_system()
	})

	active_raid = null
	return rewards

## Отменяет вылазку (без наград)
func cancel_raid() -> void:
	if active_raid == null:
		return

	# Герои возвращаются с тем HP, с которым ушли
	active_raid.update_roster_states()
	active_raid = null

## Начинает бой в вылазке
func begin_raid_combat(squad: Array[CharacterData], event_data: Dictionary) -> void:
	pending_raid_event = event_data
	pending_combat_squad.clear()
	for c in squad:
		pending_combat_squad.append(c)

	# Генерируем encounter_id на основе врагов из события
	var enemies = event_data.get("enemies", [])
	var encounter_id = "raid_event_"
	for enemy in enemies:
		encounter_id += enemy.get("type", "") + "_"

	pending_combat_encounter = encounter_id

## Завершает бой в вылазке
func finish_raid_combat(victory: bool) -> void:
	if active_raid == null:
		return

	if victory:
		# Обрабатываем победу - можно добавить дополнительные награды
		pass
	else:
		# При поражении в событии вылазка не проваливается сразу,
		# но герои получают урон или могут погибнуть
		pass

	pending_raid_event.clear()

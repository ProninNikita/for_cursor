extends Control

## Город-хаб — центральная локация
## Портал, Башня, Мастерская, Особняк, Тренировочная площадка

const PORTAL_SCENE = "res://scenes/portal/portal.tscn"
const MANSION_SCENE = "res://scenes/mansion/mansion.tscn"
const TOWER_LOBBY_SCENE = "res://scenes/tower/tower_lobby.tscn"
const COMBAT_SCENE = "res://scenes/combat/combat.tscn"
const RAID_PROGRESS_SCENE = "res://scenes/tower/raid_progress.tscn"

@onready var portal_btn: Button = $BuildingsGrid/Portal/VBox/Btn
@onready var tower_btn: Button = $BuildingsGrid/Tower/VBox/Btn
@onready var tower_desc: Label = $BuildingsGrid/Tower/VBox/Desc
@onready var workshop_btn: Button = $BuildingsGrid/Workshop/VBox/Btn
@onready var mansion_btn: Button = $BuildingsGrid/Mansion/VBox/Btn
@onready var training_btn: Button = $BuildingsGrid/TrainingGround/VBox/Btn
@onready var save_btn: Button = $TopBar/SaveBtn

var _raid_timer: float = 0.0  # Таймер для обновления вылазки
const RAID_UPDATE_INTERVAL: float = 5.0  # Обновлять каждые 5 секунд

func _ready() -> void:
	_set_qa_ids()
	save_btn.pressed.connect(_on_save)
	portal_btn.pressed.connect(_on_portal)
	tower_btn.pressed.connect(_on_tower)
	workshop_btn.pressed.connect(_on_workshop)
	mansion_btn.pressed.connect(_on_mansion)
	training_btn.pressed.connect(_on_training)

	# Обновляем индикатор вылазки
	_update_raid_indicator()

func _set_qa_ids() -> void:
	save_btn.set_meta("qa_id", "hub.save")
	portal_btn.set_meta("qa_id", "hub.portal")
	tower_btn.set_meta("qa_id", "hub.tower")
	workshop_btn.set_meta("qa_id", "hub.workshop")
	mansion_btn.set_meta("qa_id", "hub.mansion")
	training_btn.set_meta("qa_id", "hub.training")

func _process(delta: float) -> void:
	# Обновляем активную вылазку в реальном времени
	if GameState.active_raid != null:
		_raid_timer += delta
		if _raid_timer >= RAID_UPDATE_INTERVAL:
			_raid_timer = 0.0
			_tick_raid()
			_update_raid_indicator()

func _tick_raid() -> void:
	if GameState.active_raid == null:
		return

	# Проверяем, есть ли незавершённый бой
	if GameState.active_raid.has_pending_combat():
		# Предлагаем игроку вступить в бой
		_show_combat_alert()
		return

	# Продвигаем вылазку (1 час за каждые 5 секунд реального времени)
	# Это можно настроить для баланса
	var raid = GameState.active_raid
	raid.tick(1)

	# Проверяем, появился ли боевой event
	if raid.has_pending_combat():
		_show_combat_alert()
		return

	# Проверяем, завершена ли вылазка
	if raid.is_complete():
		_handle_raid_complete()

func _show_combat_alert() -> void:
	# Меняем текст индикатора на предупреждение о бое
	var raid = GameState.active_raid
	if raid == null:
		return

	var combat_event = raid.get_pending_combat_event()
	var event_name = combat_event.get("name", "Бой")
	tower_desc.text = "⚔️ %s!\nОтряд под атакой!\nНажми Башню → Продолжить" % event_name
	tower_desc.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3, 1))

func _handle_raid_complete() -> void:
	var raid = GameState.active_raid
	if raid == null:
		return

	if raid.status == RaidExpedition.RaidStatus.COMPLETED:
		var rewards = GameState.complete_raid()
		_show_raid_notification("Вылазка завершена!", "Получено: %d лутбоксов, %d золота" % [rewards.get("lootboxes", 0), rewards.get("gold", 0)])
	elif raid.status == RaidExpedition.RaidStatus.FAILED:
		GameState.cancel_raid()
		_show_raid_notification("Вылазка провалилась!", "Отряд погиб в вылазке.")

func _show_raid_notification(title: String, message: String) -> void:
	# TODO: Показать красивое уведомление
	print("%s: %s" % [title, message])

func _update_raid_indicator() -> void:
	if GameState.active_raid != null:
		var raid = GameState.active_raid
		var progress = int(raid.get_progress() * 100)
		var remaining = raid.get_remaining_hours()
		tower_desc.text = "Активная вылазка!\nПрогресс: %d%%\nОсталось: %dч\nНажми для деталей" % [progress, remaining]
		tower_desc.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 1))
	else:
		tower_desc.text = "Возвышение и Вылазки"
		tower_desc.remove_theme_color_override("font_color")

func _on_portal() -> void:
	get_tree().change_scene_to_file(PORTAL_SCENE)

func _on_tower() -> void:
	# Если есть активная вылазка с боевым событием, идём в бой
	if GameState.active_raid != null and GameState.active_raid.has_pending_combat():
		var combat_event = GameState.active_raid.get_pending_combat_event()
		GameState.begin_raid_combat(GameState.active_raid.squad, combat_event)
		get_tree().change_scene_to_file(COMBAT_SCENE)
	elif GameState.active_raid != null:
		# Есть активная вылазка но без боя - показываем прогресс
		get_tree().change_scene_to_file(RAID_PROGRESS_SCENE)
	else:
		# Нет активной вылазки - обычное меню Башни
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)

func _on_workshop() -> void:
	pass  # TODO: открыть сцену/меню мастерской (крафт)

func _on_mansion() -> void:
	get_tree().change_scene_to_file(MANSION_SCENE)

func _on_training() -> void:
	pass  # TODO: открыть сцену/меню тренировочной площадки

func _on_save() -> void:
	if SaveManager.save_game(1):
		save_btn.text = "Сохранено!"
		await get_tree().create_timer(1.5).timeout
		save_btn.text = "Сохранить игру"

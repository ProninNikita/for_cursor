extends Control

## Главное меню Башни - выбор режима (Возвышение или Вылазка)

const HUB_SCENE = "res://scenes/hub/hub.tscn"
const ELEVATION_SCENE = "res://scenes/tower/elevation.tscn"
const RAID_LOBBY_SCENE = "res://scenes/tower/raid_lobby.tscn"
const RAID_PROGRESS_SCENE = "res://scenes/tower/raid_progress.tscn"

@onready var back_btn: Button = $TopBar/BackBtn
@onready var elevation_btn: Button = $Main/HBox/ElevationPanel/VBox/ElevationBtn
@onready var raid_btn: Button = $Main/HBox/RaidPanel/VBox/RaidBtn
@onready var elevation_label: Label = $Main/HBox/ElevationPanel/VBox/Info
@onready var raid_label: Label = $Main/HBox/RaidPanel/VBox/Info

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	elevation_btn.pressed.connect(_on_elevation)
	raid_btn.pressed.connect(_on_raid)

	_update_info()

func _update_info() -> void:
	# Информация о Возвышении
	var current_floor = GameState.tower_elevation.current_floor
	var max_floor = GameState.tower_elevation.max_floor
	elevation_label.text = "Текущий этаж: %d\nМаксимальный достигнутый: %d" % [current_floor, max_floor]

	# Информация о Вылазке
	if GameState.active_raid != null:
		var progress = GameState.active_raid.get_progress() * 100
		var remaining = GameState.active_raid.get_remaining_hours()
		raid_label.text = "Активная вылазка:\nПрогресс: %d%%\nОсталось: %d ч" % [progress, remaining]
		raid_btn.text = "Продолжить"
	else:
		raid_label.text = "Нет активных вылазок"
		raid_btn.text = "Начать"

func _on_back() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)

func _on_elevation() -> void:
	get_tree().change_scene_to_file(ELEVATION_SCENE)

func _on_raid() -> void:
	if GameState.active_raid != null:
		get_tree().change_scene_to_file(RAID_PROGRESS_SCENE)
	else:
		get_tree().change_scene_to_file(RAID_LOBBY_SCENE)

extends Control

## Прогресс активной вылазки

const TOWER_LOBBY_SCENE = "res://scenes/tower/tower_lobby.tscn"

@onready var top_bar: HBoxContainer = $TopBar
@onready var back_btn: Button = $TopBar/BackBtn
@onready var time_label: Label = $Main/ProgressSection/TimeLabel
@onready var events_list: VBoxContainer = $Main/EventsSection/EventsList/EventsList
@onready var squad_list: VBoxContainer = $Main/SquadSection/SquadList
@onready var speed_up_btn: Button = $Main/ActionsSection/SpeedUpBtn
@onready var recall_btn: Button = $Main/ActionsSection/RecallBtn

var _raid: RaidExpedition = null
var _update_timer: Timer = null

func _ready() -> void:
	if back_btn == null:
		push_error("RaidProgress: BackBtn не найден")
	else:
		top_bar.move_to_front()
		back_btn.move_to_front()
		back_btn.disabled = false
		back_btn.visible = true
		back_btn.pressed.connect(_on_back)
		print("RaidProgress: BackBtn подключен")

	speed_up_btn.pressed.connect(_on_speed_up)
	recall_btn.pressed.connect(_on_recall)

	if GameState.active_raid == null:
		_show_no_raid()
		return

	_raid = GameState.active_raid
	_update_ui()

	_update_timer = Timer.new()
	_update_timer.timeout.connect(_on_timer_tick)
	_update_timer.wait_time = 1.0
	_update_timer.autostart = true
	add_child(_update_timer)

func _on_timer_tick() -> void:
	if _raid == null or GameState.active_raid == null:
		return

	var new_events = _raid.tick(1)
	for event in new_events:
		_add_event_to_list(event)

	_update_ui()

	if _raid.is_complete():
		_on_raid_complete()

func _update_ui() -> void:
	if _raid == null:
		return

	var elapsed = _raid.elapsed_hours
	var duration = _raid.duration_hours
	time_label.text = "Прошло: %dч / %dч" % [elapsed, duration]

	_update_squad_list()

func _update_squad_list() -> void:
	for child in squad_list.get_children():
		child.queue_free()

	for hero in _raid.squad:
		var hero_id = hero.id
		if not hero_id in _raid.character_states:
			continue

		var state = _raid.character_states[hero_id]
		var hp = state["hp"]
		var max_hp = state["max_hp"]

		var row = HBoxContainer.new()
		var name_label = Label.new()
		name_label.text = "%s HP: %d/%d" % [hero.display_name, hp, max_hp]
		row.add_child(name_label)
		squad_list.add_child(row)

func _add_event_to_list(event: Dictionary) -> void:
	var event_type = event.get("type", "")
	var hour = event.get("hour", 0)

	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var hour_label = Label.new()
	hour_label.text = "[%dч] %s" % [hour, event.get("name", "Событие")]
	vbox.add_child(hour_label)

	var desc_label = Label.new()
	desc_label.text = event.get("description", "")
	vbox.add_child(desc_label)

	events_list.add_child(panel)

func _show_no_raid() -> void:
	time_label.text = "Нет активной вылазки"
	speed_up_btn.disabled = true
	recall_btn.disabled = true

func _on_raid_complete() -> void:
	_update_timer.stop()

	var status = _raid.status
	if status == RaidExpedition.RaidStatus.COMPLETED:
		var rewards = GameState.complete_raid()
		_show_rewards(rewards)
	elif status == RaidExpedition.RaidStatus.FAILED:
		GameState.cancel_raid()
		_show_failure()

func _show_rewards(rewards: Dictionary) -> void:
	var lootboxes = rewards.get("lootboxes", 0)
	var gold = rewards.get("gold", 0)

	time_label.text = "Вылазка завершена!"

	var reward_panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	reward_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Награды получены:"
	vbox.add_child(title)

	var reward_text = Label.new()
	reward_text.text = "%d лутбоксов, %d золота" % [lootboxes, gold]
	vbox.add_child(reward_text)

	squad_list.add_child(reward_panel)
	speed_up_btn.disabled = true
	recall_btn.disabled = true

func _show_failure() -> void:
	time_label.text = "Вылазка провалилась!"

	var failure_panel = PanelContainer.new()
	var msg = Label.new()
	msg.text = "Отряд погиб в вылазке."
	failure_panel.add_child(msg)

	squad_list.add_child(failure_panel)
	speed_up_btn.disabled = true
	recall_btn.disabled = true

func _on_speed_up() -> void:
	if _raid != null:
		var new_events = _raid.tick(5)
		for event in new_events:
			_add_event_to_list(event)
		_update_ui()

		if _raid.is_complete():
			_on_raid_complete()

func _on_recall() -> void:
	GameState.cancel_raid()
	_update_timer.stop()
	_show_no_raid()

func _on_back() -> void:
	print("RaidProgress: Back pressed")
	if _update_timer != null:
		_update_timer.stop()

	get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)

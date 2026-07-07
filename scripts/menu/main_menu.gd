extends Control

## Стартовый экран — новая игра или загрузить сохранение

const HUB_SCENE = "res://scenes/hub/hub.tscn"

@onready var new_game_btn: Button = $Center/NewGameBtn
@onready var load_btn: Button = $Center/LoadBtn
@onready var slot_panel: PanelContainer = $SlotPanel
@onready var slot_title: Label = $SlotPanel/Margin/VBox/SlotTitle
@onready var slot1_btn: Button = $SlotPanel/Margin/VBox/Slot1
@onready var slot2_btn: Button = $SlotPanel/Margin/VBox/Slot2
@onready var slot3_btn: Button = $SlotPanel/Margin/VBox/Slot3
@onready var cancel_btn: Button = $SlotPanel/Margin/VBox/CancelBtn

func _ready() -> void:
	_set_qa_ids()
	new_game_btn.pressed.connect(_on_new_game)
	load_btn.pressed.connect(_on_load)
	slot1_btn.pressed.connect(_on_slot_picked.bind(1))
	slot2_btn.pressed.connect(_on_slot_picked.bind(2))
	slot3_btn.pressed.connect(_on_slot_picked.bind(3))
	cancel_btn.pressed.connect(_on_cancel_slots)

func _set_qa_ids() -> void:
	new_game_btn.set_meta("qa_id", "menu.new_game")
	load_btn.set_meta("qa_id", "menu.load")
	slot1_btn.set_meta("qa_id", "menu.slot.1")
	slot2_btn.set_meta("qa_id", "menu.slot.2")
	slot3_btn.set_meta("qa_id", "menu.slot.3")
	cancel_btn.set_meta("qa_id", "menu.cancel_slots")

func _on_new_game() -> void:
	SaveManager.start_new_game()
	get_tree().change_scene_to_file(HUB_SCENE)

func _on_load() -> void:
	_show_slot_panel("Выберите сохранение")

func _show_slot_panel(title: String) -> void:
	slot_title.text = title
	_update_slot_buttons()
	slot_panel.visible = true

func _update_slot_buttons() -> void:
	var saves = SaveManager.list_saves()
	for i in range(3):
		var info = saves[i]
		var btn = [slot1_btn, slot2_btn, slot3_btn][i]
		if info.get("exists", false):
			var chars = info.get("character_count", 0)
			var date = info.get("date", "")
			if date.length() > 16:
				date = date.substr(0, 16)
			btn.text = "Слот %d: %d героев, %s" % [i + 1, chars, date]
			btn.disabled = false
		else:
			btn.text = "Слот %d: пусто" % (i + 1)
			btn.disabled = true

func _on_slot_picked(slot: int) -> void:
	if SaveManager.load_game(slot):
		get_tree().change_scene_to_file(HUB_SCENE)

func _on_cancel_slots() -> void:
	slot_panel.visible = false

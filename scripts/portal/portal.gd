extends Control

## Портал — призыв героев через лутбокс

@onready var back_btn: Button = $TopBar/BackBtn
@onready var open_btn: Button = $Center/OpenBtn
@onready var result_label: RichTextLabel = $Center/Result
@onready var roster_label: Label = $Center/RosterLabel
@onready var lootboxes_label: Label = $Center/LootboxesLabel

const HUB_SCENE = "res://scenes/hub/hub.tscn"

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	open_btn.pressed.connect(_on_open_lootbox)
	_update_labels()

func _update_labels() -> void:
	roster_label.text = "В ростре: %d персонажей" % GameState.roster.get_character_count()
	lootboxes_label.text = "Лутбоксов: %d" % GameState.lootboxes_remaining
	open_btn.disabled = GameState.lootboxes_remaining <= 0
	if GameState.lootboxes_remaining <= 0:
		result_label.text = "Лутбоксы закончились. Герои в Особняке."

func _on_back() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)

func _on_open_lootbox() -> void:
	if GameState.lootboxes_remaining <= 0:
		return
	GameState.lootboxes_remaining -= 1
	var char_data = GameState.lootbox.open()
	GameState.roster.add_character(char_data)
	
	result_label.text = "[b]%s[/b] — %s\nХарактер: %s\n%s" % [
		char_data.display_name,
		char_data.character_class_display_name if char_data.character_class_display_name else char_data.character_class,
		char_data.personality_trait,
		char_data.get_backstory_text()
	]
	
	_update_labels()

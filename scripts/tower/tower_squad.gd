extends Control

## Башня — выбор отряда 1–5 героев.
## Поддерживает как Возвышение (выбор этажа), так и обычные бои.

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"

var _is_elevation: bool = false  ## Это Возвышение?
var _target_floor: int = 1  ## Целевой этаж для Возвышения

@onready var back_btn: Button = $TopBar/BackBtn
@onready var list_container: VBoxContainer = $Main/Scroll/List
@onready var start_btn: Button = $Main/StartBtn
@onready var hint_label: Label = $Main/Hint

var _checks: Dictionary = {} ## char_id -> CheckBox
var _ordered_ids: Array[String] = []


func _ready() -> void:
	_set_qa_ids()
	back_btn.pressed.connect(_on_back)
	start_btn.pressed.connect(_on_start)

	# Проверяем, это Возвышение или обычный бой
	_is_elevation = GameState.pending_tower_floor > 0
	_target_floor = GameState.pending_tower_floor if _is_elevation else 1

	# Обновляем UI в зависимости от режима
	if _is_elevation:
		var floor_data = GameState.tower_elevation.get_floor_data(_target_floor)
		var floor_name = floor_data.get("name", "Этаж %d" % _target_floor)
		hint_label.text = "Отметь от 1 до 5 героев для %s." % floor_name

	_rebuild_list()

func _set_qa_ids() -> void:
	back_btn.set_meta("qa_id", "tower_squad.back")
	start_btn.set_meta("qa_id", "tower_squad.start")


func _rebuild_list() -> void:
	_checks.clear()
	_ordered_ids.clear()
	for ch in list_container.get_children():
		ch.queue_free()

	var chars := GameState.roster.get_characters()
	if chars.is_empty():
		hint_label.text = "Нет героев в ростере. Зайди в Портал и открой лутбоксы."
		start_btn.disabled = true
		return

	start_btn.disabled = false
	for c in chars:
		_ordered_ids.append(c.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var cb := CheckBox.new()
		cb.text = "%s  ·  %s  ·  HP %d  ·  ИНТ %d" % [
			c.display_name,
			c.character_class_display_name if c.character_class_display_name else c.character_class,
			c.get_max_hp(),
			c.get_initiative()
		]
		cb.set_meta("qa_id", "tower_squad.hero.%s" % c.id)
		cb.toggled.connect(_on_row_toggled.bind(c.id, cb))
		_checks[c.id] = cb
		row.add_child(cb)
		list_container.add_child(row)

	hint_label.text = "Отметь от 1 до 5 героев и нажми «В бой»."


func _selected_count() -> int:
	var n := 0
	for id in _checks:
		if _checks[id].button_pressed:
			n += 1
	return n


func _on_row_toggled(pressed: bool, char_id: String, cb: CheckBox) -> void:
	if pressed and _selected_count() > 5:
		cb.set_pressed_no_signal(false)
		hint_label.text = "Максимум 5 героев в отряде."


func _on_start() -> void:
	var squad: Array[CharacterData] = []
	for id in _ordered_ids:
		var cb: CheckBox = _checks.get(id, null)
		if cb != null and cb.button_pressed:
			var c := GameState.roster.get_by_id(id)
			if c != null:
				squad.append(c)

	if squad.is_empty():
		hint_label.text = "Выбери хотя бы одного героя."
		return

	if _is_elevation:
		# Регистрируем попытку прохождения этажа
		GameState.tower_elevation.register_attempt(_target_floor)
		GameState.is_tower_elevation = true
		GameState.begin_tower_combat(squad, _target_floor)
	else:
		GameState.is_tower_elevation = false
		GameState.begin_combat(squad, "tower_floor_1")

	get_tree().change_scene_to_file(COMBAT_SCENE)


func _on_back() -> void:
	# Очищаем временные данные
	GameState.pending_tower_floor = 0

	# Возвращаемся в соответствующее меню
	if _is_elevation:
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)

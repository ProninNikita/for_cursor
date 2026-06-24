extends Control

## Возвышение - выбор этажа для прохождения

const TOWER_LOBBY_SCENE = "res://scenes/tower/tower_lobby.tscn"
const TOWER_SQUAD_SCENE = "res://scenes/tower/tower_squad.tscn"
const COMBAT_SCENE = "res://scenes/combat/combat.tscn"

@onready var back_btn: Button = $TopBar/BackBtn
@onready var floors_container: ScrollContainer = $Main/FloorsContainer
@onready var floors_list: VBoxContainer = $Main/FloorsContainer/List
@onready var current_floor_label: Label = $Main/CurrentFloor
@onready var hint_label: Label = $Main/Hint

var _selected_floor: int = 1
var _floor_buttons: Dictionary = {}  ## floor_num -> Button

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	_build_floor_list()
	_update_info()

func _build_floor_list() -> void:
	# Очищаем список
	for child in floors_list.get_children():
		child.queue_free()

	_floor_buttons.clear()

	var max_floor = GameState.tower_elevation.max_floor
	var current_floor = GameState.tower_elevation.current_floor

	# Показываем этажи от 1 до max_floor + 1
	for i in range(1, mini(11, max_floor + 2)):  # Максимум 10 этажей для начала
		var floor_data = GameState.tower_elevation.get_floor_data(i)

		if floor_data.is_empty():
			break

		var floor_panel = _create_floor_panel(i, floor_data)
		floors_list.add_child(floor_panel)

func _create_floor_panel(floor_num: int, floor_data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 80)

	var vbox = VBoxContainer.new()
	vbox.layout_mode = 2
	panel.add_child(vbox)

	# Верхняя строка: номер и название
	var hbox = HBoxContainer.new()
	hbox.layout_mode = 2
	vbox.add_child(hbox)

	var num_label = Label.new()
	num_label.text = "[%d]" % floor_num
	num_label.custom_minimum_size = Vector2(60, 0)
	num_label.layout_mode = 2
	num_label.add_theme_font_size_override("font_size", 18)
	num_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1))
	hbox.add_child(num_label)

	var name_label = Label.new()
	name_label.text = floor_data.get("name", "Этаж %d" % floor_num)
	name_label.layout_mode = 2
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hbox.add_child(name_label)

	var stats = GameState.tower_elevation.get_floor_stats(floor_num)
	var attempts = stats["attempts"]
	var victories = stats["victories"]

	# Звёзды побед
	var stars = ""
	for j in range(3):
		if j < victories:
			stars += "★"
		else:
			stars += "☆"

	var status_label = Label.new()
	status_label.text = stars
	status_label.custom_minimum_size = Vector2(80, 0)
	status_label.layout_mode = 2
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	hbox.add_child(status_label)

	# Описание
	var desc_label = Label.new()
	desc_label.text = floor_data.get("description", "")
	desc_label.layout_mode = 2
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62, 1))
	vbox.add_child(desc_label)

	# Проверка доступности
	var can_attempt = GameState.tower_elevation.can_attempt_floor(floor_num)
	var is_current = (floor_num == GameState.tower_elevation.current_floor)

	# Кнопка выбора
	var btn = Button.new()
	btn.text = "Выбрать" if can_attempt else "Закрыто"
	btn.disabled = not can_attempt
	btn.custom_minimum_size = Vector2(0, 30)
	btn.layout_mode = 2
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_floor_selected.bind(floor_num))
	vbox.add_child(btn)

	_floor_buttons[floor_num] = btn

	# Подсветка текущего этажа
	if is_current:
		var style = panel.get("theme_override_styles/panel")
		if style == null:
			style = StyleBoxFlat.new()
			style.bg_color = Color(0.3, 0.25, 0.2, 0.8)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.border_color = Color(0.8, 0.6, 0.3, 1)
			panel.add_theme_stylebox_override("panel", style)

	return panel

func _update_info() -> void:
	var current = GameState.tower_elevation.current_floor
	var max_f = GameState.tower_elevation.max_floor
	current_floor_label.text = "Текущий этаж: %d / Максимальный достигнутый: %d" % [current, max_f]

func _on_floor_selected(floor_num: int) -> void:
	_selected_floor = floor_num
	hint_label.text = "Выбран этаж %d. Перейди к выбору отряда." % floor_num

	# Переходим к выбору отряда
	GameState.pending_tower_floor = floor_num
	get_tree().change_scene_to_file(TOWER_SQUAD_SCENE)

func _on_back() -> void:
	get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)

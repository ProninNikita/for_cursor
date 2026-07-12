extends Control

## Башня — выбор отряда 1–5 героев.
## Поддерживает как Возвышение (выбор этажа), так и обычные бои.

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"
const ENEMY_ARCHETYPES_PATH := "res://data/rt_enemies.json"
const CombatContextScript = preload("res://scripts/combat_rt/rt_combat_context.gd")

var _is_elevation: bool = false  ## Это Возвышение?
var _target_floor: int = 1  ## Целевой этаж для Возвышения

@onready var back_btn: Button = $TopBar/BackBtn
@onready var list_container: VBoxContainer = $Main/Scroll/List
@onready var start_btn: Button = $Main/StartBtn
@onready var hint_label: Label = $Main/Hint

var _checks: Dictionary = {} ## char_id -> CheckBox
var _ordered_ids: Array[String] = []
var _enemy_archetypes: Dictionary = {}


func _ready() -> void:
	_set_qa_ids()
	back_btn.pressed.connect(_on_back)
	start_btn.pressed.connect(_on_start)

	# Проверяем, это Возвышение или обычный бой
	_is_elevation = GameState.is_tower_elevation and GameState.pending_tower_floor > 0
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
	if _is_elevation:
		_add_elevation_preview()
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

func _add_elevation_preview() -> void:
	_enemy_archetypes = _load_enemy_archetypes()
	var floor_data := GameState.tower_elevation.get_floor_data(_target_floor)
	var context = CombatContextScript.new()
	context.combat_type = CombatContextScript.CombatType.TOWER
	context.tower_floor = _target_floor
	context.floor_data = floor_data.duplicate(true)
	context.floor_name = str(floor_data.get("name", "Этаж %d" % _target_floor))
	context.arena_id = str(floor_data.get("arena_id", "training_ruins"))
	context.enemy_plan = CombatContextScript._duplicate_entries(floor_data.get("enemies", []))
	context.reward_data = floor_data.get("reward", {}).duplicate(true)
	context._setup_tower_rules()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 118)
	panel.set_meta("qa_id", "tower_squad.threat_preview")
	list_container.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s\n%s\nВраги: %s\nПрогноз: %s\nНаграда: %s" % [
		context.floor_name,
		context.threat_text(),
		_format_enemy_plan(context.enemy_plan),
		_squad_danger_forecast(context),
		_format_rewards(context.reward_data)
	]
	margin.add_child(label)

func _format_enemy_plan(enemy_plan: Array) -> String:
	var parts: PackedStringArray = []
	for entry in enemy_plan:
		if not (entry is Dictionary):
			continue
		var enemy_type := str(entry.get("type", "enemy"))
		parts.append("%s x%d" % [_enemy_display_name(enemy_type), int(entry.get("count", 1))])
	if parts.is_empty():
		return "нет данных"
	return ", ".join(parts)

func _enemy_display_name(enemy_type: String) -> String:
	var archetype: Dictionary = _enemy_archetypes.get(enemy_type, {})
	return str(archetype.get("name", enemy_type))

func _squad_danger_forecast(context) -> String:
	var enemy_danger: float = _enemy_plan_danger(context.enemy_plan) * context.modifier_float("enemy_scale", 1.0)
	var squad_power: float = _available_squad_power()
	if squad_power <= 0.0:
		return "нет данных по отряду"
	var ratio: float = enemy_danger / squad_power
	if ratio < 0.42:
		return "низкая угроза"
	if ratio < 0.68:
		return "осторожно, возможны ранения"
	if ratio < 0.94:
		return "опасно, нужен сильный состав"
	return "смертельно опасно"

func _enemy_plan_danger(enemy_plan: Array) -> float:
	var total := 0.0
	for entry in enemy_plan:
		if not (entry is Dictionary):
			continue
		var enemy_type := str(entry.get("type", "enemy"))
		var archetype: Dictionary = _enemy_archetypes.get(enemy_type, {})
		total += float(archetype.get("danger", 1.0)) * float(int(entry.get("count", 1)))
	return total

func _available_squad_power() -> float:
	var power := 0.0
	var count := 0
	for hero in GameState.roster.get_characters():
		if count >= 5:
			break
		power += (
			float(hero.get_max_hp()) / 18.0
			+ float(hero.stats.get("atk", 0)) / 3.2
			+ float(hero.stats.get("def", 0)) / 4.0
			+ float(hero.stats.get("magic", 0)) / 3.2
			+ float(hero.get_initiative()) / 5.0
		)
		count += 1
	return power

func _load_enemy_archetypes() -> Dictionary:
	var file := FileAccess.open(ENEMY_ARCHETYPES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	return data.get("enemies", {})

func _format_rewards(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	var lootboxes := int(rewards.get("lootboxes", 0))
	if lootboxes > 0:
		parts.append("%d лутбоксов" % lootboxes)
	var gold := int(rewards.get("gold", 0))
	if gold > 0:
		parts.append("%d золота" % gold)
	if bool(rewards.get("unique_item", false)):
		parts.append("уникальный предмет")
	if parts.is_empty():
		return "без награды"
	return ", ".join(parts)


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
	GameState.is_tower_elevation = false

	# Возвращаемся в соответствующее меню
	if _is_elevation:
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)

extends Control

## Вылазка - создание экспедиции

const TOWER_LOBBY_SCENE = "res://scenes/tower/tower_lobby.tscn"

@onready var back_btn: Button = $TopBar/BackBtn
@onready var start_btn: Button = $Main/RightPanel/StartBtn
@onready var hint_label: Label = $Main/RightPanel/Hint

# Опции вылазки
@onready var duration_2h: CheckBox = get_node("Main/LeftPanel/Options/Duration/2H")
@onready var duration_6h: CheckBox = get_node("Main/LeftPanel/Options/Duration/6H")
@onready var duration_12h: CheckBox = get_node("Main/LeftPanel/Options/Duration/12H")
@onready var duration_24h: CheckBox = get_node("Main/LeftPanel/Options/Duration/24H")

@onready var diff_easy: CheckBox = $Main/LeftPanel/Options/Difficulty/Easy
@onready var diff_normal: CheckBox = $Main/LeftPanel/Options/Difficulty/Normal
@onready var diff_hard: CheckBox = $Main/LeftPanel/Options/Difficulty/Hard

@onready var type_hunt: CheckBox = $Main/LeftPanel/Options/Type/Hunt
@onready var type_scout: CheckBox = $Main/LeftPanel/Options/Type/Scout
@onready var type_caravan: CheckBox = $Main/LeftPanel/Options/Type/Caravan

@onready var squad_list: VBoxContainer = $Main/RightPanel/SquadContainer/List
@onready var rewards_label: Label = $Main/LeftPanel/RewardsPanel/Info

var _checks: Dictionary = {}  ## char_id -> CheckBox
var _ordered_ids: Array[String] = []

var _selected_duration: int = 6  ## часы
var _selected_difficulty: RaidExpedition.RaidDifficulty = RaidExpedition.RaidDifficulty.NORMAL
var _selected_type: RaidExpedition.RaidType = RaidExpedition.RaidType.HUNT

func _ready() -> void:
	_set_qa_ids()
	back_btn.pressed.connect(_on_back)
	start_btn.pressed.connect(_on_start)

	# Подключаем опции
	duration_2h.pressed.connect(_on_duration_changed.bind(2))
	duration_6h.pressed.connect(_on_duration_changed.bind(6))
	duration_12h.pressed.connect(_on_duration_changed.bind(12))
	duration_24h.pressed.connect(_on_duration_changed.bind(24))

	diff_easy.pressed.connect(_on_diff_changed.bind(RaidExpedition.RaidDifficulty.EASY))
	diff_normal.pressed.connect(_on_diff_changed.bind(RaidExpedition.RaidDifficulty.NORMAL))
	diff_hard.pressed.connect(_on_diff_changed.bind(RaidExpedition.RaidDifficulty.HARD))

	type_hunt.pressed.connect(_on_type_changed.bind(RaidExpedition.RaidType.HUNT))
	type_scout.pressed.connect(_on_type_changed.bind(RaidExpedition.RaidType.SCOUT))
	type_caravan.pressed.connect(_on_type_changed.bind(RaidExpedition.RaidType.CARAVAN))

	# Устанавливаем значения по умолчанию
	duration_6h.button_pressed = true
	diff_normal.button_pressed = true
	type_hunt.button_pressed = true

	_rebuild_squad_list()
	_update_rewards()

func _set_qa_ids() -> void:
	back_btn.set_meta("qa_id", "raid_lobby.back")
	start_btn.set_meta("qa_id", "raid_lobby.start")
	duration_2h.set_meta("qa_id", "raid_lobby.duration.2")
	duration_6h.set_meta("qa_id", "raid_lobby.duration.6")
	duration_12h.set_meta("qa_id", "raid_lobby.duration.12")
	duration_24h.set_meta("qa_id", "raid_lobby.duration.24")
	diff_easy.set_meta("qa_id", "raid_lobby.difficulty.easy")
	diff_normal.set_meta("qa_id", "raid_lobby.difficulty.normal")
	diff_hard.set_meta("qa_id", "raid_lobby.difficulty.hard")
	type_hunt.set_meta("qa_id", "raid_lobby.type.hunt")
	type_scout.set_meta("qa_id", "raid_lobby.type.scout")
	type_caravan.set_meta("qa_id", "raid_lobby.type.caravan")

func _rebuild_squad_list() -> void:
	_checks.clear()
	_ordered_ids.clear()
	for ch in squad_list.get_children():
		ch.queue_free()

	var chars := GameState.roster.get_characters()
	if chars.is_empty():
		hint_label.text = "Нет героев в ростере."
		start_btn.disabled = true
		return

	start_btn.disabled = false
	for c in chars:
		_ordered_ids.append(c.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var cb := CheckBox.new()
		var current_hp = c.get_current_hp()
		var hp_percent = float(current_hp) / float(c.get_max_hp()) * 100.0
		cb.text = "%s  ·  HP %d/%d (%.0f%%)" % [c.display_name, current_hp, c.get_max_hp(), hp_percent]
		cb.set_meta("qa_id", "raid_lobby.hero.%s" % c.id)
		cb.toggled.connect(_on_row_toggled.bind(c.id, cb))
		_checks[c.id] = cb
		row.add_child(cb)
		squad_list.add_child(row)

	hint_label.text = "Выбери отряд (1-3 героя) и отправь в вылазку."

func _on_row_toggled(pressed: bool, char_id: String, cb: CheckBox) -> void:
	var count = _selected_count()
	if count > 3:
		cb.set_pressed_no_signal(false)
		hint_label.text = "Максимум 3 героя в вылазке."
	else:
		hint_label.text = "Выбрано героев: %d/3" % count

func _selected_count() -> int:
	var n := 0
	for id in _checks:
		if _checks[id].button_pressed:
			n += 1
	return n

func _on_duration_changed(hours: int) -> void:
	_selected_duration = hours
	# Сбрасываем все чекбоксы
	duration_2h.button_pressed = (hours == 2)
	duration_6h.button_pressed = (hours == 6)
	duration_12h.button_pressed = (hours == 12)
	duration_24h.button_pressed = (hours == 24)
	_update_rewards()

func _on_diff_changed(diff: RaidExpedition.RaidDifficulty) -> void:
	_selected_difficulty = diff
	# Сбрасываем все чекбоксы
	diff_easy.button_pressed = (diff == RaidExpedition.RaidDifficulty.EASY)
	diff_normal.button_pressed = (diff == RaidExpedition.RaidDifficulty.NORMAL)
	diff_hard.button_pressed = (diff == RaidExpedition.RaidDifficulty.HARD)
	_update_rewards()

func _on_type_changed(type: RaidExpedition.RaidType) -> void:
	_selected_type = type
	# Сбрасываем все чекбоксы
	type_hunt.button_pressed = (type == RaidExpedition.RaidType.HUNT)
	type_scout.button_pressed = (type == RaidExpedition.RaidType.SCOUT)
	type_caravan.button_pressed = (type == RaidExpedition.RaidType.CARAVAN)
	_update_rewards()

func _update_rewards() -> void:
	# Ожидаемые награды
	var base_lootboxes = 1
	var base_gold = 25

	match _selected_duration:
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
	var diff_mult = 1.0
	match _selected_difficulty:
		RaidExpedition.RaidDifficulty.EASY:
			diff_mult = 0.8
		RaidExpedition.RaidDifficulty.NORMAL:
			diff_mult = 1.0
		RaidExpedition.RaidDifficulty.HARD:
			diff_mult = 1.5

	# Множитель типа
	var type_mult = 1.0
	match _selected_type:
		RaidExpedition.RaidType.HUNT:
			type_mult = 1.2
		RaidExpedition.RaidType.SCOUT:
			type_mult = 0.8
		RaidExpedition.RaidType.CARAVAN:
			type_mult = 1.0

	var lootboxes = int(base_lootboxes * diff_mult * type_mult)
	var gold = int(base_gold * diff_mult * type_mult)

	rewards_label.text = "Ожидаемые награды:\n• %d лутбоксов\n• %d золота\n\n⚠️ ВНИМАНИЕ: Смерть в вылазке = постоянная смерть!" % [lootboxes, gold]

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

	if squad.size() > 3:
		hint_label.text = "Максимум 3 героя в вылазке."
		return

	# Создаём вылазку
	GameState.begin_raid(squad, _selected_duration, int(_selected_type), int(_selected_difficulty))
	get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)

func _on_back() -> void:
	get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)

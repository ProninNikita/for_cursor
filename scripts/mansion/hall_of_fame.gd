extends Control

const MANSION_SCENE = "res://scenes/mansion/mansion.tscn"

@onready var back_btn: Button = $TopBar/BackBtn
@onready var list: VBoxContainer = $Scroll/List

func _ready() -> void:
	back_btn.set_meta("qa_id", "hall.back")
	back_btn.pressed.connect(_on_back)
	_refresh_list()

func _refresh_list() -> void:
	for child in list.get_children():
		child.queue_free()

	var fallen: Array[Dictionary] = GameState.get_fallen_heroes()
	if fallen.is_empty():
		var empty := Label.new()
		empty.text = "Павших героев пока нет."
		empty.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
		list.add_child(empty)
		return

	for i in range(fallen.size() - 1, -1, -1):
		list.add_child(_fallen_panel(fallen[i]))

func _fallen_panel(record: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.2, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.48, 0.38, 0.34, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var name_label := Label.new()
	name_label.text = "%s — %s" % [
		str(record.get("name", "Неизвестный герой")),
		str(record.get("class_display", record.get("class", "")))
	]
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.78))
	box.add_child(name_label)

	var battle: Dictionary = record.get("battle", {})
	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text = "%s. Причина: %s%s. Бой: %s%s, %s." % [
		_format_stats(record.get("stats", {})),
		str(record.get("cause", "неизвестно")),
		", " + str(record.get("killer", "")) if str(record.get("killer", "")) != "" else "",
		_format_battle_place(battle),
		", seed " + str(battle.get("seed", "")) if str(battle.get("seed", "")) != "" else "",
		_format_duration(float(battle.get("duration_seconds", 0.0)))
	]
	detail.add_theme_color_override("font_color", Color(0.74, 0.74, 0.74))
	detail.add_theme_font_size_override("font_size", 12)
	box.add_child(detail)
	return panel

func _format_stats(raw_stats) -> String:
	if not (raw_stats is Dictionary):
		return "Статы: нет данных"
	var stats: Dictionary = raw_stats
	return "HP %d, ATK %d, DEF %d, INT %d" % [
		int(stats.get("hp", 0)),
		int(stats.get("atk", 0)),
		int(stats.get("def", 0)),
		int(stats.get("initiative", stats.get("speed", 0)))
	]

func _format_battle_place(battle: Dictionary) -> String:
	var combat_type := str(battle.get("combat_type", "training"))
	if combat_type == "tower":
		return "Возвышение %d" % int(battle.get("floor", 0))
	if combat_type == "raid":
		return "вылазка"
	return "тренировка"

func _format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(round(seconds)))
	var minutes := floori(float(total_seconds) / 60.0)
	var seconds_part := total_seconds % 60
	return "%d:%s" % [minutes, str(seconds_part).pad_zeros(2)]

func _on_back() -> void:
	get_tree().change_scene_to_file(MANSION_SCENE)

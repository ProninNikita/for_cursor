extends Control

## Особняк — список героев из ростра

const HUB_SCENE = "res://scenes/hub/hub.tscn"

@onready var back_btn: Button = $TopBar/BackBtn
@onready var characters_list: VBoxContainer = $Scroll/CharactersList

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	_refresh_list()

func _refresh_list() -> void:
	for child in characters_list.get_children():
		child.queue_free()
	
	var chars = GameState.roster.get_characters()
	if chars.is_empty():
		var empty_label = Label.new()
		empty_label.text = "Пока никого нет. Откройте лутбоксы в Портале!"
		empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		characters_list.add_child(empty_label)
	else:
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.2, 0.24, 0.3, 0.9)
		panel_style.set_border_width_all(1)
		panel_style.border_color = Color(0.35, 0.42, 0.52, 1)
		panel_style.set_corner_radius_all(8)
		for c in chars:
			var panel = PanelContainer.new()
			panel.add_theme_stylebox_override("panel", panel_style)
			var margin = MarginContainer.new()
			margin.add_theme_constant_override("margin_left", 12)
			margin.add_theme_constant_override("margin_top", 8)
			margin.add_theme_constant_override("margin_right", 12)
			margin.add_theme_constant_override("margin_bottom", 8)
			var vbox = VBoxContainer.new()
			var name_label = Label.new()
			name_label.text = "%s — %s" % [c.display_name, c.character_class_display_name if c.character_class_display_name else c.character_class]
			name_label.add_theme_font_size_override("font_size", 16)
			var desc_label = Label.new()
			desc_label.text = c.get_backstory_text()
			desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			desc_label.add_theme_font_size_override("font_size", 12)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_label.custom_minimum_size.x = 600
			vbox.add_child(name_label)
			vbox.add_child(desc_label)
			margin.add_child(vbox)
			panel.add_child(margin)
			characters_list.add_child(panel)

func _on_back() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)

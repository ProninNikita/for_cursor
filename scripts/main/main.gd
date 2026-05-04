extends Control

## Главная сцена — тестовый экран с кнопкой "Открыть лутбокс"

var roster: Roster
var lootbox: Lootbox

var vbox: VBoxContainer
var open_button: Button
var result_label: RichTextLabel
var roster_label: Label

func _ready() -> void:
	roster = Roster.new()
	lootbox = Lootbox.new()
	_setup_ui()

func _setup_ui() -> void:
	# Фон
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	
	# Контейнер
	vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -200
	vbox.offset_top = -150
	vbox.offset_right = 200
	vbox.offset_bottom = 150
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)
	
	# Заголовок
	var title = Label.new()
	title.text = "Squad Tactics"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Кнопка открыть лутбокс
	open_button = Button.new()
	open_button.text = "Открыть лутбокс"
	open_button.pressed.connect(_on_open_lootbox)
	vbox.add_child(open_button)
	
	# Результат
	result_label = RichTextLabel.new()
	result_label.custom_minimum_size = Vector2(380, 120)
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	result_label.scroll_active = false
	result_label.text = "Нажми кнопку, чтобы получить нового персонажа!"
	vbox.add_child(result_label)
	
	# Счётчик ростра
	roster_label = Label.new()
	roster_label.text = "В ростре: 0 персонажей"
	vbox.add_child(roster_label)

func _on_open_lootbox() -> void:
	var char_data = lootbox.open()
	roster.add_character(char_data)
	
	result_label.text = "[b]%s[/b] — %s\nХарактер: %s\n%s" % [
		char_data.display_name,
		char_data.character_class_display_name if char_data.character_class_display_name else char_data.character_class,
		char_data.personality_trait,
		char_data.get_backstory_text()
	]
	
	roster_label.text = "В ростре: %d персонажей" % roster.get_character_count()

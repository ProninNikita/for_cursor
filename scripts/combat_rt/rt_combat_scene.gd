extends Control

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_SQUAD_SCENE := "res://scenes/tower/tower_squad.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const RAID_PROGRESS_SCENE := "res://scenes/tower/raid_progress.tscn"
const BattlefieldScript = preload("res://scripts/combat_rt/rt_battlefield.gd")
const UnitScript = preload("res://scripts/combat_rt/rt_battle_unit.gd")
const PerceptionScript = preload("res://scripts/combat_rt/rt_perception.gd")
const BrainScript = preload("res://scripts/combat_rt/rt_utility_brain.gd")
const ResolverScript = preload("res://scripts/combat_rt/rt_action_resolver.gd")

const MAP_ORIGIN := Vector2(38, 94)
const DECISION_INTERVAL := 0.35
const MAX_LOG_LINES := 14
const SPEED_MODES := [0.5, 1.0, 2.0, 4.0]

var _battlefield = BattlefieldScript.new()
var _perception = PerceptionScript.new()
var _brain = BrainScript.new()
var _resolver = ResolverScript.new()
var _rng := RandomNumberGenerator.new()
var _units: Array = []
var _intents: Dictionary = {}
var _decision_timer: float = 0.0
var _battle_finished := false
var _paused := false
var _time_scale := 0.5
var _speed_index: int = 0
var _log_lines: PackedStringArray = []
var _floating_texts: Array[Dictionary] = []
var _visual_effects: Array[Dictionary] = []
var _focus_unit_id: String = ""
var _is_tower_elevation: bool = false
var _is_raid_combat: bool = false
var _current_tower_floor: int = 0
var _battle_elapsed_seconds: float = 0.0
var _battle_start_hp: Dictionary = {}
var _battle_damage_dealt: Dictionary = {}
var _battle_healing_done: Dictionary = {}

var _return_btn: Button
var _pause_btn: Button
var _speed_btn: Button
var _status_label: Label
var _focus_label: Label
var _unit_list_label: RichTextLabel
var _log_label: RichTextLabel
var _end_panel: PanelContainer
var _end_title: Label
var _end_detail: Label
var _end_btn: Button

func _ready() -> void:
	AbilityRegistry.initialize()
	_rng.randomize()
	_resolver.rng.randomize()
	_create_ui()
	_capture_battle_context()
	_setup_battle()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_update_floating_texts(delta)
	_update_visual_effects(delta)
	if _battle_finished or _paused:
		queue_redraw()
		return

	var scaled_delta := delta * _time_scale
	_battle_elapsed_seconds += scaled_delta
	_decision_timer -= scaled_delta
	if _decision_timer <= 0.0:
		_decision_timer = DECISION_INTERVAL
		_update_perception_and_intents()

	for unit in _units:
		var intent: Dictionary = _intents.get(unit.unit_id, {"type": "hold", "reason": "ждёт", "destination": unit.grid_pos})
		var messages: Array[String] = _resolver.update_unit(unit, scaled_delta, intent, _battlefield, MAP_ORIGIN)
		for message in messages:
			_log_line(message)
		for event in _resolver.consume_events():
			_record_resolver_event(event)

	_check_end()
	_refresh_status()
	queue_redraw()

func _create_ui() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(20, 18)
	top_bar.size = Vector2(1240, 44)
	top_bar.add_theme_constant_override("separation", 10)
	add_child(top_bar)

	_return_btn = Button.new()
	_return_btn.text = "В город"
	_return_btn.set_meta("qa_id", "combat_rt.return")
	_return_btn.pressed.connect(_on_return_pressed)
	top_bar.add_child(_return_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "Пауза"
	_pause_btn.set_meta("qa_id", "combat_rt.pause")
	_pause_btn.pressed.connect(_on_pause_pressed)
	top_bar.add_child(_pause_btn)

	_speed_btn = Button.new()
	_speed_btn.text = _speed_label()
	_speed_btn.set_meta("qa_id", "combat_rt.speed")
	_speed_btn.pressed.connect(_on_speed_pressed)
	top_bar.add_child(_speed_btn)

	var title := Label.new()
	title.text = "Real-time бой: обзор, укрытия, страх, намерения"
	title.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(title)

	_status_label = Label.new()
	_status_label.position = Vector2(850, 78)
	_status_label.size = Vector2(390, 58)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_focus_label = Label.new()
	_focus_label.position = Vector2(850, 136)
	_focus_label.size = Vector2(390, 82)
	_focus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_focus_label.add_theme_font_size_override("font_size", 13)
	add_child(_focus_label)

	_unit_list_label = RichTextLabel.new()
	_unit_list_label.position = Vector2(850, 220)
	_unit_list_label.size = Vector2(390, 174)
	_unit_list_label.bbcode_enabled = false
	_unit_list_label.scroll_active = false
	_unit_list_label.add_theme_font_size_override("normal_font_size", 12)
	add_child(_unit_list_label)

	_log_label = RichTextLabel.new()
	_log_label.position = Vector2(850, 410)
	_log_label.size = Vector2(390, 198)
	_log_label.bbcode_enabled = false
	_log_label.scroll_following = true
	add_child(_log_label)

	_create_end_panel()

func _create_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.name = "EndPanel"
	_end_panel.visible = false
	_end_panel.z_index = 10
	_end_panel.position = Vector2(344, 154)
	_end_panel.size = Vector2(592, 350)
	add_child(_end_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.115, 0.98)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.54, 0.59, 0.68)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 14
	_end_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	_end_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_end_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_end_title)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(0.45, 0.5, 0.6, 0.55)
	box.add_child(divider)

	_end_detail = Label.new()
	_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_end_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_detail.add_theme_font_size_override("font_size", 14)
	_end_detail.add_theme_color_override("font_color", Color(0.88, 0.9, 0.88))
	_end_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_end_detail)

	_end_btn = Button.new()
	_end_btn.text = "Продолжить"
	_end_btn.custom_minimum_size = Vector2(0, 38)
	_end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_btn.set_meta("qa_id", "combat.return")
	_end_btn.pressed.connect(_on_end_return_pressed)
	box.add_child(_end_btn)

func _capture_battle_context() -> void:
	_is_tower_elevation = GameState.is_tower_elevation
	_is_raid_combat = not GameState.pending_raid_event.is_empty()
	_current_tower_floor = GameState.pending_tower_floor

func _setup_battle() -> void:
	_battlefield.setup_test_arena()
	_units.clear()
	_intents.clear()
	_log_lines.clear()
	_battle_elapsed_seconds = 0.0
	_battle_start_hp.clear()
	_battle_damage_dealt.clear()
	_battle_healing_done.clear()

	var squad := _combat_squad_or_demo()
	for i in squad.size():
		var battle_unit := BattleUnit.from_hero(squad[i], _rng)
		var spawn: Vector2i = _battlefield.ally_spawns[i % _battlefield.ally_spawns.size()]
		var unit = UnitScript.new()
		unit.setup_from_battle_unit(battle_unit, "ally_%d" % i, spawn, MAP_ORIGIN, _battlefield)
		_units.append(unit)
		_battle_start_hp[squad[i].id] = battle_unit.current_hp
		_battle_damage_dealt[squad[i].id] = 0
		_battle_healing_done[squad[i].id] = 0

	var enemies := _build_enemy_units()
	for i in enemies.size():
		var enemy_unit: BattleUnit = enemies[i]
		var spawn: Vector2i = _battlefield.enemy_spawns[i % _battlefield.enemy_spawns.size()]
		var unit = UnitScript.new()
		unit.setup_from_battle_unit(enemy_unit, "enemy_%d" % i, spawn, MAP_ORIGIN, _battlefield)
		unit.apply_enemy_profile()
		_units.append(unit)

	_log_line("Симуляция началась: юниты действуют одновременно.")
	_log_line("Конусы обзора, укрытия, вода, засады и страх уже подключены как базовый слой.")
	if not _units.is_empty():
		_focus_unit_id = _units[0].unit_id
	_update_perception_and_intents()
	_refresh_status()

func _combat_squad_or_demo() -> Array[CharacterData]:
	var squad: Array[CharacterData] = []
	if not GameState.pending_combat_squad.is_empty():
		for cd in GameState.pending_combat_squad:
			if squad.size() >= Roster.MAX_SQUAD_SIZE:
				break
			cd.ensure_combat_brain()
			squad.append(cd)
	elif GameState.roster != null and GameState.roster.get_character_count() > 0:
		for cd in GameState.roster.get_characters():
			if squad.size() >= Roster.MAX_SQUAD_SIZE:
				break
			cd.ensure_combat_brain()
			squad.append(cd)

	if squad.is_empty():
		squad.append(_make_demo_hero("rt_warrior", "Ивар", "warrior", "агрессивный"))
		squad.append(_make_demo_hero("rt_healer", "Мира", "healer", "защитник"))
		squad.append(_make_demo_hero("rt_scout", "Рейн", "scout", "осторожный"))
		squad.append(_make_demo_hero("rt_mage", "Селен", "mage", "расчётливый"))
	return squad

func _make_demo_hero(id: String, hero_name: String, class_id: String, personality: String) -> CharacterData:
	var hero := CharacterData.new()
	hero.id = id
	hero.display_name = hero_name
	hero.character_class = class_id
	hero.character_class_display_name = class_id
	hero.personality_trait = personality
	hero.backstory_origin = "sandbox"
	hero.backstory_event = "first contact"
	hero.backstory_motivation = "survive"
	match class_id:
		"warrior":
			hero.stats = {"hp": 52, "atk": 11, "def": 6, "speed": 5, "magic": 0, "initiative": 6}
			hero.ability_ids = ["basic_attack", "heavy_strike", "guard"]
		"healer":
			hero.stats = {"hp": 42, "atk": 4, "def": 5, "speed": 5, "magic": 10, "initiative": 5}
			hero.ability_ids = ["basic_attack", "heal", "blessing"]
		"scout":
			hero.stats = {"hp": 44, "atk": 8, "def": 5, "speed": 9, "magic": 0, "initiative": 8}
			hero.ability_ids = ["basic_attack", "quick_strike", "mark_target"]
		"mage":
			hero.stats = {"hp": 38, "atk": 3, "def": 4, "speed": 6, "magic": 12, "initiative": 6}
			hero.ability_ids = ["basic_attack", "fireball", "barrier"]
	hero.set_current_hp(hero.get_max_hp())
	hero.initialize_combat_brain()
	return hero

func _build_enemy_units() -> Array[BattleUnit]:
	var enemies: Array[BattleUnit] = []
	var enemy_plan: Array = _enemy_plan_for_context()
	var index := 0
	for entry in enemy_plan:
		var enemy_type := str(entry.get("type", "goblin"))
		var count := int(entry.get("count", 1))
		for _i in count:
			enemies.append(_make_enemy_unit(enemy_type, index))
			index += 1
	if enemies.is_empty():
		for i in 3:
			enemies.append(_make_enemy_unit("goblin", i))
	return enemies

func _enemy_plan_for_context() -> Array:
	if _is_raid_combat:
		return GameState.pending_raid_event.get("enemies", [])
	if _is_tower_elevation and GameState.tower_elevation != null:
		var floor_data := GameState.tower_elevation.get_floor_data(_current_tower_floor)
		return floor_data.get("enemies", [])
	return [{"type": "goblin", "count": 3}]

func _make_enemy_unit(enemy_type: String, index: int) -> BattleUnit:
	var unit := BattleUnit.goblin(index, _rng)
	match enemy_type:
		"orc":
			unit.display_name = "Орк %d" % (index + 1)
			unit.max_hp = 28
			unit.current_hp = unit.max_hp
			unit.atk = 6
			unit.def = 3
			unit.initiative = 3
		"troll":
			unit.display_name = "Тролль %d" % (index + 1)
			unit.max_hp = 48
			unit.current_hp = unit.max_hp
			unit.atk = 8
			unit.def = 5
			unit.initiative = 2
		"boss":
			unit.display_name = "Хранитель"
			unit.max_hp = 86
			unit.current_hp = unit.max_hp
			unit.atk = 11
			unit.def = 7
			unit.magic = 4
			unit.initiative = 4
		_:
			unit.display_name = "Гоблин %d" % (index + 1)
	return unit

func _update_perception_and_intents() -> void:
	_perception.update(_units, _battlefield)
	for unit in _units:
		if not unit.is_alive():
			continue
		var previous := str(_intents.get(unit.unit_id, {}).get("type", ""))
		var intent: Dictionary = _brain.choose_intent(unit, _units, _battlefield, _rng)
		_intents[unit.unit_id] = intent
		var current := str(intent.get("type", "hold"))
		if current != previous:
			_log_line("%s: %s (%s)." % [unit.display_name, _intent_label(current), intent.get("reason", "")])
			_add_floating_text(unit.world_position, _intent_float_label(current), _intent_color(current), 1.15, Vector2(0, -22))
			if unit.side == BattleUnit.UnitSide.ALLY:
				_focus_unit_id = unit.unit_id

func _check_end() -> void:
	if _battle_finished:
		return
	var allies_alive := false
	var enemies_alive := false
	for unit in _units:
		if not unit.is_alive():
			continue
		if unit.side == BattleUnit.UnitSide.ALLY:
			allies_alive = true
		else:
			enemies_alive = true
	if allies_alive and enemies_alive:
		return
	_finish_battle(allies_alive)

func _refresh_status() -> void:
	var allies := 0
	var enemies := 0
	var visible_contacts := 0
	for unit in _units:
		if not unit.is_alive():
			continue
		if unit.side == BattleUnit.UnitSide.ALLY:
			allies += 1
		else:
			enemies += 1
		visible_contacts += unit.visible_enemies.size()
	_status_label.text = "Живые: союзники %d / враги %d\nКонтактов в поле зрения: %d\nСкорость: %.1fx%s" % [
		allies,
		enemies,
		visible_contacts,
		_time_scale,
		"  |  Пауза" if _paused else ""
	]
	_refresh_focus_panel()
	_refresh_unit_list()

func _log_line(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)

func _add_floating_text(world_position: Vector2, text: String, color: Color, ttl: float = 1.0, velocity: Vector2 = Vector2(0, -28)) -> void:
	if text == "":
		return
	_floating_texts.append({
		"pos": world_position,
		"text": text,
		"color": color,
		"age": 0.0,
		"ttl": ttl,
		"velocity": velocity
	})

func _update_floating_texts(delta: float) -> void:
	for i in range(_floating_texts.size() - 1, -1, -1):
		var item: Dictionary = _floating_texts[i]
		var age: float = float(item.get("age", 0.0)) + delta
		item["age"] = age
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		var velocity: Vector2 = item.get("velocity", Vector2.ZERO)
		item["pos"] = pos + velocity * delta
		_floating_texts[i] = item
		if age >= float(item.get("ttl", 1.0)):
			_floating_texts.remove_at(i)

func _add_visual_effect(kind: String, from_pos: Vector2, to_pos: Vector2, color: Color, ttl: float = 0.28, radius: float = 18.0) -> void:
	_visual_effects.append({
		"kind": kind,
		"from": from_pos,
		"to": to_pos,
		"color": color,
		"age": 0.0,
		"ttl": ttl,
		"radius": radius
	})

func _update_visual_effects(delta: float) -> void:
	for i in range(_visual_effects.size() - 1, -1, -1):
		var item: Dictionary = _visual_effects[i]
		item["age"] = float(item.get("age", 0.0)) + delta
		_visual_effects[i] = item
		if float(item.get("age", 0.0)) >= float(item.get("ttl", 0.28)):
			_visual_effects.remove_at(i)

func _finish_battle(victory: bool) -> void:
	if _battle_finished:
		return
	_battle_finished = true
	_pause_btn.disabled = true
	_speed_btn.disabled = true
	_sync_roster_hp()
	_update_combat_brains(victory)

	var applied_rewards: Dictionary = {}
	var floor_data: Dictionary = {}
	if victory:
		if _is_tower_elevation:
			floor_data = GameState.tower_elevation.get_floor_data(_current_tower_floor)
			applied_rewards = GameState.apply_rewards(floor_data.get("reward", {}))
			GameState.tower_elevation.register_victory(_current_tower_floor)
			GameState.tower_elevation.advance_to_next_floor()
		elif _is_raid_combat:
			_sync_active_raid_hp()
			GameState.finish_raid_combat(true)
			if GameState.active_raid != null:
				GameState.active_raid.complete_combat_event(true)
		else:
			applied_rewards = GameState.apply_rewards({"lootboxes": 1})
	elif _is_raid_combat:
		_sync_active_raid_hp()
		GameState.finish_raid_combat(false)
		if GameState.active_raid != null:
			GameState.active_raid.complete_combat_event(false)

	_show_end_panel(victory, applied_rewards, floor_data)
	GameState.clear_pending_combat()
	GameState.is_tower_elevation = false
	GameState.pending_tower_floor = 0
	GameState.pending_raid_event.clear()
	_log_line("RT-бой завершён: %s." % ("отряд выжил" if victory else "отряд уничтожен"))

func _show_end_panel(victory: bool, applied_rewards: Dictionary, floor_data: Dictionary) -> void:
	_end_panel.visible = true
	_style_end_panel_result(victory)
	if victory:
		_end_title.text = "Победа!"
		if _is_tower_elevation:
			_end_btn.text = "В башню"
		elif _is_raid_combat:
			_end_btn.text = "К вылазке"
		else:
			_end_btn.text = "В город"
	else:
		_end_title.text = "Поражение"
		_end_btn.text = "В город"
		if _is_raid_combat:
			_end_btn.text = "К вылазке"
	_end_detail.text = _end_result_text(victory, applied_rewards, floor_data)

func _style_end_panel_result(victory: bool) -> void:
	var accent := Color(0.38, 1.0, 0.64) if victory else Color(1.0, 0.34, 0.24)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.115, 0.985)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = accent
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	panel_style.shadow_size = 14
	_end_panel.add_theme_stylebox_override("panel", panel_style)
	_end_title.add_theme_color_override("font_color", accent)

	var button_normal := _end_button_style(accent.darkened(0.35), accent)
	var button_hover := _end_button_style(accent.darkened(0.22), accent.lightened(0.12))
	var button_pressed := _end_button_style(accent.darkened(0.48), accent)
	_end_btn.add_theme_stylebox_override("normal", button_normal)
	_end_btn.add_theme_stylebox_override("hover", button_hover)
	_end_btn.add_theme_stylebox_override("pressed", button_pressed)
	_end_btn.add_theme_color_override("font_color", Color(0.96, 0.98, 0.96))

func _end_button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	return style

func _end_result_text(victory: bool, applied_rewards: Dictionary, floor_data: Dictionary) -> String:
	var sections: PackedStringArray = []
	sections.append(_end_context_text(victory, floor_data))
	sections.append(_end_rewards_text(victory, applied_rewards))
	sections.append(_end_unit_summary_text())
	sections.append(_end_stats_text())
	return "\n\n".join(sections)

func _end_context_text(victory: bool, floor_data: Dictionary) -> String:
	if victory:
		if _is_tower_elevation:
			return "%s пройден. Следующий этаж: %d." % [
				floor_data.get("name", "Этаж %d" % _current_tower_floor),
				_current_tower_floor + 1
			]
		if _is_raid_combat:
			return "Враги разбиты. Отряд продолжает вылазку."
		return "Враги разбиты. Отряд возвращается в город."

	if _is_raid_combat:
		return "Отряд отступил из вылазки. Проверь состояние героев."
	return "Бой проигран. Выжившие герои обновлены в ростере."

func _end_rewards_text(victory: bool, applied_rewards: Dictionary) -> String:
	if not victory:
		return "Награда: нет."
	if _is_raid_combat:
		return "Награда: будет учтена в событии вылазки."
	return "Награда: %s\nВсего: %d лутбоксов, %d золота." % [
		_format_rewards(applied_rewards),
		GameState.lootboxes_remaining,
		GameState.gold
	]

func _end_unit_summary_text() -> String:
	var lines: PackedStringArray = []
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY:
			continue
		if unit.is_alive():
			lines.append("%s: %d/%d HP" % [
				_short_name(unit.display_name),
				unit.battle_unit.current_hp,
				unit.battle_unit.max_hp
			])
		else:
			lines.append("%s: выбыл" % [_short_name(unit.display_name)])
	if lines.is_empty():
		return "Отряд: нет данных."
	return "Отряд:\n%s" % "\n".join(lines)

func _end_stats_text() -> String:
	var allies_alive := _count_units(BattleUnit.UnitSide.ALLY, true)
	var allies_total := _count_units(BattleUnit.UnitSide.ALLY, false)
	var enemies_alive := _count_units(BattleUnit.UnitSide.ENEMY, true)
	var enemies_total := _count_units(BattleUnit.UnitSide.ENEMY, false)
	var enemies_defeated := enemies_total - enemies_alive
	return "Статистика: время %s, союзники %d/%d, враги повержены %d/%d, урон %d, лечение %d." % [
		_format_duration(_battle_elapsed_seconds),
		allies_alive,
		allies_total,
		enemies_defeated,
		enemies_total,
		_sum_dictionary_int(_battle_damage_dealt),
		_sum_dictionary_int(_battle_healing_done)
	]

func _count_units(side: int, alive_only: bool) -> int:
	var count := 0
	for unit in _units:
		if unit.side != side:
			continue
		if alive_only and not unit.is_alive():
			continue
		count += 1
	return count

func _sum_dictionary_int(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total

func _format_duration(seconds: float) -> String:
	var total_seconds := maxi(0, int(round(seconds)))
	var minutes := floori(float(total_seconds) / 60.0)
	var seconds_part := total_seconds % 60
	return "%d:%s" % [minutes, str(seconds_part).pad_zeros(2)]

func _record_resolver_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type not in ["area", "damage", "heal", "buff"]:
		return
	var attacker = event.get("attacker", null)
	var target = event.get("target", null)
	if attacker == null:
		return
	var amount := int(event.get("amount", 0))
	var ability: AbilityData = event.get("ability", null)
	if event_type == "area":
		var center: Vector2 = event.get("center", Vector2.ZERO)
		var radius_pixels := maxf(18.0, float(event.get("radius_tiles", 0.0)) * _battlefield.tile_size())
		var area_color := _ability_event_color(ability, "damage")
		_add_visual_effect("line", attacker.world_position, center, area_color, 0.22, 0.0)
		_add_visual_effect("area", center, center, area_color, 0.48, radius_pixels)
		var target_count := int(event.get("target_count", 0))
		if target_count > 1:
			_add_floating_text(center + Vector2(0, -18), "область x%d" % target_count, area_color, 0.9, Vector2(0, -22))
		return
	if event_type == "damage" and amount > 0 and attacker.character_data != null:
		var char_id: String = attacker.character_data.id
		_battle_damage_dealt[char_id] = int(_battle_damage_dealt.get(char_id, 0)) + amount
	elif event_type == "heal" and amount > 0 and attacker.character_data != null:
		var char_id: String = attacker.character_data.id
		_battle_healing_done[char_id] = int(_battle_healing_done.get(char_id, 0)) + amount
	if target != null and event_type == "damage" and amount > 0:
		_focus_unit_id = attacker.unit_id if attacker.side == BattleUnit.UnitSide.ALLY else target.unit_id
		var hit_color := Color(1.0, 0.34, 0.24) if target.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.86, 0.28)
		var effect_color := _ability_event_color(ability, event_type)
		if ability == null or ability.rt_radius_tiles <= 0.0:
			_add_visual_effect("line", attacker.world_position, target.world_position, effect_color, 0.24, 0.0)
		_add_visual_effect("ring", target.world_position, target.world_position, hit_color, 0.34, 17.0)
		_add_floating_text(target.world_position + Vector2(0, -16), "-%d" % amount, hit_color, 1.0, Vector2(0, -34))
		if not target.is_alive():
			_add_floating_text(target.world_position + Vector2(0, -32), "выведен", Color(0.95, 0.95, 0.95), 1.4, Vector2(0, -24))
	elif target != null and event_type == "heal" and amount > 0:
		_focus_unit_id = target.unit_id
		_add_visual_effect("line", attacker.world_position, target.world_position, _ability_event_color(ability, event_type), 0.28, 0.0)
		_add_visual_effect("ring", target.world_position, target.world_position, Color(0.35, 1.0, 0.55), 0.42, 19.0)
		_add_floating_text(target.world_position + Vector2(0, -16), "+%d" % amount, Color(0.35, 1.0, 0.55), 1.0, Vector2(0, -30))
	elif target != null and event_type == "buff":
		_focus_unit_id = target.unit_id
		var label := ability.name if ability != null else "бафф"
		_add_visual_effect("ring", target.world_position, target.world_position, _ability_event_color(ability, event_type), 0.5, 21.0)
		_add_floating_text(target.world_position + Vector2(0, -18), label, Color(0.45, 0.82, 1.0), 1.05, Vector2(0, -24))

func _sync_roster_hp() -> void:
	if GameState.roster == null:
		return
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		GameState.roster.apply_hp_from_battle(unit.character_data.id, unit.battle_unit.current_hp)

func _sync_active_raid_hp() -> void:
	if GameState.active_raid == null:
		return
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		var char_id: String = unit.character_data.id
		if GameState.active_raid.character_states.has(char_id):
			GameState.active_raid.character_states[char_id]["hp"] = unit.battle_unit.current_hp

func _update_combat_brains(victory: bool) -> void:
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		if not unit.is_alive():
			continue
		var char_id: String = unit.character_data.id
		var start_hp := int(_battle_start_hp.get(char_id, unit.battle_unit.max_hp))
		var damage_taken_ratio := 0.0
		if unit.battle_unit.max_hp > 0:
			damage_taken_ratio = float(maxi(0, start_hp - unit.battle_unit.current_hp)) / float(unit.battle_unit.max_hp)
		unit.character_data.record_combat_result(
			victory,
			unit.hp_ratio(),
			damage_taken_ratio,
			int(_battle_damage_dealt.get(char_id, 0)),
			int(_battle_healing_done.get(char_id, 0))
		)

func _format_rewards(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	var lootboxes := int(rewards.get("lootboxes", 0))
	if lootboxes > 0:
		parts.append("%d лутбоксов" % lootboxes)
	var gold_amount := int(rewards.get("gold", 0))
	if gold_amount > 0:
		parts.append("%d золота" % gold_amount)
	if parts.is_empty():
		return "без награды"
	return ", ".join(parts)

func _draw() -> void:
	_draw_background()
	_draw_map()
	_draw_tactical_overlays()
	_draw_unit_vision()
	_draw_paths()
	_draw_visual_effects()
	_draw_units()
	_draw_floating_texts()
	_draw_legend()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.08))
	draw_rect(Rect2(MAP_ORIGIN - Vector2(10, 10), Vector2(_battlefield.width, _battlefield.height) * _battlefield.tile_size() + Vector2(20, 20)), Color(0.09, 0.1, 0.12))
	draw_rect(Rect2(Vector2(834, 72), Vector2(424, 560)), Color(0.075, 0.082, 0.095))

func _draw_map() -> void:
	for y in _battlefield.height:
		for x in _battlefield.width:
			var pos := Vector2i(x, y)
			var rect := Rect2(MAP_ORIGIN + Vector2(x, y) * _battlefield.tile_size(), Vector2.ONE * _battlefield.tile_size())
			draw_rect(rect, _tile_color(_battlefield.get_tile(pos)))
			draw_rect(rect, Color(0.18, 0.2, 0.22), false, 1.0)

func _draw_tactical_overlays() -> void:
	var enemies := _alive_units_for_side(BattleUnit.UnitSide.ENEMY)
	if enemies.is_empty():
		return

	for y in _battlefield.height:
		for x in _battlefield.width:
			var pos := Vector2i(x, y)
			if not _battlefield.is_walkable(pos):
				continue
			var rect := _tile_rect(pos).grow(-4.0)
			var danger_score := _tile_danger_score(pos, enemies)
			if danger_score > 0:
				var danger_alpha := clampf(0.055 + float(danger_score) * 0.035, 0.075, 0.22)
				draw_rect(rect, Color(1.0, 0.12, 0.08, danger_alpha))
				if danger_score >= 2:
					draw_rect(rect, Color(1.0, 0.25, 0.16, 0.28), false, 1.5)

			var cover_rank := _tile_cover_rank(pos, enemies)
			if cover_rank > 0:
				var cover_color := Color(0.3, 1.0, 0.58, 0.56) if cover_rank >= 2 else Color(0.38, 0.82, 1.0, 0.42)
				_draw_tile_brackets(rect.grow(-2.0), cover_color, 8.0, 2.0)

func _draw_unit_vision() -> void:
	for unit in _units:
		if not unit.is_alive():
			continue
		var color := Color(0.2, 0.8, 1.0, 0.09) if unit.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.25, 0.18, 0.08)
		draw_colored_polygon(_vision_polygon(unit), color)

func _draw_paths() -> void:
	for unit in _units:
		if not unit.is_alive() or unit.path.is_empty():
			continue
		var color := Color(0.25, 0.8, 1.0, 0.6) if unit.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.3, 0.2, 0.55)
		var previous: Vector2 = unit.world_position
		for tile in unit.path:
			var point: Vector2 = _battlefield.world_from_grid(tile, MAP_ORIGIN)
			draw_line(previous, point, color, 2.0)
			previous = point

func _draw_visual_effects() -> void:
	for item in _visual_effects:
		var age := float(item.get("age", 0.0))
		var ttl := maxf(0.01, float(item.get("ttl", 0.28)))
		var progress := clampf(age / ttl, 0.0, 1.0)
		var alpha := clampf(1.0 - progress, 0.0, 1.0)
		var color: Color = item.get("color", Color.WHITE)
		color.a *= alpha
		match str(item.get("kind", "")):
			"line":
				var from_pos: Vector2 = item.get("from", Vector2.ZERO)
				var to_pos: Vector2 = item.get("to", Vector2.ZERO)
				var tip := from_pos.lerp(to_pos, clampf(progress * 1.35, 0.0, 1.0))
				var glow := Color(color.r, color.g, color.b, color.a * 0.28)
				draw_line(from_pos, tip, glow, 7.0)
				draw_line(from_pos, tip, color, 2.5)
			"ring":
				var center: Vector2 = item.get("to", item.get("from", Vector2.ZERO))
				var radius := float(item.get("radius", 18.0)) + progress * 11.0
				draw_arc(center, radius, 0.0, TAU, 36, color, 2.4, true)
			"area":
				var center: Vector2 = item.get("to", item.get("from", Vector2.ZERO))
				var radius := float(item.get("radius", 24.0))
				var fill_color := Color(color.r, color.g, color.b, color.a * 0.12)
				draw_circle(center, radius, fill_color)
				draw_arc(center, radius + progress * 7.0, 0.0, TAU, 48, color, 2.8, true)
			_:
				pass

func _draw_units() -> void:
	var font := get_theme_default_font()
	for unit in _units:
		if not unit.is_alive():
			continue
		_draw_movement_trail(unit)
		_draw_unit_token(unit, font)
		_draw_intent_badge(unit)
		var end: Vector2 = unit.world_position + unit.facing.normalized() * 20.0
		draw_line(unit.world_position, end, Color(1.0, 1.0, 1.0, 0.82), 2.0)

		var hp_width := 42.0
		var hp_origin: Vector2 = unit.world_position + Vector2(-hp_width * 0.5, -28)
		var hp_color := Color(0.2, 0.85, 0.35)
		if unit.hp_ratio() < 0.35:
			hp_color = Color(1.0, 0.25, 0.18)
		elif unit.hp_ratio() < 0.65:
			hp_color = Color(1.0, 0.72, 0.24)
		draw_rect(Rect2(hp_origin, Vector2(hp_width, 5)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(hp_origin, Vector2(hp_width * unit.hp_ratio(), 5)), hp_color)
		draw_string(font, unit.world_position + Vector2(-28, 34), _short_name(unit.display_name), HORIZONTAL_ALIGNMENT_LEFT, 72, 11, Color(0.9, 0.9, 0.82))
		draw_string(font, unit.world_position + Vector2(-34, 48), _intent_label(unit.intent), HORIZONTAL_ALIGNMENT_LEFT, 88, 10, Color(0.75, 0.85, 1.0))

func _draw_movement_trail(unit) -> void:
	if not _unit_is_moving(unit):
		return
	var direction: Vector2 = unit.facing.normalized()
	if direction.length() <= 0.01:
		return
	var phase := fmod(float(Time.get_ticks_msec()) / 1000.0 * 4.5, 1.0)
	var base_color := _unit_base_color(unit)
	for i in 3:
		var step := float(i) + phase
		var alpha := maxf(0.0, 0.22 - step * 0.055)
		var radius := maxf(2.0, 6.0 - step * 0.9)
		var pos: Vector2 = unit.world_position - direction * (10.0 + step * 7.0)
		draw_circle(pos, radius, Color(base_color.r, base_color.g, base_color.b, alpha))

func _unit_is_moving(unit) -> bool:
	if not unit.path.is_empty():
		return true
	var grid_world: Vector2 = _battlefield.world_from_grid(unit.grid_pos, MAP_ORIGIN)
	return unit.world_position.distance_to(grid_world) > 1.5

func _draw_unit_token(unit, font: Font) -> void:
	var center: Vector2 = unit.world_position
	var base_color := _unit_base_color(unit)
	var outline_color := _unit_outline_color(unit)
	draw_circle(center + Vector2(1, 2), 18.0, Color(0.0, 0.0, 0.0, 0.42))
	_draw_unit_shape(center, unit, outline_color, base_color)

	if unit.hp_ratio() < 0.35:
		draw_arc(center, 19.0, 0.0, TAU, 36, Color(1.0, 0.16, 0.12, 0.95), 3.0, true)
	elif unit.hp_ratio() < 0.65:
		draw_arc(center, 18.5, 0.0, TAU, 36, Color(1.0, 0.74, 0.22, 0.78), 2.2, true)

	if unit.fear >= 0.55:
		var fear_alpha := clampf((unit.fear - 0.45) * 1.5, 0.25, 0.9)
		draw_arc(center, 22.0, -PI * 0.5, PI * 1.5, 36, Color(0.72, 0.52, 1.0, fear_alpha), 2.0, true)

	if _unit_is_leader(unit):
		var badge_center := center + Vector2(-15, -15)
		draw_circle(badge_center, 6.5, Color(0.05, 0.04, 0.02, 0.9))
		draw_circle(badge_center, 5.0, Color(1.0, 0.78, 0.25))
		draw_string(font, badge_center + Vector2(-4, 3), "L", HORIZONTAL_ALIGNMENT_CENTER, 8, 7, Color(0.08, 0.06, 0.02))

	draw_string(font, center + Vector2(-9, 5), _unit_icon(unit), HORIZONTAL_ALIGNMENT_CENTER, 18, 12, Color(0.98, 0.98, 0.92))

func _draw_unit_shape(center: Vector2, unit, outline_color: Color, base_color: Color) -> void:
	match _unit_shape(unit):
		"square":
			draw_rect(Rect2(center - Vector2(14, 14), Vector2(28, 28)), outline_color)
			draw_rect(Rect2(center - Vector2(10, 10), Vector2(20, 20)), base_color)
		"diamond":
			var outer_diamond := PackedVector2Array([
				center + Vector2(0, -16),
				center + Vector2(16, 0),
				center + Vector2(0, 16),
				center + Vector2(-16, 0)
			])
			var inner_diamond := PackedVector2Array([
				center + Vector2(0, -11),
				center + Vector2(11, 0),
				center + Vector2(0, 11),
				center + Vector2(-11, 0)
			])
			draw_colored_polygon(outer_diamond, outline_color)
			draw_colored_polygon(inner_diamond, base_color)
		"triangle":
			var outer_triangle := PackedVector2Array([
				center + Vector2(0, -17),
				center + Vector2(16, 13),
				center + Vector2(-16, 13)
			])
			var inner_triangle := PackedVector2Array([
				center + Vector2(0, -11),
				center + Vector2(10, 8),
				center + Vector2(-10, 8)
			])
			draw_colored_polygon(outer_triangle, outline_color)
			draw_colored_polygon(inner_triangle, base_color)
		_:
			draw_circle(center, 16.0, outline_color)
			draw_circle(center, 12.0, base_color)

func _draw_intent_badge(unit) -> void:
	var center: Vector2 = unit.world_position + Vector2(18, -18)
	var badge_color: Color = _intent_color(unit.intent)
	draw_circle(center, 8.0, Color(0.02, 0.025, 0.03, 0.95))
	draw_circle(center, 6.0, badge_color)
	var font := get_theme_default_font()
	draw_string(font, center + Vector2(-5, 4), _intent_badge(unit.intent), HORIZONTAL_ALIGNMENT_CENTER, 10, 8, Color(0.02, 0.025, 0.03))

func _draw_floating_texts() -> void:
	var font := get_theme_default_font()
	for item in _floating_texts:
		var pos: Vector2 = item.get("pos", Vector2.ZERO)
		var age: float = float(item.get("age", 0.0))
		var ttl: float = float(item.get("ttl", 1.0))
		var alpha: float = clampf(1.0 - age / ttl, 0.0, 1.0)
		var color: Color = item.get("color", Color.WHITE)
		color.a *= alpha
		draw_string(font, pos + Vector2(1, 1), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, Color(0, 0, 0, alpha * 0.8))
		draw_string(font, pos, str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, 80, 13, color)

func _draw_legend() -> void:
	var font := get_theme_default_font()
	var x := 42.0
	var y := 622.0
	var entries := [
		["Пол", _tile_color(BattlefieldScript.TileType.FLOOR)],
		["Стена", _tile_color(BattlefieldScript.TileType.WALL)],
		["Вода медлит", _tile_color(BattlefieldScript.TileType.WATER)],
		["Укрытие", _tile_color(BattlefieldScript.TileType.COVER)],
		["Трава скрывает", _tile_color(BattlefieldScript.TileType.GRASS)],
	]
	for entry in entries:
		draw_rect(Rect2(Vector2(x, y), Vector2(18, 18)), entry[1])
		draw_string(font, Vector2(x + 24, y + 15), entry[0], HORIZONTAL_ALIGNMENT_LEFT, 130, 13, Color(0.86, 0.86, 0.8))
		x += 138
	draw_rect(Rect2(Vector2(x, y + 4), Vector2(18, 10)), Color(1.0, 0.12, 0.08, 0.22))
	draw_string(font, Vector2(x + 24, y + 15), "Опасно", HORIZONTAL_ALIGNMENT_LEFT, 120, 13, Color(0.86, 0.86, 0.8))
	x += 118
	_draw_tile_brackets(Rect2(Vector2(x, y), Vector2(18, 18)), Color(0.3, 1.0, 0.58, 0.68), 5.0, 1.6)
	draw_string(font, Vector2(x + 24, y + 15), "Позиция", HORIZONTAL_ALIGNMENT_LEFT, 120, 13, Color(0.86, 0.86, 0.8))

func _tile_rect(pos: Vector2i) -> Rect2:
	return Rect2(MAP_ORIGIN + Vector2(pos) * _battlefield.tile_size(), Vector2.ONE * _battlefield.tile_size())

func _draw_tile_brackets(rect: Rect2, color: Color, length: float, width: float) -> void:
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.position.x + rect.size.x
	var bottom := rect.position.y + rect.size.y
	draw_line(Vector2(left, top), Vector2(left + length, top), color, width)
	draw_line(Vector2(left, top), Vector2(left, top + length), color, width)
	draw_line(Vector2(right, top), Vector2(right - length, top), color, width)
	draw_line(Vector2(right, top), Vector2(right, top + length), color, width)
	draw_line(Vector2(left, bottom), Vector2(left + length, bottom), color, width)
	draw_line(Vector2(left, bottom), Vector2(left, bottom - length), color, width)
	draw_line(Vector2(right, bottom), Vector2(right - length, bottom), color, width)
	draw_line(Vector2(right, bottom), Vector2(right, bottom - length), color, width)

func _alive_units_for_side(side: int) -> Array:
	var result: Array = []
	for unit in _units:
		if unit.is_alive() and unit.side == side:
			result.append(unit)
	return result

func _tile_danger_score(pos: Vector2i, enemies: Array) -> int:
	var score := 0
	for enemy in enemies:
		if enemy.grid_pos == pos:
			continue
		var distance: float = Vector2(pos - enemy.grid_pos).length()
		if distance > _unit_threat_range(enemy):
			continue
		if not _battlefield.has_line_of_sight(enemy.grid_pos, pos):
			continue
		score += 2 if distance <= enemy.attack_range_tiles else 1
	return score

func _tile_cover_rank(pos: Vector2i, enemies: Array) -> int:
	if _battlefield.is_cover(pos):
		return 2
	for neighbor in _battlefield.get_neighbors(pos):
		if not _battlefield.is_cover(neighbor):
			continue
		for enemy in enemies:
			if not _battlefield.has_line_of_sight(enemy.grid_pos, pos):
				return 1
	return 0

func _unit_threat_range(unit) -> float:
	var range_tiles: float = unit.attack_range_tiles
	if unit.battle_unit == null:
		return range_tiles
	for ability in unit.battle_unit.abilities:
		if ability == null:
			continue
		if ability.target_type not in [AbilityData.TargetType.SINGLE_ENEMY, AbilityData.TargetType.ALL_ENEMIES]:
			continue
		if ability.type not in [AbilityData.AbilityType.DAMAGE, AbilityData.AbilityType.DEBUFF, AbilityData.AbilityType.SPECIAL]:
			continue
		range_tiles = maxf(range_tiles, unit.ability_range_tiles(ability))
	return range_tiles

func _vision_polygon(unit) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(unit.world_position)
	var facing_angle: float = unit.facing.angle()
	var half_angle := deg_to_rad(unit.vision_angle_deg * 0.5)
	var radius: float = unit.vision_radius_tiles * _battlefield.tile_size()
	var steps := 14
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle: float = facing_angle - half_angle + half_angle * 2.0 * t
		points.append(unit.world_position + Vector2(cos(angle), sin(angle)) * radius)
	return points

func _tile_color(tile: int) -> Color:
	match tile:
		BattlefieldScript.TileType.WALL:
			return Color(0.12, 0.13, 0.15)
		BattlefieldScript.TileType.WATER:
			return Color(0.08, 0.18, 0.26)
		BattlefieldScript.TileType.COVER:
			return Color(0.26, 0.22, 0.16)
		BattlefieldScript.TileType.DOOR:
			return Color(0.25, 0.19, 0.08)
		BattlefieldScript.TileType.GRASS:
			return Color(0.10, 0.19, 0.12)
		_:
			return Color(0.16, 0.16, 0.16)

func _unit_class_id(unit) -> String:
	if unit.character_data == null:
		return ""
	return str(unit.character_data.character_class)

func _unit_shape(unit) -> String:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return "square"
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return "diamond"
		return "triangle"

	match _unit_class_id(unit):
		"defender", "guardian", "tank":
			return "square"
		"healer", "mage":
			return "diamond"
		"scout", "rogue", "assassin":
			return "triangle"
		_:
			return "circle"

func _unit_icon(unit) -> String:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return "B"
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return "T"
		if unit.display_name.begins_with("Орк"):
			return "O"
		return "G"

	match _unit_class_id(unit):
		"warrior":
			return "W"
		"healer":
			return "+"
		"mage":
			return "M"
		"scout":
			return "S"
		"defender", "guardian", "tank":
			return "D"
		_:
			return "A"

func _unit_base_color(unit) -> Color:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return Color(0.56, 0.13, 0.16)
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return Color(0.72, 0.22, 0.16)
		if unit.display_name.begins_with("Орк"):
			return Color(0.84, 0.34, 0.16)
		return Color(0.92, 0.2, 0.17)

	match _unit_class_id(unit):
		"warrior":
			return Color(0.18, 0.58, 0.96)
		"healer":
			return Color(0.28, 0.78, 0.48)
		"mage":
			return Color(0.55, 0.46, 0.95)
		"scout":
			return Color(0.9, 0.62, 0.2)
		"defender", "guardian", "tank":
			return Color(0.34, 0.62, 0.74)
		_:
			return Color(0.24, 0.66, 0.94)

func _unit_outline_color(unit) -> Color:
	if unit.unit_id == _focus_unit_id:
		return Color(1.0, 0.86, 0.28)
	if unit.intent == "ability":
		return Color(0.62, 0.9, 1.0)
	if unit.intent == "attack":
		return Color(1.0, 0.58, 0.24)
	if unit.intent == "retreat":
		return Color(0.72, 0.55, 1.0)
	return Color(0.025, 0.03, 0.038)

func _unit_is_leader(unit) -> bool:
	return unit.side == BattleUnit.UnitSide.ALLY and unit.unit_id == "ally_0"

func _ability_event_color(ability: AbilityData, event_type: String) -> Color:
	match event_type:
		"heal":
			return Color(0.34, 1.0, 0.58)
		"buff":
			return Color(0.45, 0.82, 1.0)
		_:
			pass

	if ability == null:
		return Color(1.0, 0.72, 0.28)

	match ability.type:
		AbilityData.AbilityType.DEBUFF:
			return Color(0.78, 0.52, 1.0)
		AbilityData.AbilityType.SPECIAL:
			return Color(1.0, 0.86, 0.32)
		_:
			pass

	if ability.stat_used == "magic":
		return Color(0.58, 0.78, 1.0)
	if ability.stat_used == "speed":
		return Color(1.0, 0.82, 0.36)
	return Color(1.0, 0.5, 0.28)

func _intent_label(intent: String) -> String:
	match intent:
		"ability":
			return "способность"
		"attack":
			return "атака"
		"chase":
			return "преследует"
		"retreat":
			return "отступает"
		"take_cover":
			return "укрытие"
		"follow":
			return "рядом"
		"patrol":
			return "поиск"
		"ambush":
			return "засада"
		"hold":
			return "ждёт"
		_:
			return intent

func _short_name(value: String) -> String:
	if value.length() <= 8:
		return value
	return value.substr(0, 8)

func _refresh_focus_panel() -> void:
	var unit = _get_focus_unit()
	if unit == null:
		_focus_label.text = "Фокус: нет активного героя"
		return
	var target_text := "цель: %s" % unit.target_name if unit.target_name != "" else "цель: нет"
	var action_text: String = unit.intent_ability_name if unit.intent == "ability" and unit.intent_ability_name != "" else _intent_label(unit.intent)
	_focus_label.text = "Фокус: %s\n%s, HP %d/%d, страх %.0f%%\n%s\nпричина: %s" % [
		unit.display_name,
		action_text,
		unit.battle_unit.current_hp,
		unit.battle_unit.max_hp,
		unit.fear * 100.0,
		target_text,
		unit.intent_reason
	]

func _refresh_unit_list() -> void:
	var ally_lines: PackedStringArray = []
	var enemy_lines: PackedStringArray = []
	for unit in _units:
		var action_text: String = unit.intent_ability_name if unit.intent == "ability" and unit.intent_ability_name != "" else _intent_label(unit.intent)
		var line := "%s %d/%d %s" % [
			_short_name(unit.display_name),
			unit.battle_unit.current_hp,
			unit.battle_unit.max_hp,
			action_text
		]
		if unit.target_name != "":
			line += " -> " + _short_name(unit.target_name)
		if not unit.is_alive():
			line = "%s 0/%d выбыл" % [_short_name(unit.display_name), unit.battle_unit.max_hp]
		if unit.side == BattleUnit.UnitSide.ALLY:
			ally_lines.append(line)
		else:
			enemy_lines.append(line)
	_unit_list_label.text = "Союзники\n%s\n\nВраги\n%s" % [
		"\n".join(ally_lines),
		"\n".join(enemy_lines)
	]

func _get_focus_unit():
	for unit in _units:
		if unit.unit_id == _focus_unit_id and unit.is_alive():
			return unit
	for unit in _units:
		if unit.side == BattleUnit.UnitSide.ALLY and unit.is_alive():
			_focus_unit_id = unit.unit_id
			return unit
	return null

func _intent_badge(intent: String) -> String:
	match intent:
		"ability":
			return "*"
		"attack":
			return "A"
		"chase":
			return ">"
		"retreat":
			return "R"
		"take_cover":
			return "C"
		"follow":
			return "F"
		"patrol":
			return "S"
		"ambush":
			return "!"
		_:
			return "-"

func _intent_float_label(intent: String) -> String:
	match intent:
		"ability":
			return "умение"
		"attack":
			return "атака"
		"chase":
			return "вижу цель"
		"retreat":
			return "страх"
		"take_cover":
			return "укрытие"
		"follow":
			return "к союзнику"
		"patrol":
			return "поиск"
		"ambush":
			return "засада"
		_:
			return ""

func _intent_color(intent: String) -> Color:
	match intent:
		"ability":
			return Color(0.55, 0.82, 1.0)
		"attack":
			return Color(1.0, 0.48, 0.28)
		"chase":
			return Color(1.0, 0.78, 0.25)
		"retreat":
			return Color(0.72, 0.55, 1.0)
		"take_cover":
			return Color(0.38, 0.74, 1.0)
		"follow":
			return Color(0.45, 0.95, 0.78)
		"patrol":
			return Color(0.72, 0.82, 0.9)
		"ambush":
			return Color(0.75, 1.0, 0.36)
		_:
			return Color(0.85, 0.85, 0.85)

func _speed_label() -> String:
	return "Скорость %.1fx" % _time_scale

func _on_return_pressed() -> void:
	GameState.clear_pending_combat()
	get_tree().change_scene_to_file(HUB_SCENE)

func _on_end_return_pressed() -> void:
	if _is_raid_combat:
		get_tree().change_scene_to_file(RAID_PROGRESS_SCENE)
	elif _is_tower_elevation and _end_title.text == "Победа!":
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)

func _on_pause_pressed() -> void:
	_paused = not _paused
	_pause_btn.text = "Продолжить" if _paused else "Пауза"
	_refresh_status()

func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % SPEED_MODES.size()
	_time_scale = float(SPEED_MODES[_speed_index])
	_speed_btn.text = _speed_label()
	_refresh_status()

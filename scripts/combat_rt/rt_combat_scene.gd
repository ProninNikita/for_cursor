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
var _time_scale := 1.0
var _log_lines: PackedStringArray = []
var _is_tower_elevation: bool = false
var _is_raid_combat: bool = false
var _current_tower_floor: int = 0
var _battle_start_hp: Dictionary = {}
var _battle_damage_dealt: Dictionary = {}
var _battle_healing_done: Dictionary = {}

var _return_btn: Button
var _pause_btn: Button
var _speed_btn: Button
var _status_label: Label
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
	if _battle_finished or _paused:
		return

	var scaled_delta := delta * _time_scale
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
	_speed_btn.text = "Скорость 1x"
	_speed_btn.set_meta("qa_id", "combat_rt.speed")
	_speed_btn.pressed.connect(_on_speed_pressed)
	top_bar.add_child(_speed_btn)

	var title := Label.new()
	title.text = "RT Combat Sandbox: поле зрения, укрытия, страх, намерения"
	title.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(title)

	_status_label = Label.new()
	_status_label.position = Vector2(850, 82)
	_status_label.size = Vector2(390, 86)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_log_label = RichTextLabel.new()
	_log_label.position = Vector2(850, 178)
	_log_label.size = Vector2(390, 430)
	_log_label.bbcode_enabled = false
	_log_label.scroll_following = true
	add_child(_log_label)

	_create_end_panel()

func _create_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.name = "EndPanel"
	_end_panel.visible = false
	_end_panel.z_index = 10
	_end_panel.position = Vector2(390, 210)
	_end_panel.size = Vector2(500, 240)
	add_child(_end_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.15, 0.97)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.42, 0.46, 0.56)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	_end_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	_end_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_end_title)

	_end_detail = Label.new()
	_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_end_detail)

	_end_btn = Button.new()
	_end_btn.text = "Продолжить"
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

func _log_line(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)

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
	if victory:
		_end_title.text = "Победа!"
		if _is_tower_elevation:
			_end_btn.text = "В башню"
			_end_detail.text = "%s пройден.\nНаграда: %s\nВсего: %d лутбоксов, %d золота\nСледующий этаж: %d" % [
				floor_data.get("name", "Этаж %d" % _current_tower_floor),
				_format_rewards(applied_rewards),
				GameState.lootboxes_remaining,
				GameState.gold,
				_current_tower_floor + 1
			]
		elif _is_raid_combat:
			_end_btn.text = "К вылазке"
			_end_detail.text = "Враги разбиты.\nОтряд продолжает вылазку."
		else:
			_end_btn.text = "В город"
			_end_detail.text = "Получено: %s\nВсего: %d лутбоксов, %d золота" % [
				_format_rewards(applied_rewards),
				GameState.lootboxes_remaining,
				GameState.gold
			]
	else:
		_end_title.text = "Поражение"
		_end_btn.text = "В город"
		if _is_raid_combat:
			_end_btn.text = "К вылазке"
			_end_detail.text = "Отряд отступил и получил потери.\nПроверь состояние героев."
		else:
			_end_detail.text = "Выжившие обновлены в ростере."

func _record_resolver_event(event: Dictionary) -> void:
	if event.get("type", "") != "damage":
		return
	var attacker = event.get("attacker", null)
	if attacker == null or attacker.character_data == null:
		return
	var amount := int(event.get("amount", 0))
	if amount <= 0:
		return
	var char_id: String = attacker.character_data.id
	_battle_damage_dealt[char_id] = int(_battle_damage_dealt.get(char_id, 0)) + amount

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
	_draw_unit_vision()
	_draw_paths()
	_draw_units()
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

func _draw_units() -> void:
	var font := get_theme_default_font()
	for unit in _units:
		if not unit.is_alive():
			continue
		var color := Color(0.18, 0.62, 1.0) if unit.side == BattleUnit.UnitSide.ALLY else Color(0.95, 0.24, 0.16)
		var outline := Color(0.9, 0.78, 0.42) if unit.intent == "attack" else Color(0.02, 0.025, 0.03)
		draw_circle(unit.world_position, 15.0, outline)
		draw_circle(unit.world_position, 11.0, color)
		var end: Vector2 = unit.world_position + unit.facing.normalized() * 20.0
		draw_line(unit.world_position, end, Color.WHITE, 2.0)

		var hp_width := 42.0
		var hp_origin: Vector2 = unit.world_position + Vector2(-hp_width * 0.5, -28)
		draw_rect(Rect2(hp_origin, Vector2(hp_width, 5)), Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(hp_origin, Vector2(hp_width * unit.hp_ratio(), 5)), Color(0.2, 0.85, 0.35))
		draw_string(font, unit.world_position + Vector2(-28, 34), _short_name(unit.display_name), HORIZONTAL_ALIGNMENT_LEFT, 72, 11, Color(0.9, 0.9, 0.82))
		draw_string(font, unit.world_position + Vector2(-34, 48), _intent_label(unit.intent), HORIZONTAL_ALIGNMENT_LEFT, 88, 10, Color(0.75, 0.85, 1.0))

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

func _intent_label(intent: String) -> String:
	match intent:
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
	if is_equal_approx(_time_scale, 1.0):
		_time_scale = 0.5
	elif is_equal_approx(_time_scale, 0.5):
		_time_scale = 2.0
	else:
		_time_scale = 1.0
	_speed_btn.text = "Скорость %.1fx" % _time_scale
	_refresh_status()

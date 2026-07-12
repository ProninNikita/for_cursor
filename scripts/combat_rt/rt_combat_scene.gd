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
const CombatContextScript = preload("res://scripts/combat_rt/rt_combat_context.gd")
const CombatResultScript = preload("res://scripts/combat_rt/rt_combat_result.gd")
const CombatConfigScript = preload("res://scripts/combat_rt/rt_combat_config.gd")
const PostBattleServiceScript = preload("res://scripts/combat_rt/rt_post_battle_service.gd")
const CombatControllerScript = preload("res://scripts/combat_rt/rt_combat_controller.gd")
const CombatRendererScript = preload("res://scripts/combat_rt/rt_combat_renderer.gd")
const CombatUIFormatterScript = preload("res://scripts/combat_rt/rt_combat_ui_formatter.gd")
const CombatAudioServiceScript = preload("res://scripts/combat_rt/rt_combat_audio_service.gd")
const CombatUnitFactoryScript = preload("res://scripts/combat_rt/rt_combat_unit_factory.gd")
const CombatSessionScript = preload("res://scripts/combat_rt/rt_combat_session.gd")
const CombatEventCollectorScript = preload("res://scripts/combat_rt/rt_combat_event_collector.gd")
const CombatUIControllerScript = preload("res://scripts/combat_rt/rt_combat_ui_controller.gd")

const MAP_ORIGIN := Vector2(38, 94)
const ENEMY_ARCHETYPES_PATH := "res://data/rt_enemies.json"

var _battlefield = BattlefieldScript.new()
var _perception = PerceptionScript.new()
var _brain = BrainScript.new()
var _resolver = ResolverScript.new()
var _post_battle_service = PostBattleServiceScript.new()
var _combat_controller = CombatControllerScript.new()
var _combat_renderer = CombatRendererScript.new()
var _ui_formatter = CombatUIFormatterScript.new()
var _audio_service = CombatAudioServiceScript.new()
var _unit_factory = CombatUnitFactoryScript.new()
var _session = CombatSessionScript.new()
var _event_collector = CombatEventCollectorScript.new()
var _ui_controller = CombatUIControllerScript.new()
var _rng := RandomNumberGenerator.new()
var _units: Array = []
var _intents: Dictionary = {}
var _decision_timer: float = 0.0
var _battle_finished := false
var _paused := false
var _freeze_ai := false
var _fast_forward_to_end := false
var _auto_pause_important := false
var _time_scale := 0.5
var _speed_index: int = 0
var _log_lines: PackedStringArray = []
var _floating_texts: Array[Dictionary] = []
var _visual_effects: Array[Dictionary] = []
var _focus_unit_id: String = ""
var _battle_context = CombatContextScript.new()
var _combat_config = CombatConfigScript.new()
var _last_result = null
var _battle_elapsed_seconds: float = 0.0
var _battle_finish_reason: String = ""
var _battle_finish_detail: String = ""
var _battle_start_hp: Dictionary = {}
var _battle_damage_dealt: Dictionary = {}
var _battle_healing_done: Dictionary = {}
var _battle_ability_usage: Dictionary = {}
var _battle_damage_taken: Dictionary = {}
var _battle_successful_actions: Dictionary = {}
var _battle_dangerous_enemies: Dictionary = {}
var _battle_help_received: Dictionary = {}
var _battle_cover_seconds: Dictionary = {}
var _battle_alone_seconds: Dictionary = {}
var _battle_low_visibility_seconds: Dictionary = {}
var _battle_near_leader_seconds: Dictionary = {}
var _battle_ranged_damage: Dictionary = {}
var _battle_decision_usage: Dictionary = {}
var _battle_timeline: Array[Dictionary] = []
var _max_process_usec: int = 0
var _enemy_archetypes: Dictionary = {}
var _leader_unit_id: String = ""
var _squad_style: String = "balanced"
var _debug_setup_index: int = 0

var _return_btn: Button
var _pause_btn: Button
var _speed_btn: Button
var _freeze_btn: Button
var _fast_finish_btn: Button
var _auto_pause_btn: Button
var _setup_btn: Button
var _debug_btn: Button
var _fog_btn: Button
var _status_label: Label
var _focus_label: Label
var _unit_list_label: RichTextLabel
var _log_label: RichTextLabel
var _bottom_label: Label
var _end_panel: PanelContainer
var _end_title: Label
var _end_detail: Label
var _end_tabs: TabContainer
var _end_heroes_detail: Label
var _end_enemies_detail: Label
var _end_rewards_detail: Label
var _end_lessons_detail: Label
var _end_deaths_detail: Label
var _end_btn: Button
var _repeat_btn: Button
var _debug_perception_overlay := false
var _fog_of_war_enabled := true
var _player_visible_tiles: Dictionary = {}
var _player_known_tiles: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	AbilityRegistry.initialize()
	_capture_battle_context()
	_setup_combat_config()
	_create_ui()
	_create_audio()
	_setup_battle()
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var process_started_usec := Time.get_ticks_usec()
	_update_floating_texts(delta)
	_update_visual_effects(delta)
	if _battle_finished or _paused:
		queue_redraw()
		_record_process_time(process_started_usec)
		return

	var scaled_delta := delta * _time_scale
	_battle_elapsed_seconds += scaled_delta
	_session.elapsed_seconds = _battle_elapsed_seconds
	_battlefield.begin_path_tick(_combat_config.path_budget_per_tick, _combat_config.path_queue_per_tick)
	_update_enemy_phases()
	if not _freeze_ai:
		_decision_timer -= scaled_delta
	if not _freeze_ai and _decision_timer <= 0.0:
		_decision_timer = _combat_config.decision_interval
		_update_perception_and_intents()

	_battlefield.rebuild_occupancy(_units)
	_resolver.active_units = _units
	for unit in _units:
		var intent: Dictionary = _intents.get(unit.unit_id, {"type": "hold", "reason": "ждёт", "destination": unit.grid_pos})
		var messages: Array[String] = _resolver.update_unit(unit, scaled_delta, intent, _battlefield, MAP_ORIGIN)
		for message in messages:
			_log_line(message)
		for event in _resolver.consume_events():
			_record_resolver_event(event)

	_track_memory_context(scaled_delta)
	_check_end()
	_update_player_knowledge()
	_refresh_status()
	queue_redraw()
	_record_process_time(process_started_usec)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		var unit = _unit_at_screen_position(mouse_event.position)
		if unit != null:
			_focus_unit_id = unit.unit_id
			_refresh_focus_panel()
			queue_redraw()

func _unit_at_screen_position(pos: Vector2):
	var best = null
	var best_distance := INF
	for unit in _units:
		if not unit.is_alive() or not _unit_visible_to_player(unit):
			continue
		var distance: float = unit.world_position.distance_to(pos)
		if distance > 24.0 or distance >= best_distance:
			continue
		best = unit
		best_distance = distance
	return best

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

	_freeze_btn = Button.new()
	_freeze_btn.text = "AI"
	_freeze_btn.set_meta("qa_id", "combat_rt.freeze_ai")
	_freeze_btn.pressed.connect(_on_freeze_pressed)
	top_bar.add_child(_freeze_btn)

	_fast_finish_btn = Button.new()
	_fast_finish_btn.text = "До конца"
	_fast_finish_btn.set_meta("qa_id", "combat_rt.fast_finish")
	_fast_finish_btn.pressed.connect(_on_fast_finish_pressed)
	top_bar.add_child(_fast_finish_btn)

	_auto_pause_btn = Button.new()
	_auto_pause_btn.text = "Автопауза off"
	_auto_pause_btn.set_meta("qa_id", "combat_rt.auto_pause")
	_auto_pause_btn.pressed.connect(_on_auto_pause_pressed)
	top_bar.add_child(_auto_pause_btn)

	_setup_btn = Button.new()
	_setup_btn.text = "Сетап"
	_setup_btn.set_meta("qa_id", "combat_rt.setup")
	_setup_btn.pressed.connect(_on_setup_pressed)
	top_bar.add_child(_setup_btn)

	_debug_btn = Button.new()
	_debug_btn.text = "Debug"
	_debug_btn.set_meta("qa_id", "combat_rt.debug")
	_debug_btn.pressed.connect(_on_debug_pressed)
	top_bar.add_child(_debug_btn)

	_fog_btn = Button.new()
	_fog_btn.text = "Туман on"
	_fog_btn.set_meta("qa_id", "combat_rt.fog")
	_fog_btn.pressed.connect(_on_fog_pressed)
	top_bar.add_child(_fog_btn)

	var title := Label.new()
	title.text = "Бой"
	title.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(title)

	_status_label = Label.new()
	_status_label.position = Vector2(850, 78)
	_status_label.size = Vector2(390, 58)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_focus_label = Label.new()
	_focus_label.position = Vector2(850, 136)
	_focus_label.size = Vector2(390, 116)
	_focus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_focus_label.add_theme_font_size_override("font_size", 13)
	add_child(_focus_label)

	_unit_list_label = RichTextLabel.new()
	_unit_list_label.position = Vector2(850, 260)
	_unit_list_label.size = Vector2(390, 136)
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

	_bottom_label = Label.new()
	_bottom_label.position = Vector2(38, 652)
	_bottom_label.size = Vector2(790, 26)
	_bottom_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_label.add_theme_font_size_override("font_size", 13)
	_bottom_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.88))
	add_child(_bottom_label)

	_create_end_panel()

func _create_audio() -> void:
	_audio_service.setup(self)

func _create_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.name = "EndPanel"
	_end_panel.visible = false
	_end_panel.z_index = 10
	_end_panel.position = Vector2(304, 118)
	_end_panel.size = Vector2(672, 468)
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

	_end_tabs = TabContainer.new()
	_end_tabs.custom_minimum_size = Vector2(0, 260)
	_end_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_end_tabs)

	_end_detail = _make_end_tab("Итог")
	_end_heroes_detail = _make_end_tab("Герои")
	_end_enemies_detail = _make_end_tab("Враги")
	_end_rewards_detail = _make_end_tab("Награды")
	_end_lessons_detail = _make_end_tab("Уроки")
	_end_deaths_detail = _make_end_tab("Смерти")

	_end_btn = Button.new()
	_end_btn.text = "Продолжить"
	_end_btn.custom_minimum_size = Vector2(0, 38)
	_end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_btn.set_meta("qa_id", "combat.return")
	_end_btn.pressed.connect(_on_end_return_pressed)
	box.add_child(_end_btn)

	_repeat_btn = Button.new()
	_repeat_btn.text = "Повторить тренировку"
	_repeat_btn.custom_minimum_size = Vector2(0, 34)
	_repeat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repeat_btn.visible = false
	_repeat_btn.set_meta("qa_id", "combat.repeat_training")
	_repeat_btn.pressed.connect(_on_repeat_training_pressed)
	box.add_child(_repeat_btn)

func _make_end_tab(title: String) -> Label:
	var margin := MarginContainer.new()
	margin.name = title
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_end_tabs.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.88))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	return label

func _capture_battle_context() -> void:
	_battle_context = CombatContextScript.new()
	_battle_context.setup_from_game_state()

func _setup_combat_config() -> void:
	_combat_config = CombatConfigScript.new()
	_combat_config.setup_from_context(_battle_context)
	_combat_config.apply_to_rng(_rng, "scene")
	_combat_config.apply_to_rng(_resolver.rng, "resolver")
	_resolver.damage_multiplier = _combat_config.damage_multiplier
	_resolver.trap_damage_base = _combat_config.trap_damage_base
	_resolver.poison_damage_multiplier = _combat_config.poison_damage_multiplier
	_resolver.friendly_fire_multiplier = _combat_config.friendly_fire_multiplier
	_resolver.area_damage_multiplier = _combat_config.area_damage_multiplier
	_time_scale = _combat_config.default_time_scale
	_speed_index = _combat_config.default_speed_index()

func _setup_battle() -> void:
	if not _battlefield.setup_arena(_battle_context.arena_id):
		_battlefield.setup_test_arena()
	_load_enemy_archetypes()
	_units.clear()
	_intents.clear()
	_log_lines.clear()
	_player_visible_tiles.clear()
	_player_known_tiles.clear()
	_battle_elapsed_seconds = 0.0
	_battle_finish_reason = ""
	_battle_finish_detail = ""
	_last_result = null
	_battle_start_hp.clear()
	_battle_damage_dealt.clear()
	_battle_healing_done.clear()
	_battle_ability_usage.clear()
	_battle_damage_taken.clear()
	_battle_successful_actions.clear()
	_battle_dangerous_enemies.clear()
	_battle_help_received.clear()
	_battle_cover_seconds.clear()
	_battle_alone_seconds.clear()
	_battle_low_visibility_seconds.clear()
	_battle_near_leader_seconds.clear()
	_battle_ranged_damage.clear()
	_battle_decision_usage.clear()
	_battle_timeline.clear()
	_max_process_usec = 0
	_event_collector.reset()
	_leader_unit_id = ""
	_squad_style = "balanced"
	_fast_forward_to_end = false
	_session.reset(_battle_context, _combat_config, _battlefield, _units, _intents)

	var squad := _combat_squad_or_demo()
	var ally_units: Array = _unit_factory.build_ally_units(squad, _battlefield, MAP_ORIGIN, _rng)
	for i in ally_units.size():
		var unit = ally_units[i]
		_units.append(unit)
		_battle_start_hp[squad[i].id] = unit.battle_unit.current_hp
		_battle_damage_dealt[squad[i].id] = 0
		_battle_healing_done[squad[i].id] = 0
		_battle_damage_taken[squad[i].id] = 0
		_battle_successful_actions[squad[i].id] = {}
		_battle_dangerous_enemies[squad[i].id] = {}
		_battle_help_received[squad[i].id] = 0
		_battle_cover_seconds[squad[i].id] = 0.0
		_battle_alone_seconds[squad[i].id] = 0.0
		_battle_low_visibility_seconds[squad[i].id] = 0.0
		_battle_near_leader_seconds[squad[i].id] = 0.0
		_battle_ranged_damage[squad[i].id] = 0

	var enemy_units: Array = _unit_factory.build_enemy_units(_enemy_plan_for_context(), _enemy_archetypes, _battle_context, _battlefield, MAP_ORIGIN, _rng)
	_units.append_array(enemy_units)

	_apply_context_modifiers_to_units()
	_assign_squad_leader_and_style()
	_log_line("Бой начался: юниты действуют одновременно.")
	_record_timeline("start", "Бой начался", 2)
	_log_line(_battle_context.threat_text())
	_play_audio_cue("battle_start")
	_audio_service.play_music("training" if _battle_context.is_demo() else ("tower" if _battle_context.is_tower() else "raid"))
	_battlefield.rebuild_occupancy(_units)
	if not _units.is_empty():
		_focus_unit_id = _units[0].unit_id
	_update_perception_and_intents()
	_update_player_knowledge()
	_refresh_status()

func _assign_squad_leader_and_style() -> void:
	var leader = _best_leader_candidate()
	if leader == null:
		return
	_leader_unit_id = leader.unit_id
	_squad_style = _squad_style_for_leader(leader)
	_apply_squad_leader_context()
	_log_line("Лидер отряда: %s, стиль: %s." % [leader.display_name, _squad_style_label(_squad_style)])

func _best_leader_candidate():
	var best = null
	var best_score: float = -INF
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		var score: float = unit.brain_value("leader_trust") * 1.35
		score += unit.brain_value("teamwork") * 0.9
		score += unit.brain_value("skill_patience") * 0.55
		score += float(unit.get_stat("initiative")) * 0.045
		score += unit.morale * 0.35
		var class_id: String = _unit_class_id(unit)
		match class_id:
			"tactician":
				score += 0.75
			"defender":
				score += 0.25
			"healer":
				score += 0.16
			"berserker":
				score -= 0.12
			_:
				pass
		if score > best_score:
			best = unit
			best_score = score
	return best

func _squad_style_for_leader(leader) -> String:
	if leader == null:
		return "balanced"
	var class_id: String = _unit_class_id(leader)
	if class_id == "tactician":
		return "cohesive"
	var aggression: float = leader.brain_value("aggression")
	var caution: float = leader.brain_value("caution")
	var teamwork: float = leader.brain_value("teamwork")
	var self_preserve: float = leader.brain_value("self_preserve")
	if aggression > caution + 0.16 and aggression > teamwork:
		return "aggressive"
	if caution + self_preserve > aggression + 0.28:
		return "cautious"
	if teamwork >= 0.62:
		return "cohesive"
	return "balanced"

func _apply_squad_leader_context() -> void:
	var leader = _get_unit_by_id(_leader_unit_id)
	var anchor: Vector2i = leader.grid_pos if leader != null and leader.is_alive() else _allied_group_anchor()
	var focus = _squad_focus_enemy()
	var formation_slots: Dictionary = _formation_slots_for_squad(leader, anchor, focus)
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY:
			continue
		unit.is_leader = unit.unit_id == _leader_unit_id
		unit.leader_unit_id = _leader_unit_id
		unit.leader_name = leader.display_name if leader != null else ""
		unit.squad_style = _squad_style
		unit.squad_anchor = anchor
		unit.squad_focus_target_id = focus.unit_id if focus != null else ""
		unit.squad_focus_target_name = focus.display_name if focus != null else ""
		unit.squad_focus_target_pos = focus.grid_pos if focus != null else Vector2i.ZERO
		unit.formation_role = _formation_role_for_unit(unit)
		unit.formation_slot = formation_slots.get(unit.unit_id, anchor)
		unit.formation_distance = Vector2(unit.grid_pos - unit.formation_slot).length()

func _update_squad_context() -> void:
	var leader = _get_unit_by_id(_leader_unit_id)
	if leader == null or not leader.is_alive():
		var promoted = _best_leader_candidate()
		if promoted != null and promoted.unit_id != _leader_unit_id:
			_leader_unit_id = promoted.unit_id
			_squad_style = _squad_style_for_leader(promoted)
			_log_line("Новый лидер отряда: %s, стиль: %s." % [promoted.display_name, _squad_style_label(_squad_style)])
	_apply_squad_leader_context()
	_apply_leader_morale()

func _apply_leader_morale() -> void:
	var leader = _get_unit_by_id(_leader_unit_id)
	if leader == null or not leader.is_alive():
		return
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		if unit == leader:
			unit.morale = clampf(unit.morale + 0.006, 0.0, 1.0)
			continue
		var distance: float = Vector2(unit.grid_pos - leader.grid_pos).length()
		var trust: float = unit.brain_value("leader_trust")
		if distance <= 5.0:
			unit.morale = clampf(unit.morale + 0.004 + trust * 0.004, 0.0, 1.0)
			unit.fear = clampf(unit.fear - trust * 0.004, 0.0, 1.0)
		elif distance >= 8.0:
			unit.morale = clampf(unit.morale - unit.brain_value("solitude_fear") * 0.006, 0.0, 1.0)

func _squad_focus_enemy():
	var scores: Dictionary = {}
	var refs: Dictionary = {}
	for ally in _units:
		if ally.side != BattleUnit.UnitSide.ALLY or not ally.is_alive():
			continue
		for enemy in ally.visible_enemies:
			if enemy == null or not enemy.is_alive():
				continue
			var score: float = float(scores.get(enemy.unit_id, 0.0))
			score += 1.0 + (1.0 - enemy.hp_ratio()) * 1.15
			if enemy.hp_ratio() <= 0.35:
				score += 0.65
			scores[enemy.unit_id] = score
			refs[enemy.unit_id] = enemy
	var best = null
	var best_score: float = 0.0
	for unit_id in scores.keys():
		var score: float = float(scores[unit_id])
		if score > best_score:
			best = refs[unit_id]
			best_score = score
	if best_score < 1.8:
		return null
	return best

func _formation_slots_for_squad(leader, anchor: Vector2i, focus) -> Dictionary:
	var slots: Dictionary = {}
	var alive_allies: Array = []
	for unit in _units:
		if unit.side == BattleUnit.UnitSide.ALLY and unit.is_alive():
			alive_allies.append(unit)
	if alive_allies.is_empty():
		return slots

	var forward: Vector2 = Vector2.RIGHT
	if focus != null:
		forward = Vector2(focus.grid_pos - anchor)
	elif leader != null and leader.facing.length() > 0.01:
		forward = leader.facing
	if forward.length() <= 0.01:
		forward = Vector2.RIGHT
	forward = forward.normalized()
	var right: Vector2 = Vector2(-forward.y, forward.x)

	var role_counts: Dictionary = {}
	for unit in alive_allies:
		var role: String = _formation_role_for_unit(unit)
		var index: int = int(role_counts.get(role, 0))
		role_counts[role] = index + 1
		var offset: Vector2 = _formation_offset(role, index, forward, right)
		var ideal: Vector2i = anchor + Vector2i(roundi(offset.x), roundi(offset.y))
		slots[unit.unit_id] = _nearest_formation_slot(unit, ideal, anchor)
	return slots

func _formation_role_for_unit(unit) -> String:
	if unit == null:
		return "line"
	if unit.is_leader:
		return "center"
	var class_id: String = _unit_class_id(unit)
	if class_id in ["healer", "mage", "tactician"]:
		return "backline"
	if class_id in ["scout", "assassin"]:
		return "flank"
	if class_id == "defender" or (unit.battle_unit != null and unit.battle_unit.def >= 7):
		return "front"
	if unit.attack_range_tiles > 2.25:
		return "backline"
	return "front"

func _formation_offset(role: String, index: int, forward: Vector2, right: Vector2) -> Vector2:
	var side_sign: float = 1.0 if index % 2 == 0 else -1.0
	var lane: float = float((index + 1) / 2)
	match role:
		"center":
			return Vector2.ZERO
		"front":
			return forward * 1.7 + right * side_sign * lane
		"backline":
			return -forward * 2.0 + right * side_sign * lane
		"flank":
			return right * side_sign * (2.0 + lane) + forward * 0.4
		_:
			return right * side_sign * lane

func _nearest_formation_slot(unit, ideal: Vector2i, anchor: Vector2i) -> Vector2i:
	if _formation_slot_walkable_for(unit, ideal):
		return ideal
	var best: Vector2i = unit.grid_pos
	var best_score: float = INF
	for radius in range(1, 4):
		for y in range(ideal.y - radius, ideal.y + radius + 1):
			for x in range(ideal.x - radius, ideal.x + radius + 1):
				var candidate := Vector2i(x, y)
				if not _formation_slot_walkable_for(unit, candidate):
					continue
				var score: float = Vector2(candidate - ideal).length() + Vector2(candidate - anchor).length() * 0.08
				if score < best_score:
					best = candidate
					best_score = score
		if best != unit.grid_pos:
			return best
	return unit.grid_pos

func _formation_slot_walkable_for(unit, pos: Vector2i) -> bool:
	if not _battlefield.in_bounds(pos) or not _battlefield.is_walkable(pos):
		return false
	if _battlefield.is_occupied(pos, unit.unit_id):
		return false
	if pos != unit.grid_pos and _battlefield.find_path(unit.grid_pos, pos, unit.unit_id, false).is_empty():
		return false
	return true

func _allied_group_anchor() -> Vector2i:
	var total := Vector2.ZERO
	var count := 0
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		total += Vector2(unit.grid_pos)
		count += 1
	if count <= 0:
		return Vector2i.ZERO
	var average: Vector2 = total / float(count)
	return Vector2i(roundi(average.x), roundi(average.y))

func _get_unit_by_id(unit_id: String):
	for unit in _units:
		if unit.unit_id == unit_id:
			return unit
	return null

func _squad_style_label(style_id: String) -> String:
	match style_id:
		"aggressive":
			return "агрессивно"
		"cautious":
			return "осторожно"
		"cohesive":
			return "держаться вместе"
		_:
			return "сбалансированно"

func _combat_squad_or_demo() -> Array[CharacterData]:
	var squad: Array[CharacterData] = []
	var squad_limit := clampi(int(round(_battle_context.modifier_float("max_squad_size", float(Roster.MAX_SQUAD_SIZE)))), 1, 24)
	if not GameState.pending_combat_squad.is_empty():
		for cd in GameState.pending_combat_squad:
			if squad.size() >= squad_limit:
				break
			cd.ensure_combat_brain()
			squad.append(cd)
	elif GameState.roster != null and GameState.roster.get_character_count() > 0:
		for cd in GameState.roster.get_characters():
			if squad.size() >= squad_limit:
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

func _enemy_plan_for_context() -> Array:
	return _battle_context.enemy_plan.duplicate(true)

func _load_enemy_archetypes() -> void:
	_enemy_archetypes.clear()
	var file := FileAccess.open(ENEMY_ARCHETYPES_PATH, FileAccess.READ)
	if file == null:
		push_warning("RT enemy archetypes not found: " + ENEMY_ARCHETYPES_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		push_warning("RT enemy archetypes JSON is invalid.")
		return
	var parsed_data: Dictionary = data
	_enemy_archetypes = parsed_data.get("enemies", {})

func _apply_context_modifiers_to_units() -> void:
	var ally_fear := _battle_context.modifier_float("initial_ally_fear", 0.0)
	var enemy_morale := _battle_context.modifier_float("enemy_morale_bonus", 0.0)
	var low_visibility := _battle_context.modifier_float("low_visibility_stress", 0.0)
	for unit in _units:
		if unit.side == BattleUnit.UnitSide.ALLY:
			unit.fear = clampf(unit.fear + ally_fear, 0.0, 1.0)
			unit.visibility_stress = clampf(unit.visibility_stress + low_visibility, 0.0, 1.0)
		else:
			unit.morale = clampf(unit.morale + enemy_morale, 0.0, 1.0)

func _update_enemy_phases() -> void:
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ENEMY or not unit.is_alive():
			continue
		var activated_phases: Array = unit.activate_pending_enemy_phases()
		for phase in activated_phases:
			var phase_name := str(phase.get("name", "новая фаза"))
			var message := str(phase.get("message", "меняет тактику."))
			_log_line("%s: %s" % [unit.display_name, message])
			_add_floating_text(unit.world_position + Vector2(0, -34), phase_name, Color(1.0, 0.54, 0.22), 1.35, Vector2(0, -30))
			_add_visual_effect("ring", unit.world_position, unit.world_position, Color(1.0, 0.42, 0.18), 0.62, 30.0)

func _update_perception_and_intents() -> void:
	_perception.update(_units, _battlefield)
	_update_squad_context()
	_update_visibility_context()
	for unit in _units:
		if not unit.is_alive():
			continue
		if unit.lost_target_timer > 0.0 and unit.lost_target_notice_timer <= 0.0:
			_log_line("%s потерял цель." % unit.display_name)
			_add_floating_text(unit.world_position, "потерял цель", Color(0.7, 0.82, 0.95), 1.1, Vector2(0, -22))
			unit.lost_target_notice_timer = 2.0
		if unit.visible_enemies.is_empty() and unit.heard_noise_timer > 0.0 and unit.heard_noise_notice_timer <= 0.0:
			_log_line("%s слышит шум." % unit.display_name)
			_add_floating_text(unit.world_position, "слышит шум", Color(0.62, 0.9, 1.0), 1.1, Vector2(0, -22))
			unit.heard_noise_notice_timer = 2.5
		if unit.hidden and unit.stealth_notice_timer <= 0.0:
			_log_line("%s скрывается." % unit.display_name)
			_add_floating_text(unit.world_position, "скрыт", Color(0.52, 1.0, 0.64), 1.1, Vector2(0, -22))
			unit.stealth_notice_timer = 3.5
		var previous := str(_intents.get(unit.unit_id, {}).get("type", ""))
		var intent: Dictionary = _brain.choose_intent(unit, _units, _battlefield, _rng)
		_intents[unit.unit_id] = intent
		var current := str(intent.get("type", "hold"))
		_record_decision_usage(unit, current)
		if current != previous:
			_log_line("%s: %s (%s%s)." % [unit.display_name, _intent_label(current), intent.get("reason", ""), _intent_debug_suffix(intent)])
			_add_floating_text(unit.world_position, _intent_float_label(current), _intent_color(current), 1.15, Vector2(0, -22))
			if unit.side == BattleUnit.UnitSide.ALLY:
				_focus_unit_id = unit.unit_id

func _update_visibility_context() -> void:
	var leader = _get_unit_by_id(_leader_unit_id)
	for unit in _units:
		unit.visibility_stress = 0.0
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		var stress := _low_visibility_stress(unit)
		if leader != null and leader.is_alive() and leader != unit:
			var leader_distance: float = Vector2(unit.grid_pos - leader.grid_pos).length()
			if leader_distance <= 4.0:
				stress -= unit.brain_value("leader_trust") * (1.0 - leader_distance / 5.0) * 0.25
		unit.visibility_stress = clampf(stress, 0.0, 1.0)

func _low_visibility_stress(unit) -> float:
	var stress := 0.0
	if unit.visible_enemies.is_empty():
		if not unit.last_seen_enemies.is_empty():
			stress += 0.28
		if unit.lost_target_timer > 0.0:
			stress += 0.22
		if unit.heard_noise_timer > 0.0:
			stress += 0.24 * clampf(unit.heard_noise_strength, 0.35, 1.0)
	if _battlefield.is_grass(unit.grid_pos):
		stress += 0.1
	if _battlefield.is_dark(unit.grid_pos):
		stress += 0.24

	var local_visibility := _local_visibility_ratio(unit, 3)
	stress += clampf((0.42 - local_visibility) * 0.55, 0.0, 0.25)
	return clampf(stress, 0.0, 1.0)

func _local_visibility_ratio(unit, radius: int) -> float:
	var checked := 0
	var visible := 0
	for y in range(maxi(0, unit.grid_pos.y - radius), mini(_battlefield.height, unit.grid_pos.y + radius + 1)):
		for x in range(maxi(0, unit.grid_pos.x - radius), mini(_battlefield.width, unit.grid_pos.x + radius + 1)):
			var pos := Vector2i(x, y)
			if not _battlefield.is_walkable(pos):
				continue
			checked += 1
			if _ally_observes_tile(unit, pos):
				visible += 1
	if checked <= 0:
		return 1.0
	return float(visible) / float(checked)

func _update_player_knowledge() -> void:
	_player_visible_tiles.clear()
	for unit in _units:
		if not unit.is_alive() or unit.side != BattleUnit.UnitSide.ALLY:
			continue
		var radius := ceili(unit.vision_radius_tiles)
		for y in range(maxi(0, unit.grid_pos.y - radius), mini(_battlefield.height, unit.grid_pos.y + radius + 1)):
			for x in range(maxi(0, unit.grid_pos.x - radius), mini(_battlefield.width, unit.grid_pos.x + radius + 1)):
				var pos := Vector2i(x, y)
				if not _ally_observes_tile(unit, pos):
					continue
				_player_visible_tiles[pos] = true
				_player_known_tiles[pos] = true

func _ally_observes_tile(unit, pos: Vector2i) -> bool:
	var delta: Vector2 = Vector2(pos - unit.grid_pos)
	var distance: float = delta.length()
	if distance > unit.vision_radius_tiles:
		return false
	if distance > 1.25:
		var forward: Vector2 = unit.facing.normalized()
		if forward.length() <= 0.01:
			forward = Vector2.RIGHT
		var direction: Vector2 = delta.normalized()
		var angle: float = rad_to_deg(acos(clampf(forward.dot(direction), -1.0, 1.0)))
		if angle > unit.vision_angle_deg * 0.5:
			return false
	return _battlefield.has_line_of_sight(unit.grid_pos, pos)

func _unit_visible_to_player(unit) -> bool:
	if not _fog_of_war_enabled or _debug_perception_overlay:
		return true
	if unit.side == BattleUnit.UnitSide.ALLY:
		return true
	return bool(_player_visible_tiles.get(unit.grid_pos, false))

func _check_end() -> void:
	if _battle_finished:
		return
	var finish: Dictionary = _combat_controller.evaluate_finish(_units, _battle_context, _battle_elapsed_seconds)
	if finish.is_empty():
		return
	_battle_finish_reason = str(finish.get("reason", ""))
	_battle_finish_detail = str(finish.get("detail", ""))
	_finish_battle(bool(finish.get("victory", false)))

func _victory_condition_met(allies_alive: int, enemies_alive: int) -> bool:
	if allies_alive <= 0:
		return false
	var condition := _battle_context.victory_string("type", "eliminate_enemies")
	match condition:
		"survive_seconds":
			var seconds := _battle_context.victory_float("seconds", 45.0)
			if _battle_elapsed_seconds >= seconds:
				_battle_finish_reason = "survived"
				_battle_finish_detail = "Отряд продержался %s." % CombatResultScript.new().format_duration(seconds)
				return true
		"defeat_boss":
			if not _boss_enemy_alive():
				_battle_finish_reason = "boss_defeated"
				_battle_finish_detail = "Ключевая цель выведена из боя."
				return true
		_:
			if enemies_alive <= 0:
				_battle_finish_reason = "elimination"
				_battle_finish_detail = "Все враги выведены из боя."
				return true
	return false

func _defeat_condition_met(allies_alive: int, enemies_alive: int) -> bool:
	if allies_alive <= 0:
		_battle_finish_reason = "wipe"
		_battle_finish_detail = "Все союзники выведены из боя."
		return true
	var time_limit := _battle_context.defeat_float("time_limit_seconds", 0.0)
	if time_limit > 0.0 and _battle_elapsed_seconds >= time_limit and enemies_alive > 0:
		_battle_finish_reason = "time_limit"
		_battle_finish_detail = "Время боя вышло, отряд отходит."
		return true
	if not _battle_context.modifier_bool("retreat_enabled", true):
		return false
	var retreat_after := _battle_context.defeat_float("retreat_after_seconds", 14.0)
	if _battle_elapsed_seconds < retreat_after or enemies_alive <= 0:
		return false
	var threshold := _battle_context.modifier_float("heavy_loss_threshold", 0.3)
	var total_allies := maxi(1, _unit_count_for_side(BattleUnit.UnitSide.ALLY))
	var living_ratio := float(allies_alive) / float(total_allies)
	if living_ratio <= threshold or _all_living_allies_critical():
		_battle_finish_reason = "retreat"
		_battle_finish_detail = "Отряд потерял строй и отступил до полного уничтожения."
		return true
	return false

func _boss_enemy_alive() -> bool:
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ENEMY or not unit.is_alive():
			continue
		if unit.display_name.find("Хранитель") >= 0 or unit.enemy_danger >= 5.5:
			return true
	return false

func _unit_count_for_side(side: int) -> int:
	var count := 0
	for unit in _units:
		if unit.side == side:
			count += 1
	return count

func _all_living_allies_critical() -> bool:
	var living := 0
	var critical := 0
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		living += 1
		if unit.hp_ratio() <= 0.22 or unit.has_status("broken"):
			critical += 1
	return living > 0 and critical >= living

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
	var leader = _get_unit_by_id(_leader_unit_id)
	var leader_name: String = leader.display_name if leader != null else "нет"
	_status_label.text = "%s  |  %s\nЖивые: союзники %d / враги %d\nЛидер: %s, стиль: %s  |  Контактов: %d  |  %.1fx%s%s" % [
		_mode_label(),
		CombatResultScript.new().format_duration(_battle_elapsed_seconds),
		allies,
		enemies,
		leader_name,
		_squad_style_label(_squad_style),
		visible_contacts,
		_time_scale,
		"  |  Пауза" if _paused else "",
		"  |  AI freeze" if _freeze_ai else ""
	]
	_refresh_focus_panel()
	_refresh_unit_list()

func _log_line(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > _combat_config.max_log_lines:
		_log_lines.remove_at(0)
	_log_label.text = "\n".join(_log_lines)
	if _bottom_label != null:
		_bottom_label.text = "Последнее событие: " + message

func _record_timeline(kind: String, text: String, importance: int = 1) -> void:
	_event_collector.record_timeline(_battle_elapsed_seconds, kind, text, importance, 24)
	_battle_timeline = _event_collector.timeline.duplicate(true)

func _record_process_time(started_usec: int) -> void:
	_event_collector.record_process_time(started_usec)
	_max_process_usec = _event_collector.max_process_usec

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

func _play_step_cue(tile_type: int) -> void:
	match tile_type:
		BattlefieldScript.TileType.WATER:
			_play_audio_cue("step_water")
		BattlefieldScript.TileType.DOOR, BattlefieldScript.TileType.NARROW:
			_play_audio_cue("step_door")
		_:
			if _rng.randf() < 0.12:
				_play_audio_cue("step")

func _play_audio_cue(kind: String) -> void:
	_audio_service.play(kind)

func _finish_battle(victory: bool) -> void:
	if _battle_finished:
		return
	_battle_finished = true
	_session.mark_finished(_battle_finish_reason, _battle_finish_detail)
	_pause_btn.disabled = true
	_speed_btn.disabled = true
	_update_combat_brains(victory)

	var applied_rewards: Dictionary = _post_battle_service.apply(
		victory,
		_battle_context,
		_units,
		_battle_elapsed_seconds,
		_combat_config.seed_label()
	)
	_record_timeline("finish", _battle_finish_detail if _battle_finish_detail != "" else ("Победа" if victory else "Поражение"), 3)
	_last_result = _build_combat_result(victory, applied_rewards)
	GameState.record_combat_result(_last_result.to_balance_record())
	_log_line(_last_result.summary_line())
	_show_end_panel(victory, applied_rewards)
	_play_audio_cue("victory" if victory else "defeat")
	_log_line("RT-бой завершён: %s." % ("отряд выжил" if victory else "отряд уничтожен"))

func _build_combat_result(victory: bool, applied_rewards: Dictionary):
	var result = CombatResultScript.new()
	result.setup_from_battle(
		victory,
		_battle_context,
		_combat_config,
		_units,
		_battle_damage_dealt,
		_battle_healing_done,
		_battle_ability_usage,
		_battle_decision_usage,
		applied_rewards,
		_battle_elapsed_seconds
	)
	result.finish_reason = _battle_finish_reason
	result.finish_detail = _battle_finish_detail
	result.timeline = _event_collector.timeline.duplicate(true)
	result.max_tick_ms = _event_collector.max_tick_ms()
	return result

func _show_end_panel(victory: bool, applied_rewards: Dictionary) -> void:
	_end_panel.visible = true
	_style_end_panel_result(victory)
	_repeat_btn.visible = _battle_context.is_demo()
	if victory:
		_end_title.text = "Победа!"
		if _battle_context.is_tower():
			_end_btn.text = "В башню"
		elif _battle_context.is_raid():
			_end_btn.text = "К вылазке"
		else:
			_end_btn.text = "В город"
	else:
		_end_title.text = "Поражение"
		_end_btn.text = "В город"
		if _battle_context.is_raid():
			_end_btn.text = "К вылазке"
	_update_end_tabs(victory, applied_rewards)

func _style_end_panel_result(victory: bool) -> void:
	_ui_controller.apply_end_panel_style(_end_panel, _end_title, _end_btn, victory)

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

func _end_result_text(victory: bool, applied_rewards: Dictionary) -> String:
	var sections: PackedStringArray = []
	sections.append(_end_context_text(victory))
	var consequence := _battle_context.consequence_text(victory)
	if consequence != "":
		sections.append(consequence)
	sections.append(_end_rewards_text(victory, applied_rewards))
	var death_text := _end_death_text()
	if death_text != "":
		sections.append(death_text)
	sections.append(_end_unit_summary_text())
	sections.append(_end_stats_text())
	var replay_text: String = _end_replay_text()
	if replay_text != "":
		sections.append(replay_text)
	var lessons_text: String = _end_lessons_text()
	if lessons_text != "":
		sections.append(lessons_text)
	return "\n\n".join(sections)

func _update_end_tabs(victory: bool, applied_rewards: Dictionary) -> void:
	if _end_detail != null:
		_end_detail.text = "\n\n".join([
			_end_context_text(victory),
			_end_stats_text(),
			_end_replay_text()
		]).strip_edges()
	if _end_heroes_detail != null:
		_end_heroes_detail.text = _end_unit_summary_text()
	if _end_enemies_detail != null:
		_end_enemies_detail.text = _end_enemy_summary_text()
	if _end_rewards_detail != null:
		var reward_lines: PackedStringArray = []
		var consequence := _battle_context.consequence_text(victory)
		if consequence != "":
			reward_lines.append(consequence)
		reward_lines.append(_end_rewards_text(victory, applied_rewards))
		_end_rewards_detail.text = "\n\n".join(reward_lines)
	if _end_lessons_detail != null:
		var lessons := _end_lessons_text()
		_end_lessons_detail.text = lessons if lessons != "" else "Уроки: нет новых наблюдений."
	if _end_deaths_detail != null:
		var death_text := _end_death_text()
		_end_deaths_detail.text = death_text if death_text != "" else "Павшие: нет."

func _end_context_text(victory: bool) -> String:
	var detail_suffix := ""
	if _battle_finish_detail != "":
		detail_suffix = "\n" + _battle_finish_detail
	if victory:
		if _battle_context.is_tower():
			return "%s пройден. Следующий этаж: %d.%s" % [
				_battle_context.floor_name,
				_battle_context.next_tower_floor(),
				detail_suffix
			]
		if _battle_context.is_raid():
			return "Враги разбиты. Отряд продолжает вылазку.%s" % detail_suffix
		return "Враги разбиты. Отряд возвращается в город.%s" % detail_suffix

	if _battle_context.is_raid():
		return "Отряд отступил из события вылазки.%s" % detail_suffix
	return "Бой проигран. Выжившие герои обновлены в ростере.%s" % detail_suffix

func _end_rewards_text(victory: bool, applied_rewards: Dictionary) -> String:
	if not victory:
		return "Награда: нет."
	if _battle_context.is_raid():
		return "Награда события: %s\nБудет добавлена к итогам вылазки." % _format_rewards(_battle_context.reward_data)
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
		if not unit.is_alive():
			continue
		lines.append("%s: %d/%d HP" % [
			_short_name(unit.display_name),
			unit.battle_unit.current_hp,
			unit.battle_unit.max_hp
		])
	if lines.is_empty():
		return "Выжившие: нет."
	return "Выжившие:\n%s" % "\n".join(lines)

func _end_enemy_summary_text() -> String:
	var alive_lines: PackedStringArray = []
	var defeated_lines: PackedStringArray = []
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ENEMY:
			continue
		var line := "%s: %d/%d HP" % [
			_short_name(unit.display_name),
			unit.battle_unit.current_hp,
			unit.battle_unit.max_hp
		]
		if unit.is_alive():
			alive_lines.append(line)
		else:
			defeated_lines.append(_short_name(unit.display_name))
	var sections: PackedStringArray = []
	sections.append("Остались:\n%s" % ("\n".join(alive_lines) if not alive_lines.is_empty() else "нет"))
	sections.append("Выведены:\n%s" % ("\n".join(defeated_lines) if not defeated_lines.is_empty() else "нет"))
	return "\n\n".join(sections)

func _end_death_text() -> String:
	var lines: PackedStringArray = []
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.is_alive():
			continue
		var cause: String = str(unit.last_damage_cause)
		var killer: String = str(unit.last_damage_source_name)
		var detail: String = cause if cause != "" else "неизвестно"
		if killer != "":
			detail = "%s, %s" % [cause, killer]
		lines.append("%s: погиб (%s)" % [_short_name(unit.display_name), detail])
	if lines.is_empty():
		return ""
	return "Павшие:\n%s" % "\n".join(lines)

func _end_stats_text() -> String:
	if _last_result != null:
		return _last_result.stats_text()
	return "Статистика: нет данных."

func _end_replay_text() -> String:
	if _last_result != null:
		return _last_result.replay_summary_text(8)
	return ""

func _end_lessons_text() -> String:
	var lines: PackedStringArray = []
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		var lessons: Array = unit.character_data.combat_brain.get("lessons", [])
		if lessons.is_empty():
			continue
		lines.append("%s: %s" % [
			_short_name(unit.display_name),
			str(lessons[lessons.size() - 1])
		])
		if lines.size() >= 3:
			break
	if lines.is_empty():
		return ""
	return "Уроки:\n%s" % "\n".join(lines)

func _track_memory_context(delta: float) -> void:
	var leader = _get_unit_by_id(_leader_unit_id)
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null or not unit.is_alive():
			continue
		var char_id: String = unit.character_data.id
		if _battlefield.is_cover(unit.grid_pos) or _battlefield.is_grass(unit.grid_pos):
			_battle_cover_seconds[char_id] = float(_battle_cover_seconds.get(char_id, 0.0)) + delta
		if _nearby_living_ally_count(unit, 4.0) == 0:
			_battle_alone_seconds[char_id] = float(_battle_alone_seconds.get(char_id, 0.0)) + delta
		if unit.visibility_stress >= 0.32:
			_battle_low_visibility_seconds[char_id] = float(_battle_low_visibility_seconds.get(char_id, 0.0)) + delta * unit.visibility_stress
		if leader != null and leader.is_alive() and leader != unit:
			if Vector2(unit.grid_pos - leader.grid_pos).length() <= 5.0:
				_battle_near_leader_seconds[char_id] = float(_battle_near_leader_seconds.get(char_id, 0.0)) + delta

func _record_decision_usage(unit, intent_type: String) -> void:
	if unit == null or unit.side != BattleUnit.UnitSide.ALLY:
		return
	var key := intent_type
	if key == "":
		key = "hold"
	_battle_decision_usage[key] = int(_battle_decision_usage.get(key, 0)) + 1

func _nearby_living_ally_count(unit, radius_tiles: float) -> int:
	var count := 0
	for other in _units:
		if other == unit or other.side != unit.side or not other.is_alive():
			continue
		if Vector2(other.grid_pos - unit.grid_pos).length() <= radius_tiles:
			count += 1
	return count

func _record_resolver_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type not in ["ability_used", "area", "ambush", "damage", "heal", "buff", "status_damage", "step", "terrain_destroyed", "door_opened", "trap_avoided"]:
		return
	if event_type == "step":
		_play_step_cue(int(event.get("tile", BattlefieldScript.TileType.FLOOR)))
		return
	if event_type == "door_opened":
		var door_user = event.get("attacker", null)
		var door_pos: Vector2i = event.get("tile_pos", Vector2i.ZERO)
		var door_world: Vector2 = _battlefield.world_from_grid(door_pos, MAP_ORIGIN)
		_add_visual_effect("ring", door_world, door_world, Color(0.76, 0.9, 1.0), 0.32, 15.0)
		_add_floating_text(door_world + Vector2(0, -18), "дверь", Color(0.76, 0.9, 1.0), 0.8, Vector2(0, -22))
		_play_audio_cue("door")
		if door_user != null:
			_record_timeline("terrain", "%s открывает дверь" % door_user.display_name, 1)
		return
	if event_type == "trap_avoided":
		var trap_target = event.get("target", null)
		if trap_target != null:
			_add_floating_text(trap_target.world_position + Vector2(0, -24), "обошёл", Color(0.72, 1.0, 0.58), 0.9, Vector2(0, -24))
			_add_visual_effect("ring", trap_target.world_position, trap_target.world_position, Color(0.72, 1.0, 0.58), 0.28, 14.0)
			_play_audio_cue("step")
		return
	if event_type == "status_damage":
		var status_target = event.get("target", null)
		var status_amount := int(event.get("amount", 0))
		if status_target != null and status_amount > 0:
			if status_target.character_data != null:
				var target_char_id: String = status_target.character_data.id
				_battle_damage_taken[target_char_id] = int(_battle_damage_taken.get(target_char_id, 0)) + status_amount
			_add_visual_effect("ring", status_target.world_position, status_target.world_position, Color(0.62, 1.0, 0.32), 0.34, 16.0)
			_add_floating_text(status_target.world_position + Vector2(0, -18), "-%d яд" % status_amount, Color(0.62, 1.0, 0.32), 1.0, Vector2(0, -30))
			_play_audio_cue("hit")
		return
	var attacker = event.get("attacker", null)
	var target = event.get("target", null)
	if attacker == null:
		return
	var amount := int(event.get("amount", 0))
	var friendly_fire := bool(event.get("friendly_fire", false))
	var ability: AbilityData = event.get("ability", null)
	if event_type == "ability_used":
		if ability != null:
			var ability_name := ability.name
			_battle_ability_usage[ability_name] = int(_battle_ability_usage.get(ability_name, 0)) + 1
			if attacker.side == BattleUnit.UnitSide.ALLY:
				_record_timeline("ability", "%s использует %s" % [attacker.display_name, ability_name], 1)
		return
	if event_type == "terrain_destroyed":
		var tile_pos: Vector2i = event.get("tile_pos", Vector2i.ZERO)
		var world_pos: Vector2 = _battlefield.world_from_grid(tile_pos, MAP_ORIGIN)
		_add_visual_effect("ring", world_pos, world_pos, Color(0.86, 0.66, 0.36), 0.52, 20.0)
		_add_floating_text(world_pos + Vector2(0, -18), "сломано", Color(0.9, 0.72, 0.42), 1.0, Vector2(0, -24))
		_play_audio_cue("hit")
		_record_timeline("terrain", "Разрушено препятствие", 1)
		return
	if event_type == "area":
		var center: Vector2 = event.get("center", Vector2.ZERO)
		var radius_pixels := maxf(18.0, float(event.get("radius_tiles", 0.0)) * _battlefield.tile_size())
		var area_color := _ability_event_color(ability, "damage")
		_add_visual_effect("line", attacker.world_position, center, area_color, 0.22, 0.0)
		_add_visual_effect("area", center, center, area_color, 0.48, radius_pixels)
		var target_count := int(event.get("target_count", 0))
		if target_count > 1:
			_add_floating_text(center + Vector2(0, -18), "область x%d" % target_count, area_color, 0.9, Vector2(0, -22))
		_play_audio_cue("spell")
		return
	if event_type == "ambush":
		if target != null:
			if attacker.character_data != null:
				_add_character_action_score(attacker.character_data.id, "Засада", amount)
			_focus_unit_id = attacker.unit_id if attacker.side == BattleUnit.UnitSide.ALLY else target.unit_id
			_add_visual_effect("line", attacker.world_position, target.world_position, Color(0.72, 1.0, 0.36), 0.32, 0.0)
			_add_visual_effect("ring", attacker.world_position, attacker.world_position, Color(0.72, 1.0, 0.36), 0.48, 24.0)
			_add_floating_text(attacker.world_position + Vector2(0, -30), "засада", Color(0.72, 1.0, 0.36), 1.15, Vector2(0, -26))
			_play_audio_cue("attack")
			_record_timeline("ambush", "%s атакует из засады" % attacker.display_name, 2)
		return
	if event_type == "damage" and amount > 0 and attacker.character_data != null and not friendly_fire:
		var char_id: String = attacker.character_data.id
		_battle_damage_dealt[char_id] = int(_battle_damage_dealt.get(char_id, 0)) + amount
		_add_character_action_score(char_id, _action_memory_label(ability, "Атака"), amount)
		if target != null and _is_ranged_combat_event(attacker, target, ability):
			_battle_ranged_damage[char_id] = int(_battle_ranged_damage.get(char_id, 0)) + amount
	elif event_type == "heal" and amount > 0 and attacker.character_data != null:
		var char_id: String = attacker.character_data.id
		_battle_healing_done[char_id] = int(_battle_healing_done.get(char_id, 0)) + amount
		_add_character_action_score(char_id, _action_memory_label(ability, "Лечение"), amount)
	elif event_type == "buff" and attacker.character_data != null:
		_add_character_action_score(attacker.character_data.id, _action_memory_label(ability, "Поддержка"), 1)
	if target != null and event_type == "damage" and amount > 0 and target.character_data != null:
		var target_char_id: String = target.character_data.id
		_battle_damage_taken[target_char_id] = int(_battle_damage_taken.get(target_char_id, 0)) + amount
		if attacker.side == BattleUnit.UnitSide.ENEMY:
			var danger_weight := 1.0 + maxf(0.0, float(attacker.enemy_danger) - 1.0) * 0.35
			var memory_amount := maxi(1, roundi(float(amount) * danger_weight))
			_add_nested_score(_battle_dangerous_enemies, target_char_id, _enemy_memory_key(attacker), memory_amount)
	elif target != null and event_type in ["heal", "buff"] and target.character_data != null and attacker.character_data != null and attacker != target:
		var helped_char_id: String = target.character_data.id
		_battle_help_received[helped_char_id] = int(_battle_help_received.get(helped_char_id, 0)) + maxi(1, amount)
	if target != null and event_type == "damage" and amount > 0:
		_focus_unit_id = attacker.unit_id if attacker.side == BattleUnit.UnitSide.ALLY else target.unit_id
		var hit_color := Color(1.0, 0.34, 0.24) if target.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.86, 0.28)
		var effect_color := _ability_event_color(ability, event_type)
		if ability == null or ability.rt_radius_tiles <= 0.0:
			_add_visual_effect("line", attacker.world_position, target.world_position, effect_color, 0.24, 0.0)
		_add_visual_effect("ring", target.world_position, target.world_position, hit_color, 0.34, 17.0)
		_add_floating_text(target.world_position + Vector2(0, -16), "-%d" % amount, hit_color, 1.0, Vector2(0, -34))
		_play_audio_cue("hit")
		if not target.is_alive():
			_add_floating_text(target.world_position + Vector2(0, -32), "выведен", Color(0.95, 0.95, 0.95), 1.4, Vector2(0, -24))
			_apply_death_shock(target, attacker)
			if target.side == BattleUnit.UnitSide.ALLY:
				_play_audio_cue("death")
				_auto_pause_for_important_event()
			_record_timeline("death", "%s выведен из боя" % target.display_name, 3 if target.side == BattleUnit.UnitSide.ALLY else 2)
	elif target != null and event_type == "heal" and amount > 0:
		_focus_unit_id = target.unit_id
		_add_visual_effect("line", attacker.world_position, target.world_position, _ability_event_color(ability, event_type), 0.28, 0.0)
		_add_visual_effect("ring", target.world_position, target.world_position, Color(0.35, 1.0, 0.55), 0.42, 19.0)
		_add_floating_text(target.world_position + Vector2(0, -16), "+%d" % amount, Color(0.35, 1.0, 0.55), 1.0, Vector2(0, -30))
		_play_audio_cue("heal")
	elif target != null and event_type == "buff":
		_focus_unit_id = target.unit_id
		var label := ability.name if ability != null else "бафф"
		_add_visual_effect("ring", target.world_position, target.world_position, _ability_event_color(ability, event_type), 0.5, 21.0)
		_add_floating_text(target.world_position + Vector2(0, -18), label, Color(0.45, 0.82, 1.0), 1.05, Vector2(0, -24))
		_play_audio_cue("buff")

func _apply_death_shock(dead_unit, attacker) -> void:
	if dead_unit == null or dead_unit.death_shock_emitted:
		return
	dead_unit.death_shock_emitted = true
	for unit in _units:
		if unit == dead_unit or not unit.is_alive():
			continue
		var distance: float = Vector2(unit.grid_pos - dead_unit.grid_pos).length()
		if unit.side == dead_unit.side:
			var shock: float = clampf(0.18 - distance * 0.018, 0.04, 0.18)
			if dead_unit.is_leader:
				shock += 0.16
			elif distance <= 3.5:
				shock += 0.05
			if unit.is_leader:
				shock *= 0.78
			unit.fear = clampf(unit.fear + shock, 0.0, 1.0)
			unit.morale = clampf(unit.morale - shock * 0.72, 0.0, 1.0)
			if unit.morale <= 0.12:
				unit.add_status("broken", 3.0)
			elif unit.fear >= 0.72:
				unit.add_status("panic", 2.2)
		elif attacker != null and attacker == unit:
			unit.fear = clampf(unit.fear - 0.04, 0.0, 1.0)
			unit.morale = clampf(unit.morale + 0.04, 0.0, 1.0)

func _add_character_action_score(char_id: String, action_name: String, amount: int) -> void:
	if char_id == "":
		return
	_add_nested_score(_battle_successful_actions, char_id, action_name, amount)

func _add_nested_score(store: Dictionary, owner_id: String, key: String, amount: int) -> void:
	if owner_id == "" or key == "" or amount <= 0:
		return
	var values: Dictionary = store.get(owner_id, {})
	values[key] = int(values.get(key, 0)) + amount
	store[owner_id] = values

func _action_memory_label(ability: AbilityData, fallback: String) -> String:
	if ability != null and ability.name != "":
		return ability.name
	return fallback

func _enemy_memory_key(unit) -> String:
	if unit == null:
		return "неизвестный враг"
	var label: String = unit.display_name.to_lower()
	if label.begins_with("орк"):
		return "орк"
	if label.begins_with("тролль"):
		return "тролль"
	if label.begins_with("хранитель"):
		return "хранитель"
	if label.begins_with("гоблин"):
		return "гоблин"
	return unit.display_name

func _is_ranged_combat_event(attacker, target, ability: AbilityData) -> bool:
	if attacker == null or target == null:
		return false
	if Vector2(attacker.grid_pos - target.grid_pos).length() > 2.25:
		return true
	return ability != null and attacker.ability_range_tiles(ability) > 2.25

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
		unit.character_data.record_combat_memory({
			"victory": victory,
			"damage_dealt": int(_battle_damage_dealt.get(char_id, 0)),
			"healing_done": int(_battle_healing_done.get(char_id, 0)),
			"damage_taken": int(_battle_damage_taken.get(char_id, 0)),
			"damage_taken_ratio": damage_taken_ratio,
			"successful_actions": _battle_successful_actions.get(char_id, {}),
			"dangerous_enemies": _battle_dangerous_enemies.get(char_id, {}),
			"help_received": int(_battle_help_received.get(char_id, 0)),
			"cover_seconds": float(_battle_cover_seconds.get(char_id, 0.0)),
			"alone_seconds": float(_battle_alone_seconds.get(char_id, 0.0)),
			"low_visibility_seconds": float(_battle_low_visibility_seconds.get(char_id, 0.0)),
			"near_leader_seconds": float(_battle_near_leader_seconds.get(char_id, 0.0)),
			"leader_alive": _leader_is_alive(),
			"was_leader": unit.is_leader,
			"ranged_damage": int(_battle_ranged_damage.get(char_id, 0)),
			"hp_ratio": unit.hp_ratio()
		})

func _leader_is_alive() -> bool:
	var leader = _get_unit_by_id(_leader_unit_id)
	return leader != null and leader.is_alive()

func _format_rewards(rewards: Dictionary) -> String:
	return _ui_formatter.format_rewards(rewards)

func _mode_label() -> String:
	return _ui_formatter.mode_label(_battle_context)

func _draw() -> void:
	_draw_background()
	_draw_map()
	_draw_tactical_overlays()
	_draw_fog_of_war()
	_draw_unit_vision()
	if _debug_perception_overlay:
		_draw_debug_perception()
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
			if _battlefield.is_height(pos):
				draw_rect(rect.grow(-7.0), Color(1.0, 0.86, 0.28, 0.18))
			elif _battlefield.is_trap(pos):
				_draw_tile_brackets(rect.grow(-6.0), Color(1.0, 0.18, 0.12, 0.58), 6.0, 1.8)

func _draw_fog_of_war() -> void:
	if not _fog_of_war_enabled or _debug_perception_overlay:
		return
	for y in _battlefield.height:
		for x in _battlefield.width:
			var pos := Vector2i(x, y)
			if bool(_player_visible_tiles.get(pos, false)):
				continue
			var rect := _tile_rect(pos)
			if bool(_player_known_tiles.get(pos, false)):
				draw_rect(rect, Color(0.02, 0.025, 0.032, 0.34))
			else:
				draw_rect(rect, Color(0.0, 0.0, 0.0, 0.68))
	_draw_last_known_contacts()

func _draw_last_known_contacts() -> void:
	var font := get_theme_default_font()
	var marked_positions: Dictionary = {}
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		for memory_value in unit.last_seen_enemies.values():
			if not (memory_value is Dictionary):
				continue
			var memory: Dictionary = memory_value
			var pos: Vector2i = memory.get("pos", unit.grid_pos)
			if bool(_player_visible_tiles.get(pos, false)) or marked_positions.has(pos):
				continue
			marked_positions[pos] = true
			var center: Vector2 = _battlefield.world_from_grid(pos, MAP_ORIGIN)
			_draw_tile_brackets(_tile_rect(pos).grow(-8.0), Color(1.0, 0.72, 0.28, 0.58), 7.0, 1.6)
			draw_string(font, center + Vector2(-9, 4), "?", HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color(1.0, 0.78, 0.34, 0.8))

func _draw_unit_vision() -> void:
	for unit in _units:
		if not unit.is_alive():
			continue
		var color := Color(0.2, 0.8, 1.0, 0.09) if unit.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.25, 0.18, 0.08)
		draw_colored_polygon(_vision_polygon(unit), color)

func _draw_debug_perception() -> void:
	var font := get_theme_default_font()
	for unit in _units:
		if not unit.is_alive():
			continue
		var color := Color(0.35, 0.9, 1.0, 0.5) if unit.side == BattleUnit.UnitSide.ALLY else Color(1.0, 0.38, 0.28, 0.48)
		var radius: float = unit.vision_radius_tiles * _battlefield.tile_size()
		var facing_angle: float = unit.facing.angle()
		var half_angle := deg_to_rad(unit.vision_angle_deg * 0.5)
		draw_arc(unit.world_position, radius, facing_angle - half_angle, facing_angle + half_angle, 24, color, 1.3, true)
		draw_line(unit.world_position, unit.world_position + Vector2(cos(facing_angle - half_angle), sin(facing_angle - half_angle)) * radius, Color(color.r, color.g, color.b, 0.28), 1.0)
		draw_line(unit.world_position, unit.world_position + Vector2(cos(facing_angle + half_angle), sin(facing_angle + half_angle)) * radius, Color(color.r, color.g, color.b, 0.28), 1.0)
		for enemy in unit.visible_enemies:
			if enemy == null or not enemy.is_alive():
				continue
			draw_line(unit.world_position, enemy.world_position, Color(0.42, 1.0, 0.55, 0.72), 1.6)
		for memory_value in unit.last_seen_enemies.values():
			if not (memory_value is Dictionary):
				continue
			var memory: Dictionary = memory_value
			var pos: Vector2i = memory.get("pos", unit.grid_pos)
			var rect := _tile_rect(pos).grow(-8.0)
			_draw_tile_brackets(rect, Color(1.0, 0.72, 0.28, 0.72), 6.0, 1.5)
		if unit.heard_noise_timer > 0.0:
			var noise_world: Vector2 = _battlefield.world_from_grid(unit.heard_noise_pos, MAP_ORIGIN)
			var noise_color := Color(0.5, 0.85, 1.0, 0.56)
			draw_arc(noise_world, 12.0 + unit.heard_noise_timer * 3.0, 0.0, TAU, 28, noise_color, 1.8, true)
			draw_line(unit.world_position, noise_world, Color(noise_color.r, noise_color.g, noise_color.b, 0.28), 1.0)
			draw_string(font, noise_world + Vector2(-18, -14), "noise", HORIZONTAL_ALIGNMENT_CENTER, 36, 9, noise_color)
	_draw_debug_formations(font)

func _draw_debug_formations(font: Font) -> void:
	var marked_slots: Dictionary = {}
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		if unit.formation_slot == Vector2i.ZERO or not _battlefield.in_bounds(unit.formation_slot):
			continue

		var color := Color(0.64, 0.88, 1.0, 0.68)
		if unit.is_leader:
			color = Color(1.0, 0.82, 0.28, 0.72)
		var slot_center: Vector2 = _battlefield.world_from_grid(unit.formation_slot, MAP_ORIGIN)
		if unit.grid_pos != unit.formation_slot:
			draw_line(unit.world_position, slot_center, Color(color.r, color.g, color.b, 0.26), 1.0)
		if marked_slots.has(unit.formation_slot):
			continue

		marked_slots[unit.formation_slot] = true
		var rect := _tile_rect(unit.formation_slot).grow(-10.0)
		_draw_tile_brackets(rect, color, 7.0, 1.4)
		var label := _formation_role_label(unit.formation_role).substr(0, 1).to_upper()
		draw_string(font, rect.position + Vector2(6, 15), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 12, 10, color)

func _draw_paths() -> void:
	for unit in _units:
		if not unit.is_alive() or unit.path.is_empty():
			continue
		if not _unit_visible_to_player(unit):
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
	_draw_fallen_bodies(font)
	for unit in _units:
		if not unit.is_alive():
			continue
		if not _unit_visible_to_player(unit):
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

func _draw_fallen_bodies(font: Font) -> void:
	for unit in _units:
		if unit.is_alive() or unit.body_remove_timer <= 0.0:
			continue
		if not _unit_visible_to_player(unit):
			continue
		var alpha := clampf(unit.body_remove_timer / 8.0, 0.0, 0.72)
		var center: Vector2 = unit.world_position
		var color := Color(0.18, 0.16, 0.14, alpha)
		draw_circle(center, 13.0, color)
		draw_line(center + Vector2(-8, -8), center + Vector2(8, 8), Color(0.95, 0.78, 0.58, alpha), 2.0)
		draw_line(center + Vector2(8, -8), center + Vector2(-8, 8), Color(0.95, 0.78, 0.58, alpha), 2.0)
		draw_string(font, center + Vector2(-18, 28), _short_name(unit.display_name), HORIZONTAL_ALIGNMENT_LEFT, 56, 10, Color(0.78, 0.72, 0.66, alpha))

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

	if unit.hidden:
		draw_arc(center, 24.0, 0.0, TAU, 36, Color(0.45, 1.0, 0.64, 0.72), 1.6, true)
	elif unit.stealth_reveal_timer > 0.0:
		draw_arc(center, 23.0, 0.0, TAU, 36, Color(1.0, 0.82, 0.34, 0.42), 1.2, true)

	if _unit_is_leader(unit):
		var badge_center := center + Vector2(-15, -15)
		draw_circle(badge_center, 6.5, Color(0.05, 0.04, 0.02, 0.9))
		draw_circle(badge_center, 5.0, Color(1.0, 0.78, 0.25))
		draw_string(font, badge_center + Vector2(-4, 3), "L", HORIZONTAL_ALIGNMENT_CENTER, 8, 7, Color(0.08, 0.06, 0.02))

	_draw_unit_icon(center, unit, Color(0.98, 0.98, 0.92))

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

func _draw_unit_icon(center: Vector2, unit, color: Color) -> void:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			draw_arc(center, 7.0, PI * 0.12, PI * 1.88, 20, color, 2.0, true)
			draw_line(center + Vector2(-5, 4), center + Vector2(5, 4), color, 2.0)
		elif unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			draw_line(center + Vector2(0, -8), center + Vector2(7, 5), color, 2.0)
			draw_line(center + Vector2(7, 5), center + Vector2(-7, 5), color, 2.0)
			draw_line(center + Vector2(-7, 5), center + Vector2(0, -8), color, 2.0)
		else:
			draw_line(center + Vector2(-7, -4), center + Vector2(0, 7), color, 2.0)
			draw_line(center + Vector2(7, -4), center + Vector2(0, 7), color, 2.0)
		return
	match _unit_class_id(unit):
		"healer":
			draw_line(center + Vector2(-7, 0), center + Vector2(7, 0), color, 2.4)
			draw_line(center + Vector2(0, -7), center + Vector2(0, 7), color, 2.4)
		"mage":
			var gem := PackedVector2Array([
				center + Vector2(0, -8),
				center + Vector2(8, 0),
				center + Vector2(0, 8),
				center + Vector2(-8, 0)
			])
			draw_polyline(gem, color, 2.0, true)
			draw_circle(center, 2.5, color)
		"scout", "assassin":
			draw_line(center + Vector2(-7, 5), center + Vector2(0, -7), color, 2.2)
			draw_line(center + Vector2(0, -7), center + Vector2(7, 5), color, 2.2)
			draw_line(center + Vector2(-3, 3), center + Vector2(3, 3), color, 1.8)
		"defender", "guardian", "tank":
			draw_line(center + Vector2(-7, -6), center + Vector2(7, -6), color, 2.0)
			draw_line(center + Vector2(7, -6), center + Vector2(5, 5), color, 2.0)
			draw_line(center + Vector2(5, 5), center + Vector2(0, 8), color, 2.0)
			draw_line(center + Vector2(0, 8), center + Vector2(-5, 5), color, 2.0)
			draw_line(center + Vector2(-5, 5), center + Vector2(-7, -6), color, 2.0)
		_:
			draw_line(center + Vector2(-6, 7), center + Vector2(7, -6), color, 2.2)
			draw_line(center + Vector2(2, -7), center + Vector2(8, -1), color, 1.8)

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
		["Темнота", _tile_color(BattlefieldScript.TileType.DARK)],
		["Ловушка", _tile_color(BattlefieldScript.TileType.TRAP)],
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
	return _combat_renderer.tile_color(tile)

func _unit_class_id(unit) -> String:
	if unit == null or unit.character_data == null:
		return ""
	return str(unit.character_data.character_class).to_lower()

func _unit_shape(unit) -> String:
	return _combat_renderer.unit_shape(unit)

func _unit_icon(unit) -> String:
	return _combat_renderer.unit_icon(unit)

func _unit_base_color(unit) -> Color:
	return _combat_renderer.unit_base_color(unit)

func _unit_outline_color(unit) -> Color:
	return _combat_renderer.unit_outline_color(unit, _focus_unit_id)

func _unit_is_leader(unit) -> bool:
	return unit.side == BattleUnit.UnitSide.ALLY and unit.is_leader

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
		"flank":
			return "обходит"
		"retreat":
			return "отступает"
		"keep_distance":
			return "дистанция"
		"take_cover":
			return "укрытие"
		"follow":
			return "рядом"
		"patrol":
			return "поиск"
		"ambush":
			return "засада"
		"guard_ally":
			return "прикрывает"
		"support_backline":
			return "задняя линия"
		"rally_leader":
			return "к лидеру"
		"group_retreat":
			return "общий отход"
		"formation":
			return "строй"
		"press_attack":
			return "напор"
		"hold_line":
			return "держит линию"
		"hold_choke":
			return "проход"
		"safe_los":
			return "позиция"
		"panic_seek_ally":
			return "к союзнику"
		"scout_probe":
			return "разведка"
		"scout_flank":
			return "фланг"
		"break_contact":
			return "разрыв"
		"assassin_pickoff":
			return "добивание"
		"berserk_charge":
			return "натиск"
		"tactical_position":
			return "тактика"
		"hold":
			return "ждёт"
		_:
			return intent

func _short_name(value: String) -> String:
	return _ui_formatter.short_name(value)

func _intent_debug_suffix(intent: Dictionary) -> String:
	if not _debug_perception_overlay:
		return ""
	var score := float(intent.get("score", 0.0))
	var confidence := float(intent.get("confidence", 0.0)) * 100.0
	var suffix := ", оценка %.2f, уверенность %.0f%%" % [score, confidence]
	if bool(intent.get("hysteresis", false)):
		suffix += ", держит план"
	elif bool(intent.get("mistake", false)):
		suffix += ", ошибка"
	elif bool(intent.get("shifted", false)):
		suffix += ", смена плана"
	return suffix

func _decision_debug_text(unit) -> String:
	var lines: PackedStringArray = []
	lines.append("уверенность %.0f%%, запас %.2f, ошибка %.0f%%" % [
		unit.decision_confidence * 100.0,
		unit.decision_margin,
		unit.decision_mistake_chance * 100.0
	])
	lines.append("строй: %s, слот %s, %.1f клетки" % [
		_formation_role_label(unit.formation_role),
		str(unit.formation_slot),
		unit.formation_distance
	])
	lines.append("видимость: стресс %.0f%%" % [unit.visibility_stress * 100.0])
	var score_parts: PackedStringArray = []
	for score_data in unit.decision_scores:
		score_parts.append(_decision_score_label(score_data))
		if score_parts.size() >= 4:
			break
	if not score_parts.is_empty():
		lines.append("score: " + " / ".join(score_parts))
	return "\n".join(lines)

func _decision_score_label(score_data: Dictionary) -> String:
	var intent_name := _intent_label(str(score_data.get("type", "")))
	var ability_name := str(score_data.get("ability", ""))
	if ability_name != "":
		intent_name = ability_name
	return "%s %.2f" % [intent_name, float(score_data.get("score", 0.0))]

func _formation_role_label(role: String) -> String:
	match role:
		"front":
			return "фронт"
		"backline":
			return "тыл"
		"flank":
			return "фланг"
		"center":
			return "центр"
		_:
			return "линия"

func _refresh_focus_panel() -> void:
	var unit = _get_focus_unit()
	if unit == null:
		_focus_label.text = "Фокус: нет активного героя"
		return
	var target_text := "цель: %s" % unit.target_name if unit.target_name != "" else "цель: нет"
	var squad_target_text: String = "фокус отряда: %s" % unit.squad_focus_target_name if unit.squad_focus_target_name != "" else "фокус отряда: нет"
	var action_text: String = unit.intent_ability_name if unit.intent == "ability" and unit.intent_ability_name != "" else _intent_label(unit.intent)
	var statuses: PackedStringArray = unit.status_list()
	var status_text := "статусы: %s" % ", ".join(statuses) if not statuses.is_empty() else "статусы: нет"
	var task_text := "задача: %s" % unit.current_task
	var resource_text := "ресурсы: E%.0f S%.0f M%.0f" % [unit.energy, unit.stamina, unit.mana]
	var reason_text := _current_action_reason_text(unit)
	var debug_text := ""
	if _debug_perception_overlay:
		debug_text = "\n" + _decision_debug_text(unit)
	_focus_label.text = "Фокус: %s\n%s, HP %d/%d, страх %.0f%%\n%s, %s\n%s, %s\n%s\nпричина: %s%s" % [
		unit.display_name,
		action_text,
		unit.battle_unit.current_hp,
		unit.battle_unit.max_hp,
		unit.fear * 100.0,
		target_text,
		squad_target_text,
		task_text,
		resource_text,
		status_text,
		reason_text,
		debug_text
	]

func _current_action_reason_text(unit) -> String:
	if unit == null:
		return ""
	var target_part := ""
	if unit.target_name != "":
		target_part = " -> %s" % _short_name(unit.target_name)
	var action_text: String = unit.intent_ability_name if unit.intent == "ability" and unit.intent_ability_name != "" else _intent_label(unit.intent)
	var reason: String = unit.intent_reason
	match unit.intent:
		"ability":
			if unit.intent_ability_name != "":
				action_text = unit.intent_ability_name
			if unit.target_name != "":
				return "%s%s, потому что %s" % [action_text, target_part, reason]
		"attack", "chase", "press_attack", "berserk_charge":
			if unit.target_name != "":
				return "%s %s, потому что %s" % [action_text, _short_name(unit.target_name), reason]
		"retreat", "group_retreat", "break_contact", "panic_seek_ally":
			return "%s, потому что %s" % [action_text, reason]
		"take_cover", "safe_los", "keep_distance":
			if unit.target_name != "":
				return "%s от %s, потому что %s" % [action_text, _short_name(unit.target_name), reason]
		_:
			pass
	if reason == "":
		return action_text + target_part
	return "%s%s, потому что %s" % [action_text, target_part, reason]

func _refresh_unit_list() -> void:
	var ally_lines: PackedStringArray = []
	var enemy_lines: PackedStringArray = []
	for unit in _units:
		var action_text: String = unit.intent_ability_name if unit.intent == "ability" and unit.intent_ability_name != "" else _intent_label(unit.intent)
		var name_text: String = _short_name(unit.display_name)
		if unit.is_leader:
			name_text = "L " + name_text
		var line := "%s %d/%d %s" % [
			name_text,
			unit.battle_unit.current_hp,
			unit.battle_unit.max_hp,
			action_text
		]
		if unit.target_name != "":
			line += " -> " + _short_name(unit.target_name)
		var statuses: PackedStringArray = unit.status_list()
		if not statuses.is_empty():
			line += " [" + ",".join(statuses) + "]"
		if _debug_perception_overlay and unit.decision_confidence > 0.0:
			line += " %.0f%%" % (unit.decision_confidence * 100.0)
		if not unit.is_alive():
			line = "%s 0/%d выбыл" % [_short_name(unit.display_name), unit.battle_unit.max_hp]
		if unit.side == BattleUnit.UnitSide.ALLY:
			ally_lines.append(line)
		else:
			if _unit_visible_to_player(unit):
				enemy_lines.append(line)
	var hidden_contacts := _player_hidden_contact_count()
	if hidden_contacts > 0:
		enemy_lines.append("следы врага: %d" % hidden_contacts)
	_unit_list_label.text = "Союзники\n%s\n\nВраги\n%s" % [
		"\n".join(ally_lines),
		"\n".join(enemy_lines)
	]

func _player_hidden_contact_count() -> int:
	if not _fog_of_war_enabled or _debug_perception_overlay:
		return 0
	var marked_positions: Dictionary = {}
	for unit in _units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		for memory_value in unit.last_seen_enemies.values():
			if not (memory_value is Dictionary):
				continue
			var memory: Dictionary = memory_value
			var pos: Vector2i = memory.get("pos", unit.grid_pos)
			if bool(_player_visible_tiles.get(pos, false)):
				continue
			marked_positions[pos] = true
	return marked_positions.size()

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
		"flank":
			return "/"
		"retreat":
			return "R"
		"keep_distance":
			return "D"
		"take_cover":
			return "C"
		"follow":
			return "F"
		"patrol":
			return "S"
		"ambush":
			return "!"
		"guard_ally":
			return "G"
		"support_backline":
			return "B"
		"rally_leader":
			return "L"
		"group_retreat":
			return "R"
		"formation":
			return "P"
		"press_attack":
			return ">"
		"hold_line":
			return "H"
		"hold_choke":
			return "K"
		"safe_los":
			return "V"
		"panic_seek_ally":
			return "+"
		"scout_probe":
			return "?"
		"scout_flank":
			return "/"
		"break_contact":
			return "B"
		"assassin_pickoff":
			return "X"
		"berserk_charge":
			return "!"
		"tactical_position":
			return "T"
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
		"flank":
			return "обход"
		"retreat":
			return "страх"
		"keep_distance":
			return "дистанция"
		"take_cover":
			return "укрытие"
		"follow":
			return "к союзнику"
		"patrol":
			return "поиск"
		"ambush":
			return "засада"
		"guard_ally":
			return "прикрытие"
		"support_backline":
			return "за спины"
		"rally_leader":
			return "к лидеру"
		"group_retreat":
			return "отход"
		"formation":
			return "строй"
		"press_attack":
			return "напор"
		"hold_line":
			return "линия"
		"hold_choke":
			return "проход"
		"safe_los":
			return "позиция"
		"panic_seek_ally":
			return "к союзнику"
		"scout_probe":
			return "разведка"
		"scout_flank":
			return "фланг"
		"break_contact":
			return "разрыв"
		"assassin_pickoff":
			return "добить"
		"berserk_charge":
			return "натиск"
		"tactical_position":
			return "тактика"
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
		"flank":
			return Color(1.0, 0.66, 0.32)
		"retreat":
			return Color(0.72, 0.55, 1.0)
		"keep_distance":
			return Color(0.5, 0.9, 1.0)
		"take_cover":
			return Color(0.38, 0.74, 1.0)
		"follow":
			return Color(0.45, 0.95, 0.78)
		"patrol":
			return Color(0.72, 0.82, 0.9)
		"ambush":
			return Color(0.75, 1.0, 0.36)
		"guard_ally":
			return Color(0.35, 0.95, 0.72)
		"support_backline":
			return Color(0.55, 0.82, 1.0)
		"rally_leader":
			return Color(1.0, 0.82, 0.28)
		"group_retreat":
			return Color(0.85, 0.62, 1.0)
		"formation":
			return Color(0.64, 0.88, 1.0)
		"press_attack":
			return Color(1.0, 0.62, 0.22)
		"hold_line":
			return Color(0.42, 0.92, 0.82)
		"hold_choke":
			return Color(0.5, 0.95, 0.82)
		"safe_los":
			return Color(0.52, 0.82, 1.0)
		"panic_seek_ally":
			return Color(0.45, 1.0, 0.66)
		"scout_probe":
			return Color(0.92, 0.72, 0.34)
		"scout_flank":
			return Color(0.78, 1.0, 0.34)
		"break_contact":
			return Color(0.66, 0.78, 1.0)
		"assassin_pickoff":
			return Color(1.0, 0.46, 0.62)
		"berserk_charge":
			return Color(1.0, 0.34, 0.18)
		"tactical_position":
			return Color(0.72, 0.92, 1.0)
		_:
			return Color(0.85, 0.85, 0.85)

func _speed_label() -> String:
	return "Скорость %.1fx" % _time_scale

func _on_return_pressed() -> void:
	if not _battle_finished and not _battle_context.is_demo():
		_battle_finish_reason = "manual_retreat"
		_battle_finish_detail = "Игрок приказал отряду отступить."
		_finish_battle(false)
		return
	GameState.clear_pending_combat()
	get_tree().change_scene_to_file(HUB_SCENE)

func _on_end_return_pressed() -> void:
	if _battle_context.is_raid():
		get_tree().change_scene_to_file(RAID_PROGRESS_SCENE)
	elif _battle_context.is_tower() and _end_title.text == "Победа!":
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)

func _on_pause_pressed() -> void:
	_paused = not _paused
	_pause_btn.text = "Продолжить" if _paused else "Пауза"
	_refresh_status()

func _on_speed_pressed() -> void:
	_speed_index = (_speed_index + 1) % _combat_config.speed_modes.size()
	_time_scale = float(_combat_config.speed_modes[_speed_index])
	_fast_forward_to_end = false
	_speed_btn.text = _speed_label()
	_refresh_status()

func _on_auto_pause_pressed() -> void:
	_auto_pause_important = not _auto_pause_important
	_auto_pause_btn.text = "Автопауза on" if _auto_pause_important else "Автопауза off"
	_refresh_status()

func _auto_pause_for_important_event() -> void:
	if not _auto_pause_important or _battle_finished or _fast_forward_to_end:
		return
	_paused = true
	_pause_btn.text = "Продолжить"
	_refresh_status()

func _on_freeze_pressed() -> void:
	_freeze_ai = not _freeze_ai
	_freeze_btn.text = "AI off" if _freeze_ai else "AI"
	_log_line("AI заморожен." if _freeze_ai else "AI снова принимает решения.")
	_refresh_status()

func _on_fast_finish_pressed() -> void:
	_fast_forward_to_end = not _fast_forward_to_end
	if _fast_forward_to_end:
		_time_scale = 12.0
		_fast_finish_btn.text = "1x"
	else:
		_time_scale = float(_combat_config.speed_modes[_speed_index])
		_fast_finish_btn.text = "До конца"
	_speed_btn.text = _speed_label()
	_refresh_status()

func _on_setup_pressed() -> void:
	if not _battle_context.is_demo() or not _battle_finished:
		_log_line("Сетап доступен после тренировочного боя.")
		return
	_debug_setup_index = (_debug_setup_index + 1) % 3
	match _debug_setup_index:
		1:
			_battle_context.arena_id = "flooded_crossing"
			_battle_context.enemy_plan = [{"type": "goblin_scout", "count": 2}, {"type": "orc", "count": 1}]
		2:
			_battle_context.arena_id = "generated_mixed"
			_battle_context.enemy_plan = [{"type": "orc_defender", "count": 1}, {"type": "troll", "count": 1}]
		_:
			_battle_context.arena_id = "training_ruins"
			_battle_context.enemy_plan = [{"type": "goblin", "count": 3}]
	_restart_training_battle()

func _on_debug_pressed() -> void:
	_debug_perception_overlay = not _debug_perception_overlay
	_debug_btn.text = "Debug on" if _debug_perception_overlay else "Debug"
	queue_redraw()

func _on_fog_pressed() -> void:
	_fog_of_war_enabled = not _fog_of_war_enabled
	_fog_btn.text = "Туман on" if _fog_of_war_enabled else "Туман off"
	queue_redraw()

func _on_repeat_training_pressed() -> void:
	if not _battle_context.is_demo():
		return
	_restart_training_battle()

func _restart_training_battle() -> void:
	_battle_finished = false
	_paused = false
	_freeze_ai = false
	_time_scale = _combat_config.default_time_scale
	_speed_index = _combat_config.default_speed_index()
	_pause_btn.disabled = false
	_speed_btn.disabled = false
	_pause_btn.text = "Пауза"
	_freeze_btn.text = "AI"
	_auto_pause_btn.text = "Автопауза on" if _auto_pause_important else "Автопауза off"
	_fast_finish_btn.text = "До конца"
	_speed_btn.text = _speed_label()
	_end_panel.visible = false
	_setup_battle()
	_refresh_status()
	queue_redraw()

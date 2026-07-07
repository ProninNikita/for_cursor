extends Control

## Пошаговый бой: порядок хода по инициативе + система способностей.

const TOWER_SQUAD_SCENE := "res://scenes/tower/tower_squad.tscn"
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const RAID_PROGRESS_SCENE := "res://scenes/tower/raid_progress.tscn"
const CombatSimulationScript = preload("res://scripts/combat/combat_simulation.gd")

@onready var back_btn: Button = $TopBar/BackBtn
@onready var turn_order_label: RichTextLabel = $Main/TurnOrder
@onready var current_actor_label: Label = $Main/CurrentActor
@onready var next_actor_label: Label = $Main/NextActor
@onready var allies_container: VBoxContainer = $Main/Lists/AlliesCol/Units
@onready var enemies_container: VBoxContainer = $Main/Lists/EnemiesCol/Units
@onready var combat_log: RichTextLabel = $Main/Log
@onready var hint_label: Label = $Main/Hint
@onready var end_panel: PanelContainer = $EndPanel
@onready var end_title: Label = $EndPanel/Margin/VBox/Title
@onready var end_detail: Label = $EndPanel/Margin/VBox/Detail
@onready var end_btn: Button = $EndPanel/Margin/VBox/ReturnBtn

var _combat = CombatSimulationScript.new()
var _pick_target_mode: bool = false
var _battle_finished: bool = false
var _current_ally_actor: BattleUnit
var _highlight_actor: BattleUnit
var _selected_ability: AbilityData = null
var _ability_targeting_mode: bool = false
var _abilities_container: VBoxContainer = null
var _auto_battle_enabled: bool = true
var _current_tower_floor: int = 1  ## Текущий этаж в Возвышении
var _is_tower_elevation: bool = false  ## Это бой в Возвышении?
var _is_raid_combat: bool = false  ## Это бой в вылазке?

const _HINT_PICK := "Выберите врага для атаки"
const _HINT_ENEMY_TURN := "Ход врага…"
const _HINT_ABILITY := "Выберите способность"
const _HINT_TARGET_ENEMY := "Выберите цель для атаки"
const _HINT_TARGET_ALLY := "Выберите союзника"

func _ready() -> void:
	back_btn.set_meta("qa_id", "combat.back")
	end_btn.set_meta("qa_id", "combat.return")
	_combat.rng.randomize()
	AbilityRegistry.initialize()
	back_btn.visible = false
	back_btn.pressed.connect(_on_back_pressed)
	end_btn.pressed.connect(_on_return_hub)
	end_panel.visible = false
	combat_log.clear()
	_create_abilities_container()

	# Проверяем, это Возвышение, вылазка или обычный бой
	_is_tower_elevation = GameState.is_tower_elevation
	_is_raid_combat = not GameState.pending_raid_event.is_empty()
	_current_tower_floor = GameState.pending_tower_floor

	if _is_tower_elevation:
		end_btn.text = "Продолжить"
	elif _is_raid_combat:
		end_btn.text = "Вернуться к вылазке"
	else:
		end_btn.text = "Вернуться в хаб"

	if GameState.pending_combat_squad.is_empty():
		push_warning("Нет отряда — возврат к выбору башни")
		call_deferred("_change_scene", TOWER_SQUAD_SCENE)
		return

	_setup_units()
	_refresh_ui()
	call_deferred("_run_turn")

func _change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func _setup_units() -> void:
	_combat.setup(GameState.pending_combat_squad)

func _living_enemies() -> Array[BattleUnit]:
	return _combat.living_enemies()

func _living_allies() -> Array[BattleUnit]:
	return _combat.living_allies()

func _check_end() -> bool:
	var outcome: int = _combat.get_outcome()
	match outcome:
		CombatSimulationScript.BattleOutcome.VICTORY:
			_finish_battle(true)
			return true
		CombatSimulationScript.BattleOutcome.DEFEAT:
			_finish_battle(false)
			return true
		_:
			return false

func _finish_battle(victory: bool) -> void:
	_battle_finished = true
	_pick_target_mode = false
	next_actor_label.text = ""
	_update_combat_brains(victory)
	_sync_roster_hp()

	if victory:
		# Регистрируем победу в Возвышении
		if _is_tower_elevation:
			GameState.tower_elevation.register_victory(_current_tower_floor)
			GameState.tower_elevation.advance_to_next_floor()
		elif _is_raid_combat:
			# Завершаем боевое событие вылазки
			GameState.finish_raid_combat(true)
			if GameState.active_raid != null:
				GameState.active_raid.complete_combat_event(true)
		else:
			GameState.lootboxes_remaining += 1
	else:
		# Поражение в вылазке
		if _is_raid_combat:
			GameState.finish_raid_combat(false)
			if GameState.active_raid != null:
				GameState.active_raid.complete_combat_event(false)

	end_panel.visible = true
	end_panel.z_index = 10

	if victory:
		end_title.text = "Победа!"
		if _is_tower_elevation:
			var floor_data = GameState.tower_elevation.get_floor_data(_current_tower_floor)
			var reward_text = ""
			var rewards = floor_data.get("reward", {})
			if rewards.has("lootboxes"):
				reward_text += "%d лутбоксов" % rewards["lootboxes"]
			if rewards.has("gold"):
				if reward_text != "":
					reward_text += ", "
				reward_text += "%d золота" % rewards["gold"]

			end_detail.text = "%s conquered!\nНаграда: %s\n\nСледующий этаж: %d" % [
				floor_data.get("name", "Этаж %d" % _current_tower_floor),
				reward_text,
				_current_tower_floor + 1
			]
		elif _is_raid_combat:
			end_detail.text = "Враги разбиты!\nОтряд продолжает вылазку."
		else:
			end_detail.text = "Получен лутбокс! Всего лутбоксов: %d" % GameState.lootboxes_remaining
	else:
		end_title.text = "Поражение"
		if _is_raid_combat:
			end_detail.text = "Отряд получил урон.\nПроверьте состояние героев."
		else:
			var lost: PackedStringArray = []
			for cd in GameState.pending_combat_squad:
				if GameState.roster.get_by_id(cd.id) == null:
					lost.append(cd.display_name)
			if lost.is_empty():
				end_detail.text = "Выжившие обновлены в ростере."
			else:
				end_detail.text = "Погибли: %s" % ", ".join(lost)

	GameState.clear_pending_combat()
	GameState.is_tower_elevation = false  # Сбрасываем флаг
	GameState.pending_tower_floor = 0
	GameState.pending_raid_event.clear()
	_log_line("— Бой окончен —")
	_refresh_ui()

func _sync_roster_hp() -> void:
	_combat.sync_roster_hp(GameState.roster)

func _update_combat_brains(victory: bool) -> void:
	_combat.update_combat_brains(victory)

func _record_damage_dealt(user: BattleUnit, amount: int) -> void:
	_combat.record_damage_dealt(user, amount)

func _record_healing_done(user: BattleUnit, amount: int) -> void:
	_combat.record_healing_done(user, amount)

func _record_damage_taken(target: BattleUnit, amount: int) -> void:
	_combat.record_damage_taken(target, amount)

func _next_alive_actor() -> BattleUnit:
	return _combat.next_alive_actor()

## Кто ходит следующим (указатель уже сдвинут после выбора текущего актёра).
func _peek_next_alive_in_order() -> BattleUnit:
	return _combat.peek_next_alive_actor()


func _update_next_actor_label() -> void:
	if _battle_finished:
		next_actor_label.text = ""
		return
	var nxt := _peek_next_alive_in_order()
	if nxt == null:
		next_actor_label.text = ""
		return
	next_actor_label.text = "Следующий: %s (инт. %d)" % [nxt.display_name, nxt.initiative]


func _run_turn() -> void:
	if _battle_finished:
		return
	if _check_end():
		return

	var actor := _next_alive_actor()
	if actor == null:
		_check_end()
		return

	_highlight_actor = actor
	_refresh_turn_strip()
	current_actor_label.text = "Ход: %s (инициатива %d)" % [actor.display_name, actor.initiative]
	_update_next_actor_label()

	if actor.side == BattleUnit.UnitSide.ENEMY:
		_pick_target_mode = false
		_current_ally_actor = null
		hint_label.text = _HINT_ENEMY_TURN
		_refresh_ui()
		await get_tree().create_timer(0.55).timeout
		if _battle_finished:
			return
		_enemy_action(actor)
		_refresh_ui()
	else:
		_current_ally_actor = actor
		_pick_target_mode = false
		_selected_ability = null
		_ability_targeting_mode = false
		hint_label.text = "%s оценивает ситуацию..." % actor.display_name
		_show_ability_buttons(actor)
		_refresh_ui()
		await get_tree().create_timer(0.35).timeout
		if _battle_finished:
			return
		_ally_auto_action(actor)

func _calc_damage(attacker: BattleUnit, defender: BattleUnit) -> int:
	return _combat.calc_damage(attacker, defender)

func _ally_attack_target(target: BattleUnit) -> void:
	if not _pick_target_mode or _battle_finished or _current_ally_actor == null:
		return
	if not target.is_alive() or target.side != BattleUnit.UnitSide.ENEMY:
		return

	var dmg := _calc_damage(_current_ally_actor, target)
	target.take_damage(dmg)
	_record_damage_dealt(_current_ally_actor, dmg)
	_log_line("%s бьёт %s на %d урона." % [_current_ally_actor.display_name, target.display_name, dmg])
	if not target.is_alive():
		_log_line("%s повержен." % target.display_name)

	if _check_end():
		_refresh_ui()
		return

	_pick_target_mode = false
	_current_ally_actor = null
	_refresh_ui()
	_run_turn()


func _on_enemy_hover_enter(target: BattleUnit) -> void:
	if not _pick_target_mode or _battle_finished or _current_ally_actor == null:
		return
	if not target.is_alive():
		return
	var dmg := _calc_damage(_current_ally_actor, target)
	hint_label.text = "По %s: урон ~%d (наведение)" % [target.display_name, dmg]


func _on_enemy_hover_exit() -> void:
	if _pick_target_mode and not _battle_finished:
		hint_label.text = _HINT_PICK


func _on_enemy_pressed(target: BattleUnit) -> void:
	if not _pick_target_mode or _battle_finished:
		return
	_ally_attack_target(target)

func _ally_auto_action(actor: BattleUnit) -> void:
	if actor.is_stunned():
		_log_line("%s оглушён и пропускает ход!" % actor.display_name)
		actor.tick_cooldowns()
		_end_turn(actor)
		return

	var decision = _choose_ally_decision(actor)
	var ability: AbilityData = decision.get("ability", null)
	if ability != null:
		var reason = decision.get("reason", "выбирает действие")
		_log_line("%s сам решает: %s." % [actor.display_name, reason])
		if decision.get("all_targets", false):
			_execute_ability_on_all_targets(ability, actor, decision.get("targets", []))
		else:
			var target: BattleUnit = decision.get("target", null)
			if target != null:
				_execute_ability(ability, actor, target)
			else:
				_ally_basic_attack(actor)
	else:
		_ally_basic_attack(actor)


func _ally_basic_attack(actor: BattleUnit) -> void:
	var enemies := _living_enemies()
	if enemies.is_empty():
		_check_end()
		return
	var target = _pick_weakest_enemy(enemies)
	var dmg := _calc_damage(actor, target)
	target.take_damage(dmg)
	_record_damage_dealt(actor, dmg)
	_log_line("%s выбирает простую атаку по %s: %d урона." % [actor.display_name, target.display_name, dmg])
	if not target.is_alive():
		_log_line("%s повержен." % target.display_name)
	actor.tick_cooldowns()
	_end_turn(actor)


func _choose_ally_decision(actor: BattleUnit) -> Dictionary:
	return _combat.choose_ally_decision(actor)


func _enemy_action(enemy: BattleUnit) -> void:
	if enemy.is_stunned():
		_log_line("%s оглушён и пропускает ход!" % enemy.display_name)
		enemy.tick_cooldowns()
		var result = enemy.tick_battle_state()
		_end_turn(enemy)
		return

	var ability := _choose_enemy_ability(enemy)
	var target := _choose_target_for_ability(enemy, ability)

	if ability != null and target != null:
		_execute_ability(ability, enemy, target)
	else:
		var allies := _living_allies()
		if allies.is_empty():
			return
		target = _pick_weakest_ally(allies)
		var dmg := _calc_damage(enemy, target)
		target.take_damage(dmg)
		_record_damage_taken(target, dmg)
		_log_line("%s бьёт %s на %d урона." % [enemy.display_name, target.display_name, dmg])
		if not target.is_alive():
			_log_line("%s пал в бою." % target.display_name)
		_end_turn(enemy)


func _choose_enemy_ability(enemy: BattleUnit) -> AbilityData:
	return _combat.choose_enemy_ability(enemy)


func _choose_target_for_ability(enemy: BattleUnit, ability: AbilityData) -> BattleUnit:
	if ability == null:
		return null
	return _combat.choose_target_for_ability(enemy, ability)


func _pick_weakest_enemy(enemies: Array[BattleUnit]) -> BattleUnit:
	return _combat.pick_weakest_enemy(enemies)


func _pick_weakest_ally(allies: Array[BattleUnit]) -> BattleUnit:
	return _combat.pick_weakest_ally(allies)


func _refresh_turn_strip() -> void:
	var parts: PackedStringArray = []
	for u in _combat.turn_order:
		if not u.is_alive():
			continue
		var is_cur: bool = u == _highlight_actor
		var tag := "[b]▶ [/b]" if is_cur else ""
		var name_bb: String = "[b]%s[/b]" % u.display_name if is_cur else u.display_name
		if u.side == BattleUnit.UnitSide.ALLY:
			parts.append("%s[color=cyan]%s (%d)[/color]" % [tag, name_bb, u.initiative])
		else:
			parts.append("%s[color=orange]%s (%d)[/color]" % [tag, name_bb, u.initiative])
	turn_order_label.text = "[center]" + " → ".join(parts) + "[/center]"


func _create_abilities_container() -> void:
	if _abilities_container != null:
		return

	_abilities_container = VBoxContainer.new()
	_abilities_container.name = "AbilitiesContainer"
	var parent = $Main
	parent.add_child(_abilities_container)
	parent.move_child(_abilities_container, 2)

func _show_ability_buttons(actor: BattleUnit) -> void:
	_clear_container(_abilities_container)

	var title := Label.new()
	title.text = "Способности (авто):" if _auto_battle_enabled else "Способности:"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	_abilities_container.add_child(title)

	if actor.abilities.is_empty():
		var empty := Label.new()
		empty.text = "Нет способностей"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_abilities_container.add_child(empty)
		return

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_abilities_container.add_child(hbox)

	for ability in actor.abilities:
		var btn := Button.new()
		btn.text = ability.get_display_name_with_cooldown()
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = _auto_battle_enabled or not ability.can_use()
		btn.tooltip_text = "%s\n%s" % [ability.name, ability.description]

		if not _auto_battle_enabled and not btn.disabled:
			btn.pressed.connect(_on_ability_selected.bind(ability))

		hbox.add_child(btn)

func _refresh_ui() -> void:
	_clear_container(allies_container)
	_clear_container(enemies_container)

	for u in _combat.all_units:
		if u.side != BattleUnit.UnitSide.ALLY:
			continue
		var b := Button.new()
		b.text = _unit_line(u)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = true
		if u == _highlight_actor and u.is_alive():
			b.modulate = Color(0.78, 1.0, 0.92)
		allies_container.add_child(b)

	for u in _combat.all_units:
		if u.side != BattleUnit.UnitSide.ENEMY:
			continue
		var b := Button.new()
		b.text = _unit_line(u)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if u.is_alive() and _pick_target_mode else Control.CURSOR_ARROW
		b.disabled = not u.is_alive() or (not _pick_target_mode)
		if u.is_alive() and _pick_target_mode:
			b.pressed.connect(_on_enemy_pressed.bind(u))
			b.mouse_entered.connect(_on_enemy_hover_enter.bind(u))
			b.mouse_exited.connect(_on_enemy_hover_exit)
		enemies_container.add_child(b)

	_refresh_turn_strip()


func _unit_line(u: BattleUnit) -> String:
	var dead := "" if u.is_alive() else " ☠"
	var status := u.get_status_summary()
	return "%s  HP %d/%d  ИНТ %d%s%s" % [u.display_name, u.current_hp, u.max_hp, u.initiative, status, dead]


func _clear_container(c: Node) -> void:
	for ch in c.get_children():
		ch.queue_free()


func _log_line(line: String) -> void:
	combat_log.append_text(line + "\n")


func _on_ability_selected(ability: AbilityData) -> void:
	if _battle_finished or _current_ally_actor == null:
		return

	_selected_ability = ability

	match ability.target_type:
		AbilityData.TargetType.SELF:
			_execute_ability(ability, _current_ally_actor, _current_ally_actor)
		AbilityData.TargetType.SINGLE_ENEMY:
			_ability_targeting_mode = true
			hint_label.text = _HINT_TARGET_ENEMY
			_refresh_enemy_buttons_for_targeting()
		AbilityData.TargetType.SINGLE_ALLY:
			_ability_targeting_mode = true
			hint_label.text = _HINT_TARGET_ALLY
			_refresh_ally_buttons_for_targeting()
		AbilityData.TargetType.ALL_ENEMIES:
			_execute_ability_on_all_targets(ability, _current_ally_actor, _living_enemies())
		AbilityData.TargetType.ALL_ALLIES:
			_execute_ability_on_all_targets(ability, _current_ally_actor, _living_allies())


func _execute_ability(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	_apply_ability_to_target(ability, user, target)
	ability.use()
	user.tick_cooldowns()
	_end_turn(user)


func _apply_ability_to_target(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	match ability.type:
		AbilityData.AbilityType.DAMAGE:
			_deal_ability_damage(ability, user, target)
		AbilityData.AbilityType.HEAL:
			_apply_heal(ability, user, target)
		AbilityData.AbilityType.BUFF:
			_apply_buff(ability, user, target)
		AbilityData.AbilityType.DEBUFF:
			_apply_debuff(ability, user, target)
		AbilityData.AbilityType.SPECIAL:
			_apply_special(ability, user, target)


func _execute_ability_on_all_targets(ability: AbilityData, user: BattleUnit, targets: Array[BattleUnit]) -> void:
	var used = false
	for target in targets:
		if target.is_alive():
			_apply_ability_to_target(ability, user, target)
			used = true
	if used:
		ability.use()
		user.tick_cooldowns()
	_end_turn(user)


func _deal_ability_damage(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	var stat_value = user.get_stat(ability.stat_used)
	var base_damage = stat_value * ability.power

	var mark_bonus = 0
	if target.battle_state != null and target.battle_state.has_mark():
		mark_bonus = target.battle_state.get_mark_bonus_damage()

	var defense = target.get_stat("def")
	var damage = int(maxi(1, base_damage + mark_bonus - defense / 2))

	if _combat.rng.randf() < 0.5:
		damage = int(damage * 0.9)
	else:
		damage = int(damage * 1.1)

	var hp_before = target.current_hp
	target.take_ability_damage(damage)
	var applied_damage = hp_before - target.current_hp
	_record_damage_dealt(user, applied_damage)
	_record_damage_taken(target, applied_damage)
	_log_line("%s использует %s на %s: %d урона!" % [user.display_name, ability.name, target.display_name, damage])

	_apply_ability_effects(ability, user, target)

	if not target.is_alive():
		_log_line("%s повержен." % target.display_name)


func _apply_heal(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	var stat_value = user.get_stat(ability.stat_used)
	var heal_amount = int(stat_value * ability.power)
	var hp_before = target.current_hp
	target.heal(heal_amount)
	var applied_heal = target.current_hp - hp_before
	_record_healing_done(user, applied_heal)
	_log_line("%s использует %s на %s: +%d HP" % [user.display_name, ability.name, target.display_name, heal_amount])
	_apply_ability_effects(ability, user, target)


func _apply_buff(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	_log_line("%s использует %s на %s!" % [user.display_name, ability.name, target.display_name])
	_apply_ability_effects(ability, user, target)


func _apply_debuff(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	_log_line("%s использует %s на %s!" % [user.display_name, ability.name, target.display_name])
	_apply_ability_effects(ability, user, target)


func _apply_special(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	_log_line("%s использует %s!" % [user.display_name, ability.name])
	_apply_ability_effects(ability, user, target)


func _apply_ability_effects(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> void:
	if target.battle_state == null:
		return

	for effect in ability.effects:
		var effect_target = target
		var effect_text = str(effect)
		if effect_text.begins_with("self_"):
			effect_target = user
			effect_text = effect_text.substr(5)
		_parse_and_apply_effect(effect_text, effect_target, user)


func _parse_and_apply_effect(effect_str: String, target: BattleUnit, user: BattleUnit) -> void:
	var parts = effect_str.split("_")
	if parts.is_empty():
		return

	var effect_type = parts[0]
	var value = 0
	var duration = 0
	var mode = ""

	if parts.size() >= 2:
		mode = parts[1]

	if mode == "chance" and parts.size() >= 3:
		value = int(parts[2])
		duration = 1
	elif (mode == "buff" or mode == "debuff") and parts.size() >= 3:
		value = int(parts[2])
		duration = 2
	elif effect_type == "poison" and parts.size() >= 2:
		duration = int(parts[1])
		value = 2
	elif effect_type == "regen" and parts.size() >= 2:
		duration = int(parts[1])
		value = 2
	elif effect_type == "lifesteal" and parts.size() >= 2:
		value = int(parts[1])
	elif effect_type == "mark":
		duration = 2
		value = 3
	elif effect_type == "evade" or effect_type == "taunt":
		duration = 2

	match effect_type:
		"stun":
			if _combat.rng.randf() * 100 < value:
				target.battle_state.apply_effect(BattleState.EffectType.STUN, duration)
				_log_line("%s оглушён!" % target.display_name)
		"poison":
			target.battle_state.apply_effect(BattleState.EffectType.POISON, duration, value)
			_log_line("%s отравлен на %d!" % [target.display_name, duration])
		"regen":
			target.battle_state.apply_effect(BattleState.EffectType.REGEN, duration, value)
			_log_line("%s восстанавливает HP каждый ход!" % target.display_name)
		"atk":
			if "buff" in effect_str:
				target.battle_state.atk_modifier += value
				target.battle_state.apply_effect(BattleState.EffectType.ATK_BUFF, duration, value)
				_log_line("Атака %s повышена на %d!" % [target.display_name, value])
			elif "debuff" in effect_str:
				target.battle_state.atk_modifier -= value
				target.battle_state.apply_effect(BattleState.EffectType.ATK_DEBUFF, duration, value)
				_log_line("Атака %s понижена на %d!" % [target.display_name, value])
		"def":
			if "buff" in effect_str:
				target.battle_state.def_modifier += value
				target.battle_state.apply_effect(BattleState.EffectType.DEF_BUFF, duration, value)
				_log_line("Защита %s повышена на %d!" % [target.display_name, value])
			elif "debuff" in effect_str:
				target.battle_state.def_modifier -= value
				target.battle_state.apply_effect(BattleState.EffectType.DEF_DEBUFF, duration, value)
				_log_line("Защита %s понижена на %d!" % [target.display_name, value])
		"mark":
			target.battle_state.apply_effect(BattleState.EffectType.MARK, duration, value)
			_log_line("%s помечен! Бонусный урон +%d" % [target.display_name, value])
		"evade":
			target.battle_state.apply_effect(BattleState.EffectType.EVADE, duration, 0)
			_log_line("%s уклоняется от атак!" % target.display_name)
		"taunt":
			target.battle_state.apply_effect(BattleState.EffectType.TAUNT, duration, 0)
			_log_line("%s провоцирует врагов!" % target.display_name)
		"initiative":
			if "buff" in effect_str:
				target.battle_state.initiative_modifier += value
				target.initiative += value
				target.battle_state.apply_effect(BattleState.EffectType.INITIATIVE_BUFF, duration, value)
				_log_line("Инициатива %s повышена на %d!" % [target.display_name, value])
		"lifesteal":
			var heal_amount = int(user.get_stat("atk") * value / 100.0)
			user.heal(heal_amount)
			_log_line("%s восстанавливает %d HP от вампиризма!" % [user.display_name, heal_amount])
		"cleanse":
			target.battle_state.clear_all_effects()
			_log_line("Все эффекты с %s сняты!" % target.display_name)


func _end_turn(actor: BattleUnit) -> void:
	var result = actor.tick_battle_state()
	for msg in result["messages"]:
		_log_line(msg)

	if result["damage"] > 0:
		actor.take_ability_damage(result["damage"])

	if result["heal"] > 0:
		actor.heal(result["heal"])

	_check_end()
	_refresh_ui()

	if not _battle_finished:
		_run_turn()


func _refresh_enemy_buttons_for_targeting() -> void:
	_clear_container(enemies_container)

	for u in _combat.all_units:
		if u.side != BattleUnit.UnitSide.ENEMY:
			continue
		var b := Button.new()
		b.text = _unit_line(u)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if u.is_alive() else Control.CURSOR_ARROW
		b.disabled = not u.is_alive()
		if u.is_alive():
			b.pressed.connect(_on_ability_target_selected.bind(u))
		enemies_container.add_child(b)


func _refresh_ally_buttons_for_targeting() -> void:
	_clear_container(allies_container)

	for u in _combat.all_units:
		if u.side != BattleUnit.UnitSide.ALLY:
			continue
		var b := Button.new()
		b.text = _unit_line(u)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if u.is_alive() else Control.CURSOR_ARROW
		b.disabled = not u.is_alive()
		if u.is_alive():
			b.pressed.connect(_on_ability_target_selected.bind(u))
		allies_container.add_child(b)


func _on_ability_target_selected(target: BattleUnit) -> void:
	if _selected_ability == null or _battle_finished:
		return

	_execute_ability(_selected_ability, _current_ally_actor, target)
	_selected_ability = null
	_ability_targeting_mode = false


func _on_back_pressed() -> void:
	pass


func _on_return_hub() -> void:
	# Если это бой в вылазке, возвращаемся к прогрессу вылазки
	if _is_raid_combat:
		get_tree().change_scene_to_file(RAID_PROGRESS_SCENE)
	# Если это победа в Возвышении, возвращаемся к выбору этажа
	elif _is_tower_elevation and end_title.text == "Победа!":
		get_tree().change_scene_to_file(TOWER_LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(HUB_SCENE)

class_name RTActionResolver
extends RefCounted

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var active_units: Array = []
var damage_multiplier: float = 0.82

func update_unit(unit, delta: float, intent: Dictionary, battlefield, map_origin: Vector2) -> Array[String]:
	_events.clear()
	var messages: Array[String] = []
	if not unit.is_alive():
		if unit.body_remove_timer >= 0.0:
			unit.body_remove_timer = maxf(0.0, unit.body_remove_timer - delta)
		return messages

	var state_events: Array = unit.tick_rt_state(delta)
	for state_event in state_events:
		messages.append_array(_handle_state_event(state_event))
		_events.append(state_event)
	unit.attack_timer = maxf(0.0, unit.attack_timer - delta)
	if unit.has_status("stun"):
		unit.current_task = "stunned"
		unit.clear_actions(true)
		return messages
	if unit.action_recovery_timer > 0.0:
		unit.current_task = "recover"
		return messages

	var type: String = str(intent.get("type", "hold"))
	var destination: Vector2i = intent.get("destination", unit.grid_pos)
	var target = intent.get("target", null)
	var ability: AbilityData = intent.get("ability", null)
	var targets: Array = intent.get("targets", [])
	unit.remember_decision(intent)
	unit.set_intent(type, str(intent.get("reason", "оценивает ситуацию")), destination, target, ability)
	_ensure_action_for_intent(unit, intent)
	messages.append_array(_process_current_action(unit, delta, battlefield, map_origin))

	return messages

func _handle_state_event(event: Dictionary) -> Array[String]:
	var messages: Array[String] = []
	var event_type := str(event.get("type", ""))
	if event_type == "status_damage":
		var target = event.get("target", null)
		if target != null:
			var amount := int(event.get("amount", 0))
			messages.append("%s получает %d урона от отравления." % [target.display_name, amount])
	return messages

func _ensure_action_for_intent(unit, intent: Dictionary) -> void:
	var action := _action_from_intent(unit, intent)
	if action.is_empty():
		return
	if unit.action_signature() == str(action.get("signature", "")):
		return
	if not unit.cast_action.is_empty():
		if _action_target_is_valid(unit.cast_action):
			return
		unit.clear_actions(true)
	unit.clear_actions(false)
	unit.enqueue_action(action)

func _action_from_intent(unit, intent: Dictionary) -> Dictionary:
	var intent_type := str(intent.get("type", "hold"))
	var destination: Vector2i = intent.get("destination", unit.grid_pos)
	var target = intent.get("target", null)
	var ability: AbilityData = intent.get("ability", null)
	var targets: Array = intent.get("targets", [])
	match intent_type:
		"ability":
			if ability == null:
				return {}
			return {
				"kind": "cast",
				"intent_type": intent_type,
				"destination": destination,
				"target": target,
				"ability": ability,
				"targets": targets,
				"signature": _action_signature(intent_type, destination, target, ability)
			}
		"attack":
			return {
				"kind": "attack",
				"intent_type": intent_type,
				"destination": destination,
				"target": target,
				"signature": _action_signature(intent_type, destination, target, null)
			}
		"chase", "retreat", "take_cover", "follow", "patrol", "ambush", "keep_distance", "flank", "guard_ally", "support_backline", "rally_leader", "group_retreat", "formation", "press_attack", "hold_line", "safe_los", "panic_seek_ally", "scout_probe", "scout_flank", "break_contact", "assassin_pickoff", "berserk_charge", "tactical_position":
			return {
				"kind": "flee" if intent_type in ["retreat", "group_retreat", "break_contact", "panic_seek_ally"] else "move",
				"intent_type": intent_type,
				"destination": destination,
				"target": target,
				"signature": _action_signature(intent_type, destination, target, null)
			}
		_:
			return {
				"kind": "wait",
				"intent_type": intent_type,
				"destination": unit.grid_pos,
				"signature": "wait:%s" % intent_type
			}

func _action_signature(intent_type: String, destination: Vector2i, target, ability: AbilityData) -> String:
	var target_id: String = target.unit_id if target != null else ""
	var ability_id: String = ability.id if ability != null else ""
	return "%s:%s:%s:%s" % [intent_type, str(destination), target_id, ability_id]

func _process_current_action(unit, delta: float, battlefield, map_origin: Vector2) -> Array[String]:
	if unit.current_action.is_empty():
		unit.pop_next_action()
	if unit.current_action.is_empty():
		return []
	var action: Dictionary = unit.current_action
	var kind := str(action.get("kind", "wait"))
	unit.current_task = kind
	match kind:
		"cast":
			return _process_cast_action(unit, action, delta, battlefield, map_origin)
		"attack":
			return _process_attack_action(unit, action, delta, battlefield, map_origin)
		"move", "flee":
			return _process_move_action(unit, action, delta, battlefield, map_origin)
		_:
			unit.hold_timer += delta
			unit.current_action.clear()
			return []

func _process_cast_action(unit, action: Dictionary, delta: float, battlefield, map_origin: Vector2) -> Array[String]:
	var messages: Array[String] = []
	var ability: AbilityData = action.get("ability", null)
	var targets: Array = action.get("targets", [])
	var target = action.get("target", null)
	if ability == null:
		unit.current_action.clear()
		return messages
	if target != null and not target.is_alive():
		unit.clear_actions(true)
		return messages
	if not _can_use_ability_now(unit, ability, targets, battlefield):
		if target != null and target.is_alive():
			messages.append_array(_move_towards(unit, target.grid_pos, delta, battlefield, map_origin, true))
		return messages
	if unit.cast_action.is_empty():
		unit.cast_action = action.duplicate(false)
		unit.cast_timer = maxf(0.0, ability.rt_cast_time)
		unit.add_recent_event("cast", ability.name)
	if unit.cast_timer > 0.0:
		unit.cast_timer = maxf(0.0, unit.cast_timer - delta)
		if unit.cast_timer > 0.0:
			return messages
	messages.append_array(_try_ability(unit, ability, targets, battlefield))
	unit.action_recovery_timer = maxf(unit.action_recovery_timer, 0.18 + ability.rt_cast_time * 0.35)
	unit.cast_action.clear()
	unit.current_action.clear()
	return messages

func _process_attack_action(unit, action: Dictionary, delta: float, battlefield, map_origin: Vector2) -> Array[String]:
	var target = action.get("target", null)
	if target == null or not target.is_alive():
		unit.current_action.clear()
		return []
	if _grid_distance(unit.grid_pos, target.grid_pos) > unit.attack_range_tiles:
		return _move_towards(unit, target.grid_pos, delta, battlefield, map_origin, true)
	var messages := _try_attack(unit, target, battlefield)
	if not messages.is_empty():
		unit.action_recovery_timer = maxf(unit.action_recovery_timer, 0.18)
	unit.current_action.clear()
	return messages

func _process_move_action(unit, action: Dictionary, delta: float, battlefield, map_origin: Vector2) -> Array[String]:
	var destination: Vector2i = action.get("destination", unit.grid_pos)
	var target = action.get("target", null)
	var allow_occupied_goal: bool = target != null and target.is_alive() and target.grid_pos == destination
	var messages := _move_towards(unit, destination, delta, battlefield, map_origin, allow_occupied_goal)
	if unit.grid_pos == destination or (unit.path.is_empty() and unit.destination == unit.grid_pos):
		unit.current_action.clear()
	return messages

func _action_target_is_valid(action: Dictionary) -> bool:
	var target = action.get("target", null)
	if target == null:
		return true
	return target.is_alive()

func _try_attack(attacker, target, battlefield) -> Array[String]:
	var messages: Array[String] = []
	if attacker.attack_timer > 0.0:
		return messages
	if _grid_distance(attacker.grid_pos, target.grid_pos) > attacker.attack_range_tiles:
		return messages
	if not _spend_attack_resources(attacker):
		attacker.action_recovery_timer = maxf(attacker.action_recovery_timer, 0.25)
		return ["%s выдыхается и медлит." % attacker.display_name]

	attacker.attack_timer = attacker.attack_cooldown
	var basic_ability: AbilityData = _basic_attack_ability(attacker)
	if basic_ability != null and attacker.can_use_ability(basic_ability):
		attacker.mark_ability_used(basic_ability)
		_emit_ability_used(attacker, basic_ability)
		messages.append_array(_apply_damage_ability(attacker, target, basic_ability, battlefield))
		_reveal_after_offensive_action(attacker)
		if not messages.is_empty():
			messages.push_front("%s использует %s." % [attacker.display_name, basic_ability.name])
		return messages

	var raw: int = attacker.get_stat("atk") - target.get_stat("def") / 2
	if attacker.get_stat("magic") > attacker.get_stat("atk") and attacker.attack_range_tiles > 2.0:
		raw = attacker.get_stat("magic") - target.get_stat("def") / 3
	var damage: int = maxi(1, raw + rng.randi_range(-1, 2))
	damage = maxi(1, int(round(float(damage) * _coordination_multiplier(attacker, target))))
	var ambush_multiplier: float = _ambush_multiplier(attacker, target, battlefield)
	if ambush_multiplier > 1.0:
		damage = maxi(1, int(round(float(damage) * ambush_multiplier)))
		_reveal_after_ambush(attacker, target, damage)
	damage = _scaled_damage(damage)
	target.take_damage(damage)
	_reveal_after_offensive_action(attacker)
	attacker.fear = clampf(attacker.fear - 0.04, 0.0, 1.0)
	attacker.morale = clampf(attacker.morale + 0.03, 0.0, 1.0)

	messages.append("%s атакует %s: %d урона." % [attacker.display_name, target.display_name, damage])
	if not target.is_alive():
		messages.append("%s выведен из боя." % target.display_name)
	_events.append({
		"type": "damage",
		"attacker": attacker,
		"target": target,
		"amount": damage
	})
	return messages

func _basic_attack_ability(unit) -> AbilityData:
	if unit.battle_unit == null:
		return null
	for ability in unit.battle_unit.abilities:
		if ability == null:
			continue
		if ability.id == "basic_attack" or ability.id == "goblin_basic_attack":
			return ability
		if ability.cooldown_max == 0 and ability.type == AbilityData.AbilityType.DAMAGE:
			return ability
	return null

func _can_use_ability_now(user, ability: AbilityData, targets: Array, battlefield) -> bool:
	if not user.can_use_ability(ability) or targets.is_empty():
		return false
	for target in targets:
		if not target.is_alive():
			continue
		if target == user:
			return true
		var range_tiles: float = user.ability_range_tiles(ability)
		if battlefield.is_height(user.grid_pos):
			range_tiles += 0.75
		if _grid_distance(user.grid_pos, target.grid_pos) <= range_tiles:
			if target.side == user.side or battlefield.has_line_of_sight(user.grid_pos, target.grid_pos):
				return true
	return false

func _try_ability(user, ability: AbilityData, targets: Array, battlefield) -> Array[String]:
	var messages: Array[String] = []
	if not user.can_use_ability(ability) or targets.is_empty():
		return messages
	if not _spend_ability_resources(user, ability):
		user.action_recovery_timer = maxf(user.action_recovery_timer, 0.35)
		return ["%s не хватает сил на %s." % [user.display_name, ability.name]]
	user.mark_ability_used(ability)
	_emit_ability_used(user, ability)
	_emit_area_event(user, ability, targets)

	match ability.type:
		AbilityData.AbilityType.DAMAGE, AbilityData.AbilityType.DEBUFF, AbilityData.AbilityType.SPECIAL:
			var effective_targets: Array = _targets_with_friendly_fire(user, ability, targets)
			for target in effective_targets:
				if target == null or not target.is_alive():
					continue
				var friendly_fire: bool = target.side == user.side
				if friendly_fire and target == user:
					continue
				if friendly_fire and not _ability_can_friendly_fire(ability):
					continue
				messages.append_array(_apply_damage_ability(user, target, ability, battlefield, friendly_fire))
			_reveal_after_offensive_action(user)
		AbilityData.AbilityType.HEAL:
			for target in targets:
				if target == null or not target.is_alive() or target.side != user.side:
					continue
				messages.append_array(_apply_heal_ability(user, target, ability))
		AbilityData.AbilityType.BUFF:
			for target in targets:
				if target == null or not target.is_alive() or target.side != user.side:
					continue
				messages.append_array(_apply_buff_ability(user, target, ability))
		_:
			pass

	if messages.is_empty():
		return messages
	messages.push_front("%s использует %s." % [user.display_name, ability.name])
	return messages

func _spend_attack_resources(unit) -> bool:
	var cost := 3.0
	if unit.stamina < cost:
		return false
	unit.stamina = maxf(0.0, unit.stamina - cost)
	unit.energy = maxf(0.0, unit.energy - 1.0)
	return true

func _spend_ability_resources(unit, ability: AbilityData) -> bool:
	var cost := 6.0 + maxf(0.0, ability.rt_cast_time) * 8.0 + maxf(0.0, ability.power - 1.0) * 3.0
	if ability.stat_used == "magic":
		if unit.mana < cost:
			return false
		unit.mana = maxf(0.0, unit.mana - cost)
	elif ability.stat_used == "speed":
		if unit.energy < cost:
			return false
		unit.energy = maxf(0.0, unit.energy - cost)
	else:
		if unit.stamina < cost:
			return false
		unit.stamina = maxf(0.0, unit.stamina - cost)
	unit.add_recent_event("resource", ability.name, int(round(cost)))
	return true

func _ability_can_friendly_fire(ability: AbilityData) -> bool:
	if ability == null:
		return false
	return ability.rt_radius_tiles > 0.0 and ability.id in ["fireball", "guardian_smite"]

func _targets_with_friendly_fire(user, ability: AbilityData, targets: Array) -> Array:
	if not _ability_can_friendly_fire(ability) or targets.is_empty():
		return targets
	var result: Array = targets.duplicate()
	var center = targets[0]
	if center == null:
		return result
	for unit in active_units:
		if unit == null or unit == user or not unit.is_alive() or unit.side != user.side:
			continue
		if Vector2(unit.grid_pos - center.grid_pos).length() > ability.rt_radius_tiles:
			continue
		if not result.has(unit):
			result.append(unit)
	return result

func _emit_ability_used(user, ability: AbilityData) -> void:
	if ability == null:
		return
	_events.append({
		"type": "ability_used",
		"attacker": user,
		"ability": ability
	})

func _emit_area_event(user, ability: AbilityData, targets: Array) -> void:
	if ability == null or ability.rt_radius_tiles <= 0.0 or targets.is_empty():
		return
	var center = targets[0]
	if center == null:
		return
	_events.append({
		"type": "area",
		"attacker": user,
		"target": center,
		"center": center.world_position,
		"radius_tiles": ability.rt_radius_tiles,
		"ability": ability,
		"target_count": targets.size()
	})

func _apply_damage_ability(user, target, ability: AbilityData, battlefield, friendly_fire: bool = false) -> Array[String]:
	var messages: Array[String] = []
	var stat_value: int = user.get_stat(ability.stat_used)
	var raw: int = int(round(float(stat_value) * ability.power)) - target.get_stat("def") / 2
	if ability.type == AbilityData.AbilityType.DEBUFF:
		raw = max(raw, 1)
	var damage: int = maxi(1, raw + rng.randi_range(-1, 2))
	damage = maxi(1, int(round(float(damage) * _coordination_multiplier(user, target))))
	var ambush_multiplier: float = _ambush_multiplier(user, target, battlefield)
	if ambush_multiplier > 1.0:
		damage = maxi(1, int(round(float(damage) * ambush_multiplier)))
		messages.append("%s атакует из засады." % user.display_name)
		_reveal_after_ambush(user, target, damage)
	if friendly_fire:
		damage = maxi(1, roundi(float(damage) * 0.55))
	damage = _scaled_damage(damage)
	target.take_damage(damage)
	user.fear = clampf(user.fear - 0.05, 0.0, 1.0)
	user.morale = clampf(user.morale + 0.04, 0.0, 1.0)
	if friendly_fire:
		target.fear = clampf(target.fear + 0.08, 0.0, 1.0)
		messages.append("%s задет союзным %s: %d урона." % [target.display_name, ability.name, damage])
	else:
		messages.append("%s получает %d урона от %s." % [target.display_name, damage, ability.name])
	_events.append({
		"type": "damage",
		"attacker": user,
		"target": target,
		"amount": damage,
		"ability": ability,
		"friendly_fire": friendly_fire
	})
	_apply_secondary_effects(user, target, ability, damage)
	if not target.is_alive():
		messages.append("%s выведен из боя." % target.display_name)
	return messages

func _apply_heal_ability(user, target, ability: AbilityData) -> Array[String]:
	var before: int = target.battle_unit.current_hp
	var stat_value: int = user.get_stat(ability.stat_used)
	var amount: int = maxi(2, int(round(float(stat_value) * ability.power)) + rng.randi_range(0, 2))
	target.heal(amount)
	var healed: int = target.battle_unit.current_hp - before
	if healed <= 0:
		return []
	target.morale = clampf(target.morale + 0.08, 0.0, 1.0)
	target.fear = clampf(target.fear - 0.08, 0.0, 1.0)
	_events.append({
		"type": "heal",
		"attacker": user,
		"target": target,
		"amount": healed,
		"ability": ability
	})
	return ["%s восстанавливает %d HP." % [target.display_name, healed]]

func _apply_buff_ability(user, target, ability: AbilityData) -> Array[String]:
	_apply_secondary_effects(user, target, ability, 0)
	target.morale = clampf(target.morale + 0.12, 0.0, 1.0)
	target.fear = clampf(target.fear - 0.06, 0.0, 1.0)
	_events.append({
		"type": "buff",
		"attacker": user,
		"target": target,
		"amount": 0,
		"ability": ability
	})
	return ["%s получает эффект %s." % [target.display_name, ability.name]]

func _apply_secondary_effects(user, target, ability: AbilityData, damage: int) -> void:
	for raw_effect in ability.effects:
		var effect: String = str(raw_effect)
		if effect.begins_with("def_buff_"):
			target.apply_stat_modifier("def", int(effect.get_slice("_", 2)), 5.0)
			if ability.id == "guard":
				target.add_status("guard", 5.0)
		elif effect.begins_with("atk_buff_"):
			target.apply_stat_modifier("atk", int(effect.get_slice("_", 2)), 5.0)
		elif effect.begins_with("initiative_buff_"):
			target.apply_stat_modifier("initiative", int(effect.get_slice("_", 2)), 5.0)
		elif effect.begins_with("self_def_debuff_"):
			user.apply_stat_modifier("def", -int(effect.get_slice("_", 3)), 4.0)
		elif effect == "mark_debuff":
			target.apply_stat_modifier("def", -2, 5.0)
			target.fear = clampf(target.fear + 0.05, 0.0, 1.0)
			target.add_status("marked", 5.0)
		elif effect == "evade_buff":
			target.add_status("evade", 4.0)
			target.apply_stat_modifier("initiative", 2, 4.0)
		elif effect == "cleanse":
			target.clear_negative_statuses()
		elif effect.begins_with("poison_"):
			var poison_damage := maxi(1, int(effect.get_slice("_", 1)))
			target.add_status("poison", 5.0, {"damage": poison_damage, "tick_timer": 1.0})
		elif effect.begins_with("lifesteal_") and damage > 0:
			var percent: float = float(effect.get_slice("_", 1)) / 100.0
			var healed: int = int(round(float(damage) * percent))
			if healed > 0:
				user.heal(healed)
				_events.append({
					"type": "heal",
					"attacker": user,
					"target": user,
					"amount": healed,
					"ability": ability
				})
		elif effect.begins_with("stun_chance_"):
			if rng.randi_range(1, 100) <= int(effect.get_slice("_", 2)):
				target.fear = clampf(target.fear + 0.12, 0.0, 1.0)
				target.add_status("stun", 1.1)

func _ambush_multiplier(attacker, target, battlefield) -> float:
	if attacker == null or target == null or battlefield == null:
		return 1.0
	if target.visible_enemies.has(attacker):
		return 1.0
	var hiding_bonus: float = 0.0
	if attacker.hidden or attacker.ambush_ready:
		hiding_bonus += 0.18 + attacker.stealth_rating * 0.32
	if battlefield.is_grass(attacker.grid_pos):
		hiding_bonus += 0.12
	elif battlefield.is_cover(attacker.grid_pos):
		hiding_bonus += 0.1
	elif _near_vision_blocker(attacker.grid_pos, battlefield):
		hiding_bonus += 0.08
	if hiding_bonus <= 0.0:
		return 1.0
	return 1.0 + clampf(hiding_bonus, 0.0, 0.42)

func _coordination_multiplier(attacker, target) -> float:
	if attacker == null or target == null:
		return 1.0
	if attacker.side != BattleUnit.UnitSide.ALLY:
		return 1.0
	if attacker.squad_focus_target_id == "" or attacker.squad_focus_target_id != target.unit_id:
		return 1.0
	var bonus: float = attacker.brain_value("teamwork") * 0.18 + attacker.brain_value("leader_trust") * 0.08
	if attacker.squad_style == "aggressive":
		bonus += 0.12
	elif attacker.squad_style == "cohesive":
		bonus += 0.1
	if attacker.is_leader:
		bonus += 0.04
	return 1.0 + clampf(bonus, 0.0, 0.36)

func _near_vision_blocker(pos: Vector2i, battlefield) -> bool:
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var nearby: Vector2i = pos + offset
		if not battlefield.in_bounds(nearby) or battlefield.blocks_vision(nearby):
			return true
	return false

func _reveal_after_ambush(attacker, target, damage: int) -> void:
	attacker.hidden = false
	attacker.ambush_ready = false
	attacker.stealth_reveal_timer = 2.4
	target.fear = clampf(target.fear + 0.1, 0.0, 1.0)
	_events.append({
		"type": "ambush",
		"attacker": attacker,
		"target": target,
		"amount": damage
	})

func _reveal_after_offensive_action(unit) -> void:
	if unit == null or unit.stealth_rating <= 0.0:
		return
	unit.hidden = false
	unit.ambush_ready = false
	unit.stealth_reveal_timer = maxf(unit.stealth_reveal_timer, 1.4)

func consume_events() -> Array[Dictionary]:
	var result := _events.duplicate()
	_events.clear()
	return result

func _move_towards(
	unit,
	destination: Vector2i,
	delta: float,
	battlefield,
	map_origin: Vector2,
	allow_occupied_goal: bool = false
) -> Array[String]:
	var messages: Array[String] = []
	var movement_destination := _resolve_movement_destination(unit, destination, battlefield, allow_occupied_goal)
	if movement_destination == unit.grid_pos:
		unit.path.clear()
		unit.path_fail_count = 0
		return messages

	var path_may_end_occupied := allow_occupied_goal and movement_destination == destination
	if unit.path.is_empty() or unit.destination != movement_destination:
		unit.destination = movement_destination
		unit.path = battlefield.find_path(unit.grid_pos, movement_destination, unit.unit_id, path_may_end_occupied)

	if unit.path.is_empty():
		return _recover_from_blocked_path(unit, movement_destination, battlefield)

	var next_grid: Vector2i = unit.path[0]
	if battlefield.is_occupied(next_grid, unit.unit_id):
		unit.path = battlefield.find_path(unit.grid_pos, movement_destination, unit.unit_id, path_may_end_occupied)
		if unit.path.is_empty():
			return _recover_from_blocked_path(unit, movement_destination, battlefield)
		next_grid = unit.path[0]
		if battlefield.is_occupied(next_grid, unit.unit_id):
			unit.path.clear()
			return _recover_from_blocked_path(unit, movement_destination, battlefield)

	if _should_make_panic_mistake(unit):
		unit.panic_mistake_timer = rng.randf_range(0.9, 1.4)
		var panic_step: Vector2i = _panic_mistake_tile(unit, next_grid, movement_destination, battlefield)
		unit.path.clear()
		if panic_step == unit.grid_pos:
			messages.append("%s замирает от паники." % unit.display_name)
			return messages
		next_grid = panic_step
		unit.destination = panic_step
		unit.path = [panic_step]
		messages.append("%s сбивается с пути из-за паники." % unit.display_name)

	var next_world: Vector2 = battlefield.world_from_grid(next_grid, map_origin)
	var to_next: Vector2 = next_world - unit.world_position
	var distance: float = to_next.length()
	if distance <= 1.0:
		var previous_grid: Vector2i = unit.grid_pos
		unit.grid_pos = next_grid
		unit.world_position = next_world
		unit.path.remove_at(0)
		battlefield.move_occupant(previous_grid, next_grid, unit.unit_id)
		unit.path_fail_count = 0
		if battlefield.is_trap(next_grid):
			var trap_damage := 2
			unit.take_damage(trap_damage)
			unit.add_status("panic", 1.2)
			_events.append({
				"type": "status_damage",
				"status": "trap",
				"target": unit,
				"amount": trap_damage
			})
			messages.append("%s попадает в ловушку." % unit.display_name)
		if battlefield.is_noisy(next_grid):
			unit.heard_noise_strength = maxf(unit.heard_noise_strength, 0.7)
		_events.append({
			"type": "step",
			"target": unit,
			"tile": battlefield.get_tile(next_grid)
		})
		return messages

	if not battlefield.reserve_occupied(next_grid, unit.unit_id):
		unit.path.clear()
		return _recover_from_blocked_path(unit, movement_destination, battlefield)

	var speed: float = (
		battlefield.tile_size()
		* unit.speed_tiles_per_second
		* _movement_speed_multiplier(unit)
		/ battlefield.movement_cost(next_grid)
	)
	var step: float = minf(distance, speed * delta)
	var direction: Vector2 = to_next.normalized()
	unit.world_position += direction * step
	if direction.length() > 0.01:
		unit.facing = unit.facing.lerp(direction, minf(1.0, delta * 9.0)).normalized()
	unit.path_fail_count = 0
	return messages

func _resolve_movement_destination(unit, destination: Vector2i, battlefield, allow_occupied_goal: bool) -> Vector2i:
	if not allow_occupied_goal or not battlefield.is_occupied(destination, unit.unit_id):
		return destination

	var best: Vector2i = destination
	var best_score := INF
	for candidate in battlefield.get_neighbors(destination):
		if battlefield.is_occupied(candidate, unit.unit_id):
			continue
		if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
			continue
		var score: float = _grid_distance(unit.grid_pos, candidate)
		if score < best_score:
			best = candidate
			best_score = score
	return best

func _recover_from_blocked_path(unit, destination: Vector2i, battlefield) -> Array[String]:
	var messages: Array[String] = []
	unit.path_fail_count += 1
	unit.movement_recovery_timer = maxf(unit.movement_recovery_timer, 0.35)
	if unit.path_fail_count >= 7:
		unit.path_fail_count = 0
		unit.destination = unit.grid_pos
		unit.path.clear()
		unit.current_action.clear()
		unit.add_recent_event("path_failed", "маршрут недоступен")
		if unit.movement_notice_timer <= 0.0:
			messages.append("%s прекращает недоступный манёвр." % unit.display_name)
			unit.movement_notice_timer = 1.8
		return messages
	var fallback: Vector2i = _best_recovery_destination(unit, destination, battlefield)
	if fallback != unit.grid_pos:
		unit.destination = fallback
		unit.path = battlefield.find_path(unit.grid_pos, fallback, unit.unit_id, false)
		if not unit.path.is_empty():
			if unit.movement_notice_timer <= 0.0:
				messages.append("%s ищет обход." % unit.display_name)
				unit.movement_notice_timer = 1.8
			return messages

	unit.path.clear()
	if unit.movement_notice_timer <= 0.0:
		messages.append("%s ждёт свободный проход." % unit.display_name)
		unit.movement_notice_timer = 1.8
	return messages

func _best_recovery_destination(unit, destination: Vector2i, battlefield) -> Vector2i:
	var best: Vector2i = unit.grid_pos
	var best_score := INF
	for radius in range(1, 5):
		for y in range(destination.y - radius, destination.y + radius + 1):
			for x in range(destination.x - radius, destination.x + radius + 1):
				var candidate := Vector2i(x, y)
				if not battlefield.in_bounds(candidate) or not battlefield.is_walkable(candidate):
					continue
				if battlefield.is_occupied(candidate, unit.unit_id):
					continue
				if candidate != unit.grid_pos and battlefield.find_path(unit.grid_pos, candidate, unit.unit_id, false).is_empty():
					continue
				var score: float = _grid_distance(candidate, destination) + _grid_distance(unit.grid_pos, candidate) * 0.2
				if score < best_score:
					best = candidate
					best_score = score
		if best != unit.grid_pos:
			return best

	for neighbor in battlefield.get_neighbors(unit.grid_pos):
		if battlefield.is_occupied(neighbor, unit.unit_id):
			continue
		return neighbor
	return unit.grid_pos

func _movement_speed_multiplier(unit) -> float:
	var fear: float = clampf(unit.fear, 0.0, 1.0)
	if unit.intent in ["retreat", "keep_distance", "berserk_charge", "press_attack"]:
		if unit.intent in ["berserk_charge", "press_attack"]:
			return 1.05 + fear * 0.08
		return 1.0 + fear * 0.18
	if fear > 0.55:
		return 1.0 - minf(0.28, (fear - 0.55) * 0.62)
	return 1.0

func _scaled_damage(amount: int) -> int:
	if amount <= 0:
		return amount
	return maxi(1, int(round(float(amount) * clampf(damage_multiplier, 0.35, 1.75))))

func _should_make_panic_mistake(unit) -> bool:
	if unit.panic_mistake_timer > 0.0:
		return false
	if unit.intent in ["retreat", "keep_distance"]:
		return false
	var fear: float = clampf(unit.fear, 0.0, 1.0)
	if fear < 0.72:
		return false
	var chance: float = minf(0.16, (fear - 0.72) * 0.55)
	return rng.randf() < chance

func _panic_mistake_tile(unit, intended_next: Vector2i, destination: Vector2i, battlefield) -> Vector2i:
	if rng.randf() < 0.35:
		return unit.grid_pos

	var best: Vector2i = unit.grid_pos
	var best_score := INF
	for candidate in battlefield.get_neighbors(unit.grid_pos):
		if candidate == intended_next:
			continue
		if battlefield.is_occupied(candidate, unit.unit_id):
			continue
		var score: float = _grid_distance(candidate, destination) + rng.randf_range(0.0, 1.2)
		if score < best_score:
			best = candidate
			best_score = score
	return best

func _grid_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

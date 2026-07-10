class_name RTActionResolver
extends RefCounted

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _events: Array[Dictionary] = []

func update_unit(unit, delta: float, intent: Dictionary, battlefield, map_origin: Vector2) -> Array[String]:
	_events.clear()
	var messages: Array[String] = []
	if not unit.is_alive():
		return messages

	unit.tick_rt_state(delta)
	unit.attack_timer = maxf(0.0, unit.attack_timer - delta)
	var type: String = str(intent.get("type", "hold"))
	var destination: Vector2i = intent.get("destination", unit.grid_pos)
	var target = intent.get("target", null)
	var ability: AbilityData = intent.get("ability", null)
	var targets: Array = intent.get("targets", [])
	unit.set_intent(type, str(intent.get("reason", "оценивает ситуацию")), destination, target, ability)

	match type:
		"ability":
			if ability != null:
				if _can_use_ability_now(unit, ability, targets, battlefield):
					messages.append_array(_try_ability(unit, ability, targets))
				elif target != null and target.is_alive():
					_move_towards(unit, target.grid_pos, delta, battlefield, map_origin)
		"attack":
			if target != null and target.is_alive():
				messages.append_array(_try_attack(unit, target))
				if _grid_distance(unit.grid_pos, target.grid_pos) > unit.attack_range_tiles:
					_move_towards(unit, target.grid_pos, delta, battlefield, map_origin)
		"chase", "retreat", "take_cover", "follow", "patrol", "ambush":
			_move_towards(unit, destination, delta, battlefield, map_origin)
		"hold":
			unit.hold_timer += delta
		_:
			unit.hold_timer += delta

	return messages

func _try_attack(attacker, target) -> Array[String]:
	var messages: Array[String] = []
	if attacker.attack_timer > 0.0:
		return messages
	if _grid_distance(attacker.grid_pos, target.grid_pos) > attacker.attack_range_tiles:
		return messages

	attacker.attack_timer = attacker.attack_cooldown
	var basic_ability: AbilityData = _basic_attack_ability(attacker)
	if basic_ability != null and attacker.can_use_ability(basic_ability):
		attacker.mark_ability_used(basic_ability)
		messages.append_array(_apply_damage_ability(attacker, target, basic_ability))
		if not messages.is_empty():
			messages.push_front("%s использует %s." % [attacker.display_name, basic_ability.name])
		return messages

	var raw: int = attacker.get_stat("atk") - target.get_stat("def") / 2
	if attacker.get_stat("magic") > attacker.get_stat("atk") and attacker.attack_range_tiles > 2.0:
		raw = attacker.get_stat("magic") - target.get_stat("def") / 3
	var damage: int = maxi(1, raw + rng.randi_range(-1, 2))
	target.take_damage(damage)
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
		if _grid_distance(user.grid_pos, target.grid_pos) <= user.ability_range_tiles(ability):
			if target.side == user.side or battlefield.has_line_of_sight(user.grid_pos, target.grid_pos):
				return true
	return false

func _try_ability(user, ability: AbilityData, targets: Array) -> Array[String]:
	var messages: Array[String] = []
	if not user.can_use_ability(ability) or targets.is_empty():
		return messages
	user.mark_ability_used(ability)
	_emit_area_event(user, ability, targets)

	match ability.type:
		AbilityData.AbilityType.DAMAGE, AbilityData.AbilityType.DEBUFF, AbilityData.AbilityType.SPECIAL:
			for target in targets:
				if target == null or not target.is_alive() or target.side == user.side:
					continue
				messages.append_array(_apply_damage_ability(user, target, ability))
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

func _apply_damage_ability(user, target, ability: AbilityData) -> Array[String]:
	var messages: Array[String] = []
	var stat_value: int = user.get_stat(ability.stat_used)
	var raw: int = int(round(float(stat_value) * ability.power)) - target.get_stat("def") / 2
	if ability.type == AbilityData.AbilityType.DEBUFF:
		raw = max(raw, 1)
	var damage: int = maxi(1, raw + rng.randi_range(-1, 2))
	target.take_damage(damage)
	user.fear = clampf(user.fear - 0.05, 0.0, 1.0)
	user.morale = clampf(user.morale + 0.04, 0.0, 1.0)
	messages.append("%s получает %d урона от %s." % [target.display_name, damage, ability.name])
	_events.append({
		"type": "damage",
		"attacker": user,
		"target": target,
		"amount": damage,
		"ability": ability
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
		elif effect.begins_with("atk_buff_"):
			target.apply_stat_modifier("atk", int(effect.get_slice("_", 2)), 5.0)
		elif effect.begins_with("initiative_buff_"):
			target.apply_stat_modifier("initiative", int(effect.get_slice("_", 2)), 5.0)
		elif effect.begins_with("self_def_debuff_"):
			user.apply_stat_modifier("def", -int(effect.get_slice("_", 3)), 4.0)
		elif effect == "mark_debuff":
			target.apply_stat_modifier("def", -2, 5.0)
			target.fear = clampf(target.fear + 0.05, 0.0, 1.0)
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

func consume_events() -> Array[Dictionary]:
	var result := _events.duplicate()
	_events.clear()
	return result

func _move_towards(unit, destination: Vector2i, delta: float, battlefield, map_origin: Vector2) -> void:
	if destination == unit.grid_pos:
		unit.path.clear()
		return

	if unit.path.is_empty() or unit.destination != destination:
		unit.destination = destination
		unit.path = battlefield.find_path(unit.grid_pos, destination)

	if unit.path.is_empty():
		return

	var next_grid: Vector2i = unit.path[0]
	var next_world: Vector2 = battlefield.world_from_grid(next_grid, map_origin)
	var to_next: Vector2 = next_world - unit.world_position
	var distance: float = to_next.length()
	if distance <= 1.0:
		unit.grid_pos = next_grid
		unit.world_position = next_world
		unit.path.remove_at(0)
		return

	var speed: float = battlefield.tile_size() * unit.speed_tiles_per_second / battlefield.movement_cost(next_grid)
	var step: float = minf(distance, speed * delta)
	var direction: Vector2 = to_next.normalized()
	unit.world_position += direction * step
	if direction.length() > 0.01:
		unit.facing = direction

func _grid_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

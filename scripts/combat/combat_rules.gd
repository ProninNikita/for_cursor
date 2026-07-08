extends RefCounted

var simulation

func _init(combat_simulation) -> void:
	simulation = combat_simulation

func execute_basic_attack(user: BattleUnit, target: BattleUnit, style: String = "strike") -> Array[String]:
	var messages: Array[String] = []
	var damage: int = simulation.calc_damage(user, target)
	target.take_damage(damage)
	simulation.record_damage_dealt(user, damage)
	simulation.record_damage_taken(target, damage)

	if style == "ally_auto":
		messages.append("%s выбирает простую атаку по %s: %d урона." % [user.display_name, target.display_name, damage])
	else:
		messages.append("%s бьёт %s на %d урона." % [user.display_name, target.display_name, damage])

	if not target.is_alive():
		messages.append(_defeat_message(target))
	return messages

func execute_ability(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = _apply_ability_to_target(ability, user, target)
	ability.use()
	user.tick_cooldowns()
	return messages

func execute_ability_on_targets(ability: AbilityData, user: BattleUnit, targets: Array[BattleUnit]) -> Array[String]:
	var messages: Array[String] = []
	var used := false
	for target in targets:
		if target.is_alive():
			messages.append_array(_apply_ability_to_target(ability, user, target))
			used = true
	if used:
		ability.use()
		user.tick_cooldowns()
	return messages

func apply_turn_end(actor: BattleUnit) -> Array[String]:
	var messages: Array[String] = []
	var result: Dictionary = actor.tick_battle_state()
	for msg in result["messages"]:
		messages.append(str(msg))

	if result["damage"] > 0:
		actor.take_ability_damage(result["damage"])

	if result["heal"] > 0:
		actor.heal(result["heal"])

	return messages

func _apply_ability_to_target(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	match ability.type:
		AbilityData.AbilityType.DAMAGE:
			return _deal_ability_damage(ability, user, target)
		AbilityData.AbilityType.HEAL:
			return _apply_heal(ability, user, target)
		AbilityData.AbilityType.BUFF:
			return _apply_buff(ability, user, target)
		AbilityData.AbilityType.DEBUFF:
			return _apply_debuff(ability, user, target)
		AbilityData.AbilityType.SPECIAL:
			return _apply_special(ability, user, target)
		_:
			return _empty_messages()

func _deal_ability_damage(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = []
	var stat_value := user.get_stat(ability.stat_used)
	var base_damage := stat_value * ability.power

	var mark_bonus := 0
	if target.battle_state != null and target.battle_state.has_mark():
		mark_bonus = target.battle_state.get_mark_bonus_damage()

	var defense := target.get_stat("def")
	var damage := int(maxi(1, base_damage + mark_bonus - defense / 2))

	if simulation.rng.randf() < 0.5:
		damage = int(damage * 0.9)
	else:
		damage = int(damage * 1.1)

	var hp_before := target.current_hp
	target.take_ability_damage(damage)
	var applied_damage := hp_before - target.current_hp
	simulation.record_damage_dealt(user, applied_damage)
	simulation.record_damage_taken(target, applied_damage)
	messages.append("%s использует %s на %s: %d урона!" % [user.display_name, ability.name, target.display_name, damage])

	messages.append_array(_apply_ability_effects(ability, user, target))

	if not target.is_alive():
		messages.append(_defeat_message(target))
	return messages

func _apply_heal(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = []
	var stat_value := user.get_stat(ability.stat_used)
	var heal_amount := int(stat_value * ability.power)
	var hp_before := target.current_hp
	target.heal(heal_amount)
	var applied_heal := target.current_hp - hp_before
	simulation.record_healing_done(user, applied_heal)
	messages.append("%s использует %s на %s: +%d HP" % [user.display_name, ability.name, target.display_name, heal_amount])
	messages.append_array(_apply_ability_effects(ability, user, target))
	return messages

func _apply_buff(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = ["%s использует %s на %s!" % [user.display_name, ability.name, target.display_name]]
	messages.append_array(_apply_ability_effects(ability, user, target))
	return messages

func _apply_debuff(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = ["%s использует %s на %s!" % [user.display_name, ability.name, target.display_name]]
	messages.append_array(_apply_ability_effects(ability, user, target))
	return messages

func _apply_special(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = ["%s использует %s!" % [user.display_name, ability.name]]
	messages.append_array(_apply_ability_effects(ability, user, target))
	return messages

func _apply_ability_effects(ability: AbilityData, user: BattleUnit, target: BattleUnit) -> Array[String]:
	var messages: Array[String] = []
	for effect in ability.effects:
		var effect_target := target
		var effect_text := str(effect)
		if effect_text.begins_with("self_"):
			effect_target = user
			effect_text = effect_text.substr(5)
		if effect_target.battle_state == null:
			continue
		messages.append_array(_parse_and_apply_effect(effect_text, effect_target, user))
	return messages

func _parse_and_apply_effect(effect_str: String, target: BattleUnit, user: BattleUnit) -> Array[String]:
	var messages: Array[String] = []
	var parts := effect_str.split("_")
	if parts.is_empty():
		return messages

	var effect_type := parts[0]
	var value := 0
	var duration := 0
	var mode := ""

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
			if simulation.rng.randf() * 100 < value:
				target.battle_state.apply_effect(BattleState.EffectType.STUN, duration)
				messages.append("%s оглушён!" % target.display_name)
		"poison":
			target.battle_state.apply_effect(BattleState.EffectType.POISON, duration, value)
			messages.append("%s отравлен на %d!" % [target.display_name, duration])
		"regen":
			target.battle_state.apply_effect(BattleState.EffectType.REGEN, duration, value)
			messages.append("%s восстанавливает HP каждый ход!" % target.display_name)
		"atk":
			if "buff" in effect_str:
				target.battle_state.atk_modifier += value
				target.battle_state.apply_effect(BattleState.EffectType.ATK_BUFF, duration, value)
				messages.append("Атака %s повышена на %d!" % [target.display_name, value])
			elif "debuff" in effect_str:
				target.battle_state.atk_modifier -= value
				target.battle_state.apply_effect(BattleState.EffectType.ATK_DEBUFF, duration, value)
				messages.append("Атака %s понижена на %d!" % [target.display_name, value])
		"def":
			if "buff" in effect_str:
				target.battle_state.def_modifier += value
				target.battle_state.apply_effect(BattleState.EffectType.DEF_BUFF, duration, value)
				messages.append("Защита %s повышена на %d!" % [target.display_name, value])
			elif "debuff" in effect_str:
				target.battle_state.def_modifier -= value
				target.battle_state.apply_effect(BattleState.EffectType.DEF_DEBUFF, duration, value)
				messages.append("Защита %s понижена на %d!" % [target.display_name, value])
		"mark":
			target.battle_state.apply_effect(BattleState.EffectType.MARK, duration, value)
			messages.append("%s помечен! Бонусный урон +%d" % [target.display_name, value])
		"evade":
			target.battle_state.apply_effect(BattleState.EffectType.EVADE, duration, 0)
			messages.append("%s уклоняется от атак!" % target.display_name)
		"taunt":
			target.battle_state.apply_effect(BattleState.EffectType.TAUNT, duration, 0)
			messages.append("%s провоцирует врагов!" % target.display_name)
		"initiative":
			if "buff" in effect_str:
				target.battle_state.initiative_modifier += value
				target.initiative += value
				target.battle_state.apply_effect(BattleState.EffectType.INITIATIVE_BUFF, duration, value)
				messages.append("Инициатива %s повышена на %d!" % [target.display_name, value])
		"lifesteal":
			var heal_amount := int(user.get_stat("atk") * value / 100.0)
			user.heal(heal_amount)
			messages.append("%s восстанавливает %d HP от вампиризма!" % [user.display_name, heal_amount])
		"cleanse":
			target.battle_state.clear_all_effects()
			messages.append("Все эффекты с %s сняты!" % target.display_name)

	return messages

func _defeat_message(target: BattleUnit) -> String:
	if target.side == BattleUnit.UnitSide.ALLY:
		return "%s пал в бою." % target.display_name
	return "%s повержен." % target.display_name

func _empty_messages() -> Array[String]:
	var messages: Array[String] = []
	return messages

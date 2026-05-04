class_name BattleState
extends RefCounted

enum EffectType {
	STUN,
	POISON,
	REGEN,
	ATK_BUFF,
	DEF_BUFF,
	ATK_DEBUFF,
	DEF_DEBUFF,
	MARK,
	EVADE,
	TAUNT,
	INITIATIVE_BUFF
}

var atk_modifier: int = 0
var def_modifier: int = 0
var initiative_modifier: int = 0
var effects: Dictionary = {}

func _init():
	effects = {}

func apply_effect(effect_type: EffectType, duration: int, value: int = 0):
	var effect_key = _effect_type_to_string(effect_type)
	effects[effect_key] = {
		"type": effect_type,
		"duration": duration,
		"value": value
	}

func has_effect(effect_type: EffectType) -> bool:
	var effect_key = _effect_type_to_string(effect_type)
	return effects.has(effect_key) and effects[effect_key]["duration"] > 0

func get_effect_value(effect_type: EffectType) -> int:
	var effect_key = _effect_type_to_string(effect_type)
	if effects.has(effect_key):
		return effects[effect_key]["value"]
	return 0

func get_effect_duration(effect_type: EffectType) -> int:
	var effect_key = _effect_type_to_string(effect_type)
	if effects.has(effect_key):
		return effects[effect_key]["duration"]
	return 0

func remove_effect(effect_type: EffectType):
	var effect_key = _effect_type_to_string(effect_type)
	effects.erase(effect_key)

func clear_all_effects():
	effects.clear()
	atk_modifier = 0
	def_modifier = 0
	initiative_modifier = 0

func tick_down() -> Dictionary:
	var damage_to_apply: int = 0
	var heal_to_apply: int = 0
	var log_messages: PackedStringArray = []

	var keys_to_remove: PackedStringArray = []
	for key in effects:
		var effect = effects[key]
		effect["duration"] -= 1

		match effect["type"]:
			EffectType.POISON:
				var poison_damage = effect["value"]
				damage_to_apply += poison_damage
				log_messages.append("Отравление наносит %d урона" % poison_damage)
			EffectType.REGEN:
				var regen_heal = effect["value"]
				heal_to_apply += regen_heal
				log_messages.append("Регенерация восстанавливает %d HP" % regen_heal)

		if effect["duration"] <= 0:
			keys_to_remove.append(key)

	for key in keys_to_remove:
		var effect = effects[key]
		log_messages.append("Эффект %s закончился" % _effect_type_to_string(effect["type"]))
		effects.erase(key)

	return {
		"damage": damage_to_apply,
		"heal": heal_to_apply,
		"messages": log_messages
	}

func get_modified_stat(base_stat: int, stat_type: String) -> int:
	match stat_type:
		"atk":
			return base_stat + atk_modifier
		"def":
			return base_stat + def_modifier
		"initiative":
			return base_stat + initiative_modifier
		_:
			return base_stat

func is_stunned() -> bool:
	return has_effect(EffectType.STUN)

func is_taunting() -> bool:
	return has_effect(EffectType.TAUNT)

func has_mark() -> bool:
	return has_effect(EffectType.MARK)

func get_mark_bonus_damage() -> int:
	return get_effect_value(EffectType.MARK)

func get_status_summary() -> String:
	if effects.is_empty():
		return ""

	var parts: PackedStringArray = []
	for key in effects:
		var effect = effects[key]
		var duration_str = "(%d)" % effect["duration"] if effect["duration"] > 1 else ""
		parts.append("%s%s" % [_effect_type_to_display_name(effect["type"]), duration_str])

	return " [%s]" % ", ".join(parts)

static func _effect_type_to_string(effect_type: EffectType) -> String:
	match effect_type:
		EffectType.STUN: return "stun"
		EffectType.POISON: return "poison"
		EffectType.REGEN: return "regen"
		EffectType.ATK_BUFF: return "atk_buff"
		EffectType.DEF_BUFF: return "def_buff"
		EffectType.ATK_DEBUFF: return "atk_debuff"
		EffectType.DEF_DEBUFF: return "def_debuff"
		EffectType.MARK: return "mark"
		EffectType.EVADE: return "evade"
		EffectType.TAUNT: return "taunt"
		EffectType.INITIATIVE_BUFF: return "initiative_buff"
		_: return ""

static func _effect_type_to_display_name(effect_type: EffectType) -> String:
	match effect_type:
		EffectType.STUN: return "Оглушение"
		EffectType.POISON: return "Отравление"
		EffectType.REGEN: return "Регенерация"
		EffectType.ATK_BUFF: return "Атака+"
		EffectType.DEF_BUFF: return "Защита+"
		EffectType.ATK_DEBUFF: return "Атака-"
		EffectType.DEF_DEBUFF: return "Защита-"
		EffectType.MARK: return "Метка"
		EffectType.EVADE: return "Уклонение"
		EffectType.TAUNT: return "Насмешка"
		EffectType.INITIATIVE_BUFF: return "Иниц+"
		_: return "?"

func clone() -> BattleState:
	var cloned = BattleState.new()
	cloned.atk_modifier = atk_modifier
	cloned.def_modifier = def_modifier
	cloned.initiative_modifier = initiative_modifier
	for key in effects:
		cloned.effects[key] = effects[key].duplicate()
	return cloned

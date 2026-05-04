class_name AbilityData
extends RefCounted

enum AbilityType { DAMAGE, HEAL, BUFF, DEBUFF, SPECIAL, PASSIVE }
enum TargetType { SELF, SINGLE_ALLY, SINGLE_ENEMY, ALL_ALLIES, ALL_ENEMIES }

var id: String
var name: String
var description: String
var type: AbilityType
var target_type: TargetType
var stat_used: String = "atk"
var power: float = 1.0
var cooldown_max: int = 0
var cooldown_current: int = 0
var effects: Array = []

static func from_dict(data: Dictionary) -> AbilityData:
	var ability = AbilityData.new()
	ability.id = data.get("id", "")
	ability.name = data.get("name", "Неизвестная способность")
	ability.description = data.get("description", "")
	ability.stat_used = data.get("stat_used", "atk")
	ability.power = float(data.get("power", 1.0))
	ability.cooldown_max = int(data.get("cooldown", 0))
	ability.cooldown_current = 0
	ability.effects = data.get("effects", [])

	var type_str = data.get("type", "damage").to_lower()
	ability.type = _parse_type(type_str)

	var target_str = data.get("target_type", "single_enemy").to_lower()
	ability.target_type = _parse_target_type(target_str)

	return ability

static func _parse_type(type_str: String) -> AbilityType:
	match type_str:
		"damage": return AbilityType.DAMAGE
		"heal": return AbilityType.HEAL
		"buff": return AbilityType.BUFF
		"debuff": return AbilityType.DEBUFF
		"special": return AbilityType.SPECIAL
		"passive": return AbilityType.PASSIVE
		_: return AbilityType.DAMAGE

static func _parse_target_type(target_str: String) -> TargetType:
	match target_str:
		"self": return TargetType.SELF
		"single_ally": return TargetType.SINGLE_ALLY
		"single_enemy": return TargetType.SINGLE_ENEMY
		"all_allies": return TargetType.ALL_ALLIES
		"all_enemies": return TargetType.ALL_ENEMIES
		_: return TargetType.SINGLE_ENEMY

func can_use() -> bool:
	return cooldown_current == 0

func use():
	cooldown_current = cooldown_max

func tick_cooldown():
	cooldown_current = maxi(0, cooldown_current - 1)

func clone() -> AbilityData:
	var cloned = AbilityData.new()
	cloned.id = id
	cloned.name = name
	cloned.description = description
	cloned.type = type
	cloned.target_type = target_type
	cloned.stat_used = stat_used
	cloned.power = power
	cloned.cooldown_max = cooldown_max
	cloned.cooldown_current = cooldown_current
	cloned.effects = effects.duplicate()
	return cloned

func get_display_name_with_cooldown() -> String:
	if cooldown_max == 0:
		return name
	if cooldown_current > 0:
		return "%s (%d)" % [name, cooldown_current]
	return name

func is_offensive() -> bool:
	return type == AbilityType.DAMAGE or type == AbilityType.DEBUFF

func is_support() -> bool:
	return type == AbilityType.HEAL or type == AbilityType.BUFF

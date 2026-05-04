class_name BattleUnit
extends RefCounted

enum UnitSide { ALLY, ENEMY }

var side: UnitSide = UnitSide.ALLY
var display_name: String = ""
var max_hp: int = 1
var current_hp: int = 1
var atk: int = 1
var def: int = 0
var magic: int = 0
var initiative: int = 5
var character_data: CharacterData
var tie_breaker: int = 0
var abilities: Array[AbilityData] = []
var battle_state: BattleState = null

func is_alive() -> bool:
	return current_hp > 0

func get_stat(stat: String) -> int:
	var base_stat := 0
	match stat:
		"atk": base_stat = atk
		"def": base_stat = def
		"magic": base_stat = magic
		"initiative": base_stat = initiative
		_: base_stat = 0

	if battle_state == null:
		return base_stat
	return battle_state.get_modified_stat(base_stat, stat)

func tick_cooldowns():
	for ability in abilities:
		ability.tick_cooldown()

func take_ability_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - amount)

func heal(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + amount)

func tick_battle_state() -> Dictionary:
	if battle_state == null:
		return {"damage": 0, "heal": 0, "messages": []}
	return battle_state.tick_down()

func is_stunned() -> bool:
	if battle_state == null:
		return false
	return battle_state.is_stunned()

func get_status_summary() -> String:
	if battle_state == null:
		return ""
	return battle_state.get_status_summary()

static func from_hero(cd: CharacterData, rng: RandomNumberGenerator) -> BattleUnit:
	var u := BattleUnit.new()
	u.side = UnitSide.ALLY
	u.character_data = cd
	u.display_name = cd.display_name
	u.max_hp = cd.get_max_hp()
	u.current_hp = u.max_hp
	u.atk = int(cd.stats.get("atk", 5))
	u.def = int(cd.stats.get("def", 0))
	u.magic = int(cd.stats.get("magic", 0))
	u.initiative = cd.get_initiative()
	u.tie_breaker = rng.randi()
	u.battle_state = BattleState.new()
	u._load_abilities_from_character_data(cd)
	return u

static func goblin(index: int, rng: RandomNumberGenerator) -> BattleUnit:
	var u := BattleUnit.new()
	u.side = UnitSide.ENEMY
	u.character_data = null
	u.display_name = "Гоблин %d" % (index + 1)
	u.max_hp = 14
	u.current_hp = 14
	u.atk = 3
	u.def = 1
	u.magic = 0
	u.initiative = 4
	u.tie_breaker = rng.randi()
	u.battle_state = BattleState.new()
	u._load_goblin_abilities()
	return u

func _load_abilities_from_character_data(cd: CharacterData):
	abilities.clear()
	for ability_id in cd.ability_ids:
		var ability = AbilityRegistry.get_ability(ability_id)
		if ability != null:
			abilities.append(ability.clone())

func _load_goblin_abilities():
	abilities.clear()
	var basic_attack = AbilityRegistry.get_ability("goblin_basic_attack")
	if basic_attack != null:
		abilities.append(basic_attack.clone())
	var poison_strike = AbilityRegistry.get_ability("goblin_poison_strike")
	if poison_strike != null:
		abilities.append(poison_strike.clone())

func take_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - amount)

class_name RTCombatUnitFactory
extends RefCounted

const UnitScript = preload("res://scripts/combat_rt/rt_battle_unit.gd")
const EnemyPlanEntryScript = preload("res://scripts/combat_rt/rt_enemy_plan_entry.gd")

func build_ally_units(
	squad: Array[CharacterData],
	battlefield,
	map_origin: Vector2,
	rng: RandomNumberGenerator
) -> Array:
	var units: Array = []
	for i in squad.size():
		var battle_unit := BattleUnit.from_hero(squad[i], rng)
		var spawn: Vector2i = battlefield.ally_spawns[i % battlefield.ally_spawns.size()]
		var unit = UnitScript.new()
		unit.setup_from_battle_unit(battle_unit, "ally_%d" % i, spawn, map_origin, battlefield)
		units.append(unit)
	return units

func build_enemy_units(
	enemy_plan: Array,
	enemy_archetypes: Dictionary,
	context,
	battlefield,
	map_origin: Vector2,
	rng: RandomNumberGenerator
) -> Array:
	var enemies: Array = []
	var index := 0
	for entry in enemy_plan:
		var plan_entry = EnemyPlanEntryScript.from_variant(entry)
		for _i in plan_entry.count:
			var enemy_unit: BattleUnit = _make_enemy_unit(plan_entry.enemy_type, index, plan_entry, enemy_archetypes, context, rng)
			var spawn: Vector2i = battlefield.enemy_spawns[index % battlefield.enemy_spawns.size()]
			var unit = UnitScript.new()
			unit.setup_from_battle_unit(enemy_unit, "enemy_%d" % index, spawn, map_origin, battlefield)
			unit.apply_enemy_profile(enemy_unit.enemy_profile)
			enemies.append(unit)
			index += 1
	if enemies.is_empty():
		for i in 3:
			var fallback_entry = EnemyPlanEntryScript.from_variant({"type": "goblin", "count": 1})
			var fallback_unit: BattleUnit = _make_enemy_unit("goblin", i, fallback_entry, enemy_archetypes, context, rng)
			var spawn: Vector2i = battlefield.enemy_spawns[i % battlefield.enemy_spawns.size()]
			var unit = UnitScript.new()
			unit.setup_from_battle_unit(fallback_unit, "enemy_%d" % i, spawn, map_origin, battlefield)
			unit.apply_enemy_profile(fallback_unit.enemy_profile)
			enemies.append(unit)
	return enemies

func _make_enemy_unit(
	enemy_type: String,
	index: int,
	plan_entry,
	enemy_archetypes: Dictionary,
	context,
	rng: RandomNumberGenerator
) -> BattleUnit:
	var archetype := _enemy_archetype(enemy_type, enemy_archetypes)
	var stats: Dictionary = archetype.get("stats", {})
	var scale: float = _enemy_scale_for_plan(plan_entry, context)
	var stat_scale: float = 1.0 + (scale - 1.0) * 0.55

	var unit := BattleUnit.new()
	unit.side = BattleUnit.UnitSide.ENEMY
	unit.character_data = null
	unit.display_name = _enemy_display_name(archetype, index)
	unit.max_hp = maxi(1, roundi(float(stats.get("hp", 14)) * scale))
	unit.current_hp = unit.max_hp
	unit.atk = maxi(1, roundi(float(stats.get("atk", 3)) * stat_scale))
	unit.def = maxi(0, roundi(float(stats.get("def", 1)) * stat_scale))
	unit.magic = maxi(0, roundi(float(stats.get("magic", 0)) * stat_scale))
	unit.initiative = maxi(1, roundi(float(stats.get("initiative", 4)) * stat_scale))
	unit.tie_breaker = rng.randi() if rng != null else randi()
	unit.battle_state = BattleState.new()
	unit.enemy_profile = _enemy_profile_from_archetype(archetype)
	var ability_ids: Array = archetype.get("abilities", ["goblin_basic_attack"])
	unit.load_abilities_by_ids(ability_ids)
	return unit

func _enemy_archetype(enemy_type: String, enemy_archetypes: Dictionary) -> Dictionary:
	if enemy_archetypes.has(enemy_type):
		var archetype: Dictionary = enemy_archetypes[enemy_type]
		return archetype
	push_warning("RT enemy archetype not found: " + enemy_type)
	return enemy_archetypes.get("goblin", {
		"name": "Гоблин",
		"numbered": true,
		"stats": {"hp": 14, "atk": 3, "def": 1, "magic": 0, "initiative": 4},
		"abilities": ["goblin_basic_attack"],
		"vision": {"radius_tiles": 5.2, "angle_deg": 130.0},
		"morale": 0.58,
		"ai": {}
	})

func _enemy_scale_for_plan(plan_entry, context) -> float:
	var scale: float = float(plan_entry.scale) if plan_entry != null else 1.0
	if context != null:
		scale *= context.modifier_float("enemy_scale", 1.0)
	return maxf(0.35, scale)

func _enemy_display_name(archetype: Dictionary, index: int) -> String:
	var base_name := str(archetype.get("name", "Гоблин"))
	if not bool(archetype.get("numbered", true)):
		return base_name
	return "%s %d" % [base_name, index + 1]

func _enemy_profile_from_archetype(archetype: Dictionary) -> Dictionary:
	return {
		"vision": archetype.get("vision", {}).duplicate(true),
		"morale": float(archetype.get("morale", 0.62)),
		"stealth": float(archetype.get("stealth", 0.0)),
		"ai": archetype.get("ai", {}).duplicate(true),
		"danger": float(archetype.get("danger", 1.0)),
		"reward_weight": float(archetype.get("reward_weight", 1.0)),
		"phases": archetype.get("phases", []).duplicate(true)
	}

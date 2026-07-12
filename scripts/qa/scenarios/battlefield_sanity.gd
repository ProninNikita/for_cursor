extends RefCounted

const BattlefieldScript = preload("res://scripts/combat_rt/rt_battlefield.gd")
const UnitScript = preload("res://scripts/combat_rt/rt_battle_unit.gd")
const PerceptionScript = preload("res://scripts/combat_rt/rt_perception.gd")
const ARENAS_PATH := "res://data/rt_arenas.json"

func run(driver, _fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: battlefield_sanity")
	var arena_ids := _arena_ids()
	driver.check(not arena_ids.is_empty(), "Нет доступных RT-арен для проверки")
	for arena_id in arena_ids:
		var battlefield = BattlefieldScript.new()
		driver.check(battlefield.setup_arena(arena_id), "Арена %s не загрузилась" % arena_id)
		driver.check(battlefield.arena_validation_errors.is_empty(), "Арена %s содержит ошибки валидации" % arena_id)
		driver.check(not battlefield.find_path(battlefield.ally_spawns[0], battlefield.enemy_spawns[0]).is_empty(), "Арена %s не даёт путь от союзника к врагу" % arena_id)

	var training = BattlefieldScript.new()
	driver.check(training.setup_arena("training_ruins"), "training_ruins не загрузилась для LOS-теста")
	driver.check(not training.has_line_of_sight(Vector2i(2, 2), Vector2i(15, 2)), "Стена не блокирует line-of-sight")

	var observer = _make_unit("observer", BattleUnit.UnitSide.ALLY, Vector2i(9, 8), training)
	var target = _make_unit("target", BattleUnit.UnitSide.ENEMY, Vector2i(13, 8), training)
	var perception = PerceptionScript.new()
	driver.check(training.is_grass(target.grid_pos), "Цель для grass-теста стоит не в траве")
	driver.check(not perception.can_see(observer, target, training), "Враг в траве виден с дистанции")

	var path_test = BattlefieldScript.new()
	driver.check(path_test.setup_arena("generated_mixed"), "generated_mixed не загрузилась")
	driver.check(not path_test.find_path(path_test.ally_spawns[0], path_test.enemy_spawns[0]).is_empty(), "Юнит не может найти путь на generated_mixed")
	_check_large_unit_pathing(driver)

func _check_large_unit_pathing(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("generated_rooms"), "generated_rooms не загрузилась для large-unit sanity")
	var units: Array = []
	for i in range(8):
		var spawn: Vector2i = battlefield.ally_spawns[i % battlefield.ally_spawns.size()]
		units.append(_make_unit("ally_%d" % i, BattleUnit.UnitSide.ALLY, spawn, battlefield))
	for i in range(12):
		var spawn: Vector2i = battlefield.enemy_spawns[i % battlefield.enemy_spawns.size()]
		var offset := Vector2i(i % 3, int(i / 3) % 3)
		var pos := spawn - offset
		if not battlefield.is_walkable(pos):
			pos = spawn
		units.append(_make_unit("enemy_%d" % i, BattleUnit.UnitSide.ENEMY, pos, battlefield))
	battlefield.rebuild_occupancy(units)
	var reachable := 0
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY:
			continue
		var path := battlefield.find_path(unit.grid_pos, battlefield.enemy_spawns[0], unit.unit_id, true)
		if not path.is_empty():
			reachable += 1
	driver.check(reachable > 0, "Большая группа не может построить ни одного маршрута")
	var stats := battlefield.path_cache_stats()
	driver.check(int(stats.get("entries", 0)) > 0, "Кэш путей не наполнился в large-unit sanity")

func _arena_ids() -> Array[String]:
	var file := FileAccess.open(ARENAS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return []
	var arenas: Dictionary = parsed.get("arenas", {})
	var result: Array[String] = []
	for arena_id in arenas.keys():
		result.append(str(arena_id))
	return result

func _make_unit(unit_id: String, side: int, spawn: Vector2i, battlefield):
	var battle_unit := BattleUnit.new()
	battle_unit.side = side
	battle_unit.display_name = unit_id
	battle_unit.max_hp = 10
	battle_unit.current_hp = 10
	battle_unit.initiative = 5
	var unit = UnitScript.new()
	unit.setup_from_battle_unit(battle_unit, unit_id, spawn, Vector2.ZERO, battlefield)
	unit.facing = Vector2.RIGHT
	return unit

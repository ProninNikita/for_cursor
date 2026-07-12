extends RefCounted

const BattlefieldScript = preload("res://scripts/combat_rt/rt_battlefield.gd")
const UnitScript = preload("res://scripts/combat_rt/rt_battle_unit.gd")
const PerceptionScript = preload("res://scripts/combat_rt/rt_perception.gd")
const ActionResolverScript = preload("res://scripts/combat_rt/rt_action_resolver.gd")
const PostBattleServiceScript = preload("res://scripts/combat_rt/rt_post_battle_service.gd")
const ARENAS_PATH := "res://data/rt_arenas.json"

func run(driver, fixtures, _context: Dictionary) -> void:
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
	_check_occupancy_cache(driver)
	_check_destructible_terrain(driver)
	_check_door_actions(driver)
	_check_trap_detection(driver)
	_check_height_rules(driver)
	_check_panic_movement(driver)
	_check_permadeath_archive(driver, fixtures)

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

func _check_occupancy_cache(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("training_ruins"), "training_ruins не загрузилась для occupancy sanity")
	var unit = _make_unit("cache_ally", BattleUnit.UnitSide.ALLY, battlefield.ally_spawns[0], battlefield)
	battlefield.rebuild_occupancy([unit])
	var first_revision := int(battlefield.path_cache_stats().get("revision", 0))
	battlefield.rebuild_occupancy([unit])
	var second_revision := int(battlefield.path_cache_stats().get("revision", 0))
	driver.check(first_revision == second_revision, "occupancy rebuild без движения меняет revision")
	unit.grid_pos = battlefield.ally_spawns[1]
	battlefield.rebuild_occupancy([unit])
	var moved_revision := int(battlefield.path_cache_stats().get("revision", 0))
	driver.check(moved_revision > second_revision, "occupancy rebuild после движения не меняет revision")

func _check_destructible_terrain(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("broken_halls"), "broken_halls не загрузилась для destructible sanity")
	var target := Vector2i(8, 6)
	driver.check(battlefield.is_destructible(target), "Клетка destructible sanity не destructible")
	var destroyed := battlefield.damage_destructible(target, 99)
	driver.check(destroyed, "destructible tile не разрушился от достаточного урона")
	driver.check(battlefield.is_walkable(target), "Разрушенный destructible tile не стал walkable")

func _check_door_actions(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("training_ruins"), "training_ruins не загрузилась для door sanity")
	var door := Vector2i(5, 5)
	driver.check(battlefield.is_door(door), "Клетка door sanity не является дверью")
	driver.check(battlefield.open_door(door), "Дверь не открылась через battlefield API")
	driver.check(not battlefield.is_door(door), "Открытая дверь осталась door tile")
	driver.check(battlefield.close_door(door), "Дверь не закрылась через battlefield API")
	driver.check(battlefield.block_door(door), "Дверь не заблокировалась через battlefield API")
	driver.check(battlefield.is_destructible(door), "Заблокированная дверь не стала destructible")

	var resolver_arena = BattlefieldScript.new()
	driver.check(resolver_arena.setup_arena("training_ruins"), "training_ruins не загрузилась для resolver door sanity")
	var unit = _make_unit("door_ally", BattleUnit.UnitSide.ALLY, Vector2i(4, 5), resolver_arena)
	unit.world_position = resolver_arena.world_from_grid(door, Vector2.ZERO)
	unit.destination = door
	var door_path: Array[Vector2i] = []
	door_path.append(door)
	unit.path = door_path
	var resolver = ActionResolverScript.new()
	var messages: Array[String] = resolver._move_towards(unit, door, 0.08, resolver_arena, Vector2.ZERO, false)
	driver.check(not resolver_arena.is_door(door), "Resolver не открыл дверь при движении")
	driver.check(not messages.is_empty(), "Resolver не вернул сообщение об открытии двери")

func _check_trap_detection(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("generated_mixed"), "generated_mixed не загрузилась для trap sanity")
	var trap := Vector2i(10, 6)
	driver.check(battlefield.is_trap(trap), "Клетка trap sanity не является ловушкой")
	var observer = _make_unit("trap_scout", BattleUnit.UnitSide.ALLY, Vector2i(10, 5), battlefield)
	var perception = PerceptionScript.new()
	perception.update([observer], battlefield)
	driver.check(battlefield.is_trap_detected(trap, BattleUnit.UnitSide.ALLY), "Perception не обнаружил близкую ловушку")
	driver.check(battlefield.trap_trigger_chance(trap, BattleUnit.UnitSide.ALLY) < battlefield.trap_trigger_chance(trap, BattleUnit.UnitSide.ENEMY), "Обнаруженная ловушка не снижает шанс срабатывания")

func _check_height_rules(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("training_ruins"), "training_ruins не загрузилась для height sanity")
	var high_pos := Vector2i(3, 3)
	driver.check(battlefield.is_height(high_pos), "Клетка height sanity не является высотой")
	var high_unit = _make_unit("high", BattleUnit.UnitSide.ALLY, high_pos, battlefield)
	var low_unit = _make_unit("low", BattleUnit.UnitSide.ALLY, Vector2i(3, 4), battlefield)
	var resolver = ActionResolverScript.new()
	driver.check(resolver._attack_range_for(high_unit, battlefield) > resolver._attack_range_for(low_unit, battlefield), "Высота не даёт бонус дальности атаки")

func _check_panic_movement(driver) -> void:
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("training_ruins"), "training_ruins не загрузилась для panic sanity")
	var unit = _make_unit("panic_ally", BattleUnit.UnitSide.ALLY, battlefield.ally_spawns[0], battlefield)
	unit.fear = 1.0
	var resolver = ActionResolverScript.new()
	resolver.rng.seed = 90817
	var panic_seen := false
	for _i in range(600):
		unit.fear = 1.0
		unit.panic_mistake_timer = 0.0
		battlefield.rebuild_occupancy([unit])
		var messages: Array[String] = resolver._move_towards(
			unit,
			battlefield.enemy_spawns[0],
			0.08,
			battlefield,
			Vector2.ZERO,
			false
		)
		for message in messages:
			if str(message).contains("паник"):
				panic_seen = true
				break
		if panic_seen:
			break
	driver.check(panic_seen, "Panic movement не сработал в sanity-прогоне")

func _check_permadeath_archive(driver, fixtures) -> void:
	fixtures.reset_game(0)
	var hero: CharacterData = fixtures.make_test_hero(77, "warrior")
	fixtures.state.roster.add_character(hero)
	var battlefield = BattlefieldScript.new()
	driver.check(battlefield.setup_arena("training_ruins"), "training_ruins не загрузилась для permadeath sanity")

	var battle_unit := BattleUnit.new()
	battle_unit.side = BattleUnit.UnitSide.ALLY
	battle_unit.display_name = hero.display_name
	battle_unit.character_data = hero
	battle_unit.max_hp = hero.get_max_hp()
	battle_unit.current_hp = 0
	battle_unit.atk = int(hero.stats.get("atk", 1))
	battle_unit.def = int(hero.stats.get("def", 1))
	battle_unit.initiative = hero.get_initiative()

	var unit = UnitScript.new()
	unit.setup_from_battle_unit(battle_unit, "fallen_test", battlefield.ally_spawns[0], Vector2.ZERO, battlefield)
	unit.last_damage_cause = "qa"
	unit.last_damage_source_name = "QA Enemy"
	unit.last_damage_ability_name = "QA Strike"
	unit.last_damage_source_side = BattleUnit.UnitSide.ENEMY

	var before_archive: int = fixtures.state.fallen_hero_count()
	var service = PostBattleServiceScript.new()
	service.apply(false, null, [unit], 12.5, "qa_permadeath")
	driver.check(fixtures.state.roster.get_by_id(hero.id) == null, "Погибший герой не удалён из ростера")
	driver.check(fixtures.state.fallen_hero_count() == before_archive + 1, "Погибший герой не попал в архив")
	var fallen: Array[Dictionary] = fixtures.state.get_fallen_heroes()
	var record: Dictionary = fallen[fallen.size() - 1] if not fallen.is_empty() else {}
	driver.check(str(record.get("hero_id", "")) == hero.id, "Архив погибших не сохранил hero_id")
	driver.check(str(record.get("killer", "")) == "QA Enemy", "Архив погибших не сохранил убийцу")

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

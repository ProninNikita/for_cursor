extends RefCounted

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const ELEVATION_SCENE := "res://scenes/tower/elevation.tscn"
const TOWER_SQUAD_SCENE := "res://scenes/tower/tower_squad.tscn"
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"
const ENEMY_ARCHETYPES_PATH := "res://data/rt_enemies.json"
const ENEMY_REWARD_GOLD_PER_WEIGHT := 4.0
const ENEMY_REWARD_LOOTBOX_WEIGHT := 8.0

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: tower_flow_smoke")
	fixtures.reset_game(5)
	var floor_data: Dictionary = fixtures.state.tower_elevation.get_floor_data(1)
	var rewards: Dictionary = _expected_tower_rewards(floor_data)
	var lootboxes_before: int = fixtures.state.lootboxes_remaining
	var gold_before: int = fixtures.state.gold

	await driver.load_scene(HUB_SCENE)
	await driver.press_qa("hub.tower")
	await driver.wait_for_scene(TOWER_LOBBY_SCENE)
	await driver.press_qa("tower_lobby.elevation")
	await driver.wait_for_scene(ELEVATION_SCENE)
	await driver.press_qa("elevation.floor.1")
	await driver.wait_for_scene(TOWER_SQUAD_SCENE)

	var checkboxes: Array = driver.find_checkboxes_with_prefix("tower_squad.hero.")
	driver.check(checkboxes.size() >= 3, "В выборе отряда меньше 3 героев")
	var expected_ids: Array[String] = []
	var roster_chars: Array = fixtures.state.roster.get_characters()
	for i in range(mini(3, checkboxes.size())):
		await driver.set_checkbox(checkboxes[i], true, "tower_squad.hero.%d" % i)
		expected_ids.append(roster_chars[i].id)

	await driver.press_qa("tower_squad.start")
	await driver.wait_for_scene(COMBAT_SCENE)
	var combat_root = driver.get_current_root()
	driver.check(_combat_has_selected_heroes(combat_root, expected_ids), "Выбранные герои не попали в RT-бой")
	await driver.wait_until(Callable(self, "_combat_finished").bind(driver), 15.0, "бой из возвышения должен завершиться")
	driver.check(_roster_hp_matches_combat_units(combat_root, fixtures.state), "HP ростера не синхронизирован после боя")
	driver.check(_selected_heroes_trained(fixtures.state, expected_ids), "Герой не получил combat_brain.battle_count после боя")
	driver.check(fixtures.state.pending_combat_squad.is_empty(), "После боя pending_combat_squad не очищен")
	driver.check(
		fixtures.state.lootboxes_remaining == lootboxes_before + int(rewards.get("lootboxes", 0)),
		"Награда Возвышения не добавила лутбоксы"
	)
	driver.check(
		fixtures.state.gold == gold_before + int(rewards.get("gold", 0)),
		"Награда Возвышения не добавила золото"
	)
	var lootboxes_after: int = fixtures.state.lootboxes_remaining
	var gold_after: int = fixtures.state.gold

	await driver.press_qa("combat.return")
	await driver.wait_for_any_scene([TOWER_LOBBY_SCENE, HUB_SCENE], 3.0)
	driver.check(fixtures.state.lootboxes_remaining == lootboxes_after, "Награда Возвышения начислилась повторно после выхода")
	driver.check(fixtures.state.gold == gold_after, "Золото Возвышения начислилось повторно после выхода")

func _combat_finished(driver) -> bool:
	var root = driver.get_current_root()
	if root == null:
		return false
	var panel = root.get_node_or_null("EndPanel")
	return panel != null and panel.visible

func _expected_tower_rewards(floor_data: Dictionary) -> Dictionary:
	var rewards: Dictionary = floor_data.get("reward", {}).duplicate(true)
	var enemies_data := _load_enemy_archetypes()
	var reward_weight := 0.0
	for entry in floor_data.get("enemies", []):
		if not (entry is Dictionary):
			continue
		var enemy_type := str(entry.get("type", "goblin"))
		var count := int(entry.get("count", 1))
		var archetype: Dictionary = enemies_data.get(enemy_type, {})
		reward_weight += maxf(0.0, float(archetype.get("reward_weight", 1.0))) * float(count)

	var gold_bonus := roundi(reward_weight * ENEMY_REWARD_GOLD_PER_WEIGHT)
	if gold_bonus > 0:
		rewards["gold"] = int(rewards.get("gold", 0)) + gold_bonus
	var lootbox_bonus := floori(reward_weight / ENEMY_REWARD_LOOTBOX_WEIGHT)
	if lootbox_bonus > 0:
		rewards["lootboxes"] = int(rewards.get("lootboxes", 0)) + lootbox_bonus
	return rewards

func _combat_has_selected_heroes(root, expected_ids: Array[String]) -> bool:
	if root == null:
		return false
	var units: Array = root.get("_units")
	var found: Dictionary = {}
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		found[unit.character_data.id] = true
	for expected_id in expected_ids:
		if not found.has(expected_id):
			return false
	return true

func _roster_hp_matches_combat_units(root, state) -> bool:
	if root == null:
		return false
	var units: Array = root.get("_units")
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or unit.character_data == null:
			continue
		var roster_hero = state.roster.get_by_id(unit.character_data.id)
		if roster_hero == null:
			continue
		if roster_hero.get_current_hp() != unit.battle_unit.current_hp:
			return false
	return true

func _selected_heroes_trained(state, expected_ids: Array[String]) -> bool:
	for expected_id in expected_ids:
		var hero = state.roster.get_by_id(expected_id)
		if hero == null:
			continue
		if int(hero.combat_brain.get("battle_count", 0)) > 0:
			return true
	return false

func _load_enemy_archetypes() -> Dictionary:
	var file := FileAccess.open(ENEMY_ARCHETYPES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary):
		return {}
	var parsed_data: Dictionary = data
	return parsed_data.get("enemies", {})

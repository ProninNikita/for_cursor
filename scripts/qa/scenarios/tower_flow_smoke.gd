extends RefCounted

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const ELEVATION_SCENE := "res://scenes/tower/elevation.tscn"
const TOWER_SQUAD_SCENE := "res://scenes/tower/tower_squad.tscn"
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: tower_flow_smoke")
	fixtures.reset_game(5)
	var rewards: Dictionary = fixtures.state.tower_elevation.get_floor_data(1).get("reward", {})
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
	for i in range(mini(3, checkboxes.size())):
		await driver.set_checkbox(checkboxes[i], true, "tower_squad.hero.%d" % i)

	await driver.press_qa("tower_squad.start")
	await driver.wait_for_scene(COMBAT_SCENE)
	await driver.wait_until(Callable(self, "_combat_finished").bind(driver), 15.0, "бой из возвышения должен завершиться")
	driver.check(fixtures.state.pending_combat_squad.is_empty(), "После боя pending_combat_squad не очищен")
	driver.check(
		fixtures.state.lootboxes_remaining == lootboxes_before + int(rewards.get("lootboxes", 0)),
		"Награда Возвышения не добавила лутбоксы"
	)
	driver.check(
		fixtures.state.gold == gold_before + int(rewards.get("gold", 0)),
		"Награда Возвышения не добавила золото"
	)

	await driver.press_qa("combat.return")
	await driver.wait_for_any_scene([TOWER_LOBBY_SCENE, HUB_SCENE], 3.0)

func _combat_finished(driver) -> bool:
	var root = driver.get_current_root()
	if root == null:
		return false
	var panel = root.get_node_or_null("EndPanel")
	return panel != null and panel.visible

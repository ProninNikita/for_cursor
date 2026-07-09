extends RefCounted

const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"
const HUB_SCENE := "res://scenes/hub/hub.tscn"

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: combat_smoke")
	fixtures.prepare_combat(5)
	await driver.load_scene(COMBAT_SCENE)
	await driver.wait_until(Callable(self, "_combat_finished").bind(driver), 15.0, "автобой должен завершиться")

	var trained := 0
	for hero in fixtures.state.roster.get_characters():
		if int(hero.combat_brain.get("battle_count", 0)) > 0:
			trained += 1
	driver.check(trained > 0, "После боя ни один герой не получил запись combat_brain.battle_count")

	await driver.press_qa("combat.return")
	await driver.wait_for_scene(HUB_SCENE)

func _combat_finished(driver) -> bool:
	var root = driver.get_current_root()
	if root == null:
		return false
	var panel = root.get_node_or_null("EndPanel")
	return panel != null and panel.visible

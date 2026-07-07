extends RefCounted

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const HUB_SCENE := "res://scenes/hub/hub.tscn"
const PORTAL_SCENE := "res://scenes/portal/portal.tscn"
const MANSION_SCENE := "res://scenes/mansion/mansion.tscn"

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: main_flow_smoke")
	fixtures.reset_game(0)
	fixtures.save_manager.delete_all_saves()

	await driver.load_scene(MENU_SCENE)
	await driver.press_qa("menu.new_game")
	await driver.wait_for_scene(HUB_SCENE)
	driver.check(fixtures.state.lootboxes_remaining == fixtures.save_manager.STARTING_LOOTBOXES, "Новая игра не выдала стартовые лутбоксы")

	await driver.press_qa("hub.portal")
	await driver.wait_for_scene(PORTAL_SCENE)
	var before_count: int = fixtures.state.roster.get_character_count()
	await driver.press_qa("portal.open_lootbox")
	await driver.press_qa("portal.open_lootbox")
	await driver.press_qa("portal.open_lootbox")
	driver.check(fixtures.state.roster.get_character_count() == before_count + 3, "Портал не добавил 3 героев")
	driver.check(fixtures.state.lootboxes_remaining == fixtures.save_manager.STARTING_LOOTBOXES - 3, "Портал неправильно списал лутбоксы")

	await driver.press_qa("portal.back")
	await driver.wait_for_scene(HUB_SCENE)
	await driver.press_qa("hub.mansion")
	await driver.wait_for_scene(MANSION_SCENE)
	driver.check(fixtures.state.roster.get_character_count() >= 3, "После перехода в особняк ростер пуст")

	await driver.press_qa("mansion.back")
	await driver.wait_for_scene(HUB_SCENE)
	await driver.press_qa("hub.save")
	await driver.wait_frames(3)
	driver.check(fixtures.save_manager.get_save_info(1).get("exists", false), "Слот 1 не создался после сохранения")

	await driver.load_scene(MENU_SCENE)
	await driver.press_qa("menu.load")
	await driver.wait_frames(2)
	await driver.press_qa("menu.slot.1")
	await driver.wait_for_scene(HUB_SCENE)
	driver.check(fixtures.state.roster.get_character_count() >= 3, "После загрузки из слота ростер потерян")

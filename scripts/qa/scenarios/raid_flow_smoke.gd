extends RefCounted

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const TOWER_LOBBY_SCENE := "res://scenes/tower/tower_lobby.tscn"
const RAID_LOBBY_SCENE := "res://scenes/tower/raid_lobby.tscn"
const RAID_PROGRESS_SCENE := "res://scenes/tower/raid_progress.tscn"

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: raid_flow_smoke")
	fixtures.reset_game(3)

	await driver.load_scene(HUB_SCENE)
	await driver.press_qa("hub.tower")
	await driver.wait_for_scene(TOWER_LOBBY_SCENE)
	await driver.press_qa("tower_lobby.raid")
	await driver.wait_for_scene(RAID_LOBBY_SCENE)

	await driver.press_qa("raid_lobby.duration.2")
	await driver.press_qa("raid_lobby.difficulty.easy")
	await driver.press_qa("raid_lobby.type.hunt")

	var checkboxes: Array = driver.find_checkboxes_with_prefix("raid_lobby.hero.")
	driver.check(checkboxes.size() >= 2, "В лобби вылазки меньше 2 героев")
	for i in range(mini(2, checkboxes.size())):
		await driver.set_checkbox(checkboxes[i], true, "raid_lobby.hero.%d" % i)

	await driver.press_qa("raid_lobby.start")
	await driver.wait_for_scene(TOWER_LOBBY_SCENE)
	driver.check(fixtures.state.active_raid != null, "После старта вылазки active_raid == null")

	await driver.press_qa("tower_lobby.raid")
	await driver.wait_for_scene(RAID_PROGRESS_SCENE)
	await driver.press_qa("raid_progress.speed_up")
	await driver.wait_frames(4)
	driver.check(fixtures.state.active_raid == null, "После ускорения 2ч вылазка не завершилась")

	await driver.press_qa("raid_progress.back")
	await driver.wait_for_scene(TOWER_LOBBY_SCENE)

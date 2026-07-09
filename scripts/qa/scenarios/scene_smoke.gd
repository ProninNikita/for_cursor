extends RefCounted

const SCENES := [
	{
		"path": "res://scenes/menu/main_menu.tscn",
		"qa_ids": ["menu.new_game", "menu.load"]
	},
	{
		"path": "res://scenes/hub/hub.tscn",
		"qa_ids": ["hub.save", "hub.portal", "hub.tower", "hub.mansion"]
	},
	{
		"path": "res://scenes/portal/portal.tscn",
		"qa_ids": ["portal.back", "portal.open_lootbox"]
	},
	{
		"path": "res://scenes/mansion/mansion.tscn",
		"qa_ids": ["mansion.back"]
	},
	{
		"path": "res://scenes/tower/tower_lobby.tscn",
		"qa_ids": ["tower_lobby.back", "tower_lobby.elevation", "tower_lobby.raid"]
	},
	{
		"path": "res://scenes/tower/elevation.tscn",
		"qa_ids": ["elevation.back", "elevation.floor.1"]
	},
	{
		"path": "res://scenes/tower/tower_squad.tscn",
		"qa_ids": ["tower_squad.back", "tower_squad.start"]
	},
	{
		"path": "res://scenes/tower/raid_lobby.tscn",
		"qa_ids": ["raid_lobby.back", "raid_lobby.start", "raid_lobby.duration.2", "raid_lobby.difficulty.easy"]
	},
	{
		"path": "res://scenes/tower/raid_progress.tscn",
		"qa_ids": ["raid_progress.back", "raid_progress.speed_up", "raid_progress.recall"]
	},
	{
		"path": "res://scenes/combat_rt/combat_rt.tscn",
		"qa_ids": ["combat_rt.return", "combat_rt.pause", "combat_rt.speed", "combat.return"]
	}
]

func run(driver, fixtures, _context: Dictionary) -> void:
	print("QA_SCENARIO: scene_smoke")
	for entry in SCENES:
		var path: String = entry["path"]
		fixtures.prepare_for_scene(path)
		var root = await driver.load_scene(path)
		if root == null:
			continue
		await driver.wait_frames(2)
		driver.check(driver.count_controls() > 0, "В сцене %s нет Control-узлов" % path)
		for qa_id in entry["qa_ids"]:
			driver.check(driver.find_by_qa_id(qa_id) != null, "В сцене %s не найден qa_id=%s" % [path, qa_id])

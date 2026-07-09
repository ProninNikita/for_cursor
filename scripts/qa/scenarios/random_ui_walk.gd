extends RefCounted

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"

func run(driver, fixtures, context: Dictionary) -> void:
	print("QA_SCENARIO: random_ui_walk")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(context.get("seed", 12345))
	var actions := int(context.get("actions", 60))

	fixtures.reset_game(5)
	await driver.load_scene(HUB_SCENE)

	for step in range(actions):
		if driver.get_current_root() == null:
			driver.fail("random_ui_walk: current_scene == null на шаге %d" % step)
			return

		if driver.get_current_scene_path() == COMBAT_SCENE:
			if _combat_finished(driver):
				await driver.press_qa("combat.return")
			else:
				await driver.wait_seconds(0.2)
			continue

		var buttons: Array = driver.collect_enabled_buttons()
		if buttons.is_empty():
			driver.fail("random_ui_walk: нет доступных кнопок на шаге %d в %s" % [step, driver.get_current_scene_path()])
			return

		var button = buttons[rng.randi() % buttons.size()]
		var label := str(button.get_meta("qa_id", button.name))
		print("QA_RANDOM_ACTION %03d: %s in %s" % [step + 1, label, driver.get_current_scene_path()])
		await driver.press_button(button, label)
		await driver.wait_frames(2)

func _combat_finished(driver) -> bool:
	var root = driver.get_current_root()
	if root == null:
		return false
	var panel = root.get_node_or_null("EndPanel")
	return panel != null and panel.visible

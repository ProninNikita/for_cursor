extends SceneTree

const QaDriver = preload("res://scripts/qa/qa_driver.gd")
const QaFixtures = preload("res://scripts/qa/qa_fixtures.gd")
const SceneSmoke = preload("res://scripts/qa/scenarios/scene_smoke.gd")
const MainFlowSmoke = preload("res://scripts/qa/scenarios/main_flow_smoke.gd")
const CombatSmoke = preload("res://scripts/qa/scenarios/combat_smoke.gd")
const TowerFlowSmoke = preload("res://scripts/qa/scenarios/tower_flow_smoke.gd")
const RaidFlowSmoke = preload("res://scripts/qa/scenarios/raid_flow_smoke.gd")
const RandomUiWalk = preload("res://scripts/qa/scenarios/random_ui_walk.gd")

var _driver
var _fixtures
var _scenario := "smoke_all"
var _seed := 12345
var _actions := 60
var _time_scale := 4.0

func _initialize() -> void:
	_parse_args()
	Engine.time_scale = _time_scale
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_driver = QaDriver.new(self)
	var game_state := root.get_node_or_null("GameState")
	var save_manager := root.get_node_or_null("SaveManager")
	if game_state == null or save_manager == null:
		print("QA_DONE: FAIL (autoloads missing)")
		quit(1)
		return
	_fixtures = QaFixtures.new(game_state, save_manager, _seed)
	_fixtures.setup_sandbox("last")

	var context := {
		"seed": _seed,
		"actions": _actions
	}
	var scenarios := _scenario_names()
	print("QA_START: scenario=%s seed=%d actions=%d time_scale=%.2f" % [_scenario, _seed, _actions, _time_scale])

	for scenario_name in scenarios:
		var scenario = _create_scenario(scenario_name)
		if scenario == null:
			_driver.fail("Неизвестный QA-сценарий: %s" % scenario_name)
			continue
		await scenario.run(_driver, _fixtures, context)

	_finish()

func _finish() -> void:
	if _fixtures != null:
		_fixtures.save_manager.use_default_save_dir()
	Engine.time_scale = 1.0
	if _driver != null and _driver.has_failures():
		print("QA_DONE: FAIL (%d)" % _driver.failures.size())
		for failure in _driver.failures:
			print("QA_FAILURE: %s" % failure)
		quit(1)
	else:
		print("QA_DONE: OK")
		quit(0)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i])
		match arg:
			"--scenario":
				if i + 1 < args.size():
					_scenario = str(args[i + 1])
					i += 1
			"--seed":
				if i + 1 < args.size():
					_seed = int(args[i + 1])
					i += 1
			"--actions":
				if i + 1 < args.size():
					_actions = int(args[i + 1])
					i += 1
			"--time-scale":
				if i + 1 < args.size():
					_time_scale = max(0.1, float(args[i + 1]))
					i += 1
		i += 1

func _scenario_names() -> Array[String]:
	match _scenario:
		"smoke_all", "smoke":
			return ["scene_smoke", "main_flow_smoke", "combat_smoke", "tower_flow_smoke", "raid_flow_smoke"]
		"full":
			return ["scene_smoke", "main_flow_smoke", "combat_smoke", "tower_flow_smoke", "raid_flow_smoke", "random_ui_walk"]
		_:
			if _scenario.contains(","):
				var names: Array[String] = []
				for raw_name in _scenario.split(","):
					names.append(str(raw_name).strip_edges())
				return names
			return [_scenario]

func _create_scenario(scenario_name: String):
	match scenario_name:
		"scene_smoke":
			return SceneSmoke.new()
		"main_flow", "main_flow_smoke":
			return MainFlowSmoke.new()
		"combat", "combat_smoke":
			return CombatSmoke.new()
		"tower_flow", "tower_flow_smoke":
			return TowerFlowSmoke.new()
		"raid_flow", "raid_flow_smoke":
			return RaidFlowSmoke.new()
		"random_ui", "random_ui_walk":
			return RandomUiWalk.new()
		_:
			return null

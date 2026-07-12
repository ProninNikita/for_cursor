extends SceneTree

const QaFixtures = preload("res://scripts/qa/qa_fixtures.gd")
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"

var _fixtures
var _count: int = 100
var _seed: int = 12345
var _hero_count: int = 5
var _output_json: String = "/private/tmp/rt_combat_batch.json"
var _output_csv: String = "/private/tmp/rt_combat_batch.csv"
var _timeout_seconds: float = 20.0
var _records: Array[Dictionary] = []

func _initialize() -> void:
	_parse_args()
	Engine.time_scale = 12.0
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var game_state := root.get_node_or_null("GameState")
	var save_manager := root.get_node_or_null("SaveManager")
	if game_state == null or save_manager == null:
		print("BATCH_DONE: FAIL (autoloads missing)")
		quit(1)
		return

	_fixtures = QaFixtures.new(game_state, save_manager, _seed)
	_fixtures.setup_sandbox("batch")
	game_state.clear_combat_history()

	for index in range(_count):
		await _run_single_battle(index)

	var report := _build_report()
	_write_json(report)
	_write_csv()
	Engine.time_scale = 1.0
	print("BATCH_DONE: OK count=%d winrate=%.3f avg_duration=%.2f json=%s csv=%s" % [
		_count,
		float(report.get("winrate", 0.0)),
		float(report.get("average_duration_seconds", 0.0)),
		_output_json,
		_output_csv
	])
	quit(0)

func _run_single_battle(index: int) -> void:
	_fixtures.prepare_combat(_hero_count)
	_fixtures.state.pending_combat_encounter = "batch_%d_%d" % [_seed, index]
	var err := change_scene_to_file(COMBAT_SCENE)
	if err != OK:
		_records.append({"error": "scene_load_failed", "index": index})
		return
	await _wait_frames(3)
	var elapsed := 0.0
	while elapsed < _timeout_seconds:
		var panel = current_scene.get_node_or_null("EndPanel") if current_scene != null else null
		if panel != null and panel.visible:
			break
		await create_timer(0.05, true, false, true).timeout
		elapsed += 0.05
	var record: Dictionary = _fixtures.state.latest_combat_result()
	if record.is_empty():
		record = {"error": "timeout", "index": index}
	record["index"] = index
	_records.append(record.duplicate(true))

func _build_report() -> Dictionary:
	var wins := 0
	var total_duration := 0.0
	var completed := 0
	var mortality_by_class: Dictionary = {}
	var ability_usage: Dictionary = {}
	var decision_usage: Dictionary = {}

	for record in _records:
		if record.has("error"):
			continue
		completed += 1
		if bool(record.get("victory", false)):
			wins += 1
		total_duration += float(record.get("elapsed_seconds", 0.0))
		_merge_counts(ability_usage, record.get("ability_usage", {}))
		_merge_counts(decision_usage, record.get("decision_usage", {}))
		for ally in record.get("allies", []):
			if not (ally is Dictionary):
				continue
			var class_id := str(ally.get("class", "unknown"))
			var stats: Dictionary = mortality_by_class.get(class_id, {"total": 0, "dead": 0})
			stats["total"] = int(stats.get("total", 0)) + 1
			if not bool(ally.get("alive", false)):
				stats["dead"] = int(stats.get("dead", 0)) + 1
			mortality_by_class[class_id] = stats

	var winrate := 0.0
	var average_duration := 0.0
	if completed > 0:
		winrate = float(wins) / float(completed)
		average_duration = total_duration / float(completed)
	return {
		"seed": _seed,
		"requested_battles": _count,
		"completed_battles": completed,
		"winrate": winrate,
		"average_duration_seconds": average_duration,
		"mortality_by_class": mortality_by_class,
		"ability_usage": ability_usage,
		"decision_usage": decision_usage,
		"records": _records
	}

func _write_json(report: Dictionary) -> void:
	var file := FileAccess.open(_output_json, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write batch JSON: " + _output_json)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func _write_csv() -> void:
	var file := FileAccess.open(_output_csv, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write batch CSV: " + _output_csv)
		return
	file.store_line("index,victory,elapsed_seconds,allies_alive,allies_total,enemies_defeated,enemies_total,damage_dealt,healing_done")
	for record in _records:
		file.store_line("%d,%s,%.2f,%d,%d,%d,%d,%d,%d" % [
			int(record.get("index", -1)),
			str(bool(record.get("victory", false))),
			float(record.get("elapsed_seconds", 0.0)),
			int(record.get("allies_alive", 0)),
			int(record.get("allies_total", 0)),
			int(record.get("enemies_defeated", 0)),
			int(record.get("enemies_total", 0)),
			int(record.get("damage_dealt", 0)),
			int(record.get("healing_done", 0))
		])
	file.close()

func _merge_counts(target: Dictionary, source) -> void:
	if not (source is Dictionary):
		return
	for key in source.keys():
		target[key] = int(target.get(key, 0)) + int(source[key])

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i])
		match arg:
			"--count":
				if i + 1 < args.size():
					_count = maxi(1, int(args[i + 1]))
					i += 1
			"--seed":
				if i + 1 < args.size():
					_seed = int(args[i + 1])
					i += 1
			"--heroes":
				if i + 1 < args.size():
					_hero_count = clampi(int(args[i + 1]), 1, 8)
					i += 1
			"--output-json":
				if i + 1 < args.size():
					_output_json = str(args[i + 1])
					i += 1
			"--output-csv":
				if i + 1 < args.size():
					_output_csv = str(args[i + 1])
					i += 1
			"--timeout":
				if i + 1 < args.size():
					_timeout_seconds = maxf(3.0, float(args[i + 1]))
					i += 1
		i += 1

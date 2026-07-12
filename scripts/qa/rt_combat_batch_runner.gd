extends SceneTree

const QaFixtures = preload("res://scripts/qa/qa_fixtures.gd")
const COMBAT_SCENE := "res://scenes/combat_rt/combat_rt.tscn"

var _fixtures
var _count: int = 100
var _seed: int = 12345
var _hero_count: int = 5
var _output_json: String = "/private/tmp/rt_combat_batch.json"
var _output_csv: String = "/private/tmp/rt_combat_batch.csv"
var _timeout_seconds: float = 35.0
var _suite: String = "training"
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

	var cases := _build_cases()
	for case_data in cases:
		for index in range(_count):
			await _run_single_battle(index, case_data)

	var report := _build_report()
	_write_json(report)
	_write_csv()
	Engine.time_scale = 1.0
	var has_errors := _report_has_errors(report)
	if has_errors:
		print("BATCH_DONE: FAIL count=%d cases=%d errors=%d json=%s csv=%s" % [
			_count,
			cases.size(),
			int(report.get("error_count", 0)),
			_output_json,
			_output_csv
		])
		quit(1)
		return
	print("BATCH_DONE: OK count=%d cases=%d winrate=%.3f avg_duration=%.2f json=%s csv=%s" % [
		_count,
		cases.size(),
		float(report.get("winrate", 0.0)),
		float(report.get("average_duration_seconds", 0.0)),
		_output_json,
		_output_csv
	])
	quit(0)

func _run_single_battle(index: int, case_data: Dictionary) -> void:
	_prepare_case(case_data, index)
	_fixtures.state.pending_combat_encounter = "%s_%d_%d" % [str(case_data.get("id", "batch")), _seed, index]
	var err := change_scene_to_file(COMBAT_SCENE)
	if err != OK:
		_records.append(_error_record("scene_load_failed", index, case_data))
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
		record = _error_record("timeout", index, case_data)
	record["index"] = index
	record["case_id"] = str(case_data.get("id", "unknown"))
	record["case_mode"] = str(case_data.get("mode", "training"))
	record["case_tags"] = case_data.get("tags", [])
	record["tower_floor"] = int(case_data.get("floor", 0))
	record["raid_difficulty"] = str(case_data.get("raid_difficulty", ""))
	_records.append(record.duplicate(true))

func _build_report() -> Dictionary:
	var wins := 0
	var total_duration := 0.0
	var completed := 0
	var errors := 0
	var mortality_by_class: Dictionary = {}
	var ability_usage: Dictionary = {}
	var decision_usage: Dictionary = {}
	var failure_reasons: Dictionary = {}
	var deaths_by_floor: Dictionary = {}
	var case_summaries: Dictionary = {}
	var max_tick_ms := 0.0

	for record in _records:
		if record.has("error"):
			errors += 1
			_increment_count(failure_reasons, str(record.get("error", "unknown")))
			_update_case_summary(case_summaries, record)
			continue
		completed += 1
		if bool(record.get("victory", false)):
			wins += 1
		else:
			_increment_count(failure_reasons, str(record.get("finish_reason", "defeat")))
		total_duration += float(record.get("elapsed_seconds", 0.0))
		max_tick_ms = maxf(max_tick_ms, float(record.get("max_tick_ms", 0.0)))
		_merge_counts(ability_usage, record.get("ability_usage", {}))
		_merge_counts(decision_usage, record.get("decision_usage", {}))
		_update_case_summary(case_summaries, record)
		for ally in record.get("allies", []):
			if not (ally is Dictionary):
				continue
			var class_id := str(ally.get("class", "unknown"))
			var stats: Dictionary = mortality_by_class.get(class_id, {"total": 0, "dead": 0})
			stats["total"] = int(stats.get("total", 0)) + 1
			if not bool(ally.get("alive", false)):
				stats["dead"] = int(stats.get("dead", 0)) + 1
				var floor_key := str(int(record.get("tower_floor", 0)))
				if floor_key != "0":
					_increment_count(deaths_by_floor, floor_key)
			mortality_by_class[class_id] = stats

	var winrate := 0.0
	var average_duration := 0.0
	if completed > 0:
		winrate = float(wins) / float(completed)
		average_duration = total_duration / float(completed)
	return {
		"seed": _seed,
		"suite": _suite,
		"requested_battles": _count,
		"completed_battles": completed,
		"error_count": errors,
		"winrate": winrate,
		"average_duration_seconds": average_duration,
		"max_tick_ms": max_tick_ms,
		"mortality_by_class": mortality_by_class,
		"failure_reasons": failure_reasons,
		"deaths_by_floor": deaths_by_floor,
		"case_summaries": _finalize_case_summaries(case_summaries),
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
	file.store_line("case_id,mode,index,victory,finish_reason,elapsed_seconds,allies_alive,allies_total,allies_dead,avg_hp_loss,max_tick_ms,enemies_defeated,enemies_total,damage_dealt,healing_done,error")
	for record in _records:
		file.store_line("%s,%s,%d,%s,%s,%.2f,%d,%d,%d,%.3f,%.3f,%d,%d,%d,%d,%s" % [
			str(record.get("case_id", "")),
			str(record.get("case_mode", "")),
			int(record.get("index", -1)),
			str(bool(record.get("victory", false))),
			str(record.get("finish_reason", "")),
			float(record.get("elapsed_seconds", 0.0)),
			int(record.get("allies_alive", 0)),
			int(record.get("allies_total", 0)),
			int(record.get("allies_dead", 0)),
			_average_hp_loss(record),
			float(record.get("max_tick_ms", 0.0)),
			int(record.get("enemies_defeated", 0)),
			int(record.get("enemies_total", 0)),
			int(record.get("damage_dealt", 0)),
			int(record.get("healing_done", 0)),
			str(record.get("error", ""))
		])
	file.close()

func _merge_counts(target: Dictionary, source) -> void:
	if not (source is Dictionary):
		return
	for key in source.keys():
		target[key] = int(target.get(key, 0)) + int(source[key])

func _increment_count(target: Dictionary, key: String, amount: int = 1) -> void:
	if key == "":
		key = "unknown"
	target[key] = int(target.get(key, 0)) + amount

func _update_case_summary(case_summaries: Dictionary, record: Dictionary) -> void:
	var case_id := str(record.get("case_id", "unknown"))
	var summary: Dictionary = case_summaries.get(case_id, {
		"mode": str(record.get("case_mode", "")),
		"tags": record.get("case_tags", []),
		"runs": 0,
		"completed": 0,
		"errors": 0,
		"wins": 0,
		"duration_total": 0.0,
		"hp_loss_total": 0.0,
		"max_tick_ms": 0.0,
		"deaths": 0,
		"failure_reasons": {}
	})
	summary["runs"] = int(summary.get("runs", 0)) + 1
	if record.has("error"):
		summary["errors"] = int(summary.get("errors", 0)) + 1
		var error_failures: Dictionary = summary.get("failure_reasons", {})
		_increment_count(error_failures, str(record.get("error", "unknown")))
		summary["failure_reasons"] = error_failures
	else:
		summary["completed"] = int(summary.get("completed", 0)) + 1
		if bool(record.get("victory", false)):
			summary["wins"] = int(summary.get("wins", 0)) + 1
		else:
			var defeat_failures: Dictionary = summary.get("failure_reasons", {})
			_increment_count(defeat_failures, str(record.get("finish_reason", "defeat")))
			summary["failure_reasons"] = defeat_failures
		summary["duration_total"] = float(summary.get("duration_total", 0.0)) + float(record.get("elapsed_seconds", 0.0))
		summary["hp_loss_total"] = float(summary.get("hp_loss_total", 0.0)) + _average_hp_loss(record)
		summary["max_tick_ms"] = maxf(float(summary.get("max_tick_ms", 0.0)), float(record.get("max_tick_ms", 0.0)))
		summary["deaths"] = int(summary.get("deaths", 0)) + int(record.get("allies_dead", 0))
	case_summaries[case_id] = summary

func _finalize_case_summaries(case_summaries: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for case_id in case_summaries.keys():
		var summary: Dictionary = case_summaries[case_id]
		var completed := int(summary.get("completed", 0))
		var wins := int(summary.get("wins", 0))
		summary["winrate"] = float(wins) / float(completed) if completed > 0 else 0.0
		summary["average_duration_seconds"] = float(summary.get("duration_total", 0.0)) / float(completed) if completed > 0 else 0.0
		summary["average_hp_loss"] = float(summary.get("hp_loss_total", 0.0)) / float(completed) if completed > 0 else 0.0
		summary.erase("duration_total")
		summary.erase("hp_loss_total")
		result[case_id] = summary
	return result

func _average_hp_loss(record: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for ally in record.get("allies", []):
		if not (ally is Dictionary):
			continue
		var max_hp := maxf(1.0, float(ally.get("max_hp", 1)))
		var hp := clampf(float(ally.get("hp", 0)), 0.0, max_hp)
		total += (max_hp - hp) / max_hp
		count += 1
	return total / float(count) if count > 0 else 0.0

func _report_has_errors(report: Dictionary) -> bool:
	if int(report.get("error_count", 0)) > 0:
		return true
	return int(report.get("completed_battles", 0)) <= 0

func _error_record(error: String, index: int, case_data: Dictionary) -> Dictionary:
	return {
		"error": error,
		"index": index,
		"case_id": str(case_data.get("id", "unknown")),
		"case_mode": str(case_data.get("mode", "training")),
		"case_tags": case_data.get("tags", []),
		"tower_floor": int(case_data.get("floor", 0)),
		"raid_difficulty": str(case_data.get("raid_difficulty", ""))
	}

func _build_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	match _suite:
		"matrix":
			cases.append_array([
				{"id": "training_5", "mode": "training", "heroes": 5, "tags": ["training", "5_heroes"]},
				{"id": "training_3", "mode": "training", "heroes": 3, "tags": ["training", "3_heroes"]},
				{"id": "training_1", "mode": "training", "heroes": 1, "tags": ["training", "1_hero"]},
				{"id": "training_no_healer", "mode": "training", "classes": ["warrior", "mage", "defender", "scout", "assassin"], "tags": ["no_healer"]},
				{"id": "training_no_tank", "mode": "training", "classes": ["healer", "mage", "scout", "tactician", "assassin"], "tags": ["no_tank"]},
				{"id": "tower_floor_1", "mode": "tower", "floor": 1, "heroes": 5, "tags": ["tower", "early"]},
				{"id": "tower_floor_5", "mode": "tower", "floor": 5, "heroes": 5, "tags": ["tower", "mid"]},
				{"id": "tower_floor_10", "mode": "tower", "floor": 10, "heroes": 5, "tags": ["tower", "boss"]},
				{"id": "raid_easy", "mode": "raid", "raid_difficulty": "easy", "difficulty": 0.85, "heroes": 5, "tags": ["raid", "easy"]},
				{"id": "raid_normal", "mode": "raid", "raid_difficulty": "normal", "difficulty": 1.0, "heroes": 5, "tags": ["raid", "normal"]},
				{"id": "raid_hard", "mode": "raid", "raid_difficulty": "hard", "difficulty": 1.25, "heroes": 5, "tags": ["raid", "hard"]}
			])
		"tower":
			for floor in range(1, 11):
				cases.append({"id": "tower_floor_%d" % floor, "mode": "tower", "floor": floor, "heroes": 5, "tags": ["tower"]})
		"raid":
			cases.append_array([
				{"id": "raid_easy", "mode": "raid", "raid_difficulty": "easy", "difficulty": 0.85, "heroes": 5, "tags": ["raid", "easy"]},
				{"id": "raid_normal", "mode": "raid", "raid_difficulty": "normal", "difficulty": 1.0, "heroes": 5, "tags": ["raid", "normal"]},
				{"id": "raid_hard", "mode": "raid", "raid_difficulty": "hard", "difficulty": 1.25, "heroes": 5, "tags": ["raid", "hard"]}
			])
		"performance":
			cases.append_array([
				{"id": "perf_5v20", "mode": "performance", "heroes": 5, "enemy_count": 20, "enemy_mix": "goblins", "tags": ["performance", "5v20"]},
				{"id": "perf_10v30", "mode": "performance", "heroes": 10, "enemy_count": 30, "enemy_mix": "mixed", "tags": ["performance", "10v30"]},
				{"id": "perf_20v40", "mode": "performance", "heroes": 20, "enemy_count": 40, "enemy_mix": "mixed", "tags": ["performance", "20v40"]}
			])
		_:
			cases.append({"id": "training_%d" % _hero_count, "mode": "training", "heroes": _hero_count, "tags": ["training"]})
	return cases

func _prepare_case(case_data: Dictionary, index: int) -> void:
	var mode := str(case_data.get("mode", "training"))
	var classes: Array = case_data.get("classes", [])
	var hero_count := clampi(int(case_data.get("heroes", _hero_count)), 1, 8)
	if not classes.is_empty():
		_prepare_classes(classes)
		hero_count = classes.size()
	match mode:
		"tower":
			if classes.is_empty():
				_fixtures.prepare_tower_combat(hero_count, int(case_data.get("floor", 1)))
			else:
				var tower_squad: Array[CharacterData] = _fixtures.get_first_squad(mini(hero_count, 5))
				_fixtures.state.pending_tower_floor = int(case_data.get("floor", 1))
				_fixtures.state.is_tower_elevation = true
				_fixtures.state.begin_tower_combat(tower_squad, int(case_data.get("floor", 1)))
		"raid":
			if classes.is_empty():
				_fixtures.reset_game(hero_count)
			var raid_squad: Array[CharacterData] = _fixtures.get_first_squad(mini(hero_count, 5))
			_fixtures.state.begin_raid(raid_squad, 2, 0, 0)
			_fixtures.state.begin_raid_combat(raid_squad, _raid_event(case_data, index))
		"performance":
			_fixtures.reset_game(hero_count)
			var perf_squad: Array[CharacterData] = _fixtures.get_first_squad(hero_count)
			_fixtures.state.begin_raid_combat(perf_squad, _performance_event(case_data, index))
		_:
			if classes.is_empty():
				_fixtures.prepare_combat(hero_count)
			else:
				var training_squad: Array[CharacterData] = _fixtures.get_first_squad(mini(hero_count, 5))
				_fixtures.state.begin_combat(training_squad, "qa_combat")
				_fixtures.state.pending_tower_floor = 0
				_fixtures.state.is_tower_elevation = false

func _prepare_classes(classes: Array) -> void:
	_fixtures.reset_game(0)
	var index := 1
	for class_id in classes:
		_fixtures.state.roster.add_character(_fixtures.make_test_hero(index, str(class_id)))
		index += 1

func _raid_event(case_data: Dictionary, index: int) -> Dictionary:
	var difficulty := float(case_data.get("difficulty", 1.0))
	return {
		"name": "QA raid %s %d" % [str(case_data.get("raid_difficulty", "normal")), index],
		"arena_id": "generated_mixed",
		"difficulty": difficulty,
		"enemies": [
			{"type": "goblin", "count": 2},
			{"type": "orc", "count": 1}
		],
		"rewards": {"gold": int(round(15.0 * difficulty))},
		"modifiers": {
			"damage_taken_multiplier": clampf(0.68 + (difficulty - 1.0) * 0.1, 0.6, 1.05)
		}
	}

func _performance_event(case_data: Dictionary, index: int) -> Dictionary:
	var enemy_count := int(case_data.get("enemy_count", 20))
	var enemy_mix := str(case_data.get("enemy_mix", "goblins"))
	var enemies: Array = []
	if enemy_mix == "mixed":
		var goblins := int(enemy_count / 2)
		var scouts := int(enemy_count / 6)
		var orcs := int(enemy_count / 5)
		var defenders := int(enemy_count / 10)
		var trolls := maxi(0, enemy_count - (goblins + scouts + orcs + defenders))
		enemies = [
			{"type": "goblin", "count": goblins},
			{"type": "goblin_scout", "count": scouts},
			{"type": "orc", "count": orcs},
			{"type": "orc_defender", "count": defenders},
			{"type": "troll", "count": trolls}
		]
	else:
		enemies = [{"type": "goblin", "count": enemy_count}]
	return {
		"name": "QA performance %s %d" % [str(case_data.get("id", "perf")), index],
		"arena_id": "generated_mixed",
		"difficulty": 0.72,
		"enemies": enemies,
		"rewards": {},
		"victory": {"type": "survive_seconds", "seconds": 18.0},
		"defeat": {"type": "collapse", "time_limit_seconds": 24.0, "retreat_after_seconds": 10.0},
		"modifiers": {
			"max_squad_size": float(case_data.get("heroes", 5)),
			"enemy_scale": 0.74,
			"damage_taken_multiplier": 0.58,
			"path_budget_per_tick": 90.0,
			"path_queue_per_tick": 36.0,
			"decision_interval": 0.46,
			"max_log_lines": 10.0
		}
	}

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
			"--suite":
				if i + 1 < args.size():
					_suite = str(args[i + 1])
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

class_name RTBattlefield
extends RefCounted

enum TileType { FLOOR, WALL, WATER, COVER, DOOR, GRASS, DEEP_WATER, HEIGHT, TRAP, NARROW, DESTRUCTIBLE, DARK, NOISY }

const TILE_SIZE := 42.0
const ARENAS_PATH := "res://data/rt_arenas.json"

var width: int = 0
var height: int = 0
var arena_id: String = ""
var arena_name: String = ""
var tiles: Array[int] = []
var ally_spawns: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []
var special_zones: Array[Dictionary] = []
var arena_validation_errors: Array[String] = []
var occupied_tiles: Dictionary = {}
var path_cache: Dictionary = {}
var path_cache_hits: int = 0
var path_cache_misses: int = 0
var _occupancy_revision: int = 0

func setup_test_arena() -> void:
	if setup_arena("training_ruins"):
		return
	_setup_fallback_arena()

func setup_arena(requested_arena_id: String) -> bool:
	var data := _load_arena_file()
	var arenas: Dictionary = data.get("arenas", {})
	var selected_id := requested_arena_id
	if selected_id == "" or not arenas.has(selected_id):
		selected_id = str(data.get("default_arena", "training_ruins"))
	if not arenas.has(selected_id):
		push_warning("RT arena not found: " + requested_arena_id)
		return false
	return setup_from_data(selected_id, arenas[selected_id])

func setup_from_data(selected_id: String, arena_data: Dictionary) -> bool:
	arena_validation_errors.clear()
	occupied_tiles.clear()
	clear_path_cache()
	special_zones.clear()
	if arena_data.has("generator"):
		return _setup_generated_from_data(selected_id, arena_data)
	var rows: Array = arena_data.get("rows", [])
	if rows.is_empty():
		return _fail_arena_validation(selected_id, ["arena has no rows"])
	width = int(arena_data.get("width", str(rows[0]).length()))
	height = int(arena_data.get("height", rows.size()))
	if width <= 0 or height <= 0:
		return _fail_arena_validation(selected_id, ["arena size must be positive"])

	var shape_errors := _validate_arena_shape(rows, width, height)
	if not shape_errors.is_empty():
		return _fail_arena_validation(selected_id, shape_errors)

	arena_id = selected_id
	arena_name = str(arena_data.get("name", selected_id))
	tiles.clear()
	tiles.resize(width * height)
	for i in tiles.size():
		tiles[i] = TileType.FLOOR

	var legend: Dictionary = arena_data.get("legend", {})
	for y in mini(height, rows.size()):
		var row := str(rows[y])
		for x in mini(width, row.length()):
			var token := row.substr(x, 1)
			set_tile(Vector2i(x, y), _tile_from_token(token, legend))
	special_zones = _parse_special_zones(arena_data.get("special_zones", []))
	_apply_special_zones()
	ally_spawns = _parse_spawns(arena_data.get("ally_spawns", []))
	enemy_spawns = _parse_spawns(arena_data.get("enemy_spawns", []))

	var validation_errors := validate_current_arena()
	if not validation_errors.is_empty():
		return _fail_arena_validation(selected_id, validation_errors)
	return true

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height

func get_tile(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return TileType.WALL
	return int(tiles[_index(pos)])

func set_tile(pos: Vector2i, tile_type: int) -> void:
	if not in_bounds(pos):
		return
	tiles[_index(pos)] = tile_type

func is_walkable(pos: Vector2i) -> bool:
	var tile := get_tile(pos)
	return tile not in [TileType.WALL, TileType.DEEP_WATER, TileType.DESTRUCTIBLE]

func rebuild_occupancy(units: Array) -> void:
	occupied_tiles.clear()
	_occupancy_revision += 1
	clear_path_cache()
	for unit in units:
		if unit == null or not unit.is_alive():
			continue
		set_occupied(unit.grid_pos, unit.unit_id)

func set_occupied(pos: Vector2i, occupant_id: String) -> void:
	if not in_bounds(pos) or occupant_id == "":
		return
	if str(occupied_tiles.get(pos, "")) == occupant_id:
		return
	occupied_tiles[pos] = occupant_id
	_occupancy_revision += 1
	clear_path_cache()

func clear_occupied(pos: Vector2i, occupant_id: String = "") -> void:
	if not occupied_tiles.has(pos):
		return
	if occupant_id != "" and str(occupied_tiles.get(pos, "")) != occupant_id:
		return
	occupied_tiles.erase(pos)
	_occupancy_revision += 1
	clear_path_cache()

func move_occupant(from_pos: Vector2i, to_pos: Vector2i, occupant_id: String) -> void:
	clear_occupied(from_pos, occupant_id)
	set_occupied(to_pos, occupant_id)

func reserve_occupied(pos: Vector2i, occupant_id: String) -> bool:
	if not in_bounds(pos) or occupant_id == "":
		return false
	if is_occupied(pos, occupant_id):
		return false
	set_occupied(pos, occupant_id)
	return true

func is_occupied(pos: Vector2i, ignored_occupant_id: String = "") -> bool:
	if not occupied_tiles.has(pos):
		return false
	return ignored_occupant_id == "" or str(occupied_tiles.get(pos, "")) != ignored_occupant_id

func occupant_at(pos: Vector2i) -> String:
	return str(occupied_tiles.get(pos, ""))

func blocks_vision(pos: Vector2i) -> bool:
	return get_tile(pos) in [TileType.WALL, TileType.DESTRUCTIBLE]

func movement_cost(pos: Vector2i) -> float:
	match get_tile(pos):
		TileType.WATER:
			return 1.9
		TileType.HEIGHT:
			return 1.15
		TileType.NARROW:
			return 1.45
		TileType.TRAP:
			return 1.05
		TileType.NOISY:
			return 1.2
		TileType.GRASS:
			return 1.25
		TileType.COVER:
			return 1.1
		_:
			return 1.0

func is_cover(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.COVER

func is_grass(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.GRASS

func is_water(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.WATER

func is_deep_water(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.DEEP_WATER

func is_height(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.HEIGHT

func is_trap(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.TRAP

func is_narrow(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.NARROW

func is_destructible(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.DESTRUCTIBLE

func is_dark(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.DARK

func is_noisy(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.NOISY

func world_from_grid(pos: Vector2i, origin: Vector2 = Vector2.ZERO) -> Vector2:
	return origin + Vector2(float(pos.x) + 0.5, float(pos.y) + 0.5) * TILE_SIZE

func tile_size() -> float:
	return TILE_SIZE

func grid_from_world(world_pos: Vector2, origin: Vector2 = Vector2.ZERO) -> Vector2i:
	var local: Vector2 = (world_pos - origin) / TILE_SIZE
	return Vector2i(floori(local.x), floori(local.y))

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = pos + offset
		if is_walkable(next):
			result.append(next)
	return result

func has_line_of_sight(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if not in_bounds(from_pos) or not in_bounds(to_pos):
		return false
	var points: Array[Vector2i] = _line_points(from_pos, to_pos)
	for i in points.size():
		var p: Vector2i = points[i]
		if p == from_pos or p == to_pos:
			continue
		if blocks_vision(p):
			return false
	return true

func find_path(
	start: Vector2i,
	goal: Vector2i,
	ignored_occupant_id: String = "",
	allow_occupied_goal: bool = true
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if start == goal or not is_walkable(start) or not is_walkable(goal):
		return path
	var cache_key := _path_cache_key(start, goal, ignored_occupant_id, allow_occupied_goal)
	if path_cache.has(cache_key):
		path_cache_hits += 1
		return path_cache[cache_key].duplicate()
	path_cache_misses += 1

	var open: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}

	while not open.is_empty():
		var current: Vector2i = _lowest_score(open, f_score)
		if current == goal:
			path = _reconstruct_path(came_from, current)
			_store_path_cache(cache_key, path)
			return path.duplicate()

		open.erase(current)
		for neighbor in _path_neighbors(current):
			var tentative: float = (
				float(g_score.get(current, INF))
				+ movement_cost(neighbor)
				+ _occupancy_path_penalty(neighbor, goal, ignored_occupant_id, allow_occupied_goal)
			)
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _heuristic(neighbor, goal)
			if not open.has(neighbor):
				open.append(neighbor)
	_store_path_cache(cache_key, path)
	return path

func clear_path_cache() -> void:
	path_cache.clear()

func path_cache_stats() -> Dictionary:
	return {
		"entries": path_cache.size(),
		"hits": path_cache_hits,
		"misses": path_cache_misses,
		"revision": _occupancy_revision
	}

func find_nearest_cover(from_pos: Vector2i, threat_pos: Vector2i, max_radius: int = 7) -> Vector2i:
	var best: Vector2i = from_pos
	var best_score: float = INF
	for y in range(maxi(0, from_pos.y - max_radius), mini(height, from_pos.y + max_radius + 1)):
		for x in range(maxi(0, from_pos.x - max_radius), mini(width, from_pos.x + max_radius + 1)):
			var pos := Vector2i(x, y)
			if not is_walkable(pos):
				continue
			if not _is_defensive_position(pos, threat_pos):
				continue
			var distance: float = _heuristic(from_pos, pos)
			if distance < best_score:
				best = pos
				best_score = distance
	return best

func validate_current_arena() -> Array[String]:
	var errors: Array[String] = []
	if width <= 0 or height <= 0:
		errors.append("arena size must be positive")
	if tiles.size() != width * height:
		errors.append("tile count does not match arena size")
	_validate_spawns("ally", ally_spawns, errors)
	_validate_spawns("enemy", enemy_spawns, errors)
	_validate_spawn_overlap(errors)
	if errors.is_empty():
		_validate_spawn_routes("ally", ally_spawns, "enemy", enemy_spawns, errors)
		_validate_spawn_routes("enemy", enemy_spawns, "ally", ally_spawns, errors)
	return errors

func find_position_near(from_pos: Vector2i, anchor: Vector2i, desired_distance: int = 2, max_radius: int = 6) -> Vector2i:
	var best: Vector2i = from_pos
	var best_score: float = INF
	for y in range(maxi(0, anchor.y - max_radius), mini(height, anchor.y + max_radius + 1)):
		for x in range(maxi(0, anchor.x - max_radius), mini(width, anchor.x + max_radius + 1)):
			var pos := Vector2i(x, y)
			if not is_walkable(pos):
				continue
			var anchor_distance: int = abs(pos.x - anchor.x) + abs(pos.y - anchor.y)
			var score: float = float(abs(anchor_distance - desired_distance)) + _heuristic(from_pos, pos) * 0.25
			if score < best_score:
				best = pos
				best_score = score
	return best

func _is_defensive_position(pos: Vector2i, threat_pos: Vector2i) -> bool:
	if is_cover(pos):
		return true
	for neighbor in get_neighbors(pos):
		if is_cover(neighbor) and not has_line_of_sight(threat_pos, pos):
			return true
	return false

func _load_arena_file() -> Dictionary:
	var file := FileAccess.open(ARENAS_PATH, FileAccess.READ)
	if file == null:
		push_warning("Не удалось загрузить RT арены: " + ARENAS_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("Ошибка парсинга RT арен: " + ARENAS_PATH)
	return {}

func _validate_arena_shape(rows: Array, expected_width: int, expected_height: int) -> Array[String]:
	var errors: Array[String] = []
	if rows.size() != expected_height:
		errors.append("row count %d does not match height %d" % [rows.size(), expected_height])
	for y in rows.size():
		var row := str(rows[y])
		if row.length() != expected_width:
			errors.append("row %d width %d does not match arena width %d" % [y, row.length(), expected_width])
	return errors

func _tile_from_token(token: String, legend: Dictionary) -> int:
	var tile_name := str(legend.get(token, token)).to_lower()
	match tile_name:
		"wall", "#":
			return TileType.WALL
		"water", "~":
			return TileType.WATER
		"cover", "c":
			return TileType.COVER
		"door", "d":
			return TileType.DOOR
		"grass", "g":
			return TileType.GRASS
		"deep_water", "deep-water", "=":
			return TileType.DEEP_WATER
		"height", "high_ground", "high-ground", "^":
			return TileType.HEIGHT
		"trap", "t":
			return TileType.TRAP
		"narrow", "n":
			return TileType.NARROW
		"destructible", "b":
			return TileType.DESTRUCTIBLE
		"dark", "l":
			return TileType.DARK
		"noisy", "s":
			return TileType.NOISY
		_:
			return TileType.FLOOR

func _parse_special_zones(raw_zones: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_zone in raw_zones:
		if raw_zone is Dictionary:
			result.append(raw_zone.duplicate(true))
	return result

func _apply_special_zones() -> void:
	for zone in special_zones:
		var tile_type := _tile_from_token(str(zone.get("tile", zone.get("type", "floor"))), {})
		var points: Array[Vector2i] = _zone_points(zone)
		for pos in points:
			if not in_bounds(pos):
				continue
			if get_tile(pos) == TileType.WALL:
				continue
			set_tile(pos, tile_type)

func _zone_points(zone: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if zone.has("points"):
		for raw_point in zone.get("points", []):
			if raw_point is Array and raw_point.size() >= 2:
				result.append(Vector2i(int(raw_point[0]), int(raw_point[1])))
	if zone.has("rect"):
		var rect: Array = zone.get("rect", [])
		if rect.size() >= 4:
			var start := Vector2i(int(rect[0]), int(rect[1]))
			var size := Vector2i(int(rect[2]), int(rect[3]))
			for y in range(start.y, start.y + size.y):
				for x in range(start.x, start.x + size.x):
					result.append(Vector2i(x, y))
	return result

func _setup_generated_from_data(selected_id: String, arena_data: Dictionary) -> bool:
	var generator: Dictionary = arena_data.get("generator", {})
	var generator_type := str(generator.get("type", "rooms"))
	var seed := int(generator.get("seed", hash(selected_id)))
	match generator_type:
		"nature":
			_setup_generated_nature(selected_id, arena_data, seed)
		"mixed":
			_setup_generated_mixed(selected_id, arena_data, seed)
		_:
			_setup_generated_rooms(selected_id, arena_data, seed)
	special_zones = _parse_special_zones(arena_data.get("special_zones", []))
	_apply_special_zones()
	_clear_spawn_tiles()

	var validation_errors := validate_current_arena()
	if not validation_errors.is_empty():
		return _fail_arena_validation(selected_id, validation_errors)
	return true

func _prepare_generated_base(selected_id: String, arena_data: Dictionary, default_name: String) -> RandomNumberGenerator:
	arena_validation_errors.clear()
	occupied_tiles.clear()
	special_zones.clear()
	arena_id = selected_id
	arena_name = str(arena_data.get("name", default_name))
	width = int(arena_data.get("width", 20))
	height = int(arena_data.get("height", 13))
	tiles.clear()
	tiles.resize(width * height)
	for i in tiles.size():
		tiles[i] = TileType.FLOOR
	for x in width:
		set_tile(Vector2i(x, 0), TileType.WALL)
		set_tile(Vector2i(x, height - 1), TileType.WALL)
	for y in height:
		set_tile(Vector2i(0, y), TileType.WALL)
		set_tile(Vector2i(width - 1, y), TileType.WALL)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(arena_data.get("generator", {}).get("seed", hash(selected_id)))
	ally_spawns = _parse_spawns(arena_data.get("ally_spawns", [[2, 2], [2, 5], [2, 9], [4, 4], [4, 8]]))
	enemy_spawns = _parse_spawns(arena_data.get("enemy_spawns", [[width - 3, 2], [width - 3, 5], [width - 3, 9], [width - 5, 4], [width - 5, 8]]))
	return rng

func _clear_spawn_tiles() -> void:
	for pos in ally_spawns:
		if in_bounds(pos):
			set_tile(pos, TileType.FLOOR)
	for pos in enemy_spawns:
		if in_bounds(pos):
			set_tile(pos, TileType.FLOOR)

func _setup_generated_rooms(selected_id: String, arena_data: Dictionary, _seed: int) -> void:
	var rng := _prepare_generated_base(selected_id, arena_data, "Generated Rooms")
	for y in range(2, height - 2):
		for x in range(2, width - 2):
			if x in [6, 12] and rng.randf() < 0.72:
				set_tile(Vector2i(x, y), TileType.WALL)
			elif y in [4, 8] and rng.randf() < 0.46:
				set_tile(Vector2i(x, y), TileType.WALL)
	for y in [3, 6, 9]:
		for x in range(2, width - 2):
			if get_tile(Vector2i(x, y)) == TileType.WALL:
				set_tile(Vector2i(x, y), TileType.DOOR if rng.randf() < 0.35 else TileType.NARROW)
	for i in 10:
		var pos := Vector2i(rng.randi_range(2, width - 3), rng.randi_range(2, height - 3))
		if is_walkable(pos):
			set_tile(pos, TileType.COVER)

func _setup_generated_nature(selected_id: String, arena_data: Dictionary, _seed: int) -> void:
	var rng := _prepare_generated_base(selected_id, arena_data, "Generated Nature")
	var river_x := rng.randi_range(6, maxi(7, width - 7))
	for y in range(1, height - 1):
		var drift := int(round(sin(float(y) * 0.8) * 1.5))
		for dx in range(-1, 2):
			var pos := Vector2i(clampi(river_x + drift + dx, 1, width - 2), y)
			set_tile(pos, TileType.WATER)
		if y % 3 == 0:
			set_tile(Vector2i(clampi(river_x + drift, 1, width - 2), y), TileType.DEEP_WATER)
	for i in 26:
		var pos := Vector2i(rng.randi_range(1, width - 2), rng.randi_range(1, height - 2))
		if get_tile(pos) == TileType.FLOOR:
			set_tile(pos, TileType.GRASS if rng.randf() < 0.68 else TileType.COVER)
	for i in 5:
		var pos := Vector2i(rng.randi_range(3, width - 4), rng.randi_range(2, height - 3))
		if get_tile(pos) == TileType.FLOOR:
			set_tile(pos, TileType.HEIGHT)

func _setup_generated_mixed(selected_id: String, arena_data: Dictionary, _seed: int) -> void:
	_setup_generated_rooms(selected_id, arena_data, _seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(arena_data.get("generator", {}).get("seed", hash(selected_id))) + 17
	for i in 18:
		var pos := Vector2i(rng.randi_range(2, width - 3), rng.randi_range(2, height - 3))
		if get_tile(pos) == TileType.FLOOR:
			var roll := rng.randf()
			if roll < 0.35:
				set_tile(pos, TileType.GRASS)
			elif roll < 0.58:
				set_tile(pos, TileType.DARK)
			elif roll < 0.76:
				set_tile(pos, TileType.NOISY)
			else:
				set_tile(pos, TileType.TRAP)

func _parse_spawns(raw_spawns: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw_spawn in raw_spawns:
		if raw_spawn is Array and raw_spawn.size() >= 2:
			var pos := Vector2i(int(raw_spawn[0]), int(raw_spawn[1]))
			result.append(pos)
	return result

func _validate_spawns(label: String, spawns: Array[Vector2i], errors: Array[String]) -> void:
	if spawns.is_empty():
		errors.append("%s spawns are empty" % label)
		return
	var seen := {}
	for pos in spawns:
		if not in_bounds(pos):
			errors.append("%s spawn %s is outside arena" % [label, str(pos)])
			continue
		if not is_walkable(pos):
			errors.append("%s spawn %s is not walkable" % [label, str(pos)])
		if seen.has(pos):
			errors.append("%s spawn %s is duplicated" % [label, str(pos)])
		seen[pos] = true

func _validate_spawn_overlap(errors: Array[String]) -> void:
	var occupied := {}
	for pos in ally_spawns:
		occupied[pos] = "ally"
	for pos in enemy_spawns:
		if occupied.has(pos):
			errors.append("ally and enemy spawns overlap at %s" % str(pos))

func _validate_spawn_routes(
	source_label: String,
	source_spawns: Array[Vector2i],
	target_label: String,
	target_spawns: Array[Vector2i],
	errors: Array[String]
) -> void:
	for source in source_spawns:
		if _can_reach_any_spawn(source, target_spawns):
			continue
		errors.append("%s spawn %s cannot reach any %s spawn" % [source_label, str(source), target_label])

func _can_reach_any_spawn(source: Vector2i, target_spawns: Array[Vector2i]) -> bool:
	for target in target_spawns:
		if source == target:
			return true
		if not find_path(source, target).is_empty():
			return true
	return false

func _fail_arena_validation(selected_id: String, errors: Array[String]) -> bool:
	arena_validation_errors.clear()
	for error in errors:
		arena_validation_errors.append(error)
	for error in arena_validation_errors:
		push_warning("RT arena '%s' invalid: %s" % [selected_id, error])
	return false

func _path_cache_key(start: Vector2i, goal: Vector2i, ignored_occupant_id: String, allow_occupied_goal: bool) -> String:
	return "%d:%s:%s:%s:%s" % [
		_occupancy_revision,
		str(start),
		str(goal),
		ignored_occupant_id,
		"1" if allow_occupied_goal else "0"
	]

func _store_path_cache(cache_key: String, path: Array[Vector2i]) -> void:
	if path_cache.size() > 320:
		path_cache.clear()
	path_cache[cache_key] = path.duplicate()

func _setup_fallback_arena() -> void:
	arena_validation_errors.clear()
	occupied_tiles.clear()
	arena_id = "fallback"
	arena_name = "Fallback"
	width = 18
	height = 12
	tiles.clear()
	tiles.resize(width * height)
	for i in tiles.size():
		tiles[i] = TileType.FLOOR
	for x in width:
		set_tile(Vector2i(x, 0), TileType.WALL)
		set_tile(Vector2i(x, height - 1), TileType.WALL)
	for y in height:
		set_tile(Vector2i(0, y), TileType.WALL)
		set_tile(Vector2i(width - 1, y), TileType.WALL)
	ally_spawns = [Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 8)]
	enemy_spawns = [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 8)]

func _path_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var next: Vector2i = pos + offset
		if not is_walkable(next):
			continue
		result.append(next)
	return result

func _occupancy_path_penalty(
	pos: Vector2i,
	goal: Vector2i,
	ignored_occupant_id: String,
	allow_occupied_goal: bool
) -> float:
	if allow_occupied_goal and pos == goal:
		return 0.0
	if is_occupied(pos, ignored_occupant_id):
		return 8.0
	return 0.0

func _index(pos: Vector2i) -> int:
	return pos.y * width + pos.x

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))

func _lowest_score(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best: Vector2i = open[0]
	var best_score := float(f_score.get(best, INF))
	for item in open:
		var score: float = float(f_score.get(item, INF))
		if score < best_score:
			best = item
			best_score = score
	return best

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var total: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		total.push_front(current)
	if not total.is_empty():
		total.remove_at(0)
	return total

func _line_points(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0 := from_pos.x
	var y0 := from_pos.y
	var x1 := to_pos.x
	var y1 := to_pos.y
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return points

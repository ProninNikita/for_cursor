class_name RTBattlefield
extends RefCounted

enum TileType { FLOOR, WALL, WATER, COVER, DOOR, GRASS }

const TILE_SIZE := 42.0

var width: int = 0
var height: int = 0
var tiles: Array[int] = []
var ally_spawns: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []

func setup_test_arena() -> void:
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

	for y in range(2, 9):
		if y != 5:
			set_tile(Vector2i(8, y), TileType.WALL)
	for x in range(10, 15):
		if x != 12:
			set_tile(Vector2i(x, 4), TileType.WALL)

	for y in range(1, height - 1):
		set_tile(Vector2i(5, y), TileType.WATER)
	set_tile(Vector2i(5, 5), TileType.DOOR)
	set_tile(Vector2i(5, 8), TileType.DOOR)

	for p in [
		Vector2i(3, 3),
		Vector2i(3, 8),
		Vector2i(7, 6),
		Vector2i(11, 2),
		Vector2i(14, 7),
		Vector2i(15, 9),
	]:
		set_tile(p, TileType.COVER)

	for p in [
		Vector2i(2, 5),
		Vector2i(2, 6),
		Vector2i(12, 8),
		Vector2i(13, 8),
		Vector2i(14, 8),
	]:
		set_tile(p, TileType.GRASS)

	ally_spawns = [Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 8), Vector2i(4, 4), Vector2i(4, 7)]
	enemy_spawns = [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 8), Vector2i(12, 6), Vector2i(13, 9)]

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
	return tile != TileType.WALL

func blocks_vision(pos: Vector2i) -> bool:
	return get_tile(pos) == TileType.WALL

func movement_cost(pos: Vector2i) -> float:
	match get_tile(pos):
		TileType.WATER:
			return 1.9
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

func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if start == goal or not is_walkable(start) or not is_walkable(goal):
		return path

	var open: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}

	while not open.is_empty():
		var current: Vector2i = _lowest_score(open, f_score)
		if current == goal:
			return _reconstruct_path(came_from, current)

		open.erase(current)
		for neighbor in get_neighbors(current):
			var tentative: float = float(g_score.get(current, INF)) + movement_cost(neighbor)
			if tentative >= float(g_score.get(neighbor, INF)):
				continue
			came_from[neighbor] = current
			g_score[neighbor] = tentative
			f_score[neighbor] = tentative + _heuristic(neighbor, goal)
			if not open.has(neighbor):
				open.append(neighbor)

	return path

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

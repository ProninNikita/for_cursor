class_name RTActionResolver
extends RefCounted

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _events: Array[Dictionary] = []

func update_unit(unit, delta: float, intent: Dictionary, battlefield, map_origin: Vector2) -> Array[String]:
	_events.clear()
	var messages: Array[String] = []
	if not unit.is_alive():
		return messages

	unit.attack_timer = maxf(0.0, unit.attack_timer - delta)
	var type: String = str(intent.get("type", "hold"))
	var destination: Vector2i = intent.get("destination", unit.grid_pos)
	var target = intent.get("target", null)
	unit.set_intent(type, str(intent.get("reason", "оценивает ситуацию")), destination)

	match type:
		"attack":
			if target != null and target.is_alive():
				messages.append_array(_try_attack(unit, target))
				if _grid_distance(unit.grid_pos, target.grid_pos) > unit.attack_range_tiles:
					_move_towards(unit, target.grid_pos, delta, battlefield, map_origin)
		"chase", "retreat", "take_cover", "follow", "patrol", "ambush":
			_move_towards(unit, destination, delta, battlefield, map_origin)
		"hold":
			unit.hold_timer += delta
		_:
			unit.hold_timer += delta

	return messages

func _try_attack(attacker, target) -> Array[String]:
	var messages: Array[String] = []
	if attacker.attack_timer > 0.0:
		return messages
	if _grid_distance(attacker.grid_pos, target.grid_pos) > attacker.attack_range_tiles:
		return messages

	attacker.attack_timer = attacker.attack_cooldown
	var raw: int = attacker.get_stat("atk") - target.get_stat("def") / 2
	if attacker.get_stat("magic") > attacker.get_stat("atk") and attacker.attack_range_tiles > 2.0:
		raw = attacker.get_stat("magic") - target.get_stat("def") / 3
	var damage: int = maxi(1, raw + rng.randi_range(-1, 2))
	target.take_damage(damage)
	attacker.fear = clampf(attacker.fear - 0.04, 0.0, 1.0)
	attacker.morale = clampf(attacker.morale + 0.03, 0.0, 1.0)

	messages.append("%s атакует %s: %d урона." % [attacker.display_name, target.display_name, damage])
	if not target.is_alive():
		messages.append("%s выведен из боя." % target.display_name)
	_events.append({
		"type": "damage",
		"attacker": attacker,
		"target": target,
		"amount": damage
	})
	return messages

func consume_events() -> Array[Dictionary]:
	var result := _events.duplicate()
	_events.clear()
	return result

func _move_towards(unit, destination: Vector2i, delta: float, battlefield, map_origin: Vector2) -> void:
	if destination == unit.grid_pos:
		unit.path.clear()
		return

	if unit.path.is_empty() or unit.destination != destination:
		unit.destination = destination
		unit.path = battlefield.find_path(unit.grid_pos, destination)

	if unit.path.is_empty():
		return

	var next_grid: Vector2i = unit.path[0]
	var next_world: Vector2 = battlefield.world_from_grid(next_grid, map_origin)
	var to_next: Vector2 = next_world - unit.world_position
	var distance: float = to_next.length()
	if distance <= 1.0:
		unit.grid_pos = next_grid
		unit.world_position = next_world
		unit.path.remove_at(0)
		return

	var speed: float = battlefield.tile_size() * unit.speed_tiles_per_second / battlefield.movement_cost(next_grid)
	var step: float = minf(distance, speed * delta)
	var direction: Vector2 = to_next.normalized()
	unit.world_position += direction * step
	if direction.length() > 0.01:
		unit.facing = direction

func _grid_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

class_name RTPerception
extends RefCounted

func update(units: Array, battlefield) -> void:
	for unit in units:
		unit.visible_enemies.clear()

	for observer in units:
		if not observer.is_alive():
			continue
		for target in units:
			if target == observer or not target.is_alive() or target.side == observer.side:
				continue
			if can_see(observer, target, battlefield):
				observer.visible_enemies.append(target)
				observer.last_seen_enemies[target.unit_id] = {
					"pos": target.grid_pos,
					"time": Time.get_ticks_msec()
				}

func can_see(observer, target, battlefield) -> bool:
	var delta: Vector2 = Vector2(target.grid_pos - observer.grid_pos)
	var distance: float = delta.length()
	if distance > observer.vision_radius_tiles:
		return false
	if distance <= 1.25:
		return battlefield.has_line_of_sight(observer.grid_pos, target.grid_pos)

	var forward: Vector2 = observer.facing.normalized()
	if forward.length() <= 0.01:
		forward = Vector2.RIGHT if observer.side == BattleUnit.UnitSide.ALLY else Vector2.LEFT
	var direction: Vector2 = delta.normalized()
	var angle: float = rad_to_deg(acos(clampf(forward.dot(direction), -1.0, 1.0)))
	if angle > observer.vision_angle_deg * 0.5:
		return false

	if battlefield.is_grass(target.grid_pos) and distance > 3.0:
		return false

	return battlefield.has_line_of_sight(observer.grid_pos, target.grid_pos)

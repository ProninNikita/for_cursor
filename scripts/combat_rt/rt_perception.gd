class_name RTPerception
extends RefCounted

func update(units: Array, battlefield) -> void:
	var previous_visible_counts: Dictionary = {}
	var now: int = Time.get_ticks_msec()
	for unit in units:
		previous_visible_counts[unit.unit_id] = unit.visible_enemies.size()
		unit.visible_enemies.clear()
		_update_hidden_state(unit, battlefield)
		_prune_last_seen(unit, now)

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
					"time": now
				}
				_alert_allies(observer, target, units, now)
			elif _can_hear(observer, target, battlefield):
				observer.heard_noise_pos = _approximate_noise_pos(observer, target.grid_pos)
				observer.heard_noise_timer = 3.2
				observer.heard_noise_strength = _noise_strength(observer, target, battlefield)

	for observer in units:
		if not observer.is_alive():
			continue
		var previous_count := int(previous_visible_counts.get(observer.unit_id, 0))
		observer.last_visible_enemy_count = observer.visible_enemies.size()
		if previous_count > 0 and observer.visible_enemies.is_empty():
			observer.lost_target_timer = 1.6

func _alert_allies(observer, target, units: Array, now: int) -> void:
	if observer.character_data != null or not observer.enemy_ai_profile.has("call_help"):
		return
	var call_strength: float = float(observer.enemy_ai_profile.get("call_help", 0.0))
	if call_strength <= 0.0:
		return
	var alert_radius: float = 4.0 + call_strength * 4.0
	for ally in units:
		if ally == observer or not ally.is_alive() or ally.side != observer.side:
			continue
		var distance: float = Vector2(ally.grid_pos - observer.grid_pos).length()
		if distance > alert_radius:
			continue
		ally.heard_noise_pos = target.grid_pos
		ally.heard_noise_timer = maxf(ally.heard_noise_timer, 2.6 + call_strength)
		ally.heard_noise_strength = maxf(ally.heard_noise_strength, call_strength)
		if ally.last_seen_enemies.is_empty() or call_strength >= 0.75:
			ally.last_seen_enemies[target.unit_id] = {
				"pos": target.grid_pos,
				"time": now
			}

func can_see(observer, target, battlefield) -> bool:
	var delta: Vector2 = Vector2(target.grid_pos - observer.grid_pos)
	var distance: float = delta.length()
	var vision_radius: float = observer.vision_radius_tiles
	if battlefield.is_dark(observer.grid_pos):
		vision_radius *= 0.82
	if battlefield.is_dark(target.grid_pos):
		vision_radius *= 0.62
	if distance > vision_radius:
		return false
	if distance <= 1.25:
		return battlefield.has_line_of_sight(observer.grid_pos, target.grid_pos)

	if target.hidden:
		var detection_range: float = 2.0 + observer.vision_radius_tiles * 0.16 - target.stealth_rating
		if distance > detection_range:
			return false

	var forward: Vector2 = observer.facing.normalized()
	if forward.length() <= 0.01:
		forward = Vector2.RIGHT if observer.side == BattleUnit.UnitSide.ALLY else Vector2.LEFT
	var direction: Vector2 = delta.normalized()
	var angle: float = rad_to_deg(acos(clampf(forward.dot(direction), -1.0, 1.0)))
	if angle > observer.vision_angle_deg * 0.5:
		return false

	if battlefield.is_grass(target.grid_pos) and distance > (3.0 - target.stealth_rating):
		return false
	if battlefield.is_dark(target.grid_pos) and distance > maxf(2.0, observer.vision_radius_tiles * 0.42):
		return false

	return battlefield.has_line_of_sight(observer.grid_pos, target.grid_pos)

func _update_hidden_state(unit, battlefield) -> void:
	unit.hidden = false
	unit.ambush_ready = false
	unit.remove_status("hidden")
	if not unit.is_alive() or unit.stealth_rating <= 0.0 or unit.stealth_reveal_timer > 0.0:
		return
	if unit.intent in ["attack", "ability", "chase"]:
		return
	var in_hiding_spot: bool = (
		battlefield.is_grass(unit.grid_pos)
		or battlefield.is_cover(unit.grid_pos)
		or _near_vision_blocker(unit.grid_pos, battlefield)
	)
	if not in_hiding_spot:
		return
	unit.hidden = true
	unit.ambush_ready = true
	unit.add_status("hidden", 0.45)

func _near_vision_blocker(pos: Vector2i, battlefield) -> bool:
	for offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var nearby: Vector2i = pos + offset
		if not battlefield.in_bounds(nearby) or battlefield.blocks_vision(nearby):
			return true
	return false

func _prune_last_seen(unit, now: int) -> void:
	for enemy_id in unit.last_seen_enemies.keys():
		var memory: Dictionary = unit.last_seen_enemies.get(enemy_id, {})
		if now - int(memory.get("time", 0)) > 12000:
			unit.last_seen_enemies.erase(enemy_id)

func _can_hear(observer, target, battlefield) -> bool:
	var strength: float = _noise_strength(observer, target, battlefield)
	if strength <= 0.0:
		return false
	var distance: float = Vector2(target.grid_pos - observer.grid_pos).length()
	if distance > strength:
		return false
	if battlefield.has_line_of_sight(observer.grid_pos, target.grid_pos):
		return true
	return distance <= strength * 0.62

func _noise_strength(observer, target, battlefield) -> float:
	var distance: float = Vector2(target.grid_pos - observer.grid_pos).length()
	var strength := 2.6
	if target.intent in ["attack", "ability"]:
		strength += 2.4
	elif target.intent in ["chase", "retreat", "flank", "keep_distance"]:
		strength += 1.5
	elif not target.path.is_empty():
		strength += 1.0
	if battlefield.is_water(target.grid_pos):
		strength += 1.2
	if battlefield.is_noisy(target.grid_pos):
		strength += 1.4
	if battlefield.is_narrow(target.grid_pos):
		strength += 0.45
	if battlefield.is_grass(target.grid_pos):
		strength -= 0.6
	if battlefield.is_dark(target.grid_pos):
		strength -= 0.25
	if distance <= 1.5:
		strength += 1.5
	return maxf(0.0, strength)

func _approximate_noise_pos(observer, real_pos: Vector2i) -> Vector2i:
	var delta: Vector2i = real_pos - observer.grid_pos
	if abs(delta.x) + abs(delta.y) <= 2:
		return real_pos
	var sx := 0 if delta.x == 0 else (1 if delta.x > 0 else -1)
	var sy := 0 if delta.y == 0 else (1 if delta.y > 0 else -1)
	return real_pos - Vector2i(sx, sy)

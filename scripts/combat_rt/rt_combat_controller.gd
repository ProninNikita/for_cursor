class_name RTCombatController
extends RefCounted

func evaluate_finish(units: Array, context, elapsed_seconds: float) -> Dictionary:
	var allies_alive := _alive_count(units, BattleUnit.UnitSide.ALLY)
	var enemies_alive := _alive_count(units, BattleUnit.UnitSide.ENEMY)
	var result := _victory_result(units, context, elapsed_seconds, allies_alive, enemies_alive)
	if not result.is_empty():
		return result
	result = _defeat_result(units, context, elapsed_seconds, allies_alive, enemies_alive)
	if not result.is_empty():
		return result
	if allies_alive > 0 and enemies_alive > 0:
		return {}
	if enemies_alive <= 0:
		return {"finished": true, "victory": true, "reason": "elimination", "detail": "Все враги выведены из боя."}
	return {"finished": true, "victory": false, "reason": "wipe", "detail": "Все союзники выведены из боя."}

func _victory_result(units: Array, context, elapsed_seconds: float, allies_alive: int, enemies_alive: int) -> Dictionary:
	if allies_alive <= 0:
		return {}
	var condition: String = "eliminate_enemies"
	if context != null:
		condition = context.victory_string("type", "eliminate_enemies")
	match condition:
		"survive_seconds":
			var seconds: float = context.victory_float("seconds", 45.0) if context != null else 45.0
			if elapsed_seconds >= seconds:
				return {"finished": true, "victory": true, "reason": "survived", "detail": "Отряд продержался %d сек." % int(round(seconds))}
		"defeat_boss":
			if not _boss_enemy_alive(units):
				return {"finished": true, "victory": true, "reason": "boss_defeated", "detail": "Ключевая цель выведена из боя."}
		_:
			if enemies_alive <= 0:
				return {"finished": true, "victory": true, "reason": "elimination", "detail": "Все враги выведены из боя."}
	return {}

func _defeat_result(units: Array, context, elapsed_seconds: float, allies_alive: int, enemies_alive: int) -> Dictionary:
	if allies_alive <= 0:
		return {"finished": true, "victory": false, "reason": "wipe", "detail": "Все союзники выведены из боя."}
	var time_limit: float = context.defeat_float("time_limit_seconds", 0.0) if context != null else 0.0
	if time_limit > 0.0 and elapsed_seconds >= time_limit and enemies_alive > 0:
		return {"finished": true, "victory": false, "reason": "time_limit", "detail": "Время боя вышло, отряд отходит."}
	var retreat_enabled: bool = context.modifier_bool("retreat_enabled", true) if context != null else true
	if not retreat_enabled:
		return {}
	var retreat_after: float = context.defeat_float("retreat_after_seconds", 14.0) if context != null else 14.0
	if elapsed_seconds < retreat_after or enemies_alive <= 0:
		return {}
	var threshold: float = context.modifier_float("heavy_loss_threshold", 0.3) if context != null else 0.3
	var total_allies := maxi(1, _unit_count(units, BattleUnit.UnitSide.ALLY))
	var living_ratio := float(allies_alive) / float(total_allies)
	if living_ratio <= threshold or _all_living_allies_critical(units):
		return {"finished": true, "victory": false, "reason": "retreat", "detail": "Отряд потерял строй и отступил до полного уничтожения."}
	return {}

func _alive_count(units: Array, side: int) -> int:
	var count := 0
	for unit in units:
		if unit.side == side and unit.is_alive():
			count += 1
	return count

func _unit_count(units: Array, side: int) -> int:
	var count := 0
	for unit in units:
		if unit.side == side:
			count += 1
	return count

func _boss_enemy_alive(units: Array) -> bool:
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ENEMY or not unit.is_alive():
			continue
		if unit.display_name.find("Хранитель") >= 0 or unit.enemy_danger >= 5.5:
			return true
	return false

func _all_living_allies_critical(units: Array) -> bool:
	var living := 0
	var critical := 0
	for unit in units:
		if unit.side != BattleUnit.UnitSide.ALLY or not unit.is_alive():
			continue
		living += 1
		if unit.hp_ratio() <= 0.22 or unit.has_status("broken"):
			critical += 1
	return living > 0 and critical >= living

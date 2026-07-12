class_name RTBattleUnit
extends RefCounted

const RECENT_EVENT_LIMIT := 12

var unit_id: String = ""
var side: int = BattleUnit.UnitSide.ALLY
var display_name: String = ""
var battle_unit: BattleUnit = null
var character_data: CharacterData = null
var grid_pos: Vector2i = Vector2i.ZERO
var world_position: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var path: Array[Vector2i] = []
var destination: Vector2i = Vector2i.ZERO
var visible_enemies: Array = []
var last_seen_enemies: Dictionary = {}
var intent: String = "idle"
var intent_reason: String = "ждёт"
var target_name: String = ""
var intent_ability_name: String = ""
var decision_scores: Array[Dictionary] = []
var decision_confidence: float = 0.0
var decision_margin: float = 0.0
var decision_mistake_chance: float = 0.0
var decision_lock_timer: float = 0.0
var is_leader: bool = false
var leader_unit_id: String = ""
var leader_name: String = ""
var squad_style: String = "balanced"
var squad_anchor: Vector2i = Vector2i.ZERO
var squad_focus_target_id: String = ""
var squad_focus_target_name: String = ""
var squad_focus_target_pos: Vector2i = Vector2i.ZERO
var formation_role: String = "line"
var formation_slot: Vector2i = Vector2i.ZERO
var formation_distance: float = 0.0
var morale: float = 0.65
var fear: float = 0.0
var vision_radius_tiles: float = 6.0
var vision_angle_deg: float = 115.0
var stealth_rating: float = 0.0
var hidden: bool = false
var ambush_ready: bool = false
var stealth_reveal_timer: float = 0.0
var stealth_notice_timer: float = 0.0
var attack_range_tiles: float = 1.25
var attack_cooldown: float = 1.25
var attack_timer: float = 0.0
var action_recovery_timer: float = 0.0
var cast_timer: float = 0.0
var cast_action: Dictionary = {}
var current_action: Dictionary = {}
var action_queue: Array[Dictionary] = []
var speed_tiles_per_second: float = 2.4
var energy: float = 100.0
var stamina: float = 100.0
var mana: float = 100.0
var hold_timer: float = 0.0
var path_fail_count: int = 0
var movement_recovery_timer: float = 0.0
var movement_notice_timer: float = 0.0
var panic_mistake_timer: float = 0.0
var patrol_destination: Vector2i = Vector2i.ZERO
var patrol_rethink_timer: float = 0.0
var last_visible_enemy_count: int = 0
var lost_target_timer: float = 0.0
var lost_target_notice_timer: float = 0.0
var heard_noise_pos: Vector2i = Vector2i.ZERO
var heard_noise_timer: float = 0.0
var heard_noise_strength: float = 0.0
var heard_noise_notice_timer: float = 0.0
var visibility_stress: float = 0.0
var ability_cooldowns: Dictionary = {}
var stat_modifiers: Dictionary = {}
var timed_effects: Array[Dictionary] = []
var statuses: Dictionary = {}
var status_payloads: Dictionary = {}
var current_task: String = "idle"
var current_target_id: String = ""
var current_path_goal: Vector2i = Vector2i.ZERO
var last_known_enemy_id: String = ""
var last_known_enemy_name: String = ""
var last_known_enemy_pos: Vector2i = Vector2i.ZERO
var recent_events: Array[Dictionary] = []
var last_damage_source_name: String = ""
var last_damage_ability_name: String = ""
var last_damage_cause: String = ""
var last_damage_source_side: int = -1
var death_shock_emitted: bool = false
var body_remove_timer: float = -1.0
var enemy_ai_profile: Dictionary = {}
var enemy_danger: float = 0.0
var enemy_reward_weight: float = 0.0
var enemy_phases: Array[Dictionary] = []
var enemy_phase_index: int = -1
var enemy_phase_name: String = ""

func setup_from_battle_unit(source: BattleUnit, id: String, spawn: Vector2i, origin: Vector2, battlefield) -> void:
	unit_id = id
	side = source.side
	display_name = source.display_name
	battle_unit = source
	character_data = source.character_data
	grid_pos = spawn
	destination = spawn
	world_position = battlefield.world_from_grid(spawn, origin)
	facing = Vector2.RIGHT if source.side == BattleUnit.UnitSide.ALLY else Vector2.LEFT
	speed_tiles_per_second = maxf(1.6, 1.6 + float(source.initiative) * 0.11)
	vision_radius_tiles = 5.5 + float(source.initiative) * 0.12
	stealth_rating = _source_stealth_rating(source)
	hidden = false
	ambush_ready = false
	stealth_reveal_timer = 0.0
	stealth_notice_timer = 0.0
	decision_scores.clear()
	decision_confidence = 0.0
	decision_margin = 0.0
	decision_mistake_chance = 0.0
	decision_lock_timer = 0.0
	is_leader = false
	leader_unit_id = ""
	leader_name = ""
	squad_style = "balanced"
	squad_anchor = spawn
	squad_focus_target_id = ""
	squad_focus_target_name = ""
	squad_focus_target_pos = Vector2i.ZERO
	formation_role = "line"
	formation_slot = spawn
	formation_distance = 0.0
	attack_range_tiles = 3.8 if source.magic > source.atk else 1.25
	attack_cooldown = maxf(0.75, 1.55 - float(source.initiative) * 0.04)
	attack_timer = 0.0
	action_recovery_timer = 0.0
	cast_timer = 0.0
	cast_action.clear()
	current_action.clear()
	action_queue.clear()
	energy = 100.0
	stamina = 100.0
	mana = 100.0
	morale = 0.55 + brain_value("leader_trust") * 0.25
	path_fail_count = 0
	movement_recovery_timer = 0.0
	movement_notice_timer = 0.0
	panic_mistake_timer = 0.0
	patrol_destination = spawn
	patrol_rethink_timer = 0.0
	last_visible_enemy_count = 0
	lost_target_timer = 0.0
	lost_target_notice_timer = 0.0
	heard_noise_pos = spawn
	heard_noise_timer = 0.0
	heard_noise_strength = 0.0
	heard_noise_notice_timer = 0.0
	visibility_stress = 0.0
	statuses.clear()
	status_payloads.clear()
	current_task = "idle"
	current_target_id = ""
	current_path_goal = spawn
	last_known_enemy_id = ""
	last_known_enemy_name = ""
	last_known_enemy_pos = spawn
	recent_events.clear()
	last_damage_source_name = ""
	last_damage_ability_name = ""
	last_damage_cause = ""
	last_damage_source_side = -1
	death_shock_emitted = false
	body_remove_timer = -1.0
	enemy_ai_profile.clear()
	enemy_danger = 0.0
	enemy_reward_weight = 0.0
	enemy_phases.clear()
	enemy_phase_index = -1
	enemy_phase_name = ""

func apply_enemy_profile(profile: Dictionary = {}) -> void:
	var vision: Dictionary = profile.get("vision", {})
	vision_radius_tiles = float(vision.get("radius_tiles", profile.get("vision_radius_tiles", 5.2)))
	vision_angle_deg = float(vision.get("angle_deg", profile.get("vision_angle_deg", 130.0)))
	morale = float(profile.get("morale", 0.62))
	stealth_rating = float(profile.get("stealth", stealth_rating))
	enemy_ai_profile = profile.get("ai", {}).duplicate(true)
	enemy_danger = float(profile.get("danger", 1.0))
	enemy_reward_weight = float(profile.get("reward_weight", enemy_danger))
	enemy_phases = _duplicate_phase_entries(profile.get("phases", []))
	enemy_phase_index = -1
	enemy_phase_name = ""

func activate_pending_enemy_phases() -> Array[Dictionary]:
	var activated: Array[Dictionary] = []
	if side != BattleUnit.UnitSide.ENEMY or enemy_phases.is_empty() or not is_alive():
		return activated

	var ratio := hp_ratio()
	while enemy_phase_index + 1 < enemy_phases.size():
		var next_phase: Dictionary = enemy_phases[enemy_phase_index + 1]
		var hp_below := float(next_phase.get("hp_below", 0.0))
		if hp_below <= 0.0 or ratio > hp_below:
			break
		enemy_phase_index += 1
		_apply_enemy_phase(next_phase)
		activated.append(next_phase)
	return activated

func _apply_enemy_phase(phase: Dictionary) -> void:
	enemy_phase_name = str(phase.get("name", enemy_phase_name))
	morale = maxf(morale, float(phase.get("morale", morale)))

	var vision: Dictionary = phase.get("vision", {})
	if not vision.is_empty():
		vision_radius_tiles = maxf(vision_radius_tiles, float(vision.get("radius_tiles", vision_radius_tiles)))
		vision_angle_deg = maxf(vision_angle_deg, float(vision.get("angle_deg", vision_angle_deg)))

	var ai_overrides: Dictionary = phase.get("ai", {})
	for key in ai_overrides:
		enemy_ai_profile[key] = ai_overrides[key]

	var modifiers: Dictionary = phase.get("stat_modifiers", {})
	for stat in modifiers:
		stat_modifiers[stat] = int(stat_modifiers.get(stat, 0)) + int(modifiers[stat])

	attack_cooldown = maxf(0.45, attack_cooldown * float(phase.get("attack_cooldown_multiplier", 1.0)))
	var cooldown_reduction := float(phase.get("cooldown_reduction", 0.0))
	if cooldown_reduction > 0.0:
		for ability_id in ability_cooldowns.keys():
			ability_cooldowns[ability_id] = maxf(0.0, float(ability_cooldowns[ability_id]) - cooldown_reduction)

func _duplicate_phase_entries(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result

func is_alive() -> bool:
	return battle_unit != null and battle_unit.is_alive()

func hp_ratio() -> float:
	if battle_unit == null or battle_unit.max_hp <= 0:
		return 0.0
	return float(battle_unit.current_hp) / float(battle_unit.max_hp)

func get_stat(stat: String) -> int:
	if battle_unit == null:
		return 0
	return maxi(0, battle_unit.get_stat(stat) + int(stat_modifiers.get(stat, 0)))

func tick_rt_state(delta: float) -> Array[Dictionary]:
	var state_events: Array[Dictionary] = []
	_regenerate_resources(delta)
	movement_recovery_timer = maxf(0.0, movement_recovery_timer - delta)
	movement_notice_timer = maxf(0.0, movement_notice_timer - delta)
	panic_mistake_timer = maxf(0.0, panic_mistake_timer - delta)
	patrol_rethink_timer = maxf(0.0, patrol_rethink_timer - delta)
	lost_target_timer = maxf(0.0, lost_target_timer - delta)
	lost_target_notice_timer = maxf(0.0, lost_target_notice_timer - delta)
	heard_noise_timer = maxf(0.0, heard_noise_timer - delta)
	heard_noise_notice_timer = maxf(0.0, heard_noise_notice_timer - delta)
	stealth_reveal_timer = maxf(0.0, stealth_reveal_timer - delta)
	stealth_notice_timer = maxf(0.0, stealth_notice_timer - delta)
	decision_lock_timer = maxf(0.0, decision_lock_timer - delta)
	action_recovery_timer = maxf(0.0, action_recovery_timer - delta)
	if body_remove_timer >= 0.0:
		body_remove_timer = maxf(0.0, body_remove_timer - delta)
	for ability_id in ability_cooldowns.keys():
		ability_cooldowns[ability_id] = maxf(0.0, float(ability_cooldowns[ability_id]) - delta)
	for i in range(timed_effects.size() - 1, -1, -1):
		var effect: Dictionary = timed_effects[i]
		effect["remaining"] = float(effect.get("remaining", 0.0)) - delta
		timed_effects[i] = effect
		if float(effect["remaining"]) <= 0.0:
			var stat := str(effect.get("stat", ""))
			var value := int(effect.get("value", 0))
			stat_modifiers[stat] = int(stat_modifiers.get(stat, 0)) - value
			if int(stat_modifiers.get(stat, 0)) == 0:
				stat_modifiers.erase(stat)
			timed_effects.remove_at(i)
	state_events.append_array(_tick_statuses(delta))
	_update_state_flags()
	return state_events

func _regenerate_resources(delta: float) -> void:
	energy = clampf(energy + delta * 8.0, 0.0, 100.0)
	stamina = clampf(stamina + delta * 5.0, 0.0, 100.0)
	mana = clampf(mana + delta * 2.2, 0.0, 100.0)

func _tick_statuses(delta: float) -> Array[Dictionary]:
	var state_events: Array[Dictionary] = []
	for status_id in statuses.keys():
		statuses[status_id] = maxf(0.0, float(statuses.get(status_id, 0.0)) - delta)
		var payload: Dictionary = status_payloads.get(status_id, {})
		if status_id == "poison" and is_alive():
			payload["tick_timer"] = float(payload.get("tick_timer", 1.0)) - delta
			if float(payload["tick_timer"]) <= 0.0:
				payload["tick_timer"] = 1.0
				var damage := maxi(1, int(payload.get("damage", 1)))
				take_damage(
					damage,
					str(payload.get("source_name", "")),
					str(payload.get("ability_name", "")),
					str(payload.get("cause", "poison")),
					int(payload.get("source_side", -1))
				)
				state_events.append({
					"type": "status_damage",
					"status": status_id,
					"target": self,
					"amount": damage
				})
		status_payloads[status_id] = payload

	for status_id in statuses.keys():
		if float(statuses.get(status_id, 0.0)) <= 0.0:
			statuses.erase(status_id)
			status_payloads.erase(status_id)
	return state_events

func _update_state_flags() -> void:
	if not is_alive():
		current_task = "dead"
		return
	if hp_ratio() <= 0.18:
		add_status("near_death", 0.35)
	elif hp_ratio() <= 0.45:
		add_status("wounded", 0.35)
	if fear >= 0.72:
		add_status("panic", 0.35)
	if morale <= 0.12:
		add_status("broken", 0.35)

func can_use_ability(ability: AbilityData) -> bool:
	return ability != null and float(ability_cooldowns.get(ability.id, 0.0)) <= 0.0

func mark_ability_used(ability: AbilityData) -> void:
	if ability == null:
		return
	ability_cooldowns[ability.id] = ability_cooldown_seconds(ability)

func ability_cooldown_seconds(ability: AbilityData) -> float:
	if ability == null:
		return attack_cooldown
	if ability.rt_cooldown_seconds > 0.0:
		return maxf(0.2, ability.rt_cooldown_seconds)
	if ability.cooldown_max <= 0:
		return attack_cooldown
	return maxf(0.8, float(ability.cooldown_max) * 1.65)

func ability_range_tiles(ability: AbilityData) -> float:
	if ability == null:
		return attack_range_tiles
	if ability.rt_range_tiles >= 0.0:
		return ability.rt_range_tiles
	match ability.target_type:
		AbilityData.TargetType.SELF, AbilityData.TargetType.ALL_ALLIES:
			return 0.0
		AbilityData.TargetType.SINGLE_ALLY:
			return 4.5
		AbilityData.TargetType.ALL_ENEMIES:
			return 4.8
		_:
			pass
	if ability.stat_used == "magic":
		return 4.6
	if ability.stat_used == "speed":
		return 2.2
	return attack_range_tiles

func apply_stat_modifier(stat: String, value: int, duration: float) -> void:
	if stat == "" or value == 0 or duration <= 0.0:
		return
	stat_modifiers[stat] = int(stat_modifiers.get(stat, 0)) + value
	timed_effects.append({
		"stat": stat,
		"value": value,
		"remaining": duration
	})

func add_status(status_id: String, duration: float, payload: Dictionary = {}) -> void:
	if status_id == "" or duration <= 0.0:
		return
	statuses[status_id] = maxf(float(statuses.get(status_id, 0.0)), duration)
	status_payloads[status_id] = payload.duplicate(true)

func remove_status(status_id: String) -> void:
	statuses.erase(status_id)
	status_payloads.erase(status_id)

func clear_negative_statuses() -> void:
	for status_id in ["poison", "stun", "panic", "marked", "broken"]:
		remove_status(status_id)

func has_status(status_id: String) -> bool:
	return float(statuses.get(status_id, 0.0)) > 0.0

func status_time(status_id: String) -> float:
	return float(statuses.get(status_id, 0.0))

func status_list() -> PackedStringArray:
	var result: PackedStringArray = []
	for status_id in statuses.keys():
		if float(statuses.get(status_id, 0.0)) > 0.0:
			result.append(str(status_id))
	return result

func enqueue_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	action_queue.append(action.duplicate(false))

func pop_next_action() -> Dictionary:
	if action_queue.is_empty():
		return {}
	var action: Dictionary = action_queue[0]
	action_queue.remove_at(0)
	current_action = action.duplicate(false)
	return current_action

func clear_actions(interrupted: bool = false) -> void:
	if interrupted and not current_action.is_empty():
		add_recent_event("interrupt", str(current_action.get("kind", "")))
	action_queue.clear()
	current_action.clear()
	cast_action.clear()
	cast_timer = 0.0

func action_signature() -> String:
	if not current_action.is_empty():
		return str(current_action.get("signature", ""))
	if not action_queue.is_empty():
		var next_action: Dictionary = action_queue[0]
		return str(next_action.get("signature", ""))
	return ""

func add_recent_event(event_type: String, label: String, amount: int = 0) -> void:
	recent_events.append({
		"type": event_type,
		"label": label,
		"amount": amount,
		"time": Time.get_ticks_msec()
	})
	while recent_events.size() > RECENT_EVENT_LIMIT:
		recent_events.remove_at(0)

func take_damage(
	amount: int,
	source_name: String = "",
	ability_name: String = "",
	cause: String = "damage",
	source_side: int = -1
) -> void:
	if battle_unit == null:
		return
	if amount > 0:
		last_damage_source_name = source_name
		last_damage_ability_name = ability_name
		last_damage_cause = cause
		last_damage_source_side = source_side
	battle_unit.take_damage(amount)
	fear = clampf(fear + minf(0.35, float(amount) / float(maxi(1, battle_unit.max_hp))), 0.0, 1.0)
	morale = clampf(morale - minf(0.22, float(amount) / float(maxi(1, battle_unit.max_hp)) * 0.5), 0.0, 1.0)
	add_recent_event("damage", "получил урон", amount)
	if not is_alive():
		body_remove_timer = 8.0
		clear_actions(true)
		clear_path()
	if character_data != null:
		character_data.record_damage_taken(amount, battle_unit.max_hp)

func heal(amount: int) -> void:
	if battle_unit == null:
		return
	battle_unit.heal(amount)
	fear = clampf(fear - 0.08, 0.0, 1.0)
	add_recent_event("heal", "лечение", amount)

func brain_value(key: String) -> float:
	if character_data == null:
		if enemy_ai_profile.has(key):
			return float(enemy_ai_profile.get(key, 0.45))
		match key:
			"aggression":
				return 0.58
			"caution":
				return 0.35
			"teamwork":
				return 0.35
			"self_preserve":
				return 0.35
			"focus_fire":
				return 0.55
			"cover_usage":
				return 0.25
			"skill_patience":
				return 0.35
			"leader_trust":
				return 0.25
			"darkness_fear":
				return 0.22
			_:
				return 0.45
	return character_data.get_brain_value(key)

func set_intent(type: String, reason: String, target_destination: Vector2i = Vector2i.ZERO, target = null, ability: AbilityData = null) -> void:
	var previous_intent := intent
	intent = type
	intent_reason = reason
	target_name = target.display_name if target != null else ""
	current_target_id = target.unit_id if target != null else ""
	intent_ability_name = ability.name if ability != null else ""
	if target_destination != Vector2i.ZERO:
		destination = target_destination
		current_path_goal = target_destination
	if target != null:
		last_known_enemy_id = target.unit_id
		last_known_enemy_name = target.display_name
		last_known_enemy_pos = target.grid_pos
	if previous_intent != intent and previous_intent not in ["", "idle", "dead"]:
		decision_lock_timer = maxf(decision_lock_timer, 0.55 + decision_confidence * 0.85)

func remember_decision(intent_data: Dictionary) -> void:
	decision_scores.clear()
	for raw_score in intent_data.get("scores", []):
		if raw_score is Dictionary:
			decision_scores.append(raw_score)
	decision_confidence = clampf(float(intent_data.get("confidence", 0.0)), 0.0, 1.0)
	decision_margin = float(intent_data.get("score_margin", 0.0))
	decision_mistake_chance = clampf(float(intent_data.get("mistake_chance", 0.0)), 0.0, 1.0)

func clear_path() -> void:
	path.clear()

func side_name() -> String:
	return "союзник" if side == BattleUnit.UnitSide.ALLY else "враг"

func _source_stealth_rating(source: BattleUnit) -> float:
	if source == null or source.character_data == null:
		return 0.0
	var class_id := str(source.character_data.character_class).to_lower()
	match class_id:
		"scout":
			return 0.38
		"rogue", "assassin":
			return 0.58
		_:
			return 0.0

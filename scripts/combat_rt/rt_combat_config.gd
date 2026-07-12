class_name RTCombatConfig
extends RefCounted

var decision_interval: float = 0.35
var max_log_lines: int = 14
var default_time_scale: float = 0.5
var speed_modes: Array[float] = [0.5, 1.0, 2.0, 4.0]
var deterministic_seed: bool = false
var battle_seed: int = -1
var damage_multiplier: float = 0.68
var trap_damage_base: int = 2
var poison_damage_multiplier: float = 1.0
var friendly_fire_multiplier: float = 0.55
var area_damage_multiplier: float = 1.0
var path_budget_per_tick: int = 120
var path_queue_per_tick: int = 18
var target_min_seconds: float = 20.0
var target_max_seconds: float = 60.0

func setup_from_context(context) -> void:
	_apply_context_modifiers(context)
	var requested_seed := _requested_seed()
	if requested_seed < 0:
		deterministic_seed = false
		battle_seed = -1
		return
	deterministic_seed = true
	battle_seed = _mix_seed(requested_seed, context)

func apply_to_rng(rng: RandomNumberGenerator, salt: String) -> void:
	if rng == null:
		return
	if deterministic_seed:
		rng.seed = _salted_seed(salt)
	else:
		rng.randomize()

func seed_label() -> String:
	if deterministic_seed:
		return str(battle_seed)
	return "random"

func default_speed_index() -> int:
	for i in speed_modes.size():
		if is_equal_approx(float(speed_modes[i]), default_time_scale):
			return i
	return 0

func _requested_seed() -> int:
	var env_seed := OS.get_environment("RT_COMBAT_SEED")
	if env_seed != "":
		return int(env_seed)

	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) != "--seed":
			continue
		if i + 1 < args.size():
			return int(args[i + 1])
	return -1

func _mix_seed(base_seed: int, context) -> int:
	var encounter_id := ""
	var combat_type := 0
	var tower_floor := 0
	if context != null:
		encounter_id = str(context.encounter_id)
		combat_type = int(context.combat_type)
		tower_floor = int(context.tower_floor)
	var seed_text := "%d:%s:%d:%d" % [base_seed, encounter_id, combat_type, tower_floor]
	return absi(seed_text.hash())

func _salted_seed(salt: String) -> int:
	var seed_text := "%d:%s" % [battle_seed, salt]
	return absi(seed_text.hash())

func _apply_context_modifiers(context) -> void:
	if context == null:
		return
	damage_multiplier = clampf(context.modifier_float("damage_taken_multiplier", damage_multiplier), 0.55, 1.35)
	trap_damage_base = clampi(int(round(context.modifier_float("trap_damage", float(trap_damage_base)))), 1, 8)
	poison_damage_multiplier = clampf(context.modifier_float("poison_damage_multiplier", poison_damage_multiplier), 0.45, 1.8)
	friendly_fire_multiplier = clampf(context.modifier_float("friendly_fire_multiplier", friendly_fire_multiplier), 0.25, 0.9)
	area_damage_multiplier = clampf(context.modifier_float("area_damage_multiplier", area_damage_multiplier), 0.55, 1.4)
	path_budget_per_tick = clampi(int(round(context.modifier_float("path_budget_per_tick", float(path_budget_per_tick)))), 24, 420)
	path_queue_per_tick = clampi(int(round(context.modifier_float("path_queue_per_tick", float(path_queue_per_tick)))), 0, 80)
	decision_interval = clampf(context.modifier_float("decision_interval", decision_interval), 0.18, 0.75)
	max_log_lines = clampi(int(context.modifier_float("max_log_lines", float(max_log_lines))), 8, 28)
	target_min_seconds = maxf(8.0, context.modifier_float("target_min_seconds", target_min_seconds))
	target_max_seconds = maxf(target_min_seconds, context.modifier_float("target_max_seconds", target_max_seconds))

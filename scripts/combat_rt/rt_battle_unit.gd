class_name RTBattleUnit
extends RefCounted

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
var morale: float = 0.65
var fear: float = 0.0
var vision_radius_tiles: float = 6.0
var vision_angle_deg: float = 115.0
var attack_range_tiles: float = 1.25
var attack_cooldown: float = 1.25
var attack_timer: float = 0.0
var speed_tiles_per_second: float = 2.4
var hold_timer: float = 0.0

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
	attack_range_tiles = 3.8 if source.magic > source.atk else 1.25
	attack_cooldown = maxf(0.75, 1.55 - float(source.initiative) * 0.04)
	morale = 0.55 + brain_value("leader_trust") * 0.25

func apply_enemy_profile() -> void:
	vision_radius_tiles = 5.2
	vision_angle_deg = 130.0
	morale = 0.62

func is_alive() -> bool:
	return battle_unit != null and battle_unit.is_alive()

func hp_ratio() -> float:
	if battle_unit == null or battle_unit.max_hp <= 0:
		return 0.0
	return float(battle_unit.current_hp) / float(battle_unit.max_hp)

func get_stat(stat: String) -> int:
	if battle_unit == null:
		return 0
	return battle_unit.get_stat(stat)

func take_damage(amount: int) -> void:
	if battle_unit == null:
		return
	battle_unit.take_damage(amount)
	fear = clampf(fear + minf(0.35, float(amount) / float(maxi(1, battle_unit.max_hp))), 0.0, 1.0)
	morale = clampf(morale - minf(0.22, float(amount) / float(maxi(1, battle_unit.max_hp)) * 0.5), 0.0, 1.0)
	if character_data != null:
		character_data.record_damage_taken(amount, battle_unit.max_hp)

func heal(amount: int) -> void:
	if battle_unit == null:
		return
	battle_unit.heal(amount)
	fear = clampf(fear - 0.08, 0.0, 1.0)

func brain_value(key: String) -> float:
	if character_data == null:
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
			_:
				return 0.45
	return character_data.get_brain_value(key)

func set_intent(type: String, reason: String, target_destination: Vector2i = Vector2i.ZERO) -> void:
	intent = type
	intent_reason = reason
	if target_destination != Vector2i.ZERO:
		destination = target_destination

func clear_path() -> void:
	path.clear()

func side_name() -> String:
	return "союзник" if side == BattleUnit.UnitSide.ALLY else "враг"

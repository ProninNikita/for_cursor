class_name RTCombatRenderer
extends RefCounted

const BattlefieldScript = preload("res://scripts/combat_rt/rt_battlefield.gd")

func tile_color(tile: int) -> Color:
	match tile:
		BattlefieldScript.TileType.WALL:
			return Color(0.12, 0.13, 0.15)
		BattlefieldScript.TileType.WATER:
			return Color(0.08, 0.18, 0.26)
		BattlefieldScript.TileType.COVER:
			return Color(0.26, 0.22, 0.16)
		BattlefieldScript.TileType.DOOR:
			return Color(0.25, 0.19, 0.08)
		BattlefieldScript.TileType.GRASS:
			return Color(0.10, 0.19, 0.12)
		BattlefieldScript.TileType.DEEP_WATER:
			return Color(0.04, 0.09, 0.16)
		BattlefieldScript.TileType.HEIGHT:
			return Color(0.28, 0.24, 0.14)
		BattlefieldScript.TileType.TRAP:
			return Color(0.23, 0.08, 0.07)
		BattlefieldScript.TileType.NARROW:
			return Color(0.19, 0.17, 0.14)
		BattlefieldScript.TileType.DESTRUCTIBLE:
			return Color(0.24, 0.18, 0.13)
		BattlefieldScript.TileType.DARK:
			return Color(0.055, 0.055, 0.085)
		BattlefieldScript.TileType.NOISY:
			return Color(0.18, 0.17, 0.10)
		_:
			return Color(0.16, 0.16, 0.16)

func unit_shape(unit) -> String:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return "square"
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return "diamond"
		return "triangle"
	match _unit_class_id(unit):
		"defender", "guardian", "tank":
			return "square"
		"healer", "mage":
			return "diamond"
		"scout", "rogue", "assassin":
			return "triangle"
		_:
			return "circle"

func unit_icon(unit) -> String:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return "B"
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return "T"
		if unit.display_name.begins_with("Орк"):
			return "O"
		return "G"
	match _unit_class_id(unit):
		"warrior":
			return "W"
		"healer":
			return "+"
		"mage":
			return "M"
		"scout":
			return "S"
		"defender", "guardian", "tank":
			return "D"
		_:
			return "A"

func unit_base_color(unit) -> Color:
	if unit.side != BattleUnit.UnitSide.ALLY:
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 70:
			return Color(0.56, 0.13, 0.16)
		if unit.battle_unit != null and unit.battle_unit.max_hp >= 40:
			return Color(0.72, 0.22, 0.16)
		if unit.display_name.begins_with("Орк"):
			return Color(0.84, 0.34, 0.16)
		return Color(0.92, 0.2, 0.17)
	match _unit_class_id(unit):
		"warrior":
			return Color(0.18, 0.58, 0.96)
		"healer":
			return Color(0.28, 0.78, 0.48)
		"mage":
			return Color(0.55, 0.46, 0.95)
		"scout":
			return Color(0.9, 0.62, 0.2)
		"defender", "guardian", "tank":
			return Color(0.34, 0.62, 0.74)
		_:
			return Color(0.24, 0.66, 0.94)

func unit_outline_color(unit, focus_unit_id: String) -> Color:
	if unit.unit_id == focus_unit_id:
		return Color(1.0, 0.86, 0.28)
	if unit.intent == "ability":
		return Color(0.62, 0.9, 1.0)
	if unit.intent == "attack":
		return Color(1.0, 0.58, 0.24)
	if unit.intent == "retreat":
		return Color(0.72, 0.55, 1.0)
	return Color(0.025, 0.03, 0.038)

func _unit_class_id(unit) -> String:
	if unit == null or unit.character_data == null:
		return ""
	return str(unit.character_data.character_class).to_lower()

class_name RTEnemyPlanEntry
extends RefCounted

var enemy_type: String = "goblin"
var count: int = 1
var scale: float = 1.0
var tags: PackedStringArray = []

static func from_variant(value):
	var entry := new()
	if value is Dictionary:
		entry.enemy_type = str(value.get("type", "goblin"))
		entry.count = maxi(0, int(value.get("count", 1)))
		entry.scale = maxf(0.1, float(value.get("scale", 1.0)))
		for tag in value.get("tags", []):
			entry.tags.append(str(tag))
	else:
		entry.enemy_type = str(value)
	return entry

func to_dictionary() -> Dictionary:
	var result := {
		"type": enemy_type,
		"count": count,
		"scale": scale
	}
	if not tags.is_empty():
		result["tags"] = Array(tags)
	return result

class_name RTCombatUIFormatter
extends RefCounted

func mode_label(context) -> String:
	if context != null:
		if context.is_tower():
			return "Возвышение %d" % context.tower_floor
		if context.is_raid():
			return "Вылазка"
	return "Тренировка"

func format_rewards(rewards: Dictionary, empty_text: String = "без награды") -> String:
	var parts: PackedStringArray = []
	var lootboxes := int(rewards.get("lootboxes", 0))
	if lootboxes > 0:
		parts.append("%d лутбоксов" % lootboxes)
	var gold_amount := int(rewards.get("gold", 0))
	if gold_amount > 0:
		parts.append("%d золота" % gold_amount)
	if bool(rewards.get("unique_item", false)):
		parts.append("уникальный предмет")
	if parts.is_empty():
		return empty_text
	return ", ".join(parts)

func short_name(value: String, max_length: int = 8) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max_length)

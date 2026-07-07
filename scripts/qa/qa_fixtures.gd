extends RefCounted

var seed: int = 12345
var _generator: CharacterGenerator
var state: Node
var save_manager: Node

func _init(game_state: Node, save_manager_node: Node, seed_value: int = 12345) -> void:
	state = game_state
	save_manager = save_manager_node
	seed = seed_value
	_generator = CharacterGenerator.new(seed)

func setup_sandbox(run_id: String = "last") -> void:
	_ensure_game_state()
	save_manager.use_qa_save_dir(run_id)
	save_manager.delete_all_saves()

func reset_game(hero_count: int = 0) -> void:
	_ensure_game_state()
	save_manager.start_new_game()
	state.pending_combat_squad.clear()
	state.pending_combat_encounter = ""
	state.pending_tower_floor = 0
	state.is_tower_elevation = false
	state.pending_raid_event.clear()
	state.active_raid = null
	state.completed_raids.clear()
	if hero_count > 0:
		add_test_heroes(hero_count)

func prepare_for_scene(scene_path: String) -> void:
	match scene_path:
		"res://scenes/menu/main_menu.tscn":
			reset_game(0)
		"res://scenes/portal/portal.tscn":
			reset_game(0)
			state.lootboxes_remaining = 3
		"res://scenes/mansion/mansion.tscn":
			reset_game(3)
		"res://scenes/tower/tower_squad.tscn":
			reset_game(5)
			state.pending_tower_floor = 1
		"res://scenes/tower/raid_lobby.tscn":
			reset_game(3)
		"res://scenes/tower/raid_progress.tscn":
			prepare_raid(3)
		"res://scenes/combat/combat.tscn":
			prepare_combat(5)
		_:
			reset_game(3)

func add_test_heroes(count: int) -> void:
	var classes := ["warrior", "healer", "mage", "defender", "scout", "tactician", "assassin", "berserker"]
	for i in range(count):
		var class_id: String = classes[i % classes.size()]
		state.roster.add_character(make_test_hero(i + 1, class_id))

func prepare_combat(hero_count: int = 5) -> void:
	reset_game(hero_count)
	var squad := get_first_squad(mini(hero_count, 5))
	state.begin_combat(squad, "qa_combat")
	state.pending_tower_floor = 0
	state.is_tower_elevation = false

func prepare_tower_combat(hero_count: int = 5, floor_num: int = 1) -> void:
	reset_game(hero_count)
	var squad := get_first_squad(mini(hero_count, 5))
	state.pending_tower_floor = floor_num
	state.is_tower_elevation = true
	state.begin_tower_combat(squad, floor_num)

func prepare_raid(hero_count: int = 3) -> void:
	reset_game(hero_count)
	var squad := get_first_squad(mini(hero_count, 3))
	state.begin_raid(squad, 2, 0, 0)

func get_first_squad(count: int) -> Array[CharacterData]:
	var squad: Array[CharacterData] = []
	for hero in state.roster.get_characters():
		if squad.size() >= count:
			break
		squad.append(hero)
	return squad

func make_test_hero(index: int, class_id: String) -> CharacterData:
	var hero := CharacterData.new()
	hero.id = "qa_%s_%02d" % [class_id, index]
	hero.display_name = "QA %s %02d" % [class_id.capitalize(), index]
	hero.backstory_origin = "QA"
	hero.backstory_event = "smoke"
	hero.backstory_motivation = "stability"
	hero.personality_trait = _personality_for_class(class_id)
	hero.character_class = class_id
	hero.character_class_display_name = _display_name_for_class(class_id)
	hero.stats = _stats_for_class(class_id)
	hero.ability_ids = _abilities_for_class(class_id)
	hero.unique_ability_id = ""
	hero.set_current_hp(hero.get_max_hp())
	hero.initialize_combat_brain()
	return hero

func _ensure_game_state() -> void:
	if state.roster == null:
		state.roster = Roster.new()
	if state.lootbox == null:
		state.lootbox = Lootbox.new()
	if state.tower_elevation == null:
		state.tower_elevation = TowerElevation.new()

func _personality_for_class(class_id: String) -> String:
	match class_id:
		"warrior", "berserker":
			return "агрессивный"
		"healer", "defender":
			return "защитник"
		"mage", "tactician":
			return "расчётливый"
		"scout", "assassin":
			return "осторожный"
		_:
			return "расчётливый"

func _display_name_for_class(class_id: String) -> String:
	match class_id:
		"warrior":
			return "Воин"
		"healer":
			return "Лекарь"
		"mage":
			return "Маг"
		"defender":
			return "Защитник"
		"scout":
			return "Разведчик"
		"tactician":
			return "Тактик"
		"assassin":
			return "Ассасин"
		"berserker":
			return "Берсерк"
		_:
			return class_id

func _stats_for_class(class_id: String) -> Dictionary:
	match class_id:
		"warrior":
			return {"hp": 52, "atk": 11, "def": 6, "speed": 5, "magic": 0, "initiative": 6}
		"healer":
			return {"hp": 42, "atk": 4, "def": 5, "speed": 5, "magic": 10, "initiative": 5}
		"mage":
			return {"hp": 38, "atk": 3, "def": 4, "speed": 6, "magic": 12, "initiative": 6}
		"defender":
			return {"hp": 60, "atk": 7, "def": 10, "speed": 3, "magic": 0, "initiative": 4}
		"scout":
			return {"hp": 44, "atk": 8, "def": 5, "speed": 9, "magic": 0, "initiative": 8}
		"tactician":
			return {"hp": 46, "atk": 7, "def": 6, "speed": 7, "magic": 6, "initiative": 8}
		"assassin":
			return {"hp": 40, "atk": 11, "def": 4, "speed": 10, "magic": 0, "initiative": 9}
		"berserker":
			return {"hp": 48, "atk": 12, "def": 4, "speed": 6, "magic": 0, "initiative": 6}
		_:
			return {"hp": 45, "atk": 8, "def": 5, "speed": 5, "magic": 0, "initiative": 5}

func _abilities_for_class(class_id: String) -> Array[String]:
	match class_id:
		"warrior":
			return ["basic_attack", "heavy_strike", "guard"]
		"healer":
			return ["heal", "cure", "blessing"]
		"mage":
			return ["fireball", "arcane_bolt", "barrier"]
		"defender":
			return ["shield_bash", "taunt", "fortify"]
		"scout":
			return ["quick_strike", "evade", "mark_target"]
		"tactician":
			return ["command", "tactical_strike", "rally"]
		"assassin":
			return ["backstab", "poison_blade", "shadow_step"]
		"berserker":
			return ["frenzy", "bloodlust", "reckless_charge"]
		_:
			return ["basic_attack"]

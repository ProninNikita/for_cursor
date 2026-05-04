# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Squad Tactics** — A turn-based strategy game built in Godot 4.3. Characters are procedurally generated through a lootbox system: backstory → personality → class → stats → abilities.

## Running the Game

```bash
# Open in Godot Editor
godot --path /Users/likit/for_cursor --editor

# Or run directly
godot --path /Users/likit/for_cursor
```

Press F5 in Godot Editor to play.

## Architecture

### Autoload Singletons (scripts/autoload/)
- **GameState** — Global state, persists across scenes. Holds `roster: Roster`, `lootbox: Lootbox`, `lootboxes_remaining: int`, and temporary `pending_combat_squad` for passing data to combat scenes.
- **SaveManager** — 3 save slots stored as JSON at `user://saves/save_slot_N.json`. Includes metadata (character count, playtime, date) separate from full character data.

### Character Generation Chain (scripts/core/character_generator.gd)
```
origin + event + motivation (backstories.json)
    → personality trait (personalities.json) 
    → class (weighted by trait's class_weight)
    → stats (class base + trait stat_bonus)
    → abilities (class base_abilities + generated unique_ability_id)
```

Each trait has `class_weight` dict and `stat_bonus` dict that influence generation. The unique ability ID is a hash combining motivation + trait + class.

### Core Data Classes
- **CharacterData** (Resource) — Serializable character with `to_dict()` / `from_dict()`. Stats include: hp, atk, def, speed, magic, initiative.
- **Roster** — Stores `Array[CharacterData]`, handles squad selection (max 5), HP sync after battles, character removal on death.
- **Lootbox** — Wraps CharacterGenerator, creates new characters via `open()`.

### Combat System (scripts/combat/)
- **BattleUnit** — Runtime combat instance. Allies created via `from_hero(cd)`, enemies via `goblin(index)`. Has `side: UnitSide` enum.
- **combat.gd** — Turn-based with initiative ordering. Uses `_turn_ptr` cycling through `_turn_order`. Allies click enemies to attack; enemies auto-attack weakest ally. Victory grants +1 lootbox.
- Damage formula: `max(1, attacker.atk - defender.def / 2)`

### Scene Flow
```
main_menu.tscn → hub.tscn → portal.tscn | tower_squad.tscn | mansion.tscn
                                   ↓           ↓
                              (lootbox)   combat.tscn
```

Scene transitions use `get_tree().change_scene_to_file()`. Combat data passed through `GameState.pending_combat_squad` / `pending_combat_encounter`.

## Data Files (data/*.json)
- **classes.json** — Class definitions with base_stats and base_abilities
- **personalities.json** — Traits with class_weight and stat_bonus
- **backstories.json** — origins, key_events, motivations arrays
- **names.json** — first_names, surnames

Adding new classes: define in classes.json, add weights to personalities.json traits.

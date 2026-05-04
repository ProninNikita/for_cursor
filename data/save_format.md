# Формат файлов сохранений

## Расположение
`user://saves/` — папка сохранений (зависит от ОС)

## Имена файлов
- `save_slot_1.json`
- `save_slot_2.json`
- `save_slot_3.json`

## Структура JSON

```json
{
  "metadata": {
    "name": "Сохранение 1",
    "date": "2026-02-27T14:30:00",
    "playtime_seconds": 3600,
    "character_count": 5,
    "lootboxes_remaining": 2
  },
  "lootboxes_remaining": 2,
  "characters": [
    {
      "id": "char_123_456",
      "display_name": "Арден Чёрный",
      "backstory_origin": "солдат",
      "backstory_event": "потеря семьи в войне",
      "backstory_motivation": "месть",
      "personality_trait": "агрессивный",
      "character_class": "warrior",
      "character_class_display_name": "Воин",
      "stats": {"hp": 100, "atk": 12, "def": 8, "speed": 5, "magic": 0},
      "ability_ids": ["basic_attack", "heavy_strike", "guard"],
      "unique_ability_id": "unique_123_456",
      "portrait_path": ""
    }
  ]
}
```

## Метаданные (metadata)
Используются для отображения в меню «Продолжить» и «Удалить»:
- **name** — название слота
- **date** — дата и время сохранения
- **playtime_seconds** — время игры (секунды)
- **character_count** — количество героев в ростре
- **lootboxes_remaining** — неоткрытые лутбоксы

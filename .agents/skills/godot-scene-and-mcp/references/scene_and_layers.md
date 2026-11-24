# Карта сцен, слоёв физики (`18/32`) и инструментов `godot` MCP

---

## 1. Структура сцен (`project/scenes/` и `project/tests/`)

- **`scenes/test_arena.tscn`** (`TestArena`, `Node2D`, `TestArena.gd`, главная сцена в `project.godot`):
  - `Floor0` (`Node2D`): `FloorLayer` (`TileMapLayer`), `WallLayer` (`TileMapLayer`), `BuildingInteriorTrigger` (`Area2D` + `CollisionShape2D`), `SafeBarrierZone` (`Area2D` + `CollisionShape2D`)
  - `Floor1` (`Node2D`): `FloorLayer`, `WallLayer`, `RoofLayer` (`TileMapLayer`), `FloorSupportZone` (`Area2D` + `CollisionShape2D`)
  - `StairsArea` (`Area2D` + `CollisionShape2D`), `Decals` (`Node2D`), `Effects` (`Node2D`)
  - `Entities` (`Node2D`): `Player` (`(112, 256)`), `Rank1Swordsman` (`(240, 80)`), `TrollBerserker` (`(384, 240)`), `Rank6Guard` (`(384, 416)`)
  - `OverviewCamera` (`Camera2D`, `enabled = false`), `DebugHUD` (инстанс `debug_hud.tscn`)
- **`scenes/player.tscn`**: `Player` (`CharacterBody2D`, `PlayerController.gd`) $\rightarrow$ `CollisionShape2D` (`CircleShape2D r=8.0`), `Camera2D` (`enabled = true`)
- **`scenes/rank1_swordsman.tscn`**: `Rank1Swordsman` (`CharacterBody2D`, `EnemyDummy.gd`, `preset=0`) $\rightarrow$ `CollisionShape2D` (`r=8.0`)
- **`scenes/rank6_guard.tscn`**: `Rank6Guard` (`CharacterBody2D`, `EnemyDummy.gd`, `preset=1`) $\rightarrow$ `CollisionShape2D` (`r=8.0`)
- **`scenes/troll_berserker.tscn`**: `TrollBerserker` (`CharacterBody2D`, `EnemyDummy.gd`, `preset=2`) $\rightarrow$ `CollisionShape2D` (`r=10.5`)
- **`scenes/debug_hud.tscn`**: `DebugHUD` (`CanvasLayer`, `layer=50`, `DebugHUD.gd`) — все панели, оверлеи и `PauseOverlay` (`layer=65`) строятся процедурно в коде
- **`tests/test_runner.tscn`**: раннер `run_tests.gd` (headless + `--auto-quit`)

---

## 2. Таблица физических слоёв `2d_physics` (`project.godot` + `FloorLayerManager.gd`)

Активное окно этажей вокруг `focus_floor`: `[focus_floor - 1 .. focus_floor + 2]`. Индекс слота вычисляется как `posmod(floor_level, 4)`.

| Слои (1-based) | Имена в `project.godot` | Назначение |
| :---: | :--- | :--- |
| `1, 2, 3` | `Slot0_HighWalls`, `Slot0_LowObstacles`, `Slot0_Actors` | Твёрдая физика этажа в слоте `0` (`floor % 4 == 0`) |
| `4, 5, 6` | `Slot1_HighWalls`, `Slot1_LowObstacles`, `Slot1_Actors` | Твёрдая физика этажа в слоте `1` (`floor % 4 == 1`) |
| `7, 8, 9` | `Slot2_HighWalls`, `Slot2_LowObstacles`, `Slot2_Actors` | Твёрдая физика этажа в слоте `2` (`floor % 4 == 2`) |
| `10, 11, 12` | `Slot3_HighWalls`, `Slot3_LowObstacles`, `Slot3_Actors` | Твёрдая физика этажа в слоте `3` (`floor % 4 == 3`) |
| `13` | `HitboxZones` (`BIT_HITBOX_ZONES`) | `Area2D` анатомических зон (требует софт-проверку `floor_level` и `height_z`) |
| `14` | `Projectiles` (`BIT_PROJECTILES`) | Снаряды и баллистика (софт-проверка `floor_level` и `height_z`) |
| `15` | `Interactables` (`BIT_INTERACTABLES`) | Оружие на полу, лестницы, контейнеры |
| `16` | `MindDomains` (`BIT_MIND_DOMAINS`) | Купола Мира Разума (`v1.0`) |
| `17` | `FloorSupport` (`BIT_FLOOR_SUPPORT`) | Зоны пролома верхнего пола (`height_z <= 0.1` $\rightarrow$ падение на `floor - 1`) |
| `18` | `Triggers_Stealth` (`BIT_TRIGGERS_STEALTH`) | Зоны маскировки (`StealthCoverZone`) и триггеры стелса |
| `19..32` | Свободно (`14` бит) | Резерв под будущие системы `v0.5 / v1.0` |

> При `height_z >= FloorLayerManager.LOW_OBSTACLE_CLEARANCE_Z` (`1.0`) бит `LowObstacles` текущего слота автоматически отключается в `get_actor_collision_mask(...)`, а `HighWalls` остаётся активным.

---

## 3. Шпаргалка по инструментам `godot` MCP (`ServerName: "godot"`)

`projectPath` для этого репозитория: `"D:/My game/project"`.

| Инструмент | Обязательные аргументы | Опциональные аргументы | Назначение |
| :--- | :--- | :--- | :--- |
| `get_godot_version` | — | — | Проверка установленной версии Godot |
| `get_project_info` | `projectPath` | — | Метаданные проекта |
| `create_scene` | `projectPath`, `scenePath`, `rootNodeType` | — | Создать новую `.tscn` (путь относительно `projectPath`) |
| `add_node` | `projectPath`, `scenePath`, `nodeType`, `nodeName` | `parentNodePath`, `properties` | Добавить узел в существующую `.tscn` |
| `save_scene` | `projectPath`, `scenePath` | `newPath` | Сохранить сцену (или вариант по `newPath`) |
| `get_uid` | `projectPath`, `filePath` | — | Получить `uid://` файла (`Godot 4.4+`) |
| `update_project_uids` | `projectPath` | — | Пересохранить и обновить UID-ссылки проекта |
| `run_project` | `projectPath` | `scene` | Запустить проект/сцену с захватом вывода |
| `get_debug_output` | — | — | Прочитать накопленный лог и ошибки запущенного процесса |
| `stop_project` | — | — | Остановить запущенный проект |
| `launch_editor` | `projectPath` | — | Открыть проект в редакторе Godot (только по запросу пользователя) |

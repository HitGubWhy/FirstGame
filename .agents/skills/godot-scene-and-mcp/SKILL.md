---
name: godot-scene-and-mcp
description: >-
  Standardizes editing Godot 4.7 .tscn scenes, procedural visuals/HUD/audio, TileMapLayer
  floors, z_index/CanvasLayer ordering, .uid hygiene, and using the installed godot MCP server
  for D:\My game\project. Use whenever creating or modifying .tscn files, HUD/overlay controls,
  TileMapLayer arenas, physics layers, or running/inspecting the project via godot MCP tools.
---

# Godot Scene, HUD & MCP Workflow (`D:\My game\project`)

Протокол безопасного редактирования сцен `.tscn`, процедурного рендера/UI и работы через подключённый MCP-сервер `godot` (`Godot_v4.7.2-stable_win64.exe`).

Полные деревья всех сцен проекта, карта `18/32` физических слоёв и справочник параметров инструментов MCP находятся в [scene_and_layers.md](./references/scene_and_layers.md).

## Шаг 1. Правила использования MCP-сервера `godot`

Все вызовы используют `projectPath: "D:/My game/project"` (или `"D:\\My game\\project"`). Инструменты `godot` подгружаются лениво (`call_mcp_tool` с `ServerName: "godot"`):
1. **Проверка среды:** `get_godot_version`, `get_project_info`.
2. **Создание/правка сцен:** `create_scene`, `add_node`, `save_scene`.
   - **Стоп-правило `v0.2` (Zero External Assets):** не используйте `load_sprite` и не добавляйте внешние `.png`/`.wav` в макет `v0.2` — арена, персонажи, прицел и аудио строятся процедурно (`ProceduralTileSetBuilder`, `Polygon2D`, `CombatReticle`, `ProceduralAudioManager`), пока пользователь явно не перейдёт на ассеты.
3. **Гигиена `.uid` (Godot 4.4+ / 4.7):** после создания, переименования или перемещения `.gd` / `.tscn` / `.tres` вызывайте `update_project_uids` (и `get_uid` при необходимости), чтобы не ломать `uid://`-ссылки и `.uid`-файлы.
4. **Живой запуск и чтение логов:** `run_project` $\rightarrow$ `get_debug_output` $\rightarrow$ **обязательно `stop_project`** после проверки, чтобы не оставлять висящий процесс Godot.
5. Для регрессионного тестирования используйте не `run_project`, а headless-раннер из скилла `godot-test-and-verify`.

## Шаг 2. Обязательные инварианты сцен и рендера

### 2.1. Экран и шрифты (`640×360` $\rightarrow$ `1920×1080`)
- Базовый viewport в `project.godot`: **`640×360`**, `window/size/mode=3` (Fullscreen `1920×1080`, `F11`), `stretch/mode="canvas_items"`, `stretch/aspect="expand"`, `stretch/scale_mode="integer"` (ровно `3×`).
- Все элементы HUD строятся под виртуальные координаты `640×360`: мелкие шрифты `FONT_SIZE_HEADER = 8`, `FONT_SIZE_BODY = 7`, адаптивные якоря по углам экрана, проверка отсутствия перекрытия панелей в компактном (`F2`) и инженерном (`F1`) режимах.

### 2.2. Безопасность ввода в UI (критический инвариант `DebugHUD.gd`)
- Каждая интерактивная нода UI (`Button`, `CheckBox`, `HSlider`) **обязана** иметь `focus_mode = Control.FOCUS_NONE` — иначе клавиша `Space` (`sidestep_dash`) будет нажимать последнюю кликнутую кнопку интерфейса вместо сайдстепа!
- Все пассивные контейнеры и текстовые оверлеи (`Control`, `PanelContainer`, `Label`, `VBoxContainer`) обязаны иметь `mouse_filter = Control.MOUSE_FILTER_IGNORE`, чтобы клики `ЛКМ`/`ПКМ` проходили в бой.
- Весь UI работает на чистом системном `delta` (не зависит от замедления `SimulationClock`) и подписывается только на `EventBus` без жёстких ссылок из `PlayerController`.

### 2.3. Сортировка глубины (`z_index` и `CanvasLayer`)
Никогда не задавайте произвольные `z_index` — соблюдайте единую шкалу проекта:
- Тени, лужи крови, отрубленные конечности, декали этажа: `FloorLayerManager.get_shadow_z_index(floor_level)` (`floor_level * 100`).
- Акторы и вертикальные объекты: `FloorLayerManager.get_visual_z_index(floor_level, height_z)` (`floor_level * 100 + int(height_z * 10)`).
- Мировая подсказка `[E]`: `z_index = 850`.
- Прицел `CombatReticle`: `z_as_relative = false`, `z_index = 900`.
- `DebugHUD` / Игровой HUD / `KOOverlay` / `DeathOverlay`: `CanvasLayer` `layer = 50`.
- Меню паузы `PauseOverlay` (`Esc`): отдельный `CanvasLayer` `layer = 65`.

### 2.4. Пространство, `TileMapLayer` и `18/32` физических слоёв
- Используйте **строго `TileMapLayer`** (устаревший узел `TileMap` запрещён).
- Каждый этаж (`Floor0`, `Floor1`, …) держит отдельные `FloorLayer`, `WallLayer`, опциональный `RoofLayer`.
- Никогда не хардкодьте номера слоёв `1..12` вручную — вычисляйте `collision_layer` и `collision_mask` через `FloorLayerManager.get_actor_collision_layer(...)`, `get_actor_collision_mask(...)` и `get_solid_world_mask(...)`.
- Для общих слоёв `13..18` (`HitboxZones`, `Projectiles`, `Interactables`, `MindDomains`, `FloorSupport`, `Triggers_Stealth`) **всегда** проверяйте `floor_level` программно в обработчике контакта/луча.

### 2.5. Совместимость с headless-режимом
Любой визуальный или UI-скрипт (`CombatReticle`, `DebugHUD`, камеры, курсоры), загружаемый в `TestArena`, обязан безопасно работать при `DisplayServer.get_name() == "headless"`:
- не опираться на `get_global_mouse_position()` без ветки fallback в headless;
- предоставлять детерминированные методы обновления состояния (как `CombatReticle.evaluate_reticle_state(...)` и `DebugHUD._refresh_all_views()`).

## Шаг 3. Верификация после правок сцен/UI
1. Если создавались/переименовывались файлы ресурсов или сцен — выполните `update_project_uids` через `godot` MCP.
2. Запустите `run_headless_tests.ps1 -CheckUids` (проверит целостность всех `res://`, `.uid` и прогонит сьюты HUD/Full HD/рендера `11`, `19`, `22`, `23`, `24`, `28`).
3. При визуальных изменениях при необходимости запустите `run_project` через MCP, прочитайте `get_debug_output` (0 ошибок/ворнингов) и вызовите `stop_project`.

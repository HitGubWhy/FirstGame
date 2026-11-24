---
name: godot-test-and-verify
description: >-
  Runs, parses, and extends the headless Godot 4.7 unit and integration test suite
  for D:\My game\project (res://tests/test_runner.tscn), validates GDScript parse/runtime
  cleanliness and .uid sidecar hygiene, and provides deterministic suite templates.
  Use whenever modifying project/src/, project/data/, project/scenes/, project/project.godot,
  or adding/debugging tests in project/tests/.
---

# Godot Test & Verify (`D:\My game\project`)

Протокол детерминированной проверки проекта через headless Godot 4.7.2 без внешних тест-плагинов и шаблон добавления новых наборов тестов в `project/tests/run_tests.gd`.

## Когда применять
- После **любого** изменения в `project/src/`, `project/data/`, `project/scenes/` или `project/project.godot`.
- Перед закрытием задачи, синхронизацией GDD или коммитом.
- При написании нового тестового сьюта, расследовании регрессии или чистке падающих ассертов.

## Шаг 1. Запуск headless-тестов и проверка логов

> **Важно:** `godot` не добавлен в глобальный `PATH` — бинарник прописан в `GODOT_PATH` конфига MCP (`D:\progs\godot\Godot_v4.7.2-stable_win64.exe`). Всегда используйте готовый раннер: он сам находит Godot, захватывает `stdout + stderr`, проверяет `SCRIPT ERROR` / `Parse Error` / `FAIL` и возвращает честный код выхода.

Запустите [run_headless_tests.ps1](./scripts/run_headless_tests.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "d:\My game\.agents\skills\godot-test-and-verify\scripts\run_headless_tests.ps1"
```

Полезные флаги:
- `-CheckUids` — дополнительно проверяет, что у всех `.gd` есть `.uid` и в `.tscn`/`.tres` нет битых `res://` ссылок.
- `-Filter "Stealth"` — подсвечивает в выводе только сьюты, подходящие под подстроку (сам Godot всё равно прогоняет весь раннер, поэтому регрессии в соседних сьютах не потеряются).
- `-VerboseLog` — печатает полный нефильтрованный лог Godot.
- `-GodotPath "C:\path\to\godot.exe"` — явное переопределение пути к бинарнику.

### Критерии зелёного прогона (ВСЕ обязательны)
1. Код выхода процесса = `0`.
2. В `SUMMARY` строго `0 failed` и строка `RESULT: ALL TESTS PASSED (GREEN)`.
3. В `stderr`/`stdout` **0** ошибок `SCRIPT ERROR`, `Parse Error`, `ERROR:`, `Cannot load` и предупреждений об утечках (`Orphan StringName` / `ObjectDB instances leaked`).

## Шаг 2. Диагностика падения
1. Прочитайте строки `[FAIL]` и `FAIL:` в выводе раннера — они содержат точный `expected` / `got` и имя сьюта.
2. Если упали несколько сьютов подряд после одного зелёного изменения, сначала проверьте **протекающее состояние автолоадов** в предыдущем сьюте:
   - `EventBus.last_penetration_log`, `last_combat_outcome`, `last_blade_clash`, `debug_highlight_weak_points`, `debug_anti_regen_attacks`
   - `SimulationClock.reset_defaults()` (особенно `tempo_mode`, `active_aggro_ids`, `hitstop_timer`, `_bound_player_stats`)
   - `WorldCalendar.reset_calendar(0)` и `WorldCalendar.paused = true`
   - `FloorLayerManager.reset(0)`
   - `BrainFactory.clear_custom_brains()` (если регистрировались кастомные мозги)
3. Если тест с `TestArena` завис или упал в физике — проверьте:
   - выполнен ли `await get_tree().physics_frame` после телепортации акторов или разрушения тайлов;
   - закрыт ли предыдущий экземпляр арены через `remove_child(arena); arena.queue_free(); await get_tree().process_frame`.
4. Если падение связано с `get_global_mouse_position()` или окном в headless — оберните обращение проверкой `DisplayServer.get_name() != "headless"`.

## Шаг 3. Добавление нового тестового сьюта

Используйте шаблон [suite_template.gd](./examples/suite_template.gd).

### Обязательные правила для нового сьюта
1. **Строгая статическая типизация:** все локальные переменные, параметры и возвращаемые типы обязаны иметь явный тип (`var arena: TestArena = ...`).
2. **Детерминизм:** не опирайтесь на системные часы или `await get_tree().create_timer(...)` для игровой логики — двигайте время напрямую через `step_ai_tick`, `tick_physiology`, `WorldCalendar.advance_minutes(...)` и `SimulationClock`.
3. **Разделение sync / async:**
   - чистая математика (`StatSheet`, `PenetrationResolver`, `SimulationClock`, `WorldCalendar`, `FloorLayerManager`, `AnatomyComponent`) $\rightarrow$ `_run_suite("N. ...", _test_...)`;
   - сценарии с инстанцированием `TestArena` и физикой $\rightarrow$ `await _run_suite_async("N. ...", _test_...)`.
4. **Изоляция teardown:** в конце каждого async-сьюта обязательно удаляйте сцену (`remove_child(arena); arena.queue_free(); await get_tree().process_frame`) и сбрасывайте все затронутые синглтоны.
5. **Масштабирование `run_tests.gd`:** файл уже превышает ~6 000 строк. При добавлении крупных подсистем `v0.5` (расы, инвентарь, сейвы, чанки) выносите новые сьюты в отдельные модули `res://tests/suites/test_<domain>.gd` (`extends RefCounted`), передавая ссылку на раннер для вызовов `_assert_*`, и подключайте их из `run_tests.gd`.

## Шаг 4. Финальная валидация
После правки кода и добавления тестов:
1. Прогоните `run_headless_tests.ps1 -CheckUids`.
2. Убедитесь, что общее число `passed` выросло на количество новых ассертов, а `failed == 0`.
3. Если вы добавили новый сьют или заметно изменили число ассертов — актуализируйте счётчики в GDD по скиллу `gdd-spec-sync`.

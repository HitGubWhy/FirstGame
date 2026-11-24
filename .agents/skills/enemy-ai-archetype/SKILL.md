---
name: enemy-ai-archetype
description: >-
  Guides designing, implementing, registering, and testing modular stat-driven enemy AI
  archetypes and boss brains using EnemyAIProfile, CombatMemory, CombatBrain, BrainFactory,
  and EnemyDummy in D:\My game\project\src\ai\. Use whenever creating a new enemy/boss brain,
  tuning Utility AI scoring, modifying TP/INT reaction or feint logic, or debugging AI
  states (PATROL, COMBAT, SEARCH, flanking, flight pursuit, stealth suspicion).
---

# Enemy AI Archetype & Boss Brain Authoring (`src/ai/`)

Протокол создания, настройки и тестирования модульного стат-зависимого ИИ врагов и боссов поверх `EnemyAIProfile` + `CombatMemory` + `CombatBrain` + `BrainFactory` + `EnemyDummy`.

Подробные таблицы полей, всех 16 `ACTION_*`, ключей контекста `ctx`, формул `CombatMemory` и констант зрения вынесены в [ai_contracts.md](./references/ai_contracts.md). Готовый шаблон подкласса босса лежит в [custom_boss_brain.gd](./examples/custom_boss_brain.gd).

## Шаг 1. Выберите уровень расширения (не дублируйте базовый ИИ)

1. **Только характер/приоритеты** (новый рядовой моб, стражник, зверь): создайте новый `EnemyAIProfile` (через `.tres` или статический конструктор) с нужными весами `0.0..1.0` и флагами (`can_use_mana_flight`, `can_use_wing_flight`, `retreats_when_crippled`, `allows_self_heal_spacing`).
2. **Уникальная тактика / фазы босса**: унаследуйте `CombatBrain`, переопределите **только нужные** виртуальные хуки и зарегистрируйте билдер через `BrainFactory.register_brain(&"my_boss_id", callable)`.

### 4 виртуальных хука `CombatBrain`
- `_score_actions(ctx: Dictionary) -> Dictionary`: скорректируйте оценки `ACTION_*` поверх `super._score_actions(ctx)`.
- `_compute_movement_intent(ctx: Dictionary) -> Vector2`: кастомное позиционирование, отход, смена фланга или воздушная траектория.
- `_select_attack_plan(ctx: Dictionary, chosen_action: StringName) -> Dictionary`: выбор `attack_type`, `aim_pos` (уязвимость или корпус), `planned_feint` и `aura_burst_intent`.
- `_on_feint_resolved(actor: CombatActor, target: CombatActor, _was_reactive: bool) -> Dictionary`: мгновенная связка (`queued_followup`) сразу после отмены замаха финтом.

## Шаг 2. Соблюдайте жёсткие контракты «честного» ИИ

Нарушение любого пункта ниже сломает дизайн-философию игры или автотесты (`Suites 14, 18, 21, 25, 27, 28`):

1. **Никаких 1-кадровых реакций при низких `TP/INT`:**
   - Реакция на замах цели **обязана** идти через `memory.has_ready_threat()` (`CombatMemory.compute_reaction_delay(tp, int)` $\in [0.03\text{с}, 0.35\text{с}]$).
   - Распознавание финта цели идёт только через `CombatMemory.can_recognize_feint(enemy_tp, enemy_int, target_spd)`.
2. **Разделение времени `PATROL` vs `COMBAT` (`SimulationClock`):**
   - В `PATROL` враг ограничен бытовым `1.0x` (`eff_SPD = min(SPD, 10.0)`), а в `COMBAT` / `SEARCH` раскрывает полный `enemy.SPD` через `SimulationClock.get_enemy_action_delta(...)`.
   - Физиология, кровотечение, `REG` и таймеры нокбэка тикают строго по `world_delta` (не `action_delta`).
3. **Честный цикл аггро и побега (`PATROL -> COMBAT -> SEARCH -> PATROL`):**
   - Вход в `COMBAT` регистрирует `SimulationClock.register_aggro(get_instance_id())` (блокирует отключение `COMBAT_OVERDRIVE` клавишей `G`).
   - Потеря `LOS`/дистанции переводит в `SEARCH` (`SEARCH_DURATION_SEC = 4.0` с проверкой последней позиции, кругов шума и кровавого следа), после чего возврат в `PATROL`, смерть, KO или вход игрока в `SafeBarrierZone` **обязательно** вызывают `_unregister_aggro_safe()`.
4. **Пространственная дисциплина (`floor_level`, `height_z`, 1vN):**
   - Атаки, клинч и `LOS` обязаны учитывать совпадение `floor_level` и `abs(height_z diff) <= vertical_reach` (`vertical_aggro_tolerance` для обнаружения).
   - Если цель в воздухе, а враг без полёта — перепозиционируйтесь по горизонтали, а не упирайтесь вертикально в пустую точку.
   - В боях 1vN сохраняйте анти-слипание (`_compute_ally_separation_and_surround`, радиус `ALLY_SEPARATION_RADIUS_PX = 42.0`).
5. **Read-only профили и чистая инициализация:**
   - Передавайте в рантайм копию профиля (`profile.create_runtime_copy()` / `.duplicate(true)`), чтобы мутация одного врага не портила остальных.
   - Если добавляете новый пресет в `EnemyDummy.gd`, настраивайте `StatSheet` в `_configure_preset_before_ready()`, а экипировку, `rebuild_hitbox_zones(...)`, `save_initial_weapon_backup()` и полёт — в `_apply_preset_after_ready()`.
   - Помните про внешнюю циркуляцию маны: при `mana_awakened = true` и `M_CTRL > 10` `StatSheet` прибавит `circ_stat_bonus` к `STR/CTRL/SPD/TP/CON` (см. как `Rank6_Guard` выставляет `base = 88` для получения точных `100` при `M_CTRL = 100`).

## Шаг 3. Поведенческое тестирование нового архетипа

Добавьте проверки в тест-сьют (см. `godot-test-and-verify`):
1. Заморозьте авто-тики арены (`arena.set_all_enemies_ai_enabled(false)`) и двигайте мозг детерминированно через `enemy.step_ai_tick(action_dt, world_dt)`.
2. Проверьте минимум 5 сценариев:
   - `BrainFactory.create_brain(profile)` возвращает ваш класс, а `revive_and_heal_all()` сбрасывает `ai_brain.reset()`.
   - Задержка реакции соответствует `TP/INT` (при низком `TP/INT` враг **не** парирует/сайдстепает раньше `reaction_timer <= 0`).
   - Профильное поведение реально побеждает по `ai_brain.last_scores` / `ai_brain.last_chosen_action` в целевой ситуации (блок цели, стена рядом, низкая `STA`, ранение).
   - Выход из боя `COMBAT -> SEARCH -> PATROL` корректно снимает `SimulationClock.has_active_aggro()`.
   - В teardown теста обязательно вызывайте `BrainFactory.unregister_brain(&"my_boss_id")` или `BrainFactory.clear_custom_brains()`.
3. Прогоните `run_headless_tests.ps1 -CheckUids` и убедитесь, что сьюты `21`, `25`, `27`, `28` и ваш новый тест зелёные.

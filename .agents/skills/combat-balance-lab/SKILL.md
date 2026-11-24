---
name: combat-balance-lab
description: >-
  Audits and simulates the non-linear 1..500 combat math, 4-barrier penetration,
  blunt fracture thresholds, Aura/Aura Burst scaling, REG vs bleeding, and SimulationClock
  time dilation against live WeaponData .tres files and canonical v0.2 enemies.
  Use whenever tuning weapons, armor, stats, penetration/blunt formulas, Aura costs,
  enemy presets, or designing new combat mechanics (spells, ballistics, essences).
---

# Combat Balance Lab (`1..500` Math & 4-Barrier Simulator)

Инструмент численной проверки баланса до и после правок боевой математики в `StatSheet.gd`, `PenetrationResolver.gd`, `AnatomyComponent.gd`, `SimulationClock.gd` и `project/data/*.tres`.

## Когда применять
- Перед изменением любых формул пробития, импульса, Ауры, `REG`, `SimulationClock` или порогов перелома.
- При добавлении или ребалансе `.tres`-оружия, брони, нового пресета врага, заклинания или эссенции.
- При расследовании жалоб вида «слишком легко ваншотит», «кинжал пробивает латника в корпус» или «молот не ломает кости».

## Шаг 1. Прогон базовых матриц ДО правки кода

Запустите [balance_matrix.py](./scripts/balance_matrix.py) — скрипт читает реальные `project/data/*.tres` и воспроизводит **живые** формулы `StatSheet.gd`, `PenetrationResolver.gd`, `AnatomyComponent.gd` и `SimulationClock.gd`:

```powershell
# 1) Кривая прогрессии 1..500 (брейкпоинты 10 / 22 / 45 / 55 / 100 / 250 / 400 / 500)
python "d:\My game\.agents\skills\combat-balance-lab\scripts\balance_matrix.py" progression

# 2) Матрица канонических матчапов v0.2 (все .tres против Rank1 / Troll R4 / Guard R6)
python "d:\My game\.agents\skills\combat-balance-lab\scripts\balance_matrix.py" matchups

# 3) Проверка SimulationClock, потери управляемости и Невоспринимаемой скорости
python "d:\My game\.agents\skills\combat-balance-lab\scripts\balance_matrix.py" tempo --player-spd 100 --player-tp 100 --player-agi 50 --enemy-spd 250
```

## Шаг 2. Точечное «что если» моделирование (`strike`)

Перед изменением констант прогоните конкретный сценарий удара:

```powershell
python "d:\My game\.agents\skills\combat-balance-lab\scripts\balance_matrix.py" strike `
  --weapon greatsword --type thrust --str 100 --m-ctrl 100 --aura --aura-burst `
  --target-con 100 --target-m-ctrl 100 --armor-t 20 --armor-h 15 --zone Chest
```

Доступные модификаторы `strike`:
- `--weak-point` (обходит `100%` брони и снижает тканевой барьер до `0.25×`).
- `--half-sword` (снимает мёртвую зону у длинного оружия, режет `blade_length` до `0.55×`).
- `--dist 12` (проверяет попадание в `Dead Zone < min_optimal_range`, штраф `0.30×` к пробитию и `0.50×` к дробящему импульсу).
- `--kinetic 1.4`, `--hardening 120`, `--size-mult 1.3`, `--bone-density 120`, `--cushion 1.0`.

## Шаг 3. Проверка обязательных балансных инвариантов (`v0.2` Guardrails)

Сверьтесь с [benchmarks.md](./references/benchmarks.md). Любая правка баланса обязана сохранять эти свойства (иначе упадут автотесты или сломается геймплейный цикл):

1. **Броня имеет смысл:** `Player (STR=10)` обычным `SLASH` кинжалом/мечом в корпус `Rank6_Guard` (`barrier_depth ≈ 1247`) **не пробивает** даже `Armor` (`effective_depth == 0`).
2. **Тактический обход работает:**
   - `THRUST` в 1-px уязвимость (`weak_point_bypass = 1.0`, `tissue_bypass_mult = 0.25`) снижает барьер `Rank6_Guard` с `~1247` до `~238`, делая пробитие достижимым с `Aura` / `Aura Burst` или высоким `STR`.
   - `Warhammer BLUNT` при равном или близком ранге даёт `blunt_impulse > blunt_resistance_threshold`, ломая кости и вызывая `Wall Slam` без прокола стали.
3. **Мёртвая зона и `Half-swording`:** `greatsword.tres` (`min_optimal_range = 20`) вплотную получает `0.30×` пробития против кинжала, пока не включён `Half-swording`.
4. **Аура не бесплатна и не ломает ранний бой:** в `PenetrationResolver.gd` активны откалиброванные коэффициенты (`130 * scale^1.25`, `6 * scale^0.5`, `75 * scale^1.25`, `AURA_MP_PER_SEC = 4.5`, `AURA_BURST_MULT = 1.8`).
5. **Время не ломается при `TP < 10`:** при `player.TP = 5` `world_time_scale` остаётся `1.0`, а `tp_penalty_mult = 0.5` замедляет игрока вместо ошибочного ускорения.
6. **Регенерация `REG` vs `Anti-Regen`:** `Troll_Berserker` (`REG = 160`) успевает сворачивать кровопотерю и отращивать конечности (`>= 150`), но останавливается при наложении `Anti-Regen`.

## Шаг 4. Применение и верификация
1. Внесите согласованные числа в `project/src/` или `project/data/*.tres`.
2. Обновите формулы/таблицы в [benchmarks.md](./references/benchmarks.md) и [balance_matrix.py](./scripts/balance_matrix.py), если поменялась сама математика (чтобы симулятор никогда не расходился с GDScript).
3. Прогоните `godot-test-and-verify` (обратите особое внимание на сьюты `3`, `6`, `7`, `13`, `15`, `16`, `20`).
4. Если изменили формулы — синхронизируйте разделы `3.1`, `3.2`, `12.2`, `14.4` GDD через `gdd-spec-sync`.

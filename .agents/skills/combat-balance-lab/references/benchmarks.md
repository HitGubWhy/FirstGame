# Эталонные боевые формулы и константы (живой код `v0.2`)

> **Источник правды:** сверено напрямую с `StatSheet.gd`, `PenetrationResolver.gd`, `AnatomyComponent.gd`, `SimulationClock.gd`, `EnemyDummy.gd` и `project/data/*.tres`.

---

## 1. Живые формулы ядра

### Внешняя циркуляция (`StatSheet.gd`, при `mana_awakened = true` и `M_CTRL > 0`)
- `circ_mult = 1.0 + 0.015 * M_CTRL`
- `mana_skin_density = 5.0 * (M_CTRL / 10.0)^1.4 * circ_mult`
- `circ_stat_bonus = floor(0.5 * (M_CTRL / 10.0) * circ_mult)` $\rightarrow$ добавляется в `Flat Add` для `STR`, `CTRL`, `SPD`, `TP`, `CON` (потолок `500`).

### 4 барьера пробития (`PenetrationResolver.gd`)
- `armor_barrier = armor_thickness * armor_hardness * (1.0 - weak_point_bypass)`
- `skin_barrier = base_anatomy_thickness * size_mult + (10.0 * (CON / 10.0)^1.8 + mana_skin_density + hardening_bonus) * tissue_bypass_mult`
- `barrier_depth = armor_barrier + skin_barrier`
- `muscle_tendon_barrier = (3.5 + (CON / 10.0) * 1.5 + hardening_bonus * 0.05) * size_mult * tissue_bypass_mult`
- `bone_vessel_barrier = max(muscle_tendon_barrier + 1.0, (6.0 if is_weak_point else 12.0) * size_mult)`
- `penetration = (weapon_base_penetration * (STR / 10.0)^1.6 * kinetic_mult * type_pierce_mult * dead_zone_mult + aura_pierce_bonus) * edge_sharpness`
- `effective_depth = max(0.0, min(penetration - barrier_depth, effective_blade_len + aura_blade_extension))`
- При `is_weak_point = true`: `weak_point_bypass = 1.0`, `tissue_bypass_mult = 0.25`.
- В `Dead Zone` (`dist < min_optimal_range` и без `Half-swording`): `dead_zone_mult = 0.30`, `dead_zone_blunt_mult = 0.50`.
- В `Half-swording` (если `can_half_sword = true`): `dead_zone` снимается, `effective_blade_len = blade_length * 0.55`.

### Аура и Всплеск (`PenetrationResolver.gd` — откалибровано в Suite 20)
> **Внимание (известный дрейф с GDD 12.2):** в живом коде после баланс-патча Suite 20 используются более строгие коэффициенты, чем записано в GDD 12.2 (`250 / 15 / 150 / 2.0 MP/s`).
- `scale = M_CTRL / 10.0` (требуется `M_CTRL >= 1.0`)
- `aura_pierce_bonus = 130.0 * scale^1.25` (на `Aura Burst`: `× 1.8`)
- `aura_blade_extension = 6.0 * scale^0.5`
- `aura_impact = 75.0 * scale^1.25` (на `Aura Burst`: `× 1.8`)
- Расход `MP`: `AURA_MP_PER_SEC = 4.5`, `AURA_MP_PER_SWING = 4.0`, `AURA_MP_PER_HEAVY_HIT = 5.0`, `AURA_BURST_MP_COST = 15.0`.

### Дробящий импульс, Перелом и Отсечение (`PenetrationResolver.gd` + `AnatomyComponent.gd`)
- `blunt_impulse = (mass_factor * (STR / 10.0)^2 * kinetic_mult + aura_impact) * (1.40 if BLUNT else 1.0) * weapon.blunt_impulse_mult * (0.50 if dead_zone else 1.0)`
- `bone_density_mult = max(0.1, CON / 10.0)` при `CON <= 10`, иначе `(CON / 10.0)^1.15`
- `blunt_resistance_threshold = base_bone_density * bone_density_mult * armor_cushion_mult + mana_skin_density * 0.80 + hardening_bonus * 2.50`
- Пороги от `ratio = blunt_impulse / threshold`:
  - `>= 0.55`: контузионный шок (`sub-fracture rattle`)
  - `> 1.00`: перелом кости (`FRACTURE`, крипплинг конечности)
  - `>= 1.50` (голова/шея/грудь/живот): внутреннее кровотечение
  - `>= 1.80` (голова) / `>= 2.00` (шея/грудь): прямое размозжение жизненного органа
- `sever_threshold = (base_bone_density * (1.0 + max(0.0, CON - 10.0) * 0.10) * 0.35 * max(0.25, size_mult)) / max(0.1, slash_sever_mult)` (только `SLASH`, только `SEVERABLE_ZONES`, требуется `bone_vessel_breached` и `raw_depth >= sever_threshold`).

---

## 2. Тестовое оружие (`project/data/*.tres`)

| Параметр | `dagger.tres` | `greatsword.tres` | `warhammer.tres` |
| :--- | :---: | :---: | :---: |
| `base_penetration` | `12.0` | `28.0` | `16.0` |
| `blade_length` / `min_optimal_range` | `14.0` / `0.0` | `46.0` / `20.0` | `34.0` / `16.0` |
| `edge_sharpness` / `durability` | `1.0` / `40.0` | `1.1` / `100.0` | `0.6` / `140.0` |
| `mass_factor` / `vertical_reach` | `4.0` / `0.6` | `18.0` / `1.0` | `36.0` / `0.9` |
| `thrust / slash / blunt` pierce mult | `1.35 / 1.15 / 0.15` | `1.20 / 0.85 / 0.15` | `0.85 / 0.60 / 0.25` |
| `slash_sever_mult` / `blunt_impulse_mult` | `0.75` / `0.80` | `1.25` / `1.10` | `0.25` / `2.25` |
| `can_half_sword` | `false` | `true` | `false` |
| `windup / active / recovery` (сек) | `0.16 / 0.12 / 0.20` | `0.36 / 0.18 / 0.38` | `0.42 / 0.18 / 0.44` |
| `stamina_cost` / `poise_damage` | `10.0` / `18.0` | `26.0` / `65.0` | `30.0` / `95.0` |

---

## 3. Канонические противники арены (`EnemyDummy.gd`)

| Противник | Эффективные статы | `mana_skin` | Броня `(T × H = Barrier)` | `size_mult` / `bone_density` | Особенности |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **`Rank1_Swordsman`** (`duelist`) | Все `= 10`, мана выкл | `0` | `0 × 0 = 0` | `1.0` / `100` | `Short Sword` (`blade_length=20`), задержка реакции `~0.28с` |
| **`Troll_Berserker`** (`berserker`) | `STR/CON=45`, `CTRL=35`, `SPD/TP=25`, `AGI=20`, `STA=80`, `INT=10`, `MP_CAP=60`, `M_CTRL=10`, **`REG=160`** | `5.75` | `3 × 2 = 6` | `1.3` / `120` | `M_CTRL=10` даёт `circ_stat_bonus=0`, отрастание конечностей без `Anti-Regen` |
| **`Rank6_Guard`** (`guardian`) | Все `= 100` (`base=88 + circ 12`), `REG=60`, мана вкл | `313.99` | `20 × 15 = 300` | `1.0` / `100` | `MANA_FLIGHT (z=1.5)`, `Greatsword`, задержка реакции `~0.034с`, читает финты |

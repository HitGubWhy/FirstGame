# Контракты модульного ИИ (`project/src/ai/` и `EnemyDummy.gd`)

---

## 1. Встроенные профили `EnemyAIProfile`

| Поле | `duelist` | `berserker` | `guardian` | Назначение |
| :--- | :---: | :---: | :---: | :--- |
| `archetype_id` | `&"duelist"` | `&"berserker"` | `&"guardian"` | Ключ в `BrainFactory` |
| `custom_brain_id` | `&""` | `&""` | `&""` | Приоритетный ID кастомного подкласса |
| `aggression` / `caution` | `0.52 / 0.55` | `0.90 / 0.14` | `0.72 / 0.48` | Давление vs осторожность (`caution < 0.20` игнорирует гистерезис `STA`) |
| `flank_tendency` | `0.58` | `0.25` | `0.82` | Стрейф и обход со спины/фланга |
| `feint_affinity` | `0.38` | `0.12` | `0.72` | Плановые и реактивные финты |
| `dodge_affinity` / `parry_affinity` | `0.48 / 0.55` | `0.18 / 0.12` | `0.78 / 0.82` | Сайдстеп/рывок и дефлект/блок |
| `hardening_affinity` / `clinch_affinity` | `0.10 / 0.22` | `0.85 / 0.85` | `0.40 / 0.42` | Захват клинка мышцами и клинч/бросок |
| `aura_burst_affinity` / `weak_point_focus` | `0.25 / 0.45` | `0.35 / 0.20` | `0.85 / 0.82` | Срыв блока `Aura Burst` и прицел в 1-px |
| `preferred_range_ratio` / `adaptation_rate` | `0.84 / 0.50` | `0.62 / 0.30` | `0.86 / 0.85` | Оптимальная дистанция и адаптация к привычкам |
| `can_use_mana_flight` / `can_use_wing_flight` | `false / false` | `false / false` | `true / false` | Доступные режимы полёта |
| `flight_pursuit_enabled` | `false` | `false` | `true` | Преследование летящей цели по `height_z` |
| `retreats_when_crippled` / `allows_self_heal_spacing` | `true / false` | `false / true` | `false / true` | Отход при тяжёлой травме / под `REG` |

---

## 2. Все `16` действий `CombatBrain` (`ACTION_*`)

| Категория | Константы (`StringName`) |
| :--- | :--- |
| Ожидание / Восстановление | `ACTION_HOLD` (`&"hold"`), `ACTION_RECOVER_STAMINA` (`&"recover_stamina"`), `ACTION_REGEN_SPACING` (`&"regen_spacing"`) |
| Атаки | `ACTION_ATTACK_SLASH` (`&"attack_slash"`), `ACTION_ATTACK_THRUST` (`&"attack_thrust"`), `ACTION_ATTACK_BLUNT` (`&"attack_blunt"`) |
| Клинч | `ACTION_CLINCH_THROW` (`&"clinch_throw"`), `ACTION_CLINCH_SWEEP` (`&"clinch_sweep"`), `ACTION_CLINCH_SHOVE` (`&"clinch_shove"`) |
| Защита | `ACTION_DEFEND_PARRY` (`&"defend_parry"`), `ACTION_DEFEND_BLOCK` (`&"defend_block"`), `ACTION_DEFEND_SIDESTEP` (`&"defend_sidestep"`), `ACTION_DEFEND_DASH` (`&"defend_dash"`), `ACTION_DEFEND_HARDENING` (`&"defend_hardening"`) |
| Продвинутые тактики | `ACTION_FEINT_CANCEL` (`&"feint_cancel"`), `ACTION_AURA_BURST` (`&"aura_burst"`) |

---

## 3. Ключи словаря `ctx` (`CombatBrain.build_context`)

- **Ссылки и время:** `actor`, `target`, `arena`, `action_dt`, `world_dt`, `weapon`, `target_weapon`
- **Статы и ресурсы актора:** `str`, `ctrl`, `spd`, `agi`, `con`, `tp`, `int`, `m_ctrl`, `reg`, `mana_awakened`, `sta_ratio`, `mp_ratio`, `blood_ratio`
- **Геометрия:** `attack_range`, `vertical_reach`, `min_optimal_range`, `to_target`, `dist`, `surface_dist`, `height_diff`, `in_vertical_reach`, `in_clinch_range`
- **Состояние цели:** `target_str`, `target_spd`, `target_armor_barrier`, `target_hardening`, `target_blocking`, `target_parry`, `target_open`, `target_min_optimal_range`
- **Анатомия и среда:** `has_arm_impairment`, `has_severed_limb`, `has_arterial_bleed`, `can_fly`, `clinch_env` (`wall_slam_available`, `wall_slam_dir`, `wall_slam_dist`, `floor_drop_available`, `floor_drop_dir`)
- **Угроза (`CombatMemory`):** `threat_ready` (`bool`), `threat` (`Dictionary`: `active`, `attack_type`, `time_to_contact`, `elapsed_seen`, `attacker_str`, `weapon_mass`, `reacted`)

---

## 4. Формулы `CombatMemory` и сенсорика `EnemyDummy`

- **Задержка реакции:** `clampf(0.28 / pow(maxf(5.0, enemy_tp) / 10.0, 0.55) / (1.0 + maxf(0.0, enemy_int - 10.0) * 0.015), 0.03, 0.35)`
  - `TP=10, INT=10` $\rightarrow$ `0.280с`; `TP=100, INT=100` $\rightarrow$ `~0.034с`.
- **Интервал решений `CombatBrain`:** `clampf(0.18 / pow(maxf(5.0, enemy_tp) / 10.0, 0.45), 0.04, 0.22)`
- **Распознавание финта:** `(enemy_int >= 35.0 and tp_ratio >= 0.65) or (enemy_int >= 70.0 and tp_ratio >= 0.40)`, где `tp_ratio = enemy_tp / maxf(1.0, target_spd)`.
- **Окно памяти:** `MEMORY_WINDOW_SEC = 9.0` (экспоненциальное затухание привычек цели: `target_block_ratio`, `target_parry_baits`, `target_close_rush_count`, `target_feint_count`, `recent_damage_taken`).
- **Сенсорика и стелс (`EnemyDummy.gd`):**
  - `SEARCH_DURATION_SEC = 4.0`, `SUSPICION_SEARCH_THRESHOLD = 0.35`, `SUSPICION_DECAY_PER_SEC = 0.24`
  - `PROXIMITY_SENSE_STANDING_PX = 45.0`, `PROXIMITY_SENSE_CROUCH_PX = 16.0`, `INSTANT_SPOT_DIST_PX = 75.0`
  - Ночь: `NIGHT_VISION_RADIUS_MULT = 0.72`, `NIGHT_VISION_CONE_MULT = 0.85`
  - Кровавая Луна: `BLOOD_MOON_VISION_RADIUS_MULT = 1.25`, `BLOOD_MOON_VISION_CONE_MULT = 1.15`, `BLOOD_MOON_LEASH_MULT = 1.20`
  - Цвета телеграфа: `THRUST` `#FF3B3B`, `SLASH` `#FF9500`, `BLUNT` `#7B61FF`, нечитаемый `Color(0.75, 0.75, 0.80, 0.48)`

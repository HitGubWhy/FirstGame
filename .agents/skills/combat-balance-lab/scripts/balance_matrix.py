#!/usr/bin/env python3
"""
Combat Balance Simulator for D:\\My game\\project.
Replicates the exact live formulas from StatSheet.gd, PenetrationResolver.gd,
AnatomyComponent.gd, and SimulationClock.gd, loading weapons directly from project/data/*.tres.

Examples:
    python balance_matrix.py progression
    python balance_matrix.py matchups
    python balance_matrix.py strike --weapon greatsword --type thrust --str 100 --m-ctrl 100 --aura --target-con 100 --target-m-ctrl 100 --armor-t 20 --armor-h 15 --weak-point
    python balance_matrix.py tempo --player-spd 100 --player-tp 100 --player-agi 50 --enemy-spd 250
"""
from __future__ import annotations

import argparse
import math
import pathlib
import re
from dataclasses import dataclass

DATA_DIR = pathlib.Path(r"D:\My game\project\data")


# ---------------------------------------------------------------------------
# Live Formula Functions (1:1 mirror of GDScript)
# ---------------------------------------------------------------------------

def clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, val))


def calc_circulation(m_ctrl: float, awakened: bool) -> tuple[float, float, float]:
    if not awakened or m_ctrl <= 0.0:
        return 1.0, 0.0, 0.0
    circ_mult = 1.0 + 0.015 * m_ctrl
    mana_skin = 5.0 * ((m_ctrl / 10.0) ** 1.4) * circ_mult
    stat_bonus = math.floor(0.5 * (m_ctrl / 10.0) * circ_mult)
    return circ_mult, mana_skin, float(stat_bonus)


def calc_aura_bonuses(aura_active: bool, m_ctrl: float, aura_burst: bool = False) -> tuple[float, float, float]:
    if (not aura_active and not aura_burst) or m_ctrl < 1.0:
        return 0.0, 0.0, 0.0
    scale = m_ctrl / 10.0
    pierce = 130.0 * (scale ** 1.25)
    ext = 6.0 * (scale ** 0.5)
    impact = 75.0 * (scale ** 1.25)
    if aura_burst:
        pierce *= 1.8
        impact *= 1.8
    return pierce, ext, impact


def calc_bone_density_mult(con: float) -> float:
    if con <= 10.0:
        return max(0.1, con / 10.0)
    return (con / 10.0) ** 1.15


def calc_blunt_threshold(
    con: float,
    base_bone_density: float = 100.0,
    mana_skin: float = 0.0,
    armor_cushion_mult: float = 1.0,
    hardening_bonus: float = 0.0,
) -> float:
    eff_bone = base_bone_density * calc_bone_density_mult(con)
    return eff_bone * max(0.01, armor_cushion_mult) + max(0.0, mana_skin) * 0.80 + max(0.0, hardening_bonus) * 2.50


@dataclass
class WeaponSpec:
    weapon_id: str
    display_name: str
    base_penetration: float = 12.0
    blade_length: float = 14.0
    min_optimal_range: float = 0.0
    edge_sharpness: float = 1.0
    durability: float = 40.0
    mass_factor: float = 4.0
    vertical_reach: float = 0.6
    thrust_pierce_mult: float = 1.35
    slash_pierce_mult: float = 0.85
    blunt_pierce_mult: float = 0.15
    slash_sever_mult: float = 1.0
    blunt_impulse_mult: float = 1.0
    can_half_sword: bool = False
    stamina_cost: float = 10.0

    def type_pierce_mult(self, attack_type: str) -> float:
        return {
            "thrust": self.thrust_pierce_mult,
            "slash": self.slash_pierce_mult,
            "blunt": self.blunt_pierce_mult,
        }.get(attack_type, 1.0)


def load_weapons() -> dict[str, WeaponSpec]:
    weapons: dict[str, WeaponSpec] = {}
    if not DATA_DIR.exists():
        return weapons
    for path in sorted(DATA_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        if 'script_class="WeaponData"' not in text:
            continue
        fields: dict[str, str] = {}
        for line in text.splitlines():
            m = re.match(r"^([a-zA-Z0-9_]+)\s*=\s*(.+)$", line.strip())
            if m:
                fields[m.group(1)] = m.group(2).strip()

        def fval(k: str, default: float) -> float:
            return float(fields[k]) if k in fields else default

        def bval(k: str, default: bool) -> bool:
            return fields.get(k, str(default).lower()) == "true"

        wid = fields.get("weapon_id", f'&"{path.stem}"').strip('&"')
        dname = fields.get("display_name", f'"{wid}"').strip('"')
        weapons[wid] = WeaponSpec(
            weapon_id=wid,
            display_name=dname,
            base_penetration=fval("base_penetration", 12.0),
            blade_length=fval("blade_length", 14.0),
            min_optimal_range=fval("min_optimal_range", 0.0),
            edge_sharpness=fval("edge_sharpness", 1.0),
            durability=fval("durability", 40.0),
            mass_factor=fval("mass_factor", 4.0),
            vertical_reach=fval("vertical_reach", 0.6),
            thrust_pierce_mult=fval("thrust_pierce_mult", 1.35),
            slash_pierce_mult=fval("slash_pierce_mult", 0.85),
            blunt_pierce_mult=fval("blunt_pierce_mult", 0.15),
            slash_sever_mult=fval("slash_sever_mult", 1.0),
            blunt_impulse_mult=fval("blunt_impulse_mult", 1.0),
            can_half_sword=bval("can_half_sword", False),
            stamina_cost=fval("stamina_cost", 10.0),
        )
    return weapons


def resolve_strike(
    weapon: WeaponSpec,
    attack_type: str,
    attacker_str: float,
    attacker_m_ctrl: float = 0.0,
    aura_active: bool = False,
    aura_burst: bool = False,
    kinetic_mult: float = 1.0,
    is_weak_point: bool = False,
    distance: float = -1.0,
    half_swording: bool = False,
    target_con: float = 10.0,
    target_m_ctrl: float = 0.0,
    target_awakened: bool = False,
    armor_thickness: float = 0.0,
    armor_hardness: float = 0.0,
    hardening_bonus: float = 0.0,
    size_mult: float = 1.0,
    base_anatomy_thickness: float = 2.0,
    base_bone_density: float = 100.0,
    armor_cushion_mult: float = 1.0,
    zone: str = "Chest",
) -> dict[str, object]:
    _, target_mana_skin, _ = calc_circulation(target_m_ctrl, target_awakened)
    aura_pierce, aura_ext, aura_impact = calc_aura_bonuses(aura_active, attacker_m_ctrl, aura_burst)

    hs_active = half_swording and weapon.can_half_sword
    in_dead_zone = (
        distance >= 0.0
        and not hs_active
        and weapon.min_optimal_range > 0.0
        and distance < weapon.min_optimal_range
    )
    dz_mult = 0.30 if in_dead_zone else 1.0
    dz_blunt_mult = 0.50 if in_dead_zone else 1.0

    wp_bypass = 1.0 if is_weak_point else 0.0
    tissue_bypass = 0.25 if is_weak_point else 1.0

    armor_barrier = max(0.0, armor_thickness) * max(0.0, armor_hardness) * (1.0 - wp_bypass)
    con_density = 10.0 * ((max(0.0, target_con) / 10.0) ** 1.8)
    skin_barrier = base_anatomy_thickness * max(0.01, size_mult) + (
        con_density + target_mana_skin + max(0.0, hardening_bonus)
    ) * tissue_bypass
    barrier_depth = armor_barrier + skin_barrier

    muscle_barrier = (
        (3.5 + (max(0.0, target_con) / 10.0) * 1.5 + max(0.0, hardening_bonus) * 0.05)
        * max(0.01, size_mult)
        * tissue_bypass
    )
    bone_barrier = max(muscle_barrier + 1.0, (6.0 if is_weak_point else 12.0) * max(0.01, size_mult))

    eff_bone_for_sever = max(1.0, base_bone_density) * (1.0 + max(0.0, target_con - 10.0) * 0.10)
    sever_threshold = (eff_bone_for_sever * 0.35 * max(0.25, size_mult)) / max(0.1, weapon.slash_sever_mult)

    type_mult = weapon.type_pierce_mult(attack_type)
    eff_blade_len = weapon.blade_length * 0.55 if hs_active else weapon.blade_length
    str_scale = (max(0.0, attacker_str) / 10.0) ** 1.6
    penetration = (
        weapon.base_penetration * str_scale * kinetic_mult * type_mult * dz_mult + aura_pierce
    ) * weapon.edge_sharpness
    max_reach = eff_blade_len + aura_ext
    raw_depth = penetration - barrier_depth
    eff_depth = max(0.0, min(raw_depth, max_reach))

    armor_breached = penetration > armor_barrier
    skin_breached = eff_depth > 0.0
    muscle_breached = skin_breached and eff_depth >= muscle_barrier
    bone_breached = skin_breached and eff_depth >= bone_barrier

    if not armor_breached:
        deepest = "NONE"
    elif not skin_breached:
        deepest = "ARMOR"
    elif not muscle_breached:
        deepest = "SKIN"
    elif not bone_breached:
        deepest = "MUSCLE_TENDON"
    else:
        deepest = "BONE_VESSEL_ORGAN"

    severable = zone in {"Neck", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Wings", "Tail"}
    severed = (
        attack_type == "slash"
        and skin_breached
        and severable
        and bone_breached
        and raw_depth >= sever_threshold
        and max_reach >= bone_barrier
    )
    lodged = (
        skin_breached
        and attack_type != "blunt"
        and not severed
        and not bone_breached
        and (hardening_bonus > 0.0 or (muscle_breached and target_con >= 35.0 and not (aura_active or aura_burst)))
    )

    blunt_type_mult = (1.40 if attack_type == "blunt" else 1.0) * weapon.blunt_impulse_mult * dz_blunt_mult
    blunt_impulse = (weapon.mass_factor * ((attacker_str / 10.0) ** 2.0) * kinetic_mult + aura_impact) * blunt_type_mult
    blunt_threshold = calc_blunt_threshold(
        target_con, base_bone_density, target_mana_skin, armor_cushion_mult, hardening_bonus
    )
    blunt_ratio = blunt_impulse / max(1.0, blunt_threshold)

    return {
        "armor_barrier": armor_barrier,
        "skin_barrier": skin_barrier,
        "barrier_depth": barrier_depth,
        "muscle_barrier": muscle_barrier,
        "bone_barrier": bone_barrier,
        "penetration": penetration,
        "raw_depth": raw_depth,
        "effective_depth": eff_depth,
        "max_reach": max_reach,
        "deepest": deepest,
        "sever_threshold": sever_threshold,
        "severed": severed,
        "lodged": lodged,
        "in_dead_zone": in_dead_zone,
        "half_swording": hs_active,
        "blunt_impulse": blunt_impulse,
        "blunt_threshold": blunt_threshold,
        "blunt_ratio": blunt_ratio,
        "fractured": blunt_impulse > blunt_threshold,
    }


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_progression(_args: argparse.Namespace) -> int:
    points = [10, 22, 45, 55, 100, 250, 400, 500]
    print("=== 1..500 STAT PROGRESSION BENCHMARKS (Live StatSheet.gd) ===")
    header = (
        f"{'Stat':>4} | {'STRx':>7} | {'Carry(kg)':>10} | {'CON Skin':>9} | "
        f"{'ManaSkin':>9} | {'Circ+':>5} | {'STA':>7} | {'MP':>8} | "
        f"{'Clot/Heal':>14} | {'TimeScale':>9}"
    )
    print(header)
    print("-" * len(header))
    for s in points:
        awakened = s >= 55
        _, mana_skin, circ_bonus = calc_circulation(float(s), awakened)
        str_mult = (s / 10.0) ** 2.0
        carry = 60.0 * str_mult
        con_skin = 10.0 * ((s / 10.0) ** 1.8)
        sta = 100.0 + 50.0 * ((s / 10.0) ** 1.5)
        mp = 100.0 * ((s / 10.0) ** 1.6) if awakened else 0.0
        clot = (s / 10.0) ** 1.5
        heal = (s / 10.0) ** 1.8
        tscale = clamp(10.0 / max(10.0, float(s)), 0.02, 1.0)
        print(
            f"{s:>4} | {str_mult:>6.1f}x | {carry:>10.0f} | {con_skin:>9.1f} | "
            f"{mana_skin:>9.1f} | {int(circ_bonus):>5} | {sta:>7.0f} | {mp:>8.0f} | "
            f"{clot:>6.1f}/{heal:<7.1f} | {tscale:>9.4f}"
        )
    return 0


def cmd_matchups(_args: argparse.Namespace) -> int:
    weapons = load_weapons()
    if not weapons:
        print(f"No WeaponData .tres files found in {DATA_DIR}")
        return 1

    enemies = {
        "Rank1_Swordsman": dict(target_con=10.0, target_m_ctrl=0.0, target_awakened=False, armor_thickness=0.0, armor_hardness=0.0, size_mult=1.0, base_bone_density=100.0),
        "Troll_R4": dict(target_con=45.0, target_m_ctrl=10.0, target_awakened=True, armor_thickness=3.0, armor_hardness=2.0, size_mult=1.3, base_bone_density=120.0),
        "Rank6_Guard": dict(target_con=100.0, target_m_ctrl=100.0, target_awakened=True, armor_thickness=20.0, armor_hardness=15.0, size_mult=1.0, base_bone_density=100.0),
    }

    scenarios = [
        ("R1 Player Dagger SLASH -> Rank1 Chest", "dagger", "slash", 10, 0, False, False, False, -1, False, 0, "Rank1_Swordsman", "Chest"),
        ("R1 Player Dagger SLASH -> Rank6 Chest", "dagger", "slash", 10, 0, False, False, False, -1, False, 0, "Rank6_Guard", "Chest"),
        ("R1 Player Greatsword SLASH (DeadZone d=10) -> Rank1", "greatsword", "slash", 10, 0, False, False, False, 10, False, 0, "Rank1_Swordsman", "Chest"),
        ("R1 Player Greatsword THRUST (HalfSword d=10) -> Rank1", "greatsword", "thrust", 10, 0, False, False, False, 10, True, 0, "Rank1_Swordsman", "Chest"),
        ("R1 Player Warhammer BLUNT -> Rank1 Chest", "warhammer", "blunt", 10, 0, False, False, False, -1, False, 0, "Rank1_Swordsman", "Chest"),
        ("R4 STR45 Greatsword SLASH -> Troll LeftArm", "greatsword", "slash", 45, 10, False, False, False, -1, False, 0, "Troll_R4", "LeftArm"),
        ("R4 STR45 Greatsword SLASH -> Troll (Hardening 80)", "greatsword", "slash", 45, 10, False, False, False, -1, False, 80, "Troll_R4", "Chest"),
        ("R6 STR100 M_CTRL100 Dagger THRUST WP -> Rank6", "dagger", "thrust", 100, 100, False, False, True, -1, False, 0, "Rank6_Guard", "Chest"),
        ("R6 STR100 M_CTRL100 Greatsword THRUST Aura -> Rank6", "greatsword", "thrust", 100, 100, True, False, False, -1, False, 0, "Rank6_Guard", "Chest"),
        ("R6 STR100 M_CTRL100 Greatsword THRUST Burst -> Rank6", "greatsword", "thrust", 100, 100, True, True, False, -1, False, 0, "Rank6_Guard", "Chest"),
        ("R6 STR100 M_CTRL100 Warhammer BLUNT Aura -> Rank6", "warhammer", "blunt", 100, 100, True, False, False, -1, False, 0, "Rank6_Guard", "Chest"),
    ]

    print("=== CANONICAL v0.2 COMBAT MATCHUPS (Loaded from project/data/*.tres) ===")
    for label, wid, atype, astr, amc, aura, burst, wp, dist, hs, hard, ename, zone in scenarios:
        w = weapons[wid]
        r = resolve_strike(
            weapon=w,
            attack_type=atype,
            attacker_str=float(astr),
            attacker_m_ctrl=float(amc),
            aura_active=aura,
            aura_burst=burst,
            is_weak_point=wp,
            distance=float(dist),
            half_swording=hs,
            hardening_bonus=float(hard),
            zone=zone,
            **enemies[ename],
        )
        flags = []
        if r["in_dead_zone"]:
            flags.append("DEAD_ZONE")
        if r["half_swording"]:
            flags.append("HALF_SWORD")
        if r["severed"]:
            flags.append("SEVERED!")
        if r["lodged"]:
            flags.append("LODGED!")
        if r["fractured"]:
            flags.append(f"FRACTURE({r['blunt_ratio']:.2f}x)")
        flag_str = ", ".join(flags) if flags else "-"
        print(
            f"- {label}\n"
            f"    Pen={r['penetration']:.1f} vs Barrier={r['barrier_depth']:.1f} "
            f"-> Depth={r['effective_depth']:.1f}/{r['max_reach']:.1f} [{r['deepest']}] | "
            f"Blunt={r['blunt_impulse']:.1f}/{r['blunt_threshold']:.1f} | Flags: {flag_str}"
        )
    return 0


def cmd_strike(args: argparse.Namespace) -> int:
    weapons = load_weapons()
    if args.weapon not in weapons:
        print(f"Unknown weapon '{args.weapon}'. Available: {sorted(weapons.keys())}")
        return 2
    w = weapons[args.weapon]
    r = resolve_strike(
        weapon=w,
        attack_type=args.type,
        attacker_str=args.str_val,
        attacker_m_ctrl=args.m_ctrl,
        aura_active=args.aura,
        aura_burst=args.aura_burst,
        kinetic_mult=args.kinetic,
        is_weak_point=args.weak_point,
        distance=args.dist,
        half_swording=args.half_sword,
        target_con=args.target_con,
        target_m_ctrl=args.target_m_ctrl,
        target_awakened=args.target_m_ctrl > 0.0,
        armor_thickness=args.armor_t,
        armor_hardness=args.armor_h,
        hardening_bonus=args.hardening,
        size_mult=args.size_mult,
        base_bone_density=args.bone_density,
        armor_cushion_mult=args.cushion,
        zone=args.zone,
    )
    print(f"=== STRIKE SIMULATION: {w.display_name} ({args.type.upper()}) -> {args.zone} ===")
    for k, v in r.items():
        if isinstance(v, float):
            print(f"  {k:<18}: {v:.3f}")
        else:
            print(f"  {k:<18}: {v}")
    return 0


def cmd_tempo(args: argparse.Namespace) -> int:
    eff_tp = max(10.0, 10.0 + (args.player_tp - 10.0) * clamp(args.perc_reg, 0.0, 1.0))
    wt_scale = clamp(10.0 / eff_tp, 0.02, 1.0)
    tp_pen = clamp(args.player_tp / 10.0, 0.0, 1.0)
    spd_reg = clamp(args.speed_reg, 0.02, 1.0)

    raw_dt = 1.0 / 60.0
    world_dt = raw_dt * wt_scale
    player_act_dt = world_dt * (args.player_spd / 10.0) * spd_reg * tp_pen
    enemy_act_dt = world_dt * (args.enemy_spd / 10.0)
    player_micro = max(1, math.ceil(player_act_dt / 0.02)) if player_act_dt > 0 else 0
    enemy_micro = max(1, math.ceil(enemy_act_dt / 0.02)) if enemy_act_dt > 0 else 0

    losing_ctrl = (args.player_spd * spd_reg) / max(1.0, args.player_tp) > 1.5
    imp_ratio = args.enemy_spd / max(1.0, args.player_tp)
    imperceptible = imp_ratio >= 10.0
    instinct = (
        clamp(((args.player_agi - 5.0) / (args.player_agi + 80.0)) * min(1.0, args.player_spd / max(0.001, args.enemy_spd)), 0.0, 1.0)
        if args.player_agi > 5.0
        else 0.0
    )

    print("=== SIMULATION CLOCK TEMPO ANALYSIS (60 FPS, COMBAT_OVERDRIVE) ===")
    print(f"  effective_tp           : {eff_tp:.2f}")
    print(f"  world_time_scale       : {wt_scale:.4f} ({1.0 / wt_scale:.2f}x slow-mo)")
    print(f"  tp_penalty_mult        : {tp_pen:.3f}")
    print(f"  player_action_dt/frame : {player_act_dt:.5f}s (micro-steps={player_micro})")
    print(f"  enemy_action_dt/frame  : {enemy_act_dt:.5f}s (micro-steps={enemy_micro})")
    print(f"  losing_control (>1.5)  : {losing_ctrl} (ratio={(args.player_spd * spd_reg) / max(1.0, args.player_tp):.2f})")
    print(f"  imperceptible (>=10.0) : {imperceptible} (enemy_SPD/player_TP={imp_ratio:.2f})")
    print(f"  instinct_dodge_chance  : {instinct * 100.0:.2f}%")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Combat Balance Simulator for D:\\My game\\project")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("progression", help="Print 1..500 stat progression benchmark table")
    sub.add_parser("matchups", help="Evaluate canonical v0.2 weapon vs enemy matchups")

    st = sub.add_parser("strike", help="Simulate a custom single strike")
    st.add_argument("--weapon", default="greatsword")
    st.add_argument("--type", choices=["slash", "thrust", "blunt"], default="slash")
    st.add_argument("--str", dest="str_val", type=float, default=10.0)
    st.add_argument("--m-ctrl", type=float, default=0.0)
    st.add_argument("--aura", action="store_true")
    st.add_argument("--aura-burst", action="store_true")
    st.add_argument("--kinetic", type=float, default=1.0)
    st.add_argument("--weak-point", action="store_true")
    st.add_argument("--dist", type=float, default=-1.0)
    st.add_argument("--half-sword", action="store_true")
    st.add_argument("--target-con", type=float, default=10.0)
    st.add_argument("--target-m-ctrl", type=float, default=0.0)
    st.add_argument("--armor-t", type=float, default=0.0)
    st.add_argument("--armor-h", type=float, default=0.0)
    st.add_argument("--hardening", type=float, default=0.0)
    st.add_argument("--size-mult", type=float, default=1.0)
    st.add_argument("--bone-density", type=float, default=100.0)
    st.add_argument("--cushion", type=float, default=1.0)
    st.add_argument("--zone", default="Chest")

    tp = sub.add_parser("tempo", help="Analyze SimulationClock time dilation and imperceptible speed")
    tp.add_argument("--player-spd", type=float, default=10.0)
    tp.add_argument("--player-tp", type=float, default=10.0)
    tp.add_argument("--player-agi", type=float, default=10.0)
    tp.add_argument("--enemy-spd", type=float, default=10.0)
    tp.add_argument("--perc-reg", type=float, default=1.0)
    tp.add_argument("--speed-reg", type=float, default=1.0)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    handlers = {
        "progression": cmd_progression,
        "matchups": cmd_matchups,
        "strike": cmd_strike,
        "tempo": cmd_tempo,
    }
    return handlers[args.cmd](args)


if __name__ == "__main__":
    raise SystemExit(main())

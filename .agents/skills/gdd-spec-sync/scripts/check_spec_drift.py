#!/usr/bin/env python3
"""
Audits drift between live project files (D:\\My game\\project) and GDD
(D:\\My game\\game_design_document_gdd_godot_4.md).

Zero external dependencies. Run:
    python "d:\\My game\\.agents\\skills\\gdd-spec-sync\\scripts\\check_spec_drift.py"
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\My game")
GDD_PATH = ROOT / "game_design_document_gdd_godot_4.md"
PROJECT_DIR = ROOT / "project"
PROJECT_GODOT = PROJECT_DIR / "project.godot"
RUN_TESTS_GD = PROJECT_DIR / "tests" / "run_tests.gd"
PEN_RESOLVER_GD = PROJECT_DIR / "src" / "core" / "PenetrationResolver.gd"
DATA_DIR = PROJECT_DIR / "data"


def parse_ini_section(text: str, section_name: str) -> dict[str, str]:
    result: dict[str, str] = {}
    in_section = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_section = line[1:-1].strip() == section_name
            continue
        if in_section and "=" in line:
            key, val = line.split("=", 1)
            result[key.strip()] = val.strip()
    return result


def parse_input_actions(text: str) -> list[str]:
    actions: list[str] = []
    in_input = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_input = line[1:-1].strip() == "input"
            continue
        if in_input:
            m = re.match(r"^([a-zA-Z0-9_]+)=\{$", line)
            if m:
                actions.append(m.group(1))
    return actions


def extract_gdd_section(gdd_text: str, heading_prefix: str) -> str:
    lines = gdd_text.splitlines()
    start = None
    for idx, line in enumerate(lines):
        if line.startswith(heading_prefix):
            start = idx
            break
    if start is None:
        return ""
    level = len(heading_prefix.split(" ")[0])
    out = [lines[start]]
    for line in lines[start + 1 :]:
        m = re.match(r"^(#{1,6})\s+", line)
        if m and len(m.group(1)) <= level:
            break
        out.append(line)
    return "\n".join(out)


def main() -> int:
    if not GDD_PATH.exists() or not PROJECT_GODOT.exists():
        print(f"[ERROR] Expected workspace files missing under {ROOT}", file=sys.stderr)
        return 2

    gdd_text = GDD_PATH.read_text(encoding="utf-8")
    proj_text = PROJECT_GODOT.read_text(encoding="utf-8")
    tests_text = RUN_TESTS_GD.read_text(encoding="utf-8") if RUN_TESTS_GD.exists() else ""
    pen_text = PEN_RESOLVER_GD.read_text(encoding="utf-8") if PEN_RESOLVER_GD.exists() else ""

    drifts: list[str] = []
    ok_notes: list[str] = []

    # 1. Test suite count in run_tests.gd vs GDD mentions
    suite_matches = re.findall(r"^\s*(?:await\s+)?_run_suite(?:_async)?\(", tests_text, flags=re.MULTILINE)
    actual_suites = len(suite_matches)
    gdd_suite_nums = sorted({int(n) for n in re.findall(r"`?(\d+)`?\s+набор(?:ов|а)", gdd_text)})
    if gdd_suite_nums != [actual_suites]:
        drifts.append(
            f"Test suites count mismatch: run_tests.gd has {actual_suites} suites, "
            f"GDD cites {gdd_suite_nums} (check Sections 12.8, 13.1, 14.2)."
        )
    else:
        ok_notes.append(f"Test suites count aligned ({actual_suites}).")

    # 2. InputMap actions in project.godot vs GDD Section 14.5
    actual_actions = parse_input_actions(proj_text)
    sec_14_5 = extract_gdd_section(gdd_text, "### 14.5.")
    # Expand shorthand patterns in GDD such as "switch_weapon_1 / 2 / 3"
    expanded_sec_14_5 = sec_14_5
    for m in re.finditer(r"`([a-zA-Z0-9_]+_)(\d+)(?:\s*/\s*(\d+))+`", sec_14_5):
        prefix = m.group(1)
        nums = re.findall(r"\d+", m.group(0))
        expanded_sec_14_5 += " " + " ".join(f"{prefix}{n}" for n in nums)

    missing_in_gdd = [a for a in actual_actions if a not in expanded_sec_14_5]
    reserved_line_match = re.search(r"Зарезервировано.*$", sec_14_5, flags=re.MULTILINE)
    reserved_line = reserved_line_match.group(0) if reserved_line_match else ""
    implemented_but_marked_reserved = [a for a in actual_actions if a in reserved_line]
    if missing_in_gdd:
        drifts.append(f"InputMap actions in project.godot missing from GDD 14.5: {missing_in_gdd}")
    if implemented_but_marked_reserved:
        drifts.append(
            f"InputMap actions already in project.godot but still listed as 'Зарезервировано' in GDD 14.5: "
            f"{implemented_but_marked_reserved}"
        )
    if not missing_in_gdd and not implemented_but_marked_reserved:
        ok_notes.append(f"All {len(actual_actions)} InputMap actions aligned with GDD 14.5.")

    # 3. Physics layers (18 named layers expected) & Autoloads
    layer_names = parse_ini_section(proj_text, "layer_names")
    physics_layers = {k: v for k, v in layer_names.items() if k.startswith("2d_physics/layer_")}
    if len(physics_layers) != 18:
        drifts.append(f"Expected 18 named 2D physics layers per GDD 12.6, found {len(physics_layers)}.")
    else:
        ok_notes.append("Physics layers count aligned (18/32 named layers).")

    autoloads = parse_ini_section(proj_text, "autoload")
    expected_autoloads = {"EventBus", "SimulationClock", "WorldCalendar", "FloorLayerManager"}
    missing_auto = sorted(expected_autoloads - set(autoloads.keys()))
    extra_auto = sorted(set(autoloads.keys()) - expected_autoloads)
    if missing_auto or extra_auto:
        drifts.append(f"Autoloads delta vs v0.2 spec — missing: {missing_auto}, extra: {extra_auto}.")
    else:
        ok_notes.append(f"Autoloads aligned ({', '.join(sorted(autoloads.keys()))}).")

    # 4. Aura formula constants in PenetrationResolver.gd vs GDD 12.2
    sec_12_2 = extract_gdd_section(gdd_text, "### 12.2.")
    aura_checks = [
        ("AURA_MP_PER_SEC", r"const\s+AURA_MP_PER_SEC:\s*float\s*=\s*([0-9.]+)", r"поддержание стоит\s*\$([0-9.]+)\\text\{\s*MP/сек\}"),
        ("aura_pierce_bonus coeff", r"bonuses\.pierce_bonus\s*=\s*([0-9.]+)\s*\*", r"aura\\_pierce\\_bonus\}\s*=\s*([0-9.]+)\s*\\times"),
        ("aura_blade_extension coeff", r"bonuses\.blade_extension\s*=\s*([0-9.]+)\s*\*", r"aura\\_blade\\_extension\}\s*=\s*([0-9.]+)\s*\\times"),
        ("aura_impact coeff", r"bonuses\.impact_bonus\s*=\s*([0-9.]+)\s*\*", r"aura\\_impact\}\s*=\s*([0-9.]+)\s*\\times"),
    ]
    for label, code_rx, gdd_rx in aura_checks:
        cm = re.search(code_rx, pen_text)
        gm = re.search(gdd_rx, sec_12_2)
        if cm and gm and float(cm.group(1)) != float(gm.group(1)):
            drifts.append(
                f"Formula drift ({label}): PenetrationResolver.gd uses {cm.group(1)}, "
                f"GDD 12.2 still states {gm.group(1)}."
            )

    # 5. Weapon .tres inventory
    tres_files = sorted(p.name for p in DATA_DIR.glob("*.tres")) if DATA_DIR.exists() else []
    ok_notes.append(f"Data .tres templates ({len(tres_files)}): {', '.join(tres_files)}")

    print("=== GDD <-> CODE DRIFT AUDIT ===")
    for note in ok_notes:
        print(f"  [OK]    {note}")
    if drifts:
        print(f"\nDetected {len(drifts)} drift item(s):")
        for item in drifts:
            print(f"  [DRIFT] {item}")
        return 1

    print("\nNo spec drift detected.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

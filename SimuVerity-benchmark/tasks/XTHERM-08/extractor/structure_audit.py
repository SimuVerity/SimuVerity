"""Candidate-independent, structure-only audit for F90-XTHERM-08.

The audit recognizes either a connected Simscape Fluids implementation or
an explicit state-space energy-balance implementation.  It uses only the submitted model structure and the public output semantics.
The public output channel meanings provide the semantic anchors for the
equation path.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any


TASK_ID = "F90-XTHERM-08"
TOKEN = re.compile(r"[A-Za-z_]\w*(?:\(\d+\))?")
ASSIGNMENT = re.compile(
    r"^\s*([A-Za-z_]\w*(?:\(\d+\))?)\s*=\s*(.+?)\s*;\s*$"
)


def _normal(value: str) -> str:
    return " ".join(html.unescape(value).lower().split())


def _read_parts(model: Path) -> dict[str, str]:
    with zipfile.ZipFile(model) as archive:
        return {
            name: archive.read(name).decode("utf-8", "ignore")
            for name in archive.namelist()
            if name.endswith(".xml")
        }


def _blocks(parts: dict[str, str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for part_name, text in parts.items():
        if "/systems/" not in part_name:
            continue
        for match in re.finditer(r"<Block\b([^>]*)>(.*?)</Block>", text, re.S):
            attrs, body = match.groups()
            name = re.search(r'Name="([^"]*)"', attrs)
            kind = re.search(r'BlockType="([^"]*)"', attrs)
            sid = re.search(r'SID="([^"]*)"', attrs)
            params = {
                key: _normal(re.sub(r"<.*?>", "", value))
                for key, value in re.findall(
                    r'<P Name="([^"]+)">(.*?)</P>', body, re.S
                )
            }
            rows.append(
                {
                    "part": part_name,
                    "sid": sid.group(1) if sid else "",
                    "name": _normal(name.group(1) if name else ""),
                    "block_type": _normal(kind.group(1) if kind else ""),
                    "source_block": params.get("SourceBlock", ""),
                    "source_type": params.get("SourceType", ""),
                    "initial_condition": params.get("InitialCondition", ""),
                }
            )
    return rows


def _scripts(parts: dict[str, str]) -> list[str]:
    scripts: list[str] = []
    for part_name, text in parts.items():
        if "/stateflow/" not in part_name:
            continue
        for value in re.findall(r'<P Name="script">(.*?)</P>', text, re.S):
            scripts.append(html.unescape(value))
    return scripts


def _dependency_graph(scripts: list[str]) -> dict[str, set[str]]:
    graph: dict[str, set[str]] = defaultdict(set)
    for script in scripts:
        for raw_line in script.splitlines():
            line = raw_line.split("%", 1)[0]
            match = ASSIGNMENT.match(line)
            if not match:
                continue
            left, right = match.groups()
            graph[left].update(TOKEN.findall(right))
    return dict(graph)


def _reaches(graph: dict[str, set[str]], start: str, target: str) -> bool:
    pending = [start]
    seen: set[str] = set()
    while pending:
        item = pending.pop()
        if item == target:
            return True
        if item in seen:
            continue
        seen.add(item)
        pending.extend(graph.get(item, ()))
    return False


def _reaches_any(
    graph: dict[str, set[str]], start: str, targets: set[str]
) -> bool:
    return any(_reaches(graph, start, target) for target in targets)


def _single_source(graph: dict[str, set[str]], key: str) -> str:
    direct = sorted(
        token for token in graph.get(key, set())
        if token not in {"zeros", "min", "max", "bounded"}
    )
    return direct[0] if len(direct) == 1 else key


def _equation_audit(graph: dict[str, set[str]]) -> dict[str, Any]:
    flows = [_single_source(graph, f"flow_control_state({index})") for index in (1, 2)]
    commands = [
        _single_source(graph, f"flow_control_state({index})")
        for index in (3, 4, 5)
    ]
    heat = [_single_source(graph, f"heat_power_state({index})") for index in range(1, 9)]
    environments = [
        _single_source(graph, f"environment_state({index})") for index in (1, 2, 3)
    ]
    chilled_states = {"dx(1)", "dx(2)", "dx(3)"}
    condenser_states = {"dx(4)", "dx(5)"}
    thermal_x = {f"x({index})" for index in range(1, 6)}

    flow_assignments_present = all(
        f"flow_control_state({index})" in graph for index in (1, 2)
    )
    distinct_flows = flow_assignments_present and flows[0] != flows[1]
    chilled_flow_in_energy = any(
        _reaches(graph, state, flows[0]) for state in chilled_states
    )
    condenser_flow_in_energy = any(
        _reaches(graph, state, flows[1]) for state in condenser_states
    )
    server_heat_in_chilled = any(
        _reaches(graph, state, heat[0]) for state in chilled_states
    )
    exchanger_cross_loop = (
        any(_reaches(graph, state, heat[1]) for state in chilled_states)
        and any(_reaches(graph, state, heat[1]) for state in condenser_states)
    )
    chiller_cross_loop = (
        any(_reaches(graph, state, heat[2]) for state in chilled_states)
        and any(_reaches(graph, state, heat[2]) for state in condenser_states)
    )
    tower_weather_coupling = (
        any(_reaches(graph, state, heat[3]) for state in condenser_states)
        and (
            _reaches_any(graph, heat[3], set(environments[:2]))
            or _reaches(graph, environments[2], heat[3])
        )
    )
    pump_power_linkage = (
        _reaches(graph, heat[5], flows[1])
        and _reaches(graph, heat[6], flows[0])
    )
    capacity_scale_linkage = (
        _reaches(graph, flows[0], "ChilledWaterPumpCapacityScale")
        and (
            _reaches(graph, heat[2], "ChillerCapacityScale")
            or _reaches(graph, commands[2], "ChillerCapacityScale")
        )
    )

    loop_checks: list[dict[str, Any]] = []
    actuator_targets = (flows[0], flows[1], heat[2])
    for offset, (command, actuator) in enumerate(
        zip(commands, actuator_targets), start=6
    ):
        derivative = f"dx({offset})"
        state_key = f"x({offset})"
        stateful = _reaches(graph, command, state_key)
        feedback = _reaches_any(graph, derivative, thermal_x)
        actuator_linked = _reaches(graph, actuator, command)
        loop_checks.append(
            {
                "command_channel": offset - 3,
                "state_index": offset,
                "stateful": stateful,
                "thermal_feedback": feedback,
                "actuator_linked": actuator_linked,
                "pass": stateful and feedback and actuator_linked,
            }
        )

    energy_checks = {
        "distinct_chilled_and_condenser_flow_expressions": distinct_flows,
        "chilled_flow_in_chilled_energy_states": chilled_flow_in_energy,
        "condenser_flow_in_condenser_energy_states": condenser_flow_in_energy,
        "server_heat_enters_chilled_loop": server_heat_in_chilled,
        "heat_exchanger_couples_both_loops": exchanger_cross_loop,
        "chiller_moves_heat_between_loop_sides": chiller_cross_loop,
        "tower_rejects_heat_with_weather_coupling": tower_weather_coupling,
        "separate_pump_power_depends_on_each_flow": pump_power_linkage,
        "capacity_scales_reach_pump_and_chiller_paths": capacity_scale_linkage,
    }
    return {
        "assignment_count": len(graph),
        "energy_path_checks": energy_checks,
        "energy_path_pass": all(energy_checks.values()),
        "closed_loop_checks": loop_checks,
        "closed_loop_count": sum(bool(row["pass"]) for row in loop_checks),
        "three_closed_loops_pass": all(bool(row["pass"]) for row in loop_checks),
    }


def audit_model(model: Path) -> dict[str, Any]:
    parts = _read_parts(model)
    blocks = _blocks(parts)
    scripts = _scripts(parts)
    graph = _dependency_graph(scripts)
    equation = _equation_audit(graph)

    physical_rows = [
        row for row in blocks
        if row["source_block"].startswith(("fl_lib/", "simscapefluids_lib/"))
    ]
    physical_text = [
        f'{row["name"]} {row["source_block"]} {row["source_type"]}'
        for row in physical_rows
    ]
    pump_count = sum(
        "centrifugal pump" in text or "/pumps & motors/" in text
        for text in physical_text
    )
    heat_exchanger = any(
        "heat exchanger" in text and ("tl-tl" in text or "thermal liquid" in text)
        for text in physical_text
    )
    chiller = any(
        "refrigeration cycle" in text or "two-phase fluid" in text
        for text in physical_text
    )
    cooling_tower = any("cooling tower" in text for text in physical_text)
    server_heat_source = any("controlled heat flow" in text for text in physical_text)
    pmio_count = sum(row["block_type"] == "pmioport" for row in blocks)
    line_count = sum(text.count("<Line>") for text in parts.values())
    component_checks = {
        "two_distinct_physical_pumps": pump_count >= 2,
        "water_to_water_heat_exchanger": heat_exchanger,
        "chiller_or_refrigeration_path": chiller,
        "ambient_coupled_cooling_tower": cooling_tower,
        "physical_server_heat_source": server_heat_source,
        "conserving_port_graph": pmio_count >= 8 and line_count >= 8,
    }
    physical_graph_complete = all(component_checks.values())

    named_controller_subsystems = sum(
        row["block_type"] == "subsystem" and "controller" in row["name"]
        for row in blocks
    )
    controller_blocks = sum(
        row["block_type"] == "relay"
        or "pid controller" in row["source_type"]
        or "pid controller" in row["name"]
        for row in blocks
    )
    physical_control_count = min(3, max(named_controller_subsystems, controller_blocks))
    control_count = max(physical_control_count, int(equation["closed_loop_count"]))

    if physical_graph_complete:
        physical_score = 1.0
        physical_tier = "dedicated_conserving_physical_components"
    elif equation["energy_path_pass"]:
        physical_score = 0.4
        physical_tier = "monolithic_explicit_energy_balance_without_conserving_ports"
    else:
        physical_score = 0.0
        physical_tier = "required_physical_path_not_structurally_demonstrated"
    control_score = min(1.0, control_count / 3.0)
    core_qualified = bool(
        (physical_graph_complete or equation["energy_path_pass"])
        and control_count >= 3
    )
    return {
        "schema": "simuverity.f90-xtherm08-structure-audit.v1",
        "task_id": TASK_ID,
        "model_path": str(model.resolve()),
        "public_semantic_anchors": {
            "thermal_state_channels": 5,
            "flow_control_state_channels": 5,
            "heat_power_state_channels": 9,
            "environment_state_channels": 3,
        },
        "profile": {
            "block_count": len(blocks),
            "physical_library_block_count": len(physical_rows),
            "pmio_port_count": pmio_count,
            "line_count": line_count,
            "stateflow_script_count": len(scripts),
        },
        "physical_graph": {
            "component_checks": component_checks,
            "physical_pump_count": pump_count,
            "complete": physical_graph_complete,
        },
        "equation_graph": equation,
        "control_observations": {
            "physical_controller_count": physical_control_count,
            "equation_closed_loop_count": int(equation["closed_loop_count"]),
            "credited_closed_loop_count": control_count,
        },
        "core_semantics_qualified": core_qualified,
        "physical_device_observations_score": physical_score,
        "physical_device_observations_tier": physical_tier,
        "control_loop_observations_score": control_score,
        "scoring_tiers": {
            "dedicated_conserving_physical_components": 1.0,
            "independently_encapsulated_conservation_components": 0.7,
            "monolithic_explicit_energy_balance_without_conserving_ports": 0.4,
            "behavior_only_without_static_mechanism": 0.15,
            "required_path_absent_or_contradicted": 0.0,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit_model(args.model)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()



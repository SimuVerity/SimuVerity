#!/usr/bin/env python3
"""XMECH-08 scorer using granular topology evidence.

This module is pure offline scoring: it reads JSON evidence only.  Simulation,
candidate inspection, thresholds, weights, group aggregation, and score caps
remain owned by the existing task implementation.
"""

from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
from typing import Any


TASK_DIR = Path(__file__).resolve().parent
METRICS_PATH = TASK_DIR / "f90_xmech08_scoring_core_core.py"
POLICY_ID = 'simuverity-101-v1:f90-xmech-08:scoring'


def _load_policy_core():
    spec = importlib.util.spec_from_file_location(
        "f90_xmech08_scoring_core_core_current_dependency", METRICS_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load current scorer dependency: {METRICS_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


METRICS = _load_policy_core()
TASK_ID = METRICS.TASK_ID
WEIGHTS = METRICS.WEIGHTS


def _finite_at_least(value: Any, minimum: float) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
        and float(value) >= minimum
    )


def structure_checks(evidence: dict[str, Any]) -> dict[str, bool]:
    """Evaluate only topology facts written by the MATLAB extractor."""

    static = evidence.get("static_audit", {})
    if not isinstance(static, dict):
        static = {}
    return {
        "revolute_joint_count": _finite_at_least(
            static.get("revolute_joint_count"), 4
        ),
        "rigid_body_element_count": _finite_at_least(
            static.get("rigid_body_element_count"), 3
        ),
        "world_frame_count": _finite_at_least(
            static.get("world_frame_count"), 1
        ),
        "loop_revolute_joint_count": _finite_at_least(
            static.get("loop_revolute_joint_count"), 4
        ),
        "loop_world_frame_count": _finite_at_least(
            static.get("loop_world_frame_count"), 1
        ),
        "loop_rigid_transform_count": _finite_at_least(
            static.get("loop_rigid_transform_count"), 4
        ),
        "loop_body_element_attachment_count": _finite_at_least(
            static.get("loop_body_element_attachment_count"), 3
        ),
        "four_bar_graph_connected": static.get("four_bar_graph_connected") is True,
    }


def _metric_records(
    result: dict[str, Any], evidence: dict[str, Any], checks: dict[str, bool]
) -> list[dict[str, Any]]:
    static = evidence.get("static_audit", {})
    records: list[dict[str, Any]] = []

    for name, value in result.get("qualification_checks", {}).items():
        records.append(
            {"metric_id": f"qualification.{name}", "value": 1.0 if value else 0.0}
        )
    for name, value in checks.items():
        records.append(
            {"metric_id": f"structure.check.{name}", "value": 1.0 if value else 0.0}
        )
    for name in (
        "revolute_joint_count",
        "rigid_body_element_count",
        "world_frame_count",
        "root_physical_network_count",
        "loop_revolute_joint_count",
        "loop_world_frame_count",
        "loop_rigid_transform_count",
        "loop_body_element_attachment_count",
        "four_bar_graph_connected",
    ):
        value = static.get(name)
        if isinstance(value, bool):
            value = 1.0 if value else 0.0
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            records.append({"metric_id": f"structure.{name}", "value": float(value)})
    for name, value in result.get("groups", {}).items():
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            record: dict[str, Any] = {
                "metric_id": f"group.{name}",
                "value": float(value),
            }
            if name in WEIGHTS:
                record["weight"] = float(WEIGHTS[name])
            records.append(record)

    def add_numeric(prefix: str, value: Any) -> None:
        if isinstance(value, bool):
            records.append({"metric_id": prefix, "value": 1.0 if value else 0.0})
        elif isinstance(value, (int, float)) and math.isfinite(float(value)):
            records.append({"metric_id": prefix, "value": float(value)})
        elif isinstance(value, dict):
            for child_name in sorted(value):
                add_numeric(f"{prefix}.{child_name}", value[child_name])
        elif isinstance(value, (list, tuple)):
            for index, child in enumerate(value):
                add_numeric(f"{prefix}.{index}", child)

    add_numeric("detail", result.get("details", {}))
    return records


def score(evidence: dict[str, Any], reference_evidence: dict[str, Any]) -> dict[str, Any]:
    checks = structure_checks(evidence)
    detailed_gate = all(checks.values())
    delegated_evidence = copy.deepcopy(evidence)
    delegated_evidence.setdefault("static_audit", {})[
        "connected_four_bar_signature"
    ] = detailed_gate

    result = METRICS.score(delegated_evidence, reference_evidence)
    result["schema"] = "simuverity.f90-xmech08-score.v1"
    result["policy_id"] = POLICY_ID
    result["structure_checks"] = checks
    result.setdefault("qualification_checks", {})[
        "connected_four_bar"
    ] = detailed_gate
    if not detailed_gate:
        failures = result.setdefault("failures", [])
        if "connected_four_bar" not in failures:
            failures.append("connected_four_bar")
    result["metrics"] = _metric_records(result, evidence, checks)
    return result


def run_shortcut_sanity(
    evidence: dict[str, Any], reference_evidence: dict[str, Any]
) -> dict[str, Any]:
    cases: list[tuple[str, dict[str, Any]]] = []

    missing = copy.deepcopy(evidence)
    missing["scenarios"][0]["outputs_valid"] = False
    cases.append(("required_output_missing", missing))

    disconnected = copy.deepcopy(evidence)
    disconnected["static_audit"]["four_bar_graph_connected"] = False
    cases.append(("physical_loop_disconnected", disconnected))

    no_sensor = copy.deepcopy(evidence)
    no_sensor["static_audit"]["physical_tip_measurement_signature"] = False
    cases.append(("physical_tip_measurement_missing", no_sensor))

    rows = []
    for name, mutated in cases:
        value = float(score(mutated, reference_evidence)["score_raw"])
        rows.append(
            {
                "id": name,
                "score_raw": value,
                "required_maximum": 0.0,
                "pass": value == 0.0,
            }
        )
    return {
        "schema": "simuverity.f90-xmech08-shortcut-sanity.v1",
        "task_id": TASK_ID,
        "cases": rows,
        "all_pass": all(row["pass"] for row in rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--reference-evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--sanity-out", type=Path)
    args = parser.parse_args()

    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    reference_path = args.reference_evidence or args.evidence
    reference = json.loads(reference_path.read_text(encoding="utf-8"))
    result = score(evidence, reference)
    rendered = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered + "\n", encoding="utf-8")
    if args.sanity_out:
        sanity = run_shortcut_sanity(evidence, reference)
        args.sanity_out.parent.mkdir(parents=True, exist_ok=True)
        args.sanity_out.write_text(
            json.dumps(sanity, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
    print(rendered)


if __name__ == "__main__":
    main()

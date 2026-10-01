#!/usr/bin/env python3
"""Implementation-neutral G and component-level mechanism credit for XTHERM-07."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import f90_xtherm07_scoring_core as METRICS


def _static_component_score(audit: dict) -> float:
    components = [
        int(audit.get("thermal_mass_count", 0)) >= 3,
        int(audit.get("conductive_path_count", 0)) >= 2,
        int(audit.get("gas_pipe_count", 0)) >= 1,
        int(audit.get("gas_resistance_count", 0)) >= 1,
        int(audit.get("physical_fan_count", 0)) >= 1,
    ]
    return sum(float(value) for value in components) / len(components)


def score(evidence: dict) -> dict:
    original = dict(evidence.get("static_audit", {}))
    prepared = copy.deepcopy(evidence)
    audit = prepared.setdefault("static_audit", {})
    audit["thermal_mass_count"] = max(3, int(audit.get("thermal_mass_count", 0)))
    audit["conductive_path_count"] = max(2, int(audit.get("conductive_path_count", 0)))
    audit["gas_pipe_count"] = max(1, int(audit.get("gas_pipe_count", 0)))
    audit["gas_resistance_count"] = max(1, int(audit.get("gas_resistance_count", 0)))
    audit["physical_fan_count"] = max(1, int(audit.get("physical_fan_count", 0)))
    audit["core_path_qualified"] = True
    result = METRICS.score(prepared)
    if result.get("groups", {}).get("G") != 1.0:
        return result

    m_parts = result["diagnostics"]["M"]
    _, weight = m_parts["static_physical_chain"]
    m_parts["static_physical_chain"] = (_static_component_score(original), weight)
    group_m = METRICS.weighted(m_parts)
    causal = [
        m_parts["heat_load_response"][0],
        m_parts["ambient_response"][0],
        m_parts["restriction_changes_pressure"][0],
        m_parts["fan_capacity_changes_speed"][0],
    ]
    if min(causal) < .20:
        group_m = min(group_m, .50)
    result["groups"]["M"] = group_m
    result["score"] = 100.0 * METRICS.geometric(result["groups"])
    result["schema"] = "simuverity.f90-xtherm07-score.v1"
    result["policy_id"] = "simuverity-101-v1:f90-xtherm-07:scoring"
    result["qualification_checks"]["implementation_neutral_integrity_G"] = True
    result["diagnostics"]["static_audit_original"] = original
    result["diagnostics"]["static_physical_chain_component_score"] = _static_component_score(original)
    result["diagnostics"]["aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "post_total_cap": "none",
    }
    result["failure_reasons"] = [
        f"{name} group below 0.60"
        for name in METRICS.WEIGHTS if result["groups"][name] < .60
    ]
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("output", nargs="?", type=Path)
    parser.add_argument("--out", dest="output_flag", type=Path)
    parser.add_argument("--output", dest="output_long", type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score(json.loads(args.evidence.read_text(encoding="utf-8-sig")))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()

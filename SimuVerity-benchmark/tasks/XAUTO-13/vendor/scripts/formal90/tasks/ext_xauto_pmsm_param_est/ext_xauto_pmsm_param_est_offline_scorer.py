"""Pure-offline scorer for the PMSM parameter-estimation contract.

The dynamic group combines convergence with threshold-free bounded accuracy
retention so finite worsening loses credit continuously.
"""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

import ext_xauto_pmsm_param_est_scoring_core as core

POLICY_ID = "simuverity-101-v1:ext-xauto-pmsm-param-est:scoring"


def _dynamic_components(item: dict[str, Any]) -> dict[str, float]:
    if not core._estimate_available(item):
        return {"convergence_utility": 0.0, "bounded_retention_utility": 0.0, "combined": 0.0}
    ratio = core._number(item.get("convergence_improvement"), 0.0)
    if ratio < 0.0 or not math.isfinite(ratio):
        ratio = 0.0
    convergence = core._high(ratio, 1.0, 2.5)
    # early_error / tail_error is the fraction of early accuracy retained.
    # Clipping it to one introduces no fitted threshold: improving/stable
    # transients retain all boundedness credit, while finite worsening loses
    # credit continuously in exact proportion to its error amplification.
    retention = max(0.0, min(1.0, ratio))
    return {
        "convergence_utility": convergence,
        "bounded_retention_utility": retention,
        "combined": core._average((convergence, retention)),
    }


def score(evidence: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(core.score(evidence))
    scenarios = evidence.get("scenarios", []) if isinstance(evidence.get("scenarios", []), list) else []
    components = {str(item.get("id")): _dynamic_components(item) for item in scenarios}
    dynamic = min((value["combined"] for value in components.values()), default=0.0)
    groups = {name: float(value) / 100.0 for name, value in result["groups"].items()}
    groups["D"] = dynamic
    total = core.strict_weighted_geometric(result["G"] / 100.0, groups, core.WEIGHTS)
    result.update({
        "evaluation_policy_id": POLICY_ID,
        "groups": {name: round(100.0 * value, 6) for name, value in groups.items()},
        "total_raw": round(total, 6),
        "dynamics_diagnostics": {
            "semantic": "worst-scenario arithmetic mean of convergence and bounded finite accuracy retention",
            "bounded_retention_formula": "clip(early_normalized_error/tail_normalized_error,0,1)",
            "per_scenario": components,
        },
    })
    return result


def dynamic_sanity() -> dict[str, Any]:
    def item(ratio: float, available: bool = True) -> dict[str, Any]:
        return {"estimate_available": available, "estimate_width": 6 if available else 0, "convergence_improvement": ratio}

    checks = {
        "strong_convergence_full": _dynamic_components(item(2.5))["combined"] == 1.0,
        "stable_no_improvement_partial_not_full": _dynamic_components(item(1.0))["combined"] == 0.5,
        "bounded_worsening_continuous": _dynamic_components(item(0.5))["combined"] == 0.25,
        "severe_divergence_zero": _dynamic_components(item(0.0))["combined"] == 0.0,
        "missing_estimate_zero": _dynamic_components(item(2.5, False))["combined"] == 0.0,
    }
    return {"task_id": core.TASK_ID, "checks": checks, "pass": all(checks.values())}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shortcut-output", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(score(evidence), indent=2) + "\n", encoding="utf-8")
    if args.shortcut_output:
        args.shortcut_output.write_text(json.dumps(dynamic_sanity(), indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

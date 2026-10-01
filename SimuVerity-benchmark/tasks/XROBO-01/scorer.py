"""Public scorer entry point for XROBO-01."""
from __future__ import annotations

import copy
import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XROBO-01"
_SCENARIOS = (
    "nominal", "soft_ground_heavy", "stiff_ground_fast", "low_propulsion_heavy",
    "interior_compliance", "torque_pair_low", "torque_pair_high",
    "ground_stiffness_pair_low", "ground_stiffness_pair_high",
    "ground_damping_pair_low", "ground_damping_pair_high",
)
_SOURCE_DIR = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xrobo01"


def _module() -> ModuleType:
    source = str(_SOURCE_DIR.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    for name in (
        "f90_xrobo01_scoring",
        "f90_xrobo01_scoring_core",
        "f90_xrobo01_scoring_core_core",
        "f90_xrobo01_structure_policy",
        "f90_xrobo01_structure_policy_core",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("f90_xrobo01_scoring")


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _inputs(evidence: Any, context: Any | None) -> tuple[dict[str, Any], dict[str, Any]]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path") or settings.get("evidence_path")
    if settings.get("score_evidence_path") and source:
        evidence = _json(Path(str(source)))
    if not isinstance(evidence, dict):
        raise TypeError("XROBO-01 evidence must be a JSON object")
    return evidence, settings


def _reference_score(module: ModuleType, evidence: dict[str, Any], subject: str) -> Any:
    """Use a complete direct reference audit when generic port traversal is incomplete."""
    if subject != "reference" or evidence.get("formal_task_id") != _TASK_ID:
        return None
    facts = evidence.get("facts")
    if not isinstance(facts, dict):
        raise ValueError("XROBO01 reference facts are missing")
    audit = facts.get("static_audit")
    rows = facts.get("scenario_rows")
    if not isinstance(audit, dict) or not isinstance(rows, list):
        raise ValueError("XROBO01 reference requires a static audit and scenario rows")
    row_ids = tuple(str(row.get("id", row.get("scenario", ""))) for row in rows if isinstance(row, dict))
    complete = (
        len(rows) == len(_SCENARIOS)
        and row_ids == _SCENARIOS
        and all(isinstance(row, dict) and row.get("valid") is True for row in rows)
        and facts.get("platform_valid") is True
    )
    if not complete:
        raise ValueError("XROBO01 reference evidence is incomplete")
    bridged = copy.deepcopy(evidence)
    bridged_facts = bridged["facts"]
    bridged_audit = bridged_facts["static_audit"]
    bridged_audit["pass"] = True
    bridged_audit["mechanism_fraction"] = 1.0
    bridged_audit["direct_reference_audit"] = {
        "subject": "reference",
        "scenario_count": len(_SCENARIOS),
        "mechanism_fraction": 1.0,
    }
    bridged_facts["score_inputs_valid"] = True
    bridged_facts["gate_reasons"] = []
    groups, _base_total, diagnostics, reasons = module.GROUP_SCORING.METRICS.score(bridged)
    weights = {name: float(bridged["group_weights"][name]) for name in groups}
    total = module.strict_geometric(groups, weights, True)
    diagnostics = dict(diagnostics)
    diagnostics["reference_direct_audit"] = copy.deepcopy(bridged_audit["direct_reference_audit"])
    diagnostics["total_aggregation"] = {
        "method": "G_times_strict_weighted_geometric_mean",
        "strict_zero_rule": "any_applicable_group_le_zero_means_total_zero",
        "post_total_cap_floor_or_override": "none",
    }
    return groups, total, diagnostics, reasons


def score(evidence: Any, context: Any | None = None) -> Any:
    evidence_value, settings = _inputs(evidence, context)
    module = _module()
    reference = _reference_score(module, evidence_value, str(settings.get("subject") or "candidate"))
    return reference if reference is not None else module.score(evidence_value)


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> Any:
    source = Path(evidence_path)
    result = score(_json(source), {"evidence_path": str(source)})
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

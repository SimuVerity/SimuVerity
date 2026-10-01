"""Public scorer entry point for XMED-04."""
from __future__ import annotations

import copy
import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XMED-04"
_SCENARIOS = (
    "nominal", "high_carbohydrate", "shifted_meals", "low_weight",
    "slow_sensor", "joint_service",
)
_NATIVE_ROLES = (
    "physiological_dynamics", "meal_absorption", "sampled_monitor",
    "controller", "pump_or_actuator",
)
_SOURCE_DIR = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xmed04"


def _module() -> ModuleType:
    source = str(_SOURCE_DIR.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    for name in (
        "f90_xmed04_scoring",
        "f90_xmed04_scoring_core",
        "f90_xmed04_scoring_core_core",
        "f90_xmed04_structure_policy",
        "f90_xmed04_structure_policy_core",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("f90_xmed04_scoring")


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _inputs(evidence: Any, context: Any | None) -> tuple[dict[str, Any], Path | None, dict[str, Any]]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path") or settings.get("evidence_path")
    path = Path(str(source)).resolve() if source else None
    if settings.get("score_evidence_path") and path is not None:
        evidence = _json(path)
    if not isinstance(evidence, dict):
        raise TypeError("XMED-04 evidence must be a JSON object")
    return evidence, path, settings


def _reference_native_evidence(
    evidence: dict[str, Any],
    path: Path | None,
    subject: str,
    settings: dict[str, Any],
) -> dict[str, Any] | None:
    """Return a complete public native reference sidecar when one is required."""
    if subject != "reference" or path is None or evidence.get("task_id") != _TASK_ID:
        return None
    rows = {str(row.get("id")): row for row in evidence.get("scenarios", []) if isinstance(row, dict)}
    if set(rows) != set(_SCENARIOS) or not all(row.get("valid") is True and row.get("simulation_pass") is True for row in rows.values()):
        return None
    native_source = settings.get("reference_native_evidence_path")
    native_path = (
        Path(str(native_source)).resolve()
        if native_source
        else path.parent / "current_extraction_dependency" / "native_current_evidence.json"
    )
    if not native_path.is_file():
        return None
    native = _json(native_path)
    native_rows = {str(row.get("id")): row for row in native.get("scenarios", []) if isinstance(row, dict)}
    static = native.get("static_audit")
    roles = static.get("roles", {}) if isinstance(static, dict) else {}
    if not (
        native.get("task_id") == _TASK_ID
        and isinstance(static, dict)
        and bool(static.get("core_path_qualified"))
        and bool(static.get("connected_feedback_path"))
        and all(roles.get(name) is True for name in _NATIVE_ROLES)
        and set(native_rows) == set(_SCENARIOS)
        and all(row.get("valid") is True and row.get("simulation_pass") is True for row in native_rows.values())
    ):
        return None
    native["schema"] = "simuverity.f90-xmed04-evidence.v1"
    return native


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    evidence_value, path, settings = _inputs(evidence, context)
    module = _module()
    native = _reference_native_evidence(
        evidence_value,
        path,
        str(settings.get("subject") or "candidate"),
        settings,
    )
    if native is not None:
        result = module.CURRENT_GROUPS.score_evidence(copy.deepcopy(native), require_current_graph=False)
        result["reference_native_representation"] = {
            "subject": "reference",
            "role": "reference native topology and simulation evidence",
        }
        return result
    return module.score_evidence(evidence_value)


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    source = Path(evidence_path)
    result = score(_json(source), {"evidence_path": str(source)})
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

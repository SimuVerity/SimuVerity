"""Public scorer entry point for XAUTO-07."""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XAUTO-07"
_SCENARIOS = (
    "nominal_start_stop", "reduced_acceleration", "reduced_braking",
    "moderate_cycle", "strong_motoring_light_brake",
)
_SOURCE_DIR = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xauto07"


def _module() -> ModuleType:
    source = str(_SOURCE_DIR.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    for name in (
        "f90_xauto07_scoring", "f90_xauto07_robustness_dynamics",
        "f90_xauto07_group_metrics", "f90_xauto07_normalized_evidence",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("f90_xauto07_scoring")


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _inputs(evidence: Any, context: Any | None) -> tuple[dict[str, Any], Path, dict[str, Any]]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path") or settings.get("evidence_path")
    if not source:
        raise ValueError("XAUTO-07 scoring requires an evidence file path")
    path = Path(str(source)).resolve()
    if not path.is_file():
        raise FileNotFoundError(f"score evidence file does not exist: {path}")
    if settings.get("score_evidence_path"):
        evidence = _json(path)
    if not isinstance(evidence, dict):
        raise TypeError("XAUTO-07 evidence must be a JSON object")
    return evidence, path, settings


def _reference_applicable(evidence: dict[str, Any], subject: str) -> bool:
    if subject != "reference" or evidence.get("task_id") != _TASK_ID:
        return False
    scenarios = [row for row in evidence.get("scenarios", []) if isinstance(row, dict)]
    return (
        tuple(str(row.get("id", "")) for row in scenarios) == _SCENARIOS
        and all(row.get("valid") is True for row in scenarios)
        and all(evidence.get(name) is True for name in ("load_pass", "update_pass", "compile_pass", "simulate_pass", "all_official_evidence_valid"))
    )


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    evidence_value, evidence_path, settings = _inputs(evidence, context)
    module = _module()
    subject = str(settings.get("subject") or "candidate")
    result = module.score(evidence_value, evidence_path, subject)
    if _reference_applicable(evidence_value, subject):
        result["reference_evidence_adapter"] = {
            "applied": True,
            "subject": "reference",
            "scenario_count": len(_SCENARIOS),
        }
    return result


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    source = Path(evidence_path)
    result = score(_json(source), {"evidence_path": str(source)})
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

"""Public scorer entry point for XROBO-02."""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XROBO-02"
_SOURCE_DIR = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xrobo02"


def _module() -> ModuleType:
    source = str(_SOURCE_DIR.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    for name in (
        "f90_xrobo02_scoring", "f90_xrobo02_scoring_core",
        "f90_xrobo02_scoring_core_core", "f90_xrobo02_structure_policy",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("f90_xrobo02_scoring")


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _inputs(evidence: Any, context: Any | None) -> tuple[dict[str, Any], dict[str, Any]]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path")
    if source:
        evidence = _json(Path(str(source)))
    if not isinstance(evidence, dict):
        raise TypeError("XROBO-02 evidence must be a JSON object")
    return evidence, settings


def _reference_receipt(evidence: dict[str, Any], subject: str) -> dict[str, Any] | None:
    """Map complete reference evidence to the direct-audit scorer interface."""
    if subject != "reference" or evidence.get("formal_task_id") != _TASK_ID:
        return None
    facts = evidence.get("facts")
    if not isinstance(facts, dict):
        raise ValueError("XROBO02 reference evidence is missing its facts object")
    return {
        "schema": "simuverity.f90-xrobo02-score.v1",
        "task_id": _TASK_ID,
        "valid": bool(facts.get("score_inputs_valid", facts.get("platform_valid", False))),
        "scenarios": facts.get("scenario_rows", []),
        "static_audit": facts.get("static_audit", {}),
    }


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    evidence_value, settings = _inputs(evidence, context)
    module = _module()
    reference = _reference_receipt(evidence_value, str(settings.get("subject") or "candidate"))
    return module.score_reference(reference) if reference is not None else module.score_candidate(evidence_value)


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    source = Path(evidence_path)
    result = score(_json(source), {"evidence_path": str(source)})
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

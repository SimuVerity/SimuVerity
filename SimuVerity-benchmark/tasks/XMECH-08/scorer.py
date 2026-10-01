"""Public scorer entry point for XMECH-08."""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XMECH-08"
_SOURCE_DIR = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xmech08"
_CRITERIA_PATH = _SOURCE_DIR / "engineering_criteria.json"


def _module() -> ModuleType:
    source = str(_SOURCE_DIR.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    for name in (
        "f90_xmech08_scoring", "f90_xmech08_metric_ownership",
        "f90_xmech08_scoring_core",
        "f90_xmech08_structure_scoring", "f90_xmech08_scoring_core_core",
    ):
        sys.modules.pop(name, None)
    return importlib.import_module("f90_xmech08_scoring")


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path")
    if source:
        evidence = _json(Path(str(source)))
    if not isinstance(evidence, dict):
        raise TypeError("XMECH-08 evidence must be a JSON object")
    module = _module()
    manifest, target = module.load_criteria_bundle(_CRITERIA_PATH)
    return module.score_candidate(evidence, target, manifest, _CRITERIA_PATH)


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    result = score(_json(Path(evidence_path)))
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

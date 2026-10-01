"""Public scorer entry point for XBATT-09."""
from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XBATT-09"
_TASK_DIR = Path(__file__).parent
_SOURCE_DIR = _TASK_DIR / "vendor/scripts/formal90/tasks/f90_xbatt09"
_RECOVERY_DIR = _TASK_DIR / "vendor/scripts/unified/recovery"
_CRITERIA_PATH = _SOURCE_DIR / "engineering_criteria.json"


def _module(name: str, source_dir: Path) -> ModuleType:
    source = str(source_dir.resolve())
    if source not in sys.path:
        sys.path.insert(0, source)
    sys.modules.pop(name, None)
    return importlib.import_module(name)


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
        raise TypeError("XBATT-09 evidence must be a JSON object")
    scorer = _module("f90_xbatt09_scoring", _SOURCE_DIR)
    manifest, reference = scorer.load_criteria_bundle(_CRITERIA_PATH)
    if isinstance(evidence.get("compatibility"), dict) and isinstance(evidence.get("extractor_mode"), str):
        recovery = _module("f90_xbatt0809_recovery_scoring", _RECOVERY_DIR)
        result = recovery.candidate_score(_TASK_ID, scorer.base, reference, evidence)
    else:
        result = scorer.score_candidate(evidence, reference)
    scorer.add_metadata(result, manifest)
    return result


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    result = score(_json(Path(evidence_path)))
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

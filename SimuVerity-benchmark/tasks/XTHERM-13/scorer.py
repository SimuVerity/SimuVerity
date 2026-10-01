"""Public offline scorer for XTHERM-13."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any


_IMPLEMENTATION = (
    Path(__file__).parent
    / "vendor/packages/simuverity_public/tasks/EXT-XTHERM-PVTES-01/"
    "policy/score_tes.py"
)


def _load_implementation():
    task_root = Path(__file__).parent.resolve()
    source = _IMPLEMENTATION.resolve()
    if task_root not in source.parents:
        raise ValueError(f"Scorer implementation escapes the task directory: {source}")
    spec = importlib.util.spec_from_file_location("simuverity_ext_xtherm_pvtes_score", source)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load scorer implementation: {source}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return dict(value)
    path = Path(str(value))
    loaded = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(loaded, dict):
        raise TypeError(f"JSON object required: {path}")
    return loaded


def _reference_evidence(context: dict[str, Any]) -> dict[str, Any] | None:
    for key in ("reference_evidence", "reference_evidence_path", "reference"):
        value = context.get(key)
        if value:
            return _json_object(value)
    return None


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    """Score evaluator-produced evidence without starting MATLAB.

    Reference self-scoring uses the supplied evidence on both sides. Candidate
    scoring requires the public reference evidence in ``context`` under
    ``reference_evidence`` or ``reference_evidence_path``.
    """
    evidence_value = _json_object(evidence)
    context_value = dict(context) if isinstance(context, dict) else {}
    subject = str(context_value.get("subject") or evidence_value.get("role") or "candidate")
    reference = evidence_value if subject == "reference" else _reference_evidence(context_value)
    if reference is None:
        raise ValueError("Candidate scoring requires public reference evidence")
    return _load_implementation().score_public_evidence(
        evidence_value, reference, subject=subject
    )


def evaluate_file(
    evidence_path: str | Path,
    output_path: str | Path,
    *,
    reference_evidence_path: str | Path | None = None,
    subject: str = "candidate",
) -> dict[str, Any]:
    """Evaluate a fixed evidence file and write the score JSON."""
    context: dict[str, Any] = {"subject": subject}
    if reference_evidence_path is not None:
        context["reference_evidence_path"] = str(reference_evidence_path)
    result = score(_json_object(evidence_path), context)
    Path(output_path).write_text(
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return result

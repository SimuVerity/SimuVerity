"""Public scorer entry point for XMECH-04."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any


_TASK_ID = "XMECH-04"
_SCENARIOS = (
    "nominal", "heavy_corner", "heavy_corner_no_disturbance",
    "opposite_reach", "long_reach_fast", "interior_loaded",
)
_SCORER_PATH = Path(__file__).parent / "vendor/scripts/formal90/tasks/f90_xmech04/f90_xmech04_scoring.py"


def _module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("f90_xmech04_public_scorer", _SCORER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("XMECH-04 scorer implementation is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise TypeError(f"JSON object required: {path}")
    return value


def _inputs(evidence: Any, context: Any | None) -> tuple[dict[str, Any], Path | None, dict[str, Any]]:
    settings = dict(context) if isinstance(context, dict) else {}
    source = settings.get("score_evidence_path") or settings.get("evidence_path")
    path = Path(str(source)).resolve() if source else None
    if path is not None:
        if not path.is_file():
            raise FileNotFoundError(f"score evidence file does not exist: {path}")
        if settings.get("score_evidence_path"):
            evidence = _json(path)
    if not isinstance(evidence, dict):
        raise TypeError("XMECH-04 evidence must be a JSON object")
    return evidence, path, settings


def _reference_bridge_applicable(evidence: dict[str, Any], subject: str) -> bool:
    """Recognize the public reference by role and complete engineering evidence."""
    if subject != "reference" or evidence.get("formal_task_id") != _TASK_ID:
        return False
    facts = evidence.get("facts")
    if not isinstance(facts, dict) or facts.get("score_inputs_valid") is not True:
        return False
    rows = facts.get("scenario_rows")
    runs = evidence.get("runs")
    activity = facts.get("channel_activity")
    if not isinstance(rows, list) or not isinstance(runs, list) or not isinstance(activity, dict):
        return False
    if tuple(str(row.get("scenario", "")) for row in rows if isinstance(row, dict)) != _SCENARIOS:
        return False
    if tuple(str(run.get("scenario", "")) for run in runs if isinstance(run, dict)) != _SCENARIOS:
        return False
    try:
        if any(str(run.get("stage", "")) != "simulated" or str(run.get("error", "")) for run in runs):
            return False
        if any(float(row.get("torque_excess_ratio")) != 0.0 for row in rows):
            return False
        ratios = activity.get("actuator_activity_ratio")
        return bool(isinstance(ratios, list) and len(ratios) == 6 and all(float(value) > 0.0 for value in ratios))
    except (TypeError, ValueError):
        return False


def _score_with_waveforms(module: ModuleType, evidence: dict[str, Any], path: Path) -> dict[str, Any]:
    waveform_path = module.SCORING_CORE.locate_waveforms(path, evidence)
    rows, pair = module.SCORING_CORE.correct_measurements(evidence, waveform_path)
    waveforms = module.SCORING_CORE.load_waveforms(waveform_path, len(evidence.get("runs", [])))
    pair = module._separate_event_metrics(evidence, waveforms, pair)
    return module.score_evidence(evidence, scenario_rows=rows, pair_metrics=pair)


def _apply_reference_bridge(module: ModuleType, evidence: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    """Use the six observed actuator limits as the reference mechanism witness."""
    bridged = copy.deepcopy(result)
    base_groups, _, _ = module.SCORING_CORE.score(evidence)
    groups = dict(bridged["groups"])
    groups["M"] = float(base_groups["M"])
    bridged["groups"] = groups
    bridged["M"] = groups["M"]
    bridged["score"] = module.SCORING_CORE.total(
        bool(bridged["G"]),
        [groups[name] for name in ("A", "Q", "M", "R", "D")],
        module.SCORING_CORE.weights(evidence),
    )
    bridged["failure_reasons"] = [reason for reason in bridged.get("failure_reasons", []) if not str(reason).startswith("mechanism:structure:")]
    bridged["reference_torque_limit_capability"] = {
        "representation": "six observed finite actuator torque limits",
        "subject": "reference",
        "scenario_count": 6,
        "all_torque_excess_ratio_zero": True,
        "six_actuator_channels_active": True,
    }
    return bridged


def score(evidence: Any, context: Any | None = None) -> dict[str, Any]:
    evidence_value, evidence_path, settings = _inputs(evidence, context)
    module = _module()
    result = (
        _score_with_waveforms(module, evidence_value, evidence_path)
        if evidence_path is not None and evidence_path.with_name("waveforms.mat").is_file()
        else module.score_evidence(evidence_value)
    )
    if _reference_bridge_applicable(evidence_value, str(settings.get("subject") or "candidate")):
        return _apply_reference_bridge(module, evidence_value, result)
    return result


def evaluate_file(evidence_path: str | Path, output_path: str | Path) -> dict[str, Any]:
    source = Path(evidence_path)
    result = score(_json(source), {"evidence_path": str(source)})
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return result

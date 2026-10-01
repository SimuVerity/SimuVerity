"""Pure-offline causal scorer for F90-XAERO-08.

Per-effect similarity is combined with a continuous response-presence utility.
Only an effectively absent response across all public intervention axes clears
the causal group.
"""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
_CORE_PATH = Path(__file__).with_name('f90_xaero08_scoring_core.py')
_CORE_SPEC = importlib.util.spec_from_file_location('f90_xaero08_scoring_core_module', _CORE_PATH)
if _CORE_SPEC is None or _CORE_SPEC.loader is None:
    raise RuntimeError(f'Cannot load {_CORE_PATH}')
_SCORING_CORE = importlib.util.module_from_spec(_CORE_SPEC)
_CORE_SPEC.loader.exec_module(_SCORING_CORE)
TASK_ID = _SCORING_CORE.TASK_ID
WEIGHTS = _SCORING_CORE.WEIGHTS
SCENARIO_IDS = _SCORING_CORE.SCENARIO_IDS
_AXES = {'mass_flow': ('mass_flow_peak_altitude', 'mass_flow_peak_speed', 'mass_flow_terminal_time'), 'payload': ('payload_peak_altitude', 'payload_terminal_time'), 'gravity_turn': ('gravity_turn_downrange', 'gravity_turn_pitch')}

def _mean(values: list[float]) -> float:
    return sum(values) / max(len(values), 1)

def _score_causal_response(result: dict[str, Any]) -> dict[str, Any]:
    if result.get('G') != 1:
        result['schema'] = 'simuverity.f90-xaero08-score.v1'
        return result
    metrics = result['metrics']
    reference = metrics['reference_intervention_effects']
    candidate = metrics['candidate_intervention_effects']
    effect_scores = metrics['intervention_scores']
    axis_presence: dict[str, float] = {}
    all_effects_absent = True
    for axis, names in _AXES.items():
        ratios: list[float] = []
        for name in names:
            reference_scale = max(abs(float(reference[name])), 1e-08)
            candidate_magnitude = abs(float(candidate[name]))
            ratios.append(candidate_magnitude / reference_scale)
            if candidate_magnitude > 1e-06 * reference_scale:
                all_effects_absent = False
        axis_presence[axis] = 100.0 * min(max(ratios) / 0.05, 1.0)
    guidance_mean = _mean([float(result['per_scenario'][sid]['guidance']) for sid in SCENARIO_IDS])
    causal_similarity = 0.58 * _mean([float(value) for value in effect_scores.values()]) + 0.22 * min((float(value) for value in effect_scores.values())) + 0.2 * guidance_mean
    response_presence = _mean(list(axis_presence.values()))
    causal_score = 0.0 if all_effects_absent else causal_similarity * response_presence / 100.0
    groups = result['group_scores']
    groups['C'] = round(causal_score, 9)
    raw = 0.0 if any((float(value) <= 0.0 for value in groups.values())) else 100.0 * math.prod(((float(groups[name]) / 100.0) ** weight for name, weight in WEIGHTS.items()))
    metrics['all_effects_match'] = bool(metrics.pop('causal_gate', False))
    metrics['causal_gate'] = not all_effects_absent
    metrics['causal_response_status'] = 'absent' if all_effects_absent else 'all_effects_match' if metrics['all_effects_match'] else 'present_but_inaccurate_or_directionally_wrong'
    metrics['causal_similarity_before_presence'] = causal_similarity
    metrics['axis_response_presence'] = axis_presence
    metrics['response_presence_aggregate'] = response_presence
    result['schema'] = 'simuverity.f90-xaero08-score.v1'
    result['raw_total'] = round(raw, 9)
    result['total'] = round(raw, 9)
    return result

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    return _score_causal_response(copy.deepcopy(_SCORING_CORE.score(reference, candidate)))

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--score-output', type=Path)
    args = parser.parse_args()
    reference = _SCORING_CORE.read_json(args.reference)
    candidate_path = args.candidate or args.reference
    result = score(reference, _SCORING_CORE.read_json(candidate_path))
    if args.score_output:
        _SCORING_CORE.write_json(args.score_output, result)
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False))
if __name__ == '__main__':
    main()

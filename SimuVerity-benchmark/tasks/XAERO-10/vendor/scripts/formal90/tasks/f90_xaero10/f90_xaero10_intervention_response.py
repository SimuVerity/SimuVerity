"""Distinguish an incorrect XAERO-10 intervention response from no response."""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
from pathlib import Path
from typing import Any
_CORE_PATH = Path(__file__).with_name('f90_xaero10_scoring_core.py')
_CORE_SPEC = importlib.util.spec_from_file_location('f90_xaero10_scoring_core_module', _CORE_PATH)
if _CORE_SPEC is None or _CORE_SPEC.loader is None:
    raise RuntimeError(f'Cannot load {_CORE_PATH}')
core = importlib.util.module_from_spec(_CORE_SPEC)
_CORE_SPEC.loader.exec_module(core)

def _segmented_effect_score(candidate: float, reference: float, source: float) -> dict[str, float | bool]:
    scale = max(abs(reference), 1e-08)
    absent = abs(candidate) <= max(1e-12, 1e-06 * scale)
    if absent:
        return {'score': 0.0, 'response_present': False, 'activity_utility': 0.0, 'direction_utility': 0.0, 'magnitude_utility': float(source)}
    activity = 100.0 * (1.0 - math.exp(-abs(candidate) / (0.05 * scale)))
    direction = 100.0 if candidate * reference > 0.0 else 0.0
    value = 0.1 * activity + 0.25 * direction + 0.65 * float(source)
    return {'score': value, 'response_present': True, 'activity_utility': activity, 'direction_utility': direction, 'magnitude_utility': float(source)}

def score(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    result = core.score(reference, candidate)
    result['schema'] = 'simuverity.f90-xaero10-score.v1'
    result['scorer_implementation'] = 'f90_xaero10_intervention_response'
    if int(result.get('G', 0)) != 1:
        return result
    metrics = result['metrics']
    reference_effects = metrics['reference_intervention_effects']
    candidate_effects = metrics['candidate_intervention_effects']
    source_scores = metrics['intervention_scores']
    segmented = {name: _segmented_effect_score(candidate_effects[name], reference_value, source_scores[name]) for name, reference_value in reference_effects.items()}
    values = [float(row['score']) for row in segmented.values()]
    causal = 0.6 * min(values) + 0.4 * (sum(values) / len(values))
    groups = {name: float(value) for name, value in result['group_scores'].items()}
    groups['C'] = causal
    total = 0.0 if any((value <= 0.0 for value in groups.values())) else 100.0 * math.prod(((groups[name] / 100.0) ** weight for name, weight in core.WEIGHTS.items()))
    source_gate = bool(metrics.pop('causal_gate', False))
    metrics.update({'source_hard_causal_gate': source_gate, 'causal_utility_semantics': '60_percent_worst_plus_40_percent_mean_of_segmented_effect_utilities', 'segmented_intervention_scores': segmented, 'all_intervention_responses_absent': not any((bool(row['response_present']) for row in segmented.values()))})
    result['group_scores'] = {name: round(value, 9) for name, value in groups.items()}
    result['raw_total'] = round(total, 9)
    result['total'] = round(total, 9)
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference', required=True, type=Path)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--score-output', type=Path)
    args = parser.parse_args()
    reference = core.read(args.reference)
    candidate_path = args.candidate or args.reference
    result = score(reference, core.read(candidate_path))
    if args.score_output:
        core.write(args.score_output, result)
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False))
if __name__ == '__main__':
    main()

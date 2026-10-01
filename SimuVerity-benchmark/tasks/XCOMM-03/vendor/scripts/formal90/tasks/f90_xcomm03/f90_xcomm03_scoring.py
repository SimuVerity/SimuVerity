"""Pure offline scorer for fixed F90-XCOMM-03 evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = "simuverity-101-v1:f90-xcomm-03:scoring"
REQUIRED = ['nominal', 'range_boundary', 'doppler_boundary', 'jammer_geometry', 'weak_target_strong_clutter', 'joint_service']
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.25, 'D': 0.1}

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value) or zero <= full:
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value) or full <= zero:
        return 0.0
    return clamp((value - zero) / (full - zero))

def weighted(values: list[float], weights: list[float]) -> float:
    total = sum(weights)
    return 0.0 if total <= 0 else sum((value * weight for value, weight in zip(values, weights))) / total

def vector_distance(a: dict[str, Any], b: dict[str, Any]) -> float:
    ar = a['profiles']['adaptive_weights_real'][-1]
    ai = a['profiles']['adaptive_weights_imag'][-1]
    br = b['profiles']['adaptive_weights_real'][-1]
    bi = b['profiles']['adaptive_weights_imag'][-1]
    numerator = math.sqrt(sum(((float(x) - float(y)) ** 2 + (float(u) - float(v)) ** 2 for x, y, u, v in zip(ar, br, ai, bi))))
    denominator = max(math.sqrt(sum((float(x) ** 2 + float(u) ** 2 for x, u in zip(ar, ai)))), 1e-12)
    return numerator / denominator

def metric_with_local_target(row: dict[str, Any]) -> dict[str, Any]:
    metric = dict(row['summary'])
    if 'local_target_peak_error_m' in metric and 'late_local_peak_spread_m' in metric and ('target_to_local_peak_ratio' in metric):
        return metric
    profiles = row['profiles']
    axis = [float(value) for value in profiles['range_axis_m']]
    frames = profiles['suppressed_range_power']
    target_range = float(row['truth']['target_range_m'])
    target_bin = min(range(len(axis)), key=lambda index: abs(axis[index] - target_range))
    search = range(max(0, target_bin - 4), min(len(axis), target_bin + 5))
    aggregate = [sum((float(frame[index]) for frame in frames[-2:])) / len(frames[-2:]) for index in range(len(axis))]
    local_bin = max(search, key=lambda index: aggregate[index])
    late_bins = [max(search, key=lambda index: float(frame[index])) for frame in frames[-2:]]
    metric['local_target_peak_range_m'] = axis[local_bin]
    metric['local_target_peak_error_m'] = abs(axis[local_bin] - target_range)
    target_band = range(max(0, target_bin - 1), min(len(axis), target_bin + 2))
    target_power = max((aggregate[index] for index in target_band))
    local_power = max((aggregate[index] for index in search))
    metric['target_to_local_peak_ratio'] = target_power / max(local_power, 1e-18)
    metric['late_local_peak_spread_m'] = max((axis[index] for index in late_bins)) - min((axis[index] for index in late_bins))
    return metric

def scenario_performance(metric: dict[str, Any]) -> tuple[float, dict[str, float]]:
    parts = {'target_prominence': high(float(metric['target_prominence_db']), 2.0, 8.0), 'interference_suppression': high(float(metric['non_target_suppression_db']), -2.0, 12.0), 'target_is_local_peak': high(float(metric['target_to_local_peak_ratio']), 0.25, 0.85), 'target_is_global_peak': high(float(metric['target_to_global_peak_ratio']), 0.25, 0.9), 'finite': float(bool(metric['all_values_finite']))}
    score = weighted(list(parts.values()), [0.45, 0.2, 0.2, 0.05, 0.1])
    return (score, parts)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    failures: list[str] = []
    for key in ('load_pass', 'update_pass', 'compile_pass'):
        if not bool(evidence.get(key)):
            failures.append(f'{key} is false')
    missing = [name for name in REQUIRED if name not in rows or not bool(rows[name].get('simulation_pass')) or (not bool(rows[name].get('valid')))]
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not bool(evidence.get('model_closed_without_save')):
        failures.append('model was not closed without save')
    gate = not failures
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, {}, failures, {})
    metrics = {name: metric_with_local_target(rows[name]) for name in REQUIRED}
    per_scenario: dict[str, float] = {}
    per_parts: dict[str, dict[str, float]] = {}
    for name in REQUIRED:
        per_scenario[name], per_parts[name] = scenario_performance(metrics[name])
    nominal = metrics['nominal']
    a_parts = {'target_prominence': high(float(nominal['target_prominence_db']), 2.0, 8.0), 'target_is_local_peak': high(float(nominal['target_to_local_peak_ratio']), 0.25, 0.85), 'target_is_global_peak': high(float(nominal['target_to_global_peak_ratio']), 0.25, 0.9)}
    A = weighted(list(a_parts.values()), [0.5, 0.3, 0.2])
    q_parts = {'interference_suppression': high(float(nominal['non_target_suppression_db']), -2.0, 12.0), 'bounded_weight_norm': low(float(nominal['weight_norm_max']), 3.0, 15.0), 'stable_late_prominence': low(float(nominal['late_frame_prominence_spread_db']), 2.0, 12.0), 'finite_output': float(bool(nominal['all_values_finite']))}
    Q = weighted(list(q_parts.values()), [0.45, 0.2, 0.2, 0.15])
    range_tracking = min((high(float(metrics[name]['target_to_local_peak_ratio']), 0.25, 0.85) for name in ('range_boundary', 'joint_service')))
    doppler_weight_change = high(vector_distance(rows['nominal'], rows['doppler_boundary']), 0.02, 0.15)
    jammer_weight_change = high(vector_distance(rows['nominal'], rows['jammer_geometry']), 0.02, 0.15)
    nominal_background = max(float(nominal['received_background_power']), 1e-18)
    clutter_background = max(float(metrics['weak_target_strong_clutter']['received_background_power']), 1e-18)
    clutter_response = high(abs(math.log10(clutter_background / nominal_background)), 0.03, 0.15)
    behavioral_path = min(range_tracking, max(doppler_weight_change, jammer_weight_change), max((high(float(metrics[name]['target_prominence_db']), 0.0, 2.0) for name in REQUIRED)))
    m_parts = {'connected_physical_and_processing_roles': behavioral_path, 'target_range_causality': range_tracking, 'target_velocity_causality': doppler_weight_change, 'jammer_geometry_causality': jammer_weight_change, 'clutter_scale_causality': clutter_response}
    M = weighted(list(m_parts.values()), [0.15, 0.15, 0.25, 0.25, 0.2])
    R = min(per_scenario.values())
    frame_count = min((len(rows[name].get('time_s', [])) for name in REQUIRED))
    d_parts = {'coherent_frames_available': high(float(frame_count), 1.0, 3.0), 'peak_range_stability': low(max((float(metrics[name]['late_local_peak_spread_m']) for name in REQUIRED)), 25.0, 150.0), 'prominence_stability': low(max((float(metrics[name]['late_frame_prominence_spread_db']) for name in REQUIRED)), 2.0, 12.0)}
    D = weighted(list(d_parts.values()), [0.25, 0.4, 0.35])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, exponent in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** exponent
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': per_scenario, 'R_scenario_utilities': per_parts, 'D_utilities': d_parts, 'offline_calibration': {'target_prominence_zero_full_db': [2.0, 8.0], 'local_target_ratio_zero_full': [0.25, 0.85], 'late_local_peak_spread_full_zero_m': [25.0, 150.0], 'reason': 'Known-range STAP is credited for a resolved local target peak with useful prominence; the late spread normalization uses the native 25 m range-bin resolution and reaches zero at six bins. Scenario minimum aggregation is unchanged.'}}
    return receipt(evidence, groups, total, metrics, [], diagnostics)

def receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xcomm03-score.v1', 'task_id': 'F90-XCOMM-03', 'policy_id': POLICY_ID, 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.25*D^0.10', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': groups.get('G') == 1.0, 'groups': groups, 'score': total, 'admission_score_pass': bool(groups.get('G') == 1.0 and total >= 85), 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence_positional', nargs='?')
    parser.add_argument('--evidence')
    parser.add_argument('--output')
    parser.add_argument('--out')
    args = parser.parse_args()
    evidence_name = args.evidence or args.evidence_positional
    if not evidence_name:
        parser.error('an evidence path is required')
    source = Path(evidence_name)
    output_name = args.output or args.out
    output = Path(output_name) if output_name else source.with_name('offline_score.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    result = score_evidence(json.loads(source.read_text(encoding='utf-8')))
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    print(output)
if __name__ == '__main__':
    main()

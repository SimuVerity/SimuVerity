"""Pure offline scorer for current F90-XMECH-06 evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
POLICY_ID = 'simuverity-101-v1:f90-xmech-06:scoring'
STATIC_AUDIT_POLICY_ID = 'f90-xmech06-connected-causal-path'
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
REQUIRED = ['nominal_skidpad', 'high_speed_skidpad', 'low_friction_skidpad', 'payload_skidpad', 'combined_skidpad', 'acceleration_braking']

def clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return clamp((zero - value) / (zero - full))

def high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return clamp((value - zero) / (full - zero))

def weighted(values: list[float], weights: list[float]) -> float:
    return sum((v * w for v, w in zip(values, weights))) / sum(weights)

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    static = evidence.get('static_audit', {})
    static_audit_policy_id = str(static.get('audit_policy_id', ''))
    if static_audit_policy_id:
        audit_identity_matches = (
            static_audit_policy_id == STATIC_AUDIT_POLICY_ID
            or static_audit_policy_id.startswith(STATIC_AUDIT_POLICY_ID + '-')
        )
        connected_causal_path = bool(audit_identity_matches and static.get('connected_causal_path_qualified', False))
    else:
        connected_causal_path = bool(static.get('core_path_qualified', False))
    missing = [name for name in REQUIRED if name not in rows or not rows[name].get('valid')]
    gate = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and bool(evidence.get('nominal_smoke_pass')) and connected_causal_path and (not missing)
    failures: list[str] = []
    if missing:
        failures.append('invalid required scenarios: ' + ', '.join(missing))
    if not connected_causal_path:
        failures.append('connected full-vehicle physical path not qualified')
        failures.extend((f'static audit: {fact}' for fact in static.get('failure_facts', []) if str(fact)))
    if not gate:
        return receipt(evidence, {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}, 0.0, failures, {})
    metrics = {name: rows[name]['metrics'] for name in REQUIRED}
    nominal = metrics['nominal_skidpad']
    braking = metrics['acceleration_braking']
    a_parts = {'speed_tracking': low(float(nominal['speed_rmse_mps']), 0.6, 4.0), 'heading_tracking': low(float(nominal['yaw_rmse_rad']), 0.04, 0.35), 'closed_loop_steering': high(float(nominal['steering_peak_rad']), 0.01, 0.1)}
    A = weighted(list(a_parts.values()), [0.45, 0.4, 0.15])
    q_parts = {'roll_margin': low(float(nominal['max_abs_roll_rad']), 0.12, 0.55), 'pitch_margin': low(float(nominal['max_abs_pitch_rad']), 0.1, 0.45), 'tire_slip_margin': low(float(nominal['peak_abs_slip_deg']), 8.0, 35.0), 'suspension_travel_margin': low(float(nominal['suspension_travel_peak_m']), 0.08, 0.3), 'four_wheel_loads': high(float(nominal['independent_wheel_load_fraction']), 0.1, 0.75)}
    Q = weighted(list(q_parts.values()), [0.2, 0.15, 0.25, 0.2, 0.2])
    speed_command_effect = abs(float(metrics['high_speed_skidpad']['target_speed_mean_mps']) / max(abs(float(nominal['target_speed_mean_mps'])), 1e-09) - 1.0)
    friction_response_effect = abs(float(metrics['low_friction_skidpad']['peak_abs_slip_deg']) - float(nominal['peak_abs_slip_deg'])) + abs(float(metrics['low_friction_skidpad']['speed_rmse_mps']) - float(nominal['speed_rmse_mps']))
    payload_effect = abs(float(metrics['payload_skidpad']['vertical_load_mean_N']) - float(nominal['vertical_load_mean_N'])) / max(float(nominal['vertical_load_mean_N']), 1e-09)
    event_effect = abs(float(braking['world_distance_m']) / max(abs(float(nominal['world_distance_m'])), 1e-09) - 1.0)
    m_parts = {'connected_static_path': float(connected_causal_path), 'active_four_wheel_forces': high(min((float(metrics[name]['wheel_force_active_fraction']) for name in REQUIRED)), 0.1, 0.55), 'active_suspension': high(min((float(metrics[name]['suspension_active_fraction']) for name in REQUIRED)), 0.05, 0.55), 'force_acceleration_causality': weighted([high(float(nominal['longitudinal_force_accel_correlation']), 0.1, 0.7), high(float(nominal['lateral_force_accel_correlation']), 0.1, 0.7)], [0.45, 0.55]), 'official_input_causality': weighted([high(speed_command_effect, 0.02, 0.08), high(friction_response_effect, 0.01, 0.2), high(payload_effect, 0.015, 0.08), high(event_effect, 0.2, 1.0)], [0.3, 0.1, 0.3, 0.3])}
    M = weighted(list(m_parts.values()), [0.25, 0.15, 0.15, 0.25, 0.2])
    scenario_scores: dict[str, float] = {}
    for name in REQUIRED[:-1]:
        row = metrics[name]
        scenario_scores[name] = weighted([low(float(row['speed_rmse_mps']), 0.8, 5.0), low(float(row['yaw_rmse_rad']), 0.06, 0.45), low(float(row['peak_abs_slip_deg']), 10.0, 45.0), low(float(row['max_abs_roll_rad']), 0.15, 0.65)], [0.35, 0.3, 0.2, 0.15])
    scenario_scores['acceleration_braking'] = weighted([high(float(braking['accelerator_peak']), 0.02, 0.07), high(float(braking['brake_peak']), 0.1, 0.6), high(float(braking['braking_speed_drop_mps']), 0.5, 4.0), high(float(braking['braking_deceleration_peak_mps2']), 0.5, 3.5)], [0.15, 0.2, 0.35, 0.3])
    R = min(scenario_scores.values())
    d_parts = {'lateral_load_transfer': high(float(nominal['lateral_load_transfer_correlation']), 0.1, 0.75), 'longitudinal_load_transfer': high(float(braking['longitudinal_load_transfer_correlation']), 0.1, 0.7), 'braking_response': high(float(braking['braking_speed_drop_mps']), 0.5, 4.0), 'braking_pitch_response': high(float(braking['braking_pitch_peak_rad']), 0.002, 0.025)}
    D = weighted(list(d_parts.values()), [0.25, 0.25, 0.35, 0.15])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** weight
    findings: list[str] = []
    if min((float(metrics[name]['wheel_force_active_fraction']) for name in REQUIRED)) < 0.05:
        findings.append('four-wheel physical forces are inactive')
    if min((float(metrics[name]['suspension_active_fraction']) for name in REQUIRED)) < 0.02:
        findings.append('suspension states are inactive')
    if float(nominal['max_abs_roll_rad']) < 1e-05 and float(braking['max_abs_pitch_rad']) < 1e-05:
        findings.append('body attitude is fixed')
    active_scenario_inputs = sum([speed_command_effect >= 0.02, friction_response_effect >= 0.01, payload_effect >= 0.015, event_effect >= 0.2])
    if active_scenario_inputs < 2:
        findings.append('fewer than two official operating inputs have measurable effects')
    if float(nominal['longitudinal_force_accel_correlation']) < 0.05 and float(nominal['lateral_force_accel_correlation']) < 0.05:
        findings.append('wheel forces are unrelated to chassis acceleration')
    diagnostics = {'A_utilities': a_parts, 'Q_utilities': q_parts, 'M_utilities': m_parts, 'R_scenario_scores': scenario_scores, 'D_utilities': d_parts, 'causal_effects': {'speed_command_effect': speed_command_effect, 'friction_response_effect': friction_response_effect, 'payload_effect': payload_effect, 'event_effect': event_effect, 'active_official_input_count': active_scenario_inputs}, 'shortcut_findings': [{'reason': reason} for reason in findings]}
    failures.extend((f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6))
    failures.extend(findings)
    return receipt(evidence, groups, total, failures, diagnostics)

def receipt(evidence: dict[str, Any], groups: dict[str, float], score: float, failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xmech06-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XMECH-06', 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups['G']), 'groups': groups, 'score': float(score), 'admission_score_pass': bool(groups['G'] and score >= 85), 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    out = args.out or args.evidence.with_name('score.json')
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({'score': result['score'], 'groups': result['groups'], 'out': str(out)}))
if __name__ == '__main__':
    main()

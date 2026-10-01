"""Authoritative pure-offline scorer for F90-XAERO-03.

The scorer reads fixed JSON evidence and writes a JSON score.  It performs
no MATLAB/Simulink action and has no model-file dependency. An input object
containing the same evidence fields is accepted and can be normalized to the
evidence-only schema for score replay.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import json
import math
from pathlib import Path
from typing import Any
FORMAL_ID = 'F90-XAERO-03'
POLICY_ID = "simuverity-101-v1:f90-xaero-03:scoring"
EXPECTED_SCENARIOS = ('nominal', 'high_altitude_fast_right_turn', 'low_altitude_slow_left_turn', 'large_climb_transition', 'gust_pair_none', 'gust_pair_crosswind', 'heading_pair_left', 'heading_pair_right', 'joint_boundary')
RANGE_SCENARIOS = ('nominal', 'high_altitude_fast_right_turn', 'low_altitude_slow_left_turn', 'large_climb_transition', 'joint_boundary')
TRIM_RELEASE_SCENARIOS = ('heading_pair_left', 'heading_pair_right')
GROUP_WEIGHTS = {'A': 0.22, 'Q': 0.12, 'M': 0.32, 'R': 0.15, 'D': 0.19}

def quality(metric: float, good: float, bad: float) -> float:
    """Linear quality where lower is better."""
    metric = float(metric)
    if not math.isfinite(metric):
        return 0.0
    if bad <= good:
        return float(metric <= good)
    return min(max((bad - metric) / (bad - good), 0.0), 1.0)

def quality_high(metric: float, good: float, bad: float) -> float:
    """Linear quality where higher is better."""
    metric = float(metric)
    if not math.isfinite(metric):
        return 0.0
    if good <= bad:
        return float(metric >= good)
    return min(max((metric - bad) / (good - bad), 0.0), 1.0)

def utc_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')

def read_json(path: str | Path) -> dict[str, Any]:
    with Path(path).open('r', encoding='utf-8') as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError('evidence root must be a JSON object')
    return value

def write_json(path: str | Path, value: dict[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('w', encoding='utf-8', newline='\n') as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write('\n')

def normalize_evidence(value: dict[str, Any]) -> dict[str, Any]:
    """Strip any source score decisions and retain extraction evidence."""
    required = ('scenario_rows', 'metric_values', 'static_audit', 'load_pass', 'update_pass', 'compile_pass')
    missing = [name for name in required if name not in value]
    if missing:
        raise ValueError(f"missing evidence fields: {', '.join(missing)}")
    metrics = value['metric_values']
    if not isinstance(metrics, dict):
        raise ValueError('metric_values must be an object')
    if 'physical_suite' not in metrics or 'causal_pairs' not in metrics:
        raise ValueError('metric_values must contain physical_suite and causal_pairs')
    raw_pairs = copy.deepcopy(metrics['causal_pairs'])
    raw_pairs.pop('release_and_feedback', None)
    for pair_name in ('heading', 'gust'):
        if isinstance(raw_pairs.get(pair_name), dict):
            raw_pairs[pair_name].pop('score', None)
            raw_pairs[pair_name].pop('schedule_score', None)
            raw_pairs[pair_name].pop('consequence_score', None)
            raw_pairs[pair_name].pop('recovery_score', None)
    normalized = {'schema': 'simuverity.f90-xaero03-evidence.v1', 'formal_id': value.get('formal_id', FORMAL_ID), 'design_revision': value.get('design_revision', 'source-c05r-receipt-normalized'), 'model_path': value.get('model_path', ''), 'load_pass': bool(value['load_pass']), 'update_pass': bool(value['update_pass']), 'compile_pass': bool(value['compile_pass']), 'scenario_inputs': copy.deepcopy(value.get('scenario_inputs', [])), 'scenario_rows': copy.deepcopy(value['scenario_rows']), 'metric_values': {'physical_suite': copy.deepcopy(metrics['physical_suite']), 'causal_pairs': raw_pairs}, 'static_audit': copy.deepcopy(value['static_audit']), 'timeseries_artifact': copy.deepcopy(value.get('timeseries_artifact', {'path': '', 'format': '', 'variable': '', 'contains': ''})), 'extraction_only': True, 'contains_score_or_threshold_decisions': False, 'extracted_at': value.get('extracted_at', value.get('finished_at', '')), 'runtime_identity': copy.deepcopy(value.get('runtime_identity', {}))}
    return normalized

def row_map(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        scenario_id = str(row.get('id', ''))
        if scenario_id and scenario_id not in result:
            result[scenario_id] = row
    return result

def feedback_presence_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Summarize feedback presence without replacing worst-case M quality.

    The qualification gate asks whether feedback-causal evidence is absent from
    the required suite.  It therefore uses the median of the finite values from
    valid required scenarios.  The existing minimum remains untouched in M,
    where isolated weak feedback quality is continuously penalized.
    """
    values: list[float] = []
    for row in rows:
        if not bool(row.get('valid', False)):
            continue
        try:
            value = float(row['feedback_correlation'])
        except (KeyError, TypeError, ValueError):
            continue
        if math.isfinite(value):
            values.append(value)
    ordered = sorted(values)
    count = len(ordered)
    if count == 0:
        median_value = None
    elif count % 2:
        median_value = ordered[count // 2]
    else:
        median_value = 0.5 * (ordered[count // 2 - 1] + ordered[count // 2])
    return {'reducer': 'median_finite_valid_required_scenarios', 'threshold': 0.02, 'valid_value_count': count, 'required_value_count': len(EXPECTED_SCENARIOS), 'complete': count == len(EXPECTED_SCENARIOS), 'median': median_value, 'minimum': ordered[0] if ordered else None, 'maximum': ordered[-1] if ordered else None, 'passing_value_count': sum((value >= 0.02 for value in ordered))}

def score_trim_release(rows_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    details: list[dict[str, Any]] = []
    for scenario_id in TRIM_RELEASE_SCENARIOS:
        row = rows_by_id.get(scenario_id, {})
        valid = bool(row.get('valid', False))
        detail = {'id': scenario_id, 'valid': valid, 'initial_release_rate_peak': row.get('initial_release_rate_peak'), 'initial_release_altitude_change_m': row.get('initial_release_altitude_change_m'), 'initial_release_speed_change_m_per_s': row.get('initial_release_speed_change_m_per_s'), 'rate_score': 0.0, 'altitude_score': 0.0, 'speed_score': 0.0, 'score': 0.0}
        if valid:
            detail['rate_score'] = quality(row['initial_release_rate_peak'], 0.08, 0.6)
            detail['altitude_score'] = quality(row['initial_release_altitude_change_m'], 35.0, 180.0)
            detail['speed_score'] = quality(row['initial_release_speed_change_m_per_s'], 5.0, 25.0)
            detail['score'] = min(detail['rate_score'], detail['altitude_score'], detail['speed_score'])
        details.append(detail)
    return {'definition': 'pre-command stability on dedicated zero-offset trim scenarios', 'scenario_ids': list(TRIM_RELEASE_SCENARIOS), 'details': details, 'score': min((item['score'] for item in details), default=0.0)}

def score_heading_pair(raw_pair: dict[str, Any], rows_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    left = rows_by_id.get('heading_pair_left', {})
    right = rows_by_id.get('heading_pair_right', {})
    valid = bool(left.get('valid', False)) and bool(right.get('valid', False))
    left_mean = raw_pair.get('left_final_heading_rad', left.get('final_heading_mean_rad'))
    right_mean = raw_pair.get('right_final_heading_rad', right.get('final_heading_mean_rad'))
    left_error = raw_pair.get('left_final_heading_rms_error_rad', left.get('final_heading_rms_error_rad'))
    right_error = raw_pair.get('right_final_heading_rms_error_rad', right.get('final_heading_rms_error_rad'))
    if left_mean is None or right_mean is None:
        valid = False
    symmetry_error = abs(abs(float(left_mean)) - abs(float(right_mean))) if valid else None
    result = {'valid': valid, 'left_final_heading_rad': left_mean, 'right_final_heading_rad': right_mean, 'left_final_heading_rms_error_rad': left_error, 'right_final_heading_rms_error_rad': right_error, 'symmetry_error_rad': symmetry_error, 'left_direction_score': 0.0, 'right_direction_score': 0.0, 'symmetry_score': 0.0, 'tracking_score': 0.0, 'score': 0.0}
    if valid:
        result['left_direction_score'] = quality_high(-float(left_mean), 0.38, 0.08)
        result['right_direction_score'] = quality_high(float(right_mean), 0.38, 0.08)
        result['symmetry_score'] = quality(float(symmetry_error), 0.05, 0.3)
        result['tracking_score'] = min(quality(float(left_error), 0.05, 0.22), quality(float(right_error), 0.05, 0.22))
        result['score'] = min(result['left_direction_score'], result['right_direction_score'], result['symmetry_score'], result['tracking_score'])
    return result

def score_gust_pair(raw_pair: dict[str, Any], rows_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    no_gust = rows_by_id.get('gust_pair_none', {})
    gust = rows_by_id.get('gust_pair_crosswind', {})
    required_metrics = ('state_delta', 'air_data_delta', 'load_delta', 'actuator_delta', 'recovery_delta')
    valid = bool(no_gust.get('valid', False)) and bool(gust.get('valid', False)) and all((raw_pair.get(name) is not None for name in required_metrics))
    no_gust_schedule = raw_pair.get('no_gust_schedule_error', no_gust.get('gust_schedule_error'))
    gust_schedule = raw_pair.get('gust_schedule_error', gust.get('gust_schedule_error'))
    if no_gust_schedule is None or gust_schedule is None:
        valid = False
    result = copy.deepcopy(raw_pair)
    result.update({'valid': valid, 'no_gust_schedule_error': no_gust_schedule, 'gust_schedule_error': gust_schedule, 'schedule_score': 0.0, 'consequence_score': 0.0, 'recovery_score': 0.0, 'score': 0.0})
    if valid:
        result['schedule_score'] = min(quality(float(gust_schedule), 0.01, 0.25), quality(float(no_gust_schedule), 0.01, 0.25))
        result['consequence_score'] = quality_high(max((float(raw_pair[name]) for name in required_metrics[:-1])), 0.06, 0.008)
        result['recovery_score'] = quality(float(raw_pair['recovery_delta']), 0.18, 0.8)
        result['score'] = min(result['schedule_score'], result['consequence_score'], result['recovery_score'])
    return result

def range_detail(row: dict[str, Any], scenario_id: str) -> dict[str, Any]:
    detail = {'id': scenario_id, 'valid': bool(row.get('valid', False)), 'raw_metrics': {'final_altitude_rms_error_m': row.get('final_altitude_rms_error_m'), 'final_airspeed_rms_error_m_per_s': row.get('final_airspeed_rms_error_m_per_s'), 'final_heading_rms_error_rad': row.get('final_heading_rms_error_rad'), 'final_sideslip_rms_rad': row.get('final_sideslip_rms_rad'), 'final_body_rate_rms_rad_per_s': row.get('final_body_rate_rms_rad_per_s')}, 'altitude_score': 0.0, 'airspeed_score': 0.0, 'heading_score': 0.0, 'sideslip_score': 0.0, 'body_rate_score': 0.0, 'score': 0.0}
    if not detail['valid']:
        return detail
    detail['altitude_score'] = quality(row['final_altitude_rms_error_m'], 60.0, 240.0)
    detail['airspeed_score'] = quality(row['final_airspeed_rms_error_m_per_s'], 3.0, 12.0)
    detail['heading_score'] = quality(row['final_heading_rms_error_rad'], 0.05, 0.22)
    detail['sideslip_score'] = quality(row['final_sideslip_rms_rad'], 0.06, 0.22)
    detail['body_rate_score'] = quality(row['final_body_rate_rms_rad_per_s'], 0.04, 0.2)
    detail['score'] = (0.3 * detail['altitude_score'] + 0.2 * detail['airspeed_score'] + 0.18 * detail['heading_score'] + 0.12 * detail['sideslip_score'] + 0.1 * detail['body_rate_score']) / 0.9
    return detail

def compute_groups(rows_by_id: dict[str, dict[str, Any]], rows: list[dict[str, Any]], suite: dict[str, Any], pairs: dict[str, Any], gate: bool) -> tuple[dict[str, float], list[dict[str, Any]]]:
    zero = {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
    if not gate:
        return (zero, [])
    nominal = rows_by_id['nominal']
    groups = dict(zero)
    groups['G'] = 1.0
    groups['A'] = 0.28 * quality(nominal['final_altitude_rms_error_m'], 30.0, 140.0) + 0.22 * quality(nominal['final_airspeed_rms_error_m_per_s'], 1.5, 8.0) + 0.2 * quality(nominal['final_heading_rms_error_rad'], 0.03, 0.15) + 0.15 * quality(nominal['final_sideslip_rms_rad'], 0.03, 0.12) + 0.15 * quality(nominal['final_body_rate_rms_rad_per_s'], 0.03, 0.16)
    valid_rows = [row for row in rows if bool(row.get('valid', False))]
    actuator_bound_utility = min(quality(suite['actuator_position_violation_worst'], 0.0, 0.02), quality(suite['actuator_rate_violation_worst'], 0.005, 0.08))
    groups['Q'] = 0.17 * quality(suite['alpha_violation_worst'], 0.0, 0.03) + 0.15 * quality(suite['beta_violation_worst'], 0.0, 0.03) + 0.36 * actuator_bound_utility + 0.14 * quality(suite['actuator_saturation_worst'], 0.0, 0.75) + 0.18 * quality_high(min((float(row['minimum_altitude_m']) for row in valid_rows)), 500.0, 100.0)
    groups['M'] = 0.08 * quality(suite['position_velocity_worst'], 0.005, 0.05) + 0.08 * quality(suite['euler_rate_worst'], 0.01, 0.08) + 0.09 * quality(suite['relative_wind_worst'], 0.005, 0.05) + 0.07 * quality(max(suite['density_worst'], suite['dynamic_pressure_worst'], suite['mach_worst']), 0.005, 0.05) + 0.12 * quality(suite['translational_balance_worst'], 0.02, 0.2) + 0.12 * quality(suite['rotational_balance_worst'], 0.02, 0.2) + 0.1 * quality(max(suite['force_path_worst'], suite['total_moment_path_worst']), 0.005, 0.08) + 0.08 * quality_high(suite['actuator_response_correlation_min'], 0.65, 0.2) + 0.08 * quality_high(suite['actuator_lag_evidence_max'], 0.015, 0.003) + 0.08 * quality_high(suite['control_signature_min'], 0.3, 0.03) + 0.05 * quality_high(suite['pressure_load_correlation_min'], 0.35, 0.05) + 0.05 * quality_high(suite['feedback_correlation_min'], 0.18, 0.02)
    range_details = [range_detail(rows_by_id.get(scenario_id, {}), scenario_id) for scenario_id in RANGE_SCENARIOS]
    groups['R'] = min((item['score'] for item in range_details), default=0.0)
    component_scores = (float(pairs.get('heading', {}).get('score', 0.0)), float(pairs.get('gust', {}).get('score', 0.0)), float(pairs.get('trim_release', {}).get('score', 0.0)))
    groups['D'] = 0.7 * min(component_scores) + 0.3 * (sum(component_scores) / len(component_scores))
    return (groups, range_details)

def shortcut_findings(suite: dict[str, Any], pairs: dict[str, Any], gate: bool) -> list[dict[str, Any]]:
    return [{'id': 'general_gate', 'triggered': not gate}, {'id': 'six_dof_balance', 'triggered': suite['translational_balance_worst'] > 0.15 or suite['rotational_balance_worst'] > 0.15}, {'id': 'force_moment_path', 'triggered': suite['force_path_worst'] > 0.12 or suite['total_moment_path_worst'] > 0.08}, {'id': 'finite_actuator_dynamics', 'triggered': suite['actuator_lag_evidence_max'] < 0.003 or suite['actuator_response_correlation_min'] < 0.2}, {'id': 'physical_gust_consequence', 'triggered': pairs.get('gust', {}).get('consequence_score', 0.0) < 0.2}, {'id': 'aerodynamic_control_path', 'triggered': suite['control_signature_min'] < 0.03 or suite['pressure_load_correlation_min'] < 0.05}]

def failure_reasons(rows: list[dict[str, Any]], suite: dict[str, Any], pairs: dict[str, Any], audit: dict[str, Any], contract_complete: bool, missing_ids: list[str], duplicate_ids: list[str], feedback_presence: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    if not contract_complete:
        if missing_ids:
            reasons.append(f"SCENARIO_EVIDENCE_MISSING:{','.join(missing_ids)}")
        if duplicate_ids:
            reasons.append(f"SCENARIO_EVIDENCE_DUPLICATE:{','.join(duplicate_ids)}")
    for row in rows:
        if not bool(row.get('valid', False)):
            reasons.append(f"SCENARIO_{row.get('id', '')}:{row.get('error', '')}")
    if not bool(audit.get('output_contract_connected', False)):
        reasons.append('OUTPUT_CONTRACT_NOT_CONNECTED')
    if audit.get('precomputed_direct_output_count', 0) > 0:
        reasons.append('DIRECT_PRECOMPUTED_OUTPUT_SOURCE')
    if audit.get('suspicious_callback_count', 0) > 0:
        reasons.append('SUSPICIOUS_CALLBACK_DATA_LOAD')
    if not bool(audit.get('dynamic_state_evidence', False)):
        reasons.append('NO_DYNAMIC_STATE_EVIDENCE')
    if suite['position_velocity_worst'] > 0.05:
        reasons.append('POSITION_VELOCITY_KINEMATICS_FAILED')
    if suite['euler_rate_worst'] > 0.08:
        reasons.append('EULER_BODY_RATE_KINEMATICS_FAILED')
    if suite['relative_wind_worst'] > 0.05:
        reasons.append('RELATIVE_WIND_AIRDATA_FAILED')
    if suite['translational_balance_worst'] > 0.15:
        reasons.append('SIX_DOF_TRANSLATIONAL_BALANCE_FAILED')
    if suite['rotational_balance_worst'] > 0.15:
        reasons.append('SIX_DOF_ROTATIONAL_BALANCE_FAILED')
    if suite['force_path_worst'] > 0.12 or suite['total_moment_path_worst'] > 0.08:
        reasons.append('FORCE_MOMENT_LOAD_PATH_FAILED')
    if suite['actuator_lag_evidence_max'] < 0.003:
        reasons.append('ACTUAL_ACTUATORS_BYPASS_DYNAMICS')
    if suite['actuator_saturation_worst'] > 0.75:
        reasons.append('ACTUATOR_SATURATION_SUSTAINED')
    if pairs.get('gust', {}).get('consequence_score', 0.0) < 0.2:
        reasons.append('GUST_LOGGED_WITHOUT_PHYSICAL_CONSEQUENCE')
    if not bool(feedback_presence['complete']) or feedback_presence['median'] is None or float(feedback_presence['median']) < 0.02:
        reasons.append('FEEDBACK_CAUSAL_EVIDENCE_MISSING')
    if suite['control_signature_min'] < 0.03:
        reasons.append('NONLINEAR_AERODYNAMIC_CONTROL_SIGNATURE_FAILED')
    return list(dict.fromkeys(reasons))

def score_evidence(value: dict[str, Any]) -> dict[str, Any]:
    evidence = normalize_evidence(value)
    rows = evidence['scenario_rows']
    if not isinstance(rows, list):
        raise ValueError('scenario_rows must be an array')
    suite = evidence['metric_values']['physical_suite']
    raw_pairs = copy.deepcopy(evidence['metric_values']['causal_pairs'])
    rows_by_id = row_map(rows)
    actual_ids = [str(row.get('id', '')) for row in rows]
    missing_ids = [scenario_id for scenario_id in EXPECTED_SCENARIOS if scenario_id not in actual_ids]
    duplicate_ids = sorted({scenario_id for scenario_id in actual_ids if actual_ids.count(scenario_id) > 1})
    contract_complete = len(actual_ids) == len(EXPECTED_SCENARIOS) and (not missing_ids) and (not duplicate_ids)
    all_rows_valid = contract_complete and all((bool(row.get('valid', False)) for row in rows))
    audit = evidence['static_audit']
    feedback_presence = feedback_presence_summary(rows)
    feedback_gate = bool(feedback_presence['complete']) and feedback_presence['median'] is not None and (float(feedback_presence['median']) >= 0.02)
    gate = bool(evidence['load_pass']) and bool(evidence['update_pass']) and bool(evidence['compile_pass']) and all_rows_valid and bool(audit.get('output_contract_connected', False)) and (audit.get('precomputed_direct_output_count', 0) == 0) and (audit.get('suspicious_callback_count', 0) == 0) and bool(audit.get('dynamic_state_evidence', False)) and feedback_gate
    pairs = {'heading': score_heading_pair(raw_pairs.get('heading', {}), rows_by_id), 'gust': score_gust_pair(raw_pairs.get('gust', {}), rows_by_id), 'trim_release': score_trim_release(rows_by_id)}
    groups, range_details = compute_groups(rows_by_id, rows, suite, pairs, gate)
    if any((groups[group] <= 0.0 for group in GROUP_WEIGHTS)):
        uncapped_total = 0.0
    else:
        uncapped_total = 100.0 * math.exp(sum((GROUP_WEIGHTS[group] * math.log(groups[group]) for group in GROUP_WEIGHTS)))
    findings = shortcut_findings(suite, pairs, gate)
    total = max(uncapped_total, 0.0)
    reasons = failure_reasons(rows, suite, pairs, audit, contract_complete, missing_ids, duplicate_ids, feedback_presence)
    return {'schema': 'simuverity.f90-xaero03-offline-score.v1', 'formal_id': FORMAL_ID, 'policy_id': POLICY_ID, 'valid': gate, 'score_inputs_valid': gate, 'G': bool(groups['G']), 'groups': groups, 'group_weights': GROUP_WEIGHTS, 'total': total, 'score': total, 'uncapped_total': uncapped_total, 'shortcut_findings': findings, 'metric_values': {'physical_suite': suite, 'causal_pairs': pairs, 'range_scenario_details': range_details, 'feedback_presence': feedback_presence}, 'scenario_contract': {'expected_ids': list(EXPECTED_SCENARIOS), 'actual_ids': actual_ids, 'complete': contract_complete}, 'failure_reasons': reasons, 'policy_notes': {'simulation_or_extraction_performed': False, 'range_aggregation': 'minimum across required range scenarios', 'across_group_aggregation': 'weighted geometric mean', 'joint_boundary_role': 'mixed public-range stress condition retained in R; not used for causal isolation', 'D_components': ['paired heading', 'paired gust', 'trim release'], 'release_scenarios': list(TRIM_RELEASE_SCENARIOS), 'feedback_gate_below': 0.02, 'feedback_gate_reducer': 'median across finite feedback_correlation values from all valid required scenarios', 'feedback_continuous_quality_reducer': 'minimum across required scenarios in M', 'saturation_scored_only_in_group': 'Q', 'saturation_quality_good_fraction': 0.0, 'saturation_quality_bad_fraction': 0.75, 'saturation_penalty_continuous_from_zero': True, 'actuator_bound_aggregation': 'minimum of public position-bound and rate-bound utilities; combined Q weight 0.36', 'range_altitude_full_zero_m': [60.0, 240.0], 'balance_score_full_zero': [0.02, 0.2], 'policy_basis': 'Public actuator position and rate bounds are conjunctive within Q, so one cannot compensate for failure of the other. Complementary capability groups use a weighted geometric mean so nominal tracking cannot arithmetically dilute a failed public gust schedule. D receives 0.19 and R 0.15 because R already uses the worst required range scenario. The qualification gate distinguishes complete absence of feedback-causal evidence from isolated weak range or saturation scenarios by using the suite median; the minimum remains the continuous M metric.'}, 'scored_at': utc_timestamp()}

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, help='input evidence JSON')
    parser.add_argument('--output', required=True, help='offline score JSON')
    parser.add_argument('--normalized-evidence-output', help='optional normalized evidence-only JSON')
    return parser.parse_args()

def main() -> int:
    args = parse_args()
    source = read_json(args.evidence)
    normalized = normalize_evidence(source)
    if args.normalized_evidence_output:
        write_json(args.normalized_evidence_output, normalized)
    scored = score_evidence(normalized)
    write_json(args.output, scored)
    print(f"{FORMAL_ID} offline valid={int(scored['valid'])} total={scored['total']:.12f} output={args.output}")
    return 0
if __name__ == '__main__':
    raise SystemExit(main())

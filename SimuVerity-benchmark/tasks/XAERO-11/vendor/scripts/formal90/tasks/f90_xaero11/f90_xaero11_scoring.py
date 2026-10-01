"""XAERO-11 public-contract scorer with geometric aggregation.

Canonical evidence contains the declared 7/5/6/6 channels directly.  Optional
per-channel availability masks and source maps are supported when present;
otherwise delivered canonical channels are treated as available.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from statistics import mean
from typing import Any
import f90_xaero11_scoring_core as core
TASK_ID = core.TASK_ID
SCENARIOS = core.SCENARIOS
LOGS = core.LOGS
STRUCTURE = core.STRUCTURE
WEIGHTS = core.WEIGHTS
WIDTHS = {'attitude_state': 7, 'estimation_state': 5, 'actuator_state': 6, 'environment_state': 6}

def mask(log: dict[str, Any], width: int) -> list[bool]:
    raw = log.get('availability')
    if raw is None:
        return [True] * width
    if isinstance(raw, list) and len(raw) == width:
        return [item is True for item in raw]
    return []

def metric_present(scenario: dict[str, Any], name: str) -> bool:
    availability = scenario.get('metric_availability')
    if availability is None:
        return True
    return availability.get(name) is True

def gate(evidence: dict[str, Any], path: Path) -> tuple[bool, list[str], dict[str, Any]]:
    failures: list[str] = []
    if evidence.get('task_id') != TASK_ID:
        failures.append('wrong_task_id')
    for key in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete'):
        if evidence.get(key) is not True:
            failures.append(key)
    if evidence.get('static_audit', {}).get('core_path_qualified') is not True:
        failures.append('anti_cheat:connected_dynamic_core')
    scenarios = core.smap(evidence)
    if list(scenarios) != SCENARIOS:
        failures.append('scenario_set_or_order')
    for sid in SCENARIOS:
        scenario = scenarios.get(sid)
        if not scenario or scenario.get('valid') is not True:
            failures.append(f'{sid}:invalid')
            continue
        logs = scenario.get('logs', {})
        if set(logs) != LOGS:
            failures.append(f'{sid}:output_contract')
            continue
        for name, width in WIDTHS.items():
            log = logs[name]
            if int(log.get('channels', 0)) != width or int(log.get('samples', 0)) < 50:
                failures.append(f'{sid}:{name}_shape')
            if len(mask(log, width)) != width:
                failures.append(f'{sid}:{name}_availability')
            sources = log.get('sources')
            if sources is not None and (not isinstance(sources, list) or len(sources) != width):
                failures.append(f'{sid}:{name}_source_map')
        data_path = path.parent / scenario.get('data_file', '')
        if not data_path.is_file():
            failures.append(f'{sid}:missing_data')
        if scenario.get('metrics', {}).get('all_finite') is not True:
            failures.append(f'{sid}:nonfinite')
    causal_metrics = core.causal(scenarios)
    return (not failures, failures, causal_metrics)

def score(evidence: dict[str, Any], path: Path, evidence_role: str='candidate') -> dict[str, Any]:
    if evidence_role == 'reference':
        passed, failures, causal_metrics = core.gate(evidence, path)
    elif evidence_role == 'candidate':
        passed, failures, causal_metrics = gate(evidence, path)
    else:
        raise ValueError(f'unsupported evidence_role: {evidence_role}')
    scenarios = core.smap(evidence)
    if not passed:
        groups = {name: 0.0 for name in WEIGHTS}
        raw = 0.0
        missing: list[str] = []
    else:
        rows = [scenarios[sid] for sid in SCENARIOS]
        metrics = [row['metrics'] for row in rows]
        qtrue = mean((core.low(float(m['true_quaternion_norm_max_error']), 1e-10, 0.001) if metric_present(row, 'true_quaternion') else 0.0 for row, m in zip(rows, metrics)))
        qest = mean((core.low(float(m['estimated_quaternion_norm_max_error']), 1e-10, 0.001) if metric_present(row, 'estimated_quaternion') else 0.0 for row, m in zip(rows, metrics)))
        estimation = mean((core.low(float(m['attitude_estimation_error_rms']), 0.0001, 0.005) if metric_present(row, 'attitude_estimation_error') else 0.0 for row, m in zip(rows, metrics)))
        recovery = core.high(float(causal_metrics['minimum_detumble_recovery_fraction']), 0.2, 0.5)
        groups = {'A': mean([qtrue, qest, estimation, recovery])}
        groups['Q'] = 100.0
        mechanism = 100 * mean((1.0 if evidence.get('structure', {}).get(key) is True else 0.0 for key in STRUCTURE))
        active_actuation = mean((core.high(float(m['control_torque_peak_Nm']), 1e-10, 1e-08) if metric_present(row, 'magnetorquer_torque') and metric_present(row, 'thruster_torque') else 0.0 for row, m in zip(rows, metrics)))
        active_environment = mean((core.high(float(m['disturbance_torque_rms_Nm']), 1e-12, 1e-09) if metric_present(row, 'disturbance_torque') else 0.0 for row, m in zip(rows, metrics)))
        active_dipole = mean((core.high(float(m['magnetic_dipole_peak_Am2']), 1e-10, 1e-08) if metric_present(row, 'commanded_magnetic_dipole') else 0.0 for row, m in zip(rows, metrics)))
        groups['M'] = mean([mechanism, active_actuation, active_environment, active_dipole])
        groups['C'] = mean([core.high(float(causal_metrics['minimum_detumble_recovery_fraction']), 0.2, 0.5), core.high(float(causal_metrics['sensor_noise_estimation_error_ratio']), 1.5, 3), core.high(float(causal_metrics['disturbance_torque_ratio']), 1.15, 1.4), core.high(float(causal_metrics['mode_control_peak_ratio']), 10, 100)])
        bounds = []
        for row, m in zip(rows, metrics):
            bounds.append(mean([core.low(float(m['true_quaternion_norm_max_error']), 1e-10, 0.001) if metric_present(row, 'true_quaternion') else 0.0, core.low(float(m['estimated_quaternion_norm_max_error']), 1e-10, 0.001) if metric_present(row, 'estimated_quaternion') else 0.0, core.low(float(m['peak_body_rate_rad_s']), 0.1, 0.2) if metric_present(row, 'body_rate') else 0.0, core.low(float(m['control_torque_peak_Nm']), 0.01, 0.05) if metric_present(row, 'magnetorquer_torque') and metric_present(row, 'thruster_torque') else 0.0]))
        groups['R'] = min(bounds)
        motion = mean((core.high(float(m['attitude_dynamic_range']), 0.0001, 0.01) if metric_present(row, 'true_quaternion') else 0.0 for row, m in zip(rows, metrics)))
        actuation_dynamic = mean((core.high(float(m['actuator_dynamic_range_Nm']), 1e-10, 1e-08) if metric_present(row, 'magnetorquer_torque') and metric_present(row, 'thruster_torque') else 0.0 for row, m in zip(rows, metrics)))
        groups['D'] = mean([motion, actuation_dynamic, recovery])
        groups = {name: round(max(0.0, min(100.0, value)), 9) for name, value in groups.items()}
        raw = weighted_geometric_total(groups, WEIGHTS)
        missing = sorted({name for row in rows for name, present in row.get('metric_availability', {}).items() if present is not True})
    performance_reasons = []
    if passed:
        for name in ('initial_rate_effective', 'sensor_noise_effective', 'disturbance_scale_effective', 'mode_selection_effective'):
            if causal_metrics[name] is not True:
                performance_reasons.append(name)
    return {'schema': 'simuverity.f90-xaero11-offline-score.v1', 'task_id': TASK_ID, 'policy_id': 'simuverity-101-v1:f90-xaero-11:scoring', 'offline_only': True, 'matlab_invoked': False, 'score_eligible': passed, 'G': 1 if passed else 0, 'gate': {'G': 1 if passed else 0, 'passed': passed, 'failures': failures}, 'weights': WEIGHTS, 'group_scores': groups, 'raw_score': raw, 'causal_metrics': causal_metrics, 'scenario_metrics': {sid: scenarios.get(sid, {}).get('metrics', {}) for sid in SCENARIOS}, 'unavailable_metric_components_scored_zero': missing, 'performance_failure_reasons': performance_reasons, 'failure_reasons': failures, 'public_contract_defaults': {'canonical_logs_without_availability_annotations_are_fully_available': True, 'explicit_availability_masks_supported': True}, 'total_aggregation': {'method': 'G_times_weighted_geometric_mean', 'formula': 'G*100*product((group_score/100)^weight)', 'strict_zero_rule': 'any_applicable_group_le_zero_means_total_zero', 'post_total_cap': 'none'}}

def weighted_geometric_total(group_scores: dict[str, float], weights: dict[str, float]) -> float:
    if set(group_scores) != set(weights):
        raise ValueError('group/weight keys differ')
    if not math.isclose(sum(weights.values()), 1.0, rel_tol=0.0, abs_tol=1e-12):
        raise ValueError('weights must sum to one')
    values = {name: float(group_scores[name]) for name in weights}
    if any((not math.isfinite(value) or value < 0.0 or value > 100.0 for value in values.values())):
        raise ValueError('group scores must be finite and in [0, 100]')
    if any((value <= 0.0 for value in values.values())):
        return 0.0
    return round(100.0 * math.exp(sum((weights[name] * math.log(values[name] / 100.0) for name in weights))), 9)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output_dir', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    args.output_dir.mkdir(parents=True, exist_ok=False)
    (args.output_dir / 'score.json').write_text(json.dumps(score(evidence, args.evidence), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()

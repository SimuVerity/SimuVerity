from __future__ import annotations
import argparse, copy, json
from pathlib import Path
from statistics import mean
from typing import Any
TASK_ID = 'F90-XAERO-11'
SCENARIOS = ['nominal_slew', 'three_axis_detumble', 'skew_rate_recovery', 'high_sensor_noise', 'high_disturbance', 'combined_stress']
LOGS = {'attitude_state', 'estimation_state', 'actuator_state', 'environment_state'}
STRUCTURE = ['orbit_and_ephemeris_propagation', 'quaternion_rigid_body_dynamics', 'environmental_disturbance_torques', 'noisy_sensors_and_filtering', 'dynamic_attitude_determination', 'detumbling_and_eigenaxis_slew_modes', 'magnetorquer_and_thruster_allocation', 'closed_feedback_paths']
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.2, 'C': 0.2, 'R': 0.15, 'D': 0.1}

def high(x: float, lo: float, hi: float) -> float:
    return 100 * max(0, min(1, (x - lo) / (hi - lo)))

def low(x: float, good: float, bad: float) -> float:
    return 100 * max(0, min(1, (bad - x) / (bad - good)))

def smap(e: dict[str, Any]) -> dict[str, Any]:
    return {s.get('id', ''): s for s in e.get('scenarios', [])}

def causal(sm: dict[str, Any]) -> dict[str, Any]:
    n = sm.get('nominal_slew', {}).get('metrics', {})
    d = sm.get('three_axis_detumble', {}).get('metrics', {})
    k = sm.get('skew_rate_recovery', {}).get('metrics', {})
    z = sm.get('high_sensor_noise', {}).get('metrics', {})
    h = sm.get('high_disturbance', {}).get('metrics', {})

    def f(m, k, default=0.0):
        return float(m.get(k, default))
    recoveries = []
    for m in (d, k):
        initial = f(m, 'initial_body_rate_norm_rad_s')
        recoveries.append(0.0 if initial <= 0 else 1 - f(m, 'tail_body_rate_rms_rad_s') / initial)
    noise_ratio = f(z, 'attitude_estimation_error_rms') / max(f(n, 'attitude_estimation_error_rms'), 1e-15)
    disturbance_ratio = f(h, 'disturbance_torque_rms_Nm') / max(f(n, 'disturbance_torque_rms_Nm'), 1e-15)
    mode_control_ratio = max(f(d, 'control_torque_peak_Nm'), f(k, 'control_torque_peak_Nm')) / max(f(n, 'control_torque_peak_Nm'), 1e-15)
    return {'detumble_recovery_fractions': recoveries, 'minimum_detumble_recovery_fraction': min(recoveries), 'sensor_noise_estimation_error_ratio': noise_ratio, 'disturbance_torque_ratio': disturbance_ratio, 'mode_control_peak_ratio': mode_control_ratio, 'initial_rate_effective': min(recoveries) >= 0.2, 'sensor_noise_effective': noise_ratio >= 1.5, 'disturbance_scale_effective': disturbance_ratio >= 1.15, 'mode_selection_effective': mode_control_ratio >= 10}

def gate(e: dict[str, Any], path: Path) -> tuple[bool, list[str], dict[str, Any]]:
    fail = []
    if e.get('task_id') != TASK_ID:
        fail.append('wrong_task_id')
    for k in ['load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'runtime_model_unchanged', 'evidence_complete']:
        if e.get(k) is not True:
            fail.append(k)
    sm = smap(e)
    if list(sm) != SCENARIOS:
        fail.append('scenario_set_or_order')
    for sid in SCENARIOS:
        s = sm.get(sid)
        if not s or s.get('valid') is not True:
            fail.append(f'{sid}:invalid')
            continue
        if set(s.get('logs', {})) != LOGS:
            fail.append(f'{sid}:output_contract')
        widths = {'attitude_state': 7, 'estimation_state': 5, 'actuator_state': 6, 'environment_state': 6}
        for name, width in widths.items():
            log = s.get('logs', {}).get(name, {})
            if int(log.get('channels', 0)) != width or int(log.get('samples', 0)) < 50:
                fail.append(f'{sid}:{name}_shape')
        p = path.parent / s.get('data_file', '')
        if not p.is_file():
            fail.append(f'{sid}:missing_data')
        m = s.get('metrics', {})
        if m.get('all_finite') is not True:
            fail.append(f'{sid}:nonfinite')
        if float(m.get('true_quaternion_norm_max_error', 1)) > 0.001:
            fail.append(f'{sid}:true_quaternion')
        if float(m.get('estimated_quaternion_norm_max_error', 1)) > 0.001:
            fail.append(f'{sid}:estimated_quaternion')
    for k in STRUCTURE:
        if e.get('structure', {}).get(k) is not True:
            fail.append('structure:' + k)
    cx = causal(sm)
    for k in ['initial_rate_effective', 'sensor_noise_effective', 'disturbance_scale_effective', 'mode_selection_effective']:
        if cx[k] is not True:
            fail.append('causal:' + k)
    return (not fail, fail, cx)

def score(e: dict[str, Any], path: Path) -> dict[str, Any]:
    passed, fail, cx = gate(e, path)
    sm = smap(e)
    if not passed:
        groups = {k: 0.0 for k in WEIGHTS}
        raw = 0.0
    else:
        ms = [sm[s]['metrics'] for s in SCENARIOS]
        qtrue = mean((low(float(m['true_quaternion_norm_max_error']), 1e-10, 0.001) for m in ms))
        qest = mean((low(float(m['estimated_quaternion_norm_max_error']), 1e-10, 0.001) for m in ms))
        est = mean((low(float(m['attitude_estimation_error_rms']), 0.0001, 0.005) for m in ms))
        recovery = high(float(cx['minimum_detumble_recovery_fraction']), 0.2, 0.5)
        groups = {'A': mean([qtrue, qest, est, recovery])}
        groups['Q'] = 100.0
        mechanism = 100 * mean((1.0 if e['structure'].get(k) is True else 0.0 for k in STRUCTURE))
        active_actuation = mean((high(float(m['control_torque_peak_Nm']), 1e-10, 1e-08) for m in ms))
        active_environment = mean((high(float(m['disturbance_torque_rms_Nm']), 1e-12, 1e-09) for m in ms))
        groups['M'] = mean([mechanism, active_actuation, active_environment])
        groups['C'] = mean([high(float(cx['minimum_detumble_recovery_fraction']), 0.2, 0.5), high(float(cx['sensor_noise_estimation_error_ratio']), 1.5, 3), high(float(cx['disturbance_torque_ratio']), 1.15, 1.4), high(float(cx['mode_control_peak_ratio']), 10, 100)])
        bounds = []
        for m in ms:
            bounds.append(mean([low(float(m['true_quaternion_norm_max_error']), 1e-10, 0.001), low(float(m['estimated_quaternion_norm_max_error']), 1e-10, 0.001), low(float(m['peak_body_rate_rad_s']), 0.1, 0.2), low(float(m['control_torque_peak_Nm']), 0.01, 0.05)]))
        groups['R'] = min(bounds)
        motion = mean((high(float(m['attitude_dynamic_range']), 0.0001, 0.01) for m in ms))
        actdyn = mean((high(float(m['actuator_dynamic_range_Nm']), 1e-10, 1e-08) for m in ms))
        groups['D'] = mean([motion, actdyn, recovery])
        groups = {k: round(max(0, min(100, v)), 9) for k, v in groups.items()}
        raw = round(sum((WEIGHTS[k] * groups[k] for k in WEIGHTS)), 9)
    return {'schema': 'simuverity.f90-xaero11-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'score_eligible': passed, 'gate': {'G': 1 if passed else 0, 'passed': passed, 'failures': fail}, 'weights': WEIGHTS, 'group_scores': groups, 'raw_score': raw, 'causal_metrics': cx, 'scenario_metrics': {s: sm.get(s, {}).get('metrics', {}) for s in SCENARIOS}, 'failure_reasons': fail}

def sanity(e: dict[str, Any], path: Path) -> dict[str, Any]:
    cases = []

    def run(name, m):
        s = score(m, path)
        cases.append({'id': name, 'raw_score': s['raw_score'], 'G': s['gate']['G'], 'failures': s['gate']['failures']})
    for name, log in [('missing_attitude_state', 'attitude_state'), ('missing_estimation_state', 'estimation_state'), ('missing_actuator_state', 'actuator_state'), ('missing_environment_state', 'environment_state')]:
        m = copy.deepcopy(e)
        for s in m['scenarios']:
            s['logs'].pop(log, None)
        run(name, m)
    m = copy.deepcopy(e)
    base = copy.deepcopy(m['scenarios'][0]['metrics'])
    for s in m['scenarios'][1:]:
        s['metrics'] = copy.deepcopy(base)
    run('fixed_outputs_across_scenarios', m)
    m = copy.deepcopy(e)
    m['scenarios'][3]['metrics']['attitude_estimation_error_rms'] = m['scenarios'][0]['metrics']['attitude_estimation_error_rms']
    run('sensor_noise_without_effect', m)
    m = copy.deepcopy(e)
    m['scenarios'][4]['metrics']['disturbance_torque_rms_Nm'] = m['scenarios'][0]['metrics']['disturbance_torque_rms_Nm']
    run('disturbance_scale_without_effect', m)
    m = copy.deepcopy(e)
    m['structure']['closed_feedback_paths'] = False
    m['structure']['magnetorquer_and_thruster_allocation'] = False
    run('disconnected_feedback_or_actuation', m)
    mx = max((x['raw_score'] for x in cases))
    return {'schema': 'simuverity.f90-xaero11-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': mx, 'all_shortcuts_below_threshold': all((x['raw_score'] < 85 for x in cases))}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('evidence', type=Path)
    p.add_argument('output_dir', type=Path)
    p.add_argument('--shortcut-sanity', action='store_true')
    a = p.parse_args()
    e = json.loads(a.evidence.read_text(encoding='utf-8'))
    a.output_dir.mkdir(parents=True, exist_ok=False)
    (a.output_dir / 'score.json').write_text(json.dumps(score(e, a.evidence), indent=2) + '\n', encoding='utf-8')
    if a.shortcut_sanity:
        (a.output_dir / 'shortcut_sanity.json').write_text(json.dumps(sanity(e, a.evidence), indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()

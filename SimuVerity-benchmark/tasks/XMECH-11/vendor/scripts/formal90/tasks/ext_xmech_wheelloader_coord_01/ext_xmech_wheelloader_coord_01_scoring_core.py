"""Pure-offline scorer for EXT-XMECH-WHEELLOADER-COORD-01."""
from __future__ import annotations
import argparse
import copy
import json
import math
import sys
from pathlib import Path
import numpy as np
TASK_ID = 'EXT-XMECH-WHEELLOADER-COORD-01'
EVIDENCE_SCHEMA = 'simuverity.ext-xmech-wheelloader-coord-evidence.v1'
EXPECTED = ('nominal_y_cycle', 'low_friction', 'heavy_payload', 'pump_derate', 'low_hrb_precharge', 'combined_robust')
SCENARIO_INPUTS = {'nominal_y_cycle': (70.0, 1.0, 0.6, 0.5, 1.0, 11.101325), 'low_friction': (38.0, 1.0, 0.42, 0.34, 1.0, 11.101325), 'heavy_payload': (25.0, 1.2, 0.6, 0.5, 1.0, 11.101325), 'pump_derate': (25.0, 1.0, 0.6, 0.5, 0.82, 11.101325), 'low_hrb_precharge': (38.0, 1.0, 0.6, 0.5, 1.0, 9.5), 'combined_robust': (30.0, 1.15, 0.48, 0.39, 0.88, 12.5)}
SCENARIO_FIELDS = ('stop_time_s', 'payload_scale', 'tire_mu_static', 'tire_mu_dynamic', 'implement_pump_scale', 'hrb_precharge_pressure_MPa')
WIDTHS = {'wheel_loader_motion_response': 10, 'wheel_loader_hydraulic_response': 9, 'wheel_loader_powertrain_response': 8, 'wheel_loader_clutch_response': 7}
WEIGHTS = {'A': 0.18, 'Q': 0.12, 'M': 0.24, 'C': 0.2, 'R': 0.16, 'D': 0.1}
SHARED = Path(__file__).resolve().parents[2] / 'shared'
if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))
from ext_scoring_common import strict_weighted_geometric

def utility(value: float, good: float, bad: float, *, lower: bool=True) -> float:
    value = float(value)
    if not math.isfinite(value):
        return 0.0
    if good == bad:
        return float(value <= good if lower else value >= good)
    result = (bad - value) / (bad - good) if lower else (value - bad) / (good - bad)
    return float(np.clip(result, 0.0, 1.0))

def weighted(items: list[tuple[float, float]]) -> float:
    denominator = sum((weight for weight, _ in items))
    return sum((weight * value for weight, value in items)) / denominator if denominator else 0.0

def rms(value: np.ndarray) -> float:
    value = np.asarray(value, float)
    return float(np.sqrt(np.mean(value * value))) if value.size else math.inf

def correlation(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, float).reshape(-1)
    b = np.asarray(b, float).reshape(-1)
    if a.size < 3 or b.size != a.size or np.std(a) < 1e-10 or (np.std(b) < 1e-10):
        return 0.0
    return float(abs(np.corrcoef(a, b)[0, 1]))

def _container(item: dict, name: str, width: int, rows: int) -> tuple[np.ndarray, np.ndarray]:
    raw = np.asarray(item.get(name, []), float)
    if raw.ndim == 1 and width == 1:
        raw = raw[:, None]
    valid_shape = raw.shape == (rows, width)
    if not valid_shape:
        raw = np.zeros((rows, width), float)
    availability = np.asarray(item.get('container_availability', {}).get(name, []), bool).reshape(-1)
    if availability.size != width:
        availability = np.full(width, valid_shape, bool)
    finite = np.all(np.isfinite(raw), axis=0)
    availability &= finite
    raw[:, ~availability] = 0.0
    return (raw, availability)

def _command(item: dict, time_s: np.ndarray) -> np.ndarray:
    source = item.get('input', {})
    knots = np.asarray(source.get('command_time_s', []), float).reshape(-1)
    values = np.asarray(source.get('command_values', []), float)
    if knots.size < 2 or values.shape != (knots.size, 4):
        return np.zeros((time_s.size, 4))
    result = np.zeros((time_s.size, 4))
    for index in range(4):
        result[:, index] = np.interp(time_s, knots, values[:, index])
    return result

def _expected_command(stop_time_s: float) -> tuple[np.ndarray, np.ndarray]:
    profile_path = Path(__file__).with_name('wheel_loader_operator_profiles.json')
    profile = json.loads(profile_path.read_text(encoding='utf-8'))['profiles']['BucketYCycle']
    names = ('vVehPcnt', 'LiftCmd', 'TiltCmd', 'SteerCmd')
    knots = np.unique(np.concatenate([np.array([0.0, stop_time_s]), *(np.asarray(profile[name]['time_s'], float) for name in names)]))
    knots = knots[(knots >= 0.0) & (knots <= stop_time_s)]
    values = np.column_stack([np.interp(knots, np.asarray(profile[name]['time_s'], float), np.asarray(profile[name]['values'], float)) for name in names])
    return (knots, values)

def _scenario_input_matches(name: str, item: dict) -> bool:
    source = item.get('input', {})
    if not isinstance(source, dict):
        return False
    expected = SCENARIO_INPUTS[name]
    try:
        fields_match = all((math.isclose(float(source.get(field, math.nan)), value, rel_tol=0.0, abs_tol=1e-10) for field, value in zip(SCENARIO_FIELDS, expected, strict=True)))
        knots = np.asarray(source.get('command_time_s', []), float).reshape(-1)
        values = np.asarray(source.get('command_values', []), float)
    except (TypeError, ValueError):
        return False
    expected_knots, expected_values = _expected_command(expected[0])
    return bool(fields_match and knots.shape == expected_knots.shape and (values.shape == expected_values.shape) and np.all(np.isfinite(knots)) and np.all(np.isfinite(values)) and np.allclose(knots, expected_knots, rtol=0.0, atol=1e-10) and np.allclose(values, expected_values, rtol=0.0, atol=1e-10))

def scenario_metrics(item: dict) -> dict:
    time_s = np.asarray(item.get('time_s', []), float).reshape(-1)
    stop = float(item.get('input', {}).get('stop_time_s', -1))
    time_ok = bool(time_s.size >= 2 and np.all(np.isfinite(time_s)) and (abs(time_s[0]) <= 1e-08) and (stop >= 20) and (time_s[-1] >= stop - 0.005) and np.all(np.diff(time_s) > 0) and (np.max(np.diff(time_s)) <= 0.0500001))
    if not time_ok:
        return {'time_ok': False, 'availability': {}}
    motion, av_m = _container(item, 'wheel_loader_motion_response', 10, time_s.size)
    hydraulic, av_h = _container(item, 'wheel_loader_hydraulic_response', 9, time_s.size)
    power, av_p = _container(item, 'wheel_loader_powertrain_response', 8, time_s.size)
    clutch, av_c = _container(item, 'wheel_loader_clutch_response', 7, time_s.size)
    command = _command(item, time_s)
    active_speed = np.abs(command[:, 0]) > 3
    availability = {'motion': av_m.tolist(), 'hydraulic': av_h.tolist(), 'powertrain': av_p.tolist(), 'clutch': av_c.tolist()}
    speed_target = 0.3 * command[:, 0]
    speed_rmse = rms(motion[active_speed, 0] - speed_target[active_speed]) if av_m[0] and np.any(active_speed) else math.inf
    lift_corr = correlation(command[:, 1], np.gradient(motion[:, 8], time_s)) if av_m[8] else 0.0
    tilt_corr = correlation(command[:, 2], np.gradient(motion[:, 9], time_s)) if av_m[9] else 0.0
    steer_corr = correlation(command[:, 3], motion[:, 3]) if av_m[3] else 0.0
    dx = np.gradient(motion[:, 1], time_s) if av_m[1] else np.zeros(time_s.size)
    dy = np.gradient(motion[:, 2], time_s) if av_m[2] else np.zeros(time_s.size)
    kinematic_speed = np.sqrt(dx * dx + dy * dy) * 3.6
    signed_kinematic = kinematic_speed * np.sign(motion[:, 0] + 1e-12)
    kinematic_rmse = rms(motion[:, 0] - signed_kinematic) if all(av_m[:3]) else math.inf
    wheel_slip = rms(motion[:, 4:8] - motion[:, [0]]) if av_m[0] and np.all(av_m[4:8]) else math.inf
    pressure_channels = [2, 3, 4, 5, 8]
    max_pressure = float(np.max(np.abs(hydraulic[:, pressure_channels]))) if np.all(av_h[pressure_channels]) else math.inf
    clutch_bounds = float(np.max(np.maximum(-clutch, clutch - 1))) if np.all(av_c) else math.inf
    pressure_activity = float(np.std(hydraulic[:, 2:6])) if np.all(av_h[2:6]) else 0.0
    pump_dp_activity = float(np.std(hydraulic[:, 8])) if av_h[8] else 0.0
    flow_activity = float(np.std(hydraulic[:, 6:8])) if np.all(av_h[6:8]) else 0.0
    force_activity = float(np.std(hydraulic[:, 0:2])) if np.all(av_h[:2]) else 0.0
    engine_torque_activity = float(np.std(power[:, 0])) if av_p[0] else 0.0
    power_activity = float(np.std(power[:, 1:6])) if np.all(av_p[1:6]) else 0.0
    accumulator_activity = float(np.ptp(power[:, 6])) if av_p[6] else 0.0
    displacement_activity = float(np.ptp(power[:, 7])) if av_p[7] else 0.0
    clutch_activity = float(np.max(np.ptp(clutch, axis=0))) if np.all(av_c) else 0.0
    speed_response = utility(speed_rmse, 1.5, 7.0)
    linkage_response = min(utility(lift_corr, 0.22, 0.02, lower=False), utility(tilt_corr, 0.22, 0.02, lower=False))
    steering_response = utility(steer_corr, 0.25, 0.03, lower=False)
    kinematics = utility(kinematic_rmse, 0.5, 3.0)
    hydraulic_mechanism = min(utility(pressure_activity, 8, 0.5, lower=False), utility(pump_dp_activity, 8, 0.5, lower=False), utility(flow_activity, 0.015, 0.0005, lower=False), utility(force_activity, 500, 20, lower=False))
    power_mechanism = min(utility(engine_torque_activity, 5.0, 0.2, lower=False), utility(power_activity, 3.0, 0.1, lower=False), utility(accumulator_activity, 0.08, 0.002, lower=False), utility(displacement_activity, 0.5, 0.02, lower=False))
    clutch_mechanism = utility(clutch_activity, 0.6, 0.05, lower=False)
    quality = min(utility(wheel_slip, 4.0, 18.0), utility(max_pressure, 230.0, 275.0), utility(clutch_bounds, 1e-08, 0.05))
    reversal_required = bool(np.any(command[:, 0] > 3) and np.any(command[:, 0] < -3))
    reversal = 0.0
    if reversal_required and av_m[0]:
        reversal = min(utility(np.max(motion[:, 0]), 3.0, 0.2, lower=False), utility(-np.min(motion[:, 0]), 3.0, 0.2, lower=False))
    dynamics_terms = [(0.25, utility(clutch_activity, 0.6, 0.05, lower=False)), (0.2, utility(accumulator_activity, 0.08, 0.002, lower=False))]
    if reversal_required:
        dynamics_terms.insert(0, (0.55, reversal))
    dynamics = weighted(dynamics_terms)
    robustness = min(speed_response, quality, linkage_response, steering_response)
    return {'time_ok': True, 'availability': availability, 'speed_rmse_kph': speed_rmse, 'lift_response_correlation': lift_corr, 'tilt_response_correlation': tilt_corr, 'steering_response_correlation': steer_corr, 'kinematic_rmse_kph': kinematic_rmse, 'wheel_slip_rms_kph': wheel_slip, 'max_hydraulic_pressure_bar': max_pressure, 'pressure_activity_bar': pressure_activity, 'implement_pump_dp_activity_bar': pump_dp_activity, 'flow_activity_kgps': flow_activity, 'force_activity_N': force_activity, 'engine_torque_activity_Nm': engine_torque_activity, 'power_activity_kW': power_activity, 'accumulator_activity_MPa': accumulator_activity, 'pump_displacement_activity_cm3_rev': displacement_activity, 'clutch_activity': clutch_activity, 'reversal_required_by_command': reversal_required, 'reversal_utility': reversal if reversal_required else None, 'utilities': {'speed_response': speed_response, 'linkage_response': linkage_response, 'steering_response': steering_response, 'kinematics': kinematics, 'hydraulic_mechanism': hydraulic_mechanism, 'power_mechanism': power_mechanism, 'clutch_mechanism': clutch_mechanism, 'quality': quality, 'dynamics': dynamics, 'robustness': robustness}, '_time': time_s, '_motion': motion, '_hydraulic': hydraulic, '_power': power}

def _relative_contrast(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    scale = max(rms(a), rms(b), 1e-06)
    return rms(a - b) / scale

def causal_contrasts(metrics: dict[str, dict]) -> dict:
    nominal = metrics['nominal_y_cycle']
    result: dict[str, dict] = {}
    definitions = {'low_friction': ('_motion', 'motion', np.array([0, 4, 5, 6, 7]), 0.025, 0.002), 'heavy_payload': ('_hydraulic', 'hydraulic', slice(0, 6), 0.025, 0.002), 'pump_derate': ('_hydraulic', 'hydraulic', slice(6, 9), 0.025, 0.002), 'low_hrb_precharge': ('_power', 'powertrain', slice(5, 8), 0.025, 0.002)}
    for name, (field, availability_name, channels, good, bad) in definitions.items():
        other = metrics[name]
        nominal_available = np.asarray(nominal['availability'][availability_name], bool)[channels]
        other_available = np.asarray(other['availability'][availability_name], bool)[channels]
        if not (np.all(nominal_available) and np.all(other_available)):
            result[name] = {'available': False, 'relative_contrast': 0.0, 'utility': 0.0}
            continue
        stop = min(nominal['_time'][-1], other['_time'][-1])
        grid = np.arange(0, stop + 1e-09, 0.05)
        left_all = np.column_stack([np.interp(grid, nominal['_time'], nominal[field][:, j]) for j in range(nominal[field].shape[1])])
        right_all = np.column_stack([np.interp(grid, other['_time'], other[field][:, j]) for j in range(other[field].shape[1])])
        if name == 'low_friction':
            left = left_all[:, 4:8] - left_all[:, [0]]
            right = right_all[:, 4:8] - right_all[:, [0]]
            signal = 'wheel_speed_minus_vehicle_speed'
        else:
            left = left_all[:, channels]
            right = right_all[:, channels]
            signal = field.removeprefix('_')
        contrast = _relative_contrast(left, right)
        result[name] = {'available': True, 'signal': signal, 'relative_contrast': contrast, 'utility': utility(contrast, good, bad, lower=False)}
    return result

def _public_metrics(metrics: dict) -> dict:
    result = copy.deepcopy(metrics)
    for item in result.values():
        for key in list(item):
            if key.startswith('_'):
                del item[key]
    return result

def score_evidence(evidence: dict) -> dict:
    stages = evidence.get('stages', {})
    stage_ok = all((stages.get(name) is True for name in ('setup', 'load', 'update', 'compile', 'smoke')))
    scenarios = {str(item.get('id', '')): item for item in evidence.get('scenarios', []) if isinstance(item, dict)}
    set_ok = set(scenarios) == set(EXPECTED)
    identity_ok = evidence.get('schema') == EVIDENCE_SCHEMA and evidence.get('task_id') == TASK_ID
    interface_ok = evidence.get('public_input_names') == ['wheel_loader_command', 'wheel_loader_environment'] and evidence.get('public_output_names') == list(WIDTHS)
    scenario_validity_ok = set_ok and evidence.get('scenario_count') == len(EXPECTED) and (evidence.get('all_scenarios_valid') is True) and all((item.get('valid') is True for item in scenarios.values()))
    scenario_inputs_ok = set_ok and all((_scenario_input_matches(name, scenarios[name]) for name in EXPECTED))
    metrics = {name: scenario_metrics(scenarios[name]) for name in EXPECTED if name in scenarios}
    time_ok = set_ok and all((item.get('time_ok') for item in metrics.values()))
    runtime_model_ok = evidence.get('runtime_model_unchanged') is True
    gate_checks = {'identity': identity_ok, 'public_interface': interface_ok, 'execution_stages': stage_ok, 'scenario_set': set_ok, 'scenario_validity': scenario_validity_ok, 'scenario_inputs': scenario_inputs_ok, 'time_coverage': time_ok, 'runtime_model_unchanged': runtime_model_ok}
    gate = int(all(gate_checks.values()))
    failures: list[str] = []
    if gate:
        contrasts = causal_contrasts(metrics)
        accuracy = weighted([(0.45, metrics['nominal_y_cycle']['utilities']['speed_response']), (0.25, metrics['nominal_y_cycle']['utilities']['linkage_response']), (0.15, metrics['nominal_y_cycle']['utilities']['steering_response']), (0.15, min((item['utilities']['speed_response'] for item in metrics.values())))])
        quality = min((item['utilities']['quality'] for item in metrics.values()))
        mechanism = min(min((item['utilities']['kinematics'] for item in metrics.values())), min((item['utilities']['hydraulic_mechanism'] for item in metrics.values())), min((item['utilities']['power_mechanism'] for item in metrics.values())), min((item['utilities']['clutch_mechanism'] for item in metrics.values())))
        control = min((value['utility'] for value in contrasts.values()))
        robustness = min((item['utilities']['robustness'] for item in metrics.values()))
        dynamics = min((item['utilities']['dynamics'] for item in metrics.values()))
        groups = {'A': accuracy, 'Q': quality, 'M': mechanism, 'C': control, 'R': robustness, 'D': dynamics}
        if mechanism == 0:
            failures.append('coupled_vehicle_hydraulic_powertrain_or_clutch_mechanism_not_proven')
        if control == 0:
            failures.append('paired_environment_interventions_not_observable')
    else:
        contrasts = {}
        groups = {name: 0.0 for name in WEIGHTS}
        failures.extend((f'gate:{name}' for name, passed in gate_checks.items() if not passed))
    raw = strict_weighted_geometric(gate, groups, WEIGHTS)
    return {'schema': 'simuverity.ext-offline-score.v1', 'task_id': TASK_ID, 'evaluation_policy_id': 'simuverity-101-v1:ext-xmech-wheelloader-coord-01:scoring', 'G': gate, 'groups': {name: 100 * value for name, value in groups.items()}, 'groups_normalized': groups, 'group_weights': WEIGHTS, 'raw_score': raw, 'raw_reference_admission_threshold': 90.0, 'normalize_threshold_to_100': False, 'admission_pass': bool(gate and raw >= 90.0), 'across_groups': 'strict_weighted_geometric_mean', 'strict_zero_rule': True, 'epsilon_floor': False, 'post_total_cap': False, 'gate_checks': gate_checks, 'scenario_metrics': _public_metrics(metrics), 'causal_contrasts': contrasts, 'failure_reasons': failures}

def shortcut_sanity(evidence: dict) -> dict:
    checks: dict[str, bool] = {}
    base = score_evidence(evidence)
    mutant = copy.deepcopy(evidence)
    for item in mutant['scenarios']:
        rows = len(item['time_s'])
        for name, width in WIDTHS.items():
            item[name] = np.zeros((rows, width)).tolist()
    checks['constant_outputs_mechanism_zero'] = score_evidence(mutant)['groups']['M'] == 0
    mutant = copy.deepcopy(evidence)
    nominal = next((item for item in mutant['scenarios'] if item['id'] == 'nominal_y_cycle'))
    for item in mutant['scenarios']:
        if item is nominal:
            continue
        grid = np.asarray(item['time_s'], float)
        src_time = np.asarray(nominal['time_s'], float)
        for name, width in WIDTHS.items():
            source = np.asarray(nominal[name], float)
            item[name] = np.column_stack([np.interp(grid, src_time, source[:, j]) for j in range(width)]).tolist()
    checks['environment_ignored_control_zero'] = score_evidence(mutant)['groups']['C'] == 0
    mutant = copy.deepcopy(evidence)
    for item in mutant['scenarios']:
        item['container_availability']['wheel_loader_hydraulic_response'] = [False] * 9
    checks['missing_hydraulics_mechanism_zero'] = score_evidence(mutant)['groups']['M'] == 0
    mutant = copy.deepcopy(evidence)
    for item in mutant['scenarios']:
        item['container_availability']['wheel_loader_powertrain_response'] = [False] * 8
    checks['missing_powertrain_mechanism_zero'] = score_evidence(mutant)['groups']['M'] == 0
    mutant = copy.deepcopy(evidence)
    mutant['scenarios'][0]['container_availability']['wheel_loader_motion_response'][9] = False
    partial = score_evidence(mutant)
    checks['single_channel_partial_not_gate_failure'] = partial['G'] == 1 and partial['raw_score'] < base['raw_score']
    return {'task_id': TASK_ID, 'checks': checks, 'pass': all(checks.values())}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--shortcut-output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    args.output.write_text(json.dumps(score_evidence(evidence), indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    if args.shortcut_output:
        result = shortcut_sanity(evidence)
        if not result['pass']:
            raise AssertionError('shortcut_sanity failed')
        args.shortcut_output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
if __name__ == '__main__':
    main()

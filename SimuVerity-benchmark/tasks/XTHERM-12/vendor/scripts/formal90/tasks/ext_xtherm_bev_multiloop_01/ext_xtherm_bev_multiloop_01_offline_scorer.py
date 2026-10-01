"""Pure-offline waveform scorer for EXT-XTHERM-BEV-MULTILOOP-01.

The scorer reads only a complete JSON evidence artifact.  It never imports
MATLAB, opens a model, or reconstructs an absent public channel.  Lifecycle
success controls G; missing or malformed public outputs zero only the metrics
that consume those outputs.
"""
from __future__ import annotations
import argparse
import copy
import json
import math
import sys
from pathlib import Path
from typing import Any
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'shared'))
from ext_scoring_common import strict_weighted_geometric
TASK_ID = 'EXT-XTHERM-BEV-MULTILOOP-01'
EVIDENCE_SCHEMA = 'simuverity.ext-xtherm-bev-multiloop-evidence.v1'
EXPECTED_IDS = ('hot_pull_down', 'hot_relaxed', 'hot_fresh_air', 'hot_ac_off', 'low_occupancy', 'high_occupancy')
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.22, 'C': 0.24, 'R': 0.14, 'D': 0.1}
OFFICIAL_INPUTS = {'hot_pull_down': (40.0, 0.65, 22.0, 5, 1, 1), 'hot_relaxed': (40.0, 0.65, 30.0, 5, 1, 1), 'hot_fresh_air': (40.0, 0.65, 22.0, 5, 1, 0), 'hot_ac_off': (40.0, 0.65, 22.0, 5, 0, 1), 'low_occupancy': (35.0, 0.5, 24.0, 1, 1, 1), 'high_occupancy': (35.0, 0.5, 24.0, 5, 1, 1)}
INPUT_FIELDS = ('ambient_temperature_degC', 'relative_humidity', 'cabin_setpoint_degC', 'occupant_count', 'ac_enable', 'recirculation_enable')

def high(value: float, zero: float, full: float) -> float:
    """Piecewise-linear utility for a larger-is-better metric."""
    if not math.isfinite(value):
        return 0.0
    if value <= zero:
        return 0.0
    if value >= full:
        return 1.0
    return (value - zero) / (full - zero)

def low(value: float, full: float, zero: float) -> float:
    """Piecewise-linear utility for a smaller-is-better metric."""
    if not math.isfinite(value):
        return 0.0
    if value <= full:
        return 1.0
    if value >= zero:
        return 0.0
    return (zero - value) / (zero - full)

def weighted(parts: list[tuple[float, float]]) -> float:
    denominator = sum((weight for weight, _ in parts))
    return sum((weight * value for weight, value in parts)) / denominator if denominator else 0.0

def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0

def rms(values: np.ndarray) -> float:
    array = np.asarray(values, dtype=float)
    return float(np.sqrt(np.mean(array * array))) if array.size else 0.0

def _time(item: dict[str, Any]) -> tuple[np.ndarray, bool]:
    try:
        time_s = np.asarray(item.get('time_s', []), dtype=float).reshape(-1)
    except (TypeError, ValueError):
        return (np.asarray([], dtype=float), False)
    valid = bool(time_s.size >= 301 and np.all(np.isfinite(time_s)) and (abs(float(time_s[0])) <= 1e-08) and (float(time_s[-1]) >= 29.999999) and np.all(np.diff(time_s) > 0.0) and (float(np.max(np.diff(time_s))) <= 0.100000001))
    return (time_s, valid)

def _array(item: dict[str, Any], name: str, width: int, rows: int) -> tuple[np.ndarray, bool]:
    try:
        value = np.asarray(item.get(name, []), dtype=float)
    except (TypeError, ValueError):
        return (np.empty((0, width), dtype=float), False)
    valid = bool(value.ndim == 2 and value.shape == (rows, width) and np.all(np.isfinite(value)))
    return (value if valid else np.empty((0, width), dtype=float), valid)

def _input_contract(item: dict[str, Any], scenario_id: str) -> tuple[dict[str, float], float]:
    source = item.get('input', item)
    expected = OFFICIAL_INPUTS[scenario_id]
    decoded: dict[str, float] = {}
    checks: list[bool] = []
    for field, target in zip(INPUT_FIELDS, expected):
        try:
            value = float(source[field])
        except (KeyError, TypeError, ValueError):
            value = math.nan
        decoded[field] = value
        checks.append(math.isfinite(value) and abs(value - float(target)) <= 1e-09)
    return (decoded, float(all(checks)))

def _copy_fraction(a: np.ndarray, b: np.ndarray, tolerance: float=1e-07) -> float:
    if a.size == 0 or a.shape != b.shape:
        return 1.0
    return float(np.mean(np.abs(a - b) <= tolerance))

def _bound_utility(maximum: float, full: float, zero: float) -> float:
    return low(maximum, full, zero)

def scenario_metrics(item: dict[str, Any]) -> dict[str, Any]:
    scenario_id = str(item.get('id', ''))
    time_s, time_valid = _time(item)
    rows = int(time_s.size)
    vehicle, vehicle_valid = _array(item, 'bev_vehicle_response', 2, rows)
    temperature, temperature_valid = _array(item, 'bev_temperature_response', 6, rows)
    heat, heat_valid = _array(item, 'bev_heat_flow_response', 6, rows)
    actuator, actuator_valid = _array(item, 'bev_actuator_response', 5, rows)
    inputs, input_contract_u = _input_contract(item, scenario_id)
    expected_speed = np.minimum(1.62 * time_s, 50.0) if time_valid else np.asarray([], dtype=float)
    vehicle_reference_rmse = math.inf
    vehicle_tracking_rmse = math.inf
    vehicle_final_error = math.inf
    vehicle_tracking_u = 0.0
    vehicle_reference_u = 0.0
    speed_copy_fraction = 1.0
    speed_slew_kph_s = math.inf
    speed_bound_u = 0.0
    if time_valid and vehicle_valid:
        speed_ref, speed_actual = (vehicle[:, 0], vehicle[:, 1])
        vehicle_reference_rmse = rms(speed_ref - expected_speed)
        vehicle_tracking_rmse = rms(speed_actual - speed_ref)
        vehicle_final_error = abs(float(speed_actual[-1] - speed_ref[-1]))
        vehicle_reference_u = low(vehicle_reference_rmse, 0.02, 0.25)
        vehicle_tracking_u = weighted([(0.7, low(vehicle_tracking_rmse, 1.5, 8.0)), (0.3, low(vehicle_final_error, 1.5, 7.0))])
        speed_copy_fraction = _copy_fraction(speed_actual, speed_ref)
        speed_slew_kph_s = float(np.max(np.abs(np.diff(speed_actual) / np.diff(time_s))))
        speed_bound_u = _bound_utility(float(np.max(np.abs(vehicle))), 90.0, 160.0)
    ambient_mirror_rmse = math.inf
    setpoint_mirror_rmse = math.inf
    cabin_initial_degC = math.nan
    cabin_final_degC = math.nan
    cabin_cooling_degC = 0.0
    thermal_progress_fraction = 0.0
    thermal_progress_u = 0.0
    component_delta_degC = 0.0
    cabin_copy_fraction = 1.0
    temperature_slew_degC_s = math.inf
    temperature_bound_u = 0.0
    if time_valid and temperature_valid:
        cabin = temperature[:, 0]
        ambient = temperature[:, 1]
        setpoint = temperature[:, 2]
        ambient_mirror_rmse = rms(ambient - inputs['ambient_temperature_degC'])
        setpoint_mirror_rmse = rms(setpoint - inputs['cabin_setpoint_degC'])
        cabin_initial_degC = float(cabin[0])
        cabin_final_degC = float(cabin[-1])
        cabin_cooling_degC = cabin_initial_degC - cabin_final_degC
        initial_error = max(cabin_initial_degC - inputs['cabin_setpoint_degC'], 1.0)
        thermal_progress_fraction = max(0.0, cabin_cooling_degC / initial_error)
        thermal_progress_u = high(thermal_progress_fraction, 0.002, 0.025)
        component_delta_degC = float(np.max(np.abs(temperature[-1, 3:6] - temperature[0, 3:6])))
        cabin_copy_fraction = max(_copy_fraction(cabin, ambient), _copy_fraction(cabin, setpoint))
        temperature_slew_degC_s = float(np.max(np.abs(np.diff(temperature[:, [0, 3, 4, 5]], axis=0) / np.diff(time_s)[:, None])))
        temperature_bound_u = _bound_utility(float(np.max(np.abs(temperature))), 160.0, 250.0)
    heat_rms_W = [0.0] * 6
    heat_level_u = 0.0
    heat_variation_u = 0.0
    heat_bound_u = 0.0
    heat_max_std_W = 0.0
    if heat_valid:
        heat_rms_W = [rms(heat[:, index]) for index in range(6)]
        heat_level_u = high(rms(heat), 1.0, 100.0)
        heat_max_std_W = float(np.max(np.std(heat, axis=0)))
        heat_variation_u = high(heat_max_std_W, 0.1, 10.0)
        heat_bound_u = _bound_utility(float(np.max(np.abs(heat))), 2000000.0, 20000000.0)
    actuator_rms = [0.0] * 5
    actuator_level_u = 0.0
    actuator_variation_u = 0.0
    actuator_bound_u = 0.0
    actuator_max_std = 0.0
    if actuator_valid:
        actuator_rms = [rms(actuator[:, index]) for index in range(5)]
        actuator_level_u = high(mean(actuator_rms), 0.005, 0.08)
        actuator_max_std = float(np.max(np.std(actuator, axis=0)))
        actuator_variation_u = high(actuator_max_std, 0.0001, 0.01)
        violation = max(0.0, -float(np.min(actuator)), float(np.max(actuator)) - 1.0)
        actuator_bound_u = low(violation, 0.01, 0.5)
    ambient_setpoint_u = weighted([(0.5, low(ambient_mirror_rmse, 0.02, 0.2)), (0.5, low(setpoint_mirror_rmse, 0.02, 0.2))])
    logs_complete = float(time_valid and vehicle_valid and temperature_valid and heat_valid and actuator_valid)
    bounded_u = min(speed_bound_u, temperature_bound_u, heat_bound_u, actuator_bound_u)
    interface_u = min(logs_complete, input_contract_u, vehicle_reference_u, ambient_setpoint_u, bounded_u)
    heat_scales = np.asarray([500.0, 50.0, 5000.0, 4000.0, 4000.0, 50.0])
    response_signature = [cabin_cooling_degC / 5.0, cabin_final_degC / 40.0 if math.isfinite(cabin_final_degC) else 0.0, component_delta_degC / 2.0, *list(np.asarray(heat_rms_W) / heat_scales), *actuator_rms]
    mechanism_magnitude_u = weighted([(0.55, heat_level_u), (0.45, actuator_level_u)])
    mechanism_dynamic_u = weighted([(0.55, heat_variation_u), (0.45, actuator_variation_u)])
    ac_enabled = int(round(inputs.get('ac_enable', 0.0))) == 1
    thermal_requirement_u = thermal_progress_u if ac_enabled else 1.0
    state_evolution_u = high(abs(cabin_cooling_degC), 0.05, 0.6) if ac_enabled else high(component_delta_degC, 0.01, 0.15)
    dynamic_u = weighted([(0.35, low(vehicle_final_error, 1.5, 7.0)), (0.25, min(low(speed_slew_kph_s, 3.5, 15.0), low(temperature_slew_degC_s, 2.0, 15.0))), (0.4, state_evolution_u)])
    robustness_u = weighted([(0.35, vehicle_tracking_u), (0.3, thermal_requirement_u), (0.2, bounded_u), (0.15, mechanism_magnitude_u)])
    return {'id': scenario_id, 'time_valid': time_valid, 'input_contract_u': input_contract_u, 'vehicle_available': vehicle_valid, 'temperature_available': temperature_valid, 'heat_available': heat_valid, 'actuator_available': actuator_valid, 'interface_u': interface_u, 'bounded_u': bounded_u, 'vehicle_reference_rmse_kph': vehicle_reference_rmse, 'vehicle_reference_u': vehicle_reference_u, 'vehicle_tracking_rmse_kph': vehicle_tracking_rmse, 'vehicle_final_error_kph': vehicle_final_error, 'vehicle_tracking_u': vehicle_tracking_u, 'speed_copy_fraction': speed_copy_fraction, 'cabin_copy_fraction': cabin_copy_fraction, 'ambient_mirror_rmse_degC': ambient_mirror_rmse, 'setpoint_mirror_rmse_degC': setpoint_mirror_rmse, 'cabin_initial_degC': cabin_initial_degC, 'cabin_final_degC': cabin_final_degC, 'cabin_cooling_degC': cabin_cooling_degC, 'thermal_progress_fraction': thermal_progress_fraction, 'thermal_progress_u': thermal_progress_u, 'component_delta_degC': component_delta_degC, 'heat_rms_W': heat_rms_W, 'actuator_rms': actuator_rms, 'heat_level_u': heat_level_u, 'heat_variation_u': heat_variation_u, 'heat_max_std_W': heat_max_std_W, 'actuator_level_u': actuator_level_u, 'actuator_variation_u': actuator_variation_u, 'actuator_max_std': actuator_max_std, 'mechanism_magnitude_u': mechanism_magnitude_u, 'mechanism_dynamic_u': mechanism_dynamic_u, 'dynamic_u': dynamic_u, 'robustness_u': robustness_u, 'response_signature': response_signature}

def _signature_distance(left: dict[str, Any], right: dict[str, Any]) -> float:
    a = np.asarray(left['response_signature'], dtype=float)
    b = np.asarray(right['response_signature'], dtype=float)
    return float(np.linalg.norm(a - b) / math.sqrt(a.size))

def causal_metrics(metrics_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    pull = metrics_by_id['hot_pull_down']
    relaxed = metrics_by_id['hot_relaxed']
    fresh = metrics_by_id['hot_fresh_air']
    ac_off = metrics_by_id['hot_ac_off']
    low_occ = metrics_by_id['low_occupancy']
    high_occ = metrics_by_id['high_occupancy']
    setpoint_distance = _signature_distance(pull, relaxed)
    setpoint_cooling_delta = pull['cabin_cooling_degC'] - relaxed['cabin_cooling_degC']
    setpoint_blower_delta = pull['actuator_rms'][4] - relaxed['actuator_rms'][4]
    setpoint_u = min(high(setpoint_distance, 0.005, 0.035), high(setpoint_cooling_delta, 0.25, 1.5), high(setpoint_blower_delta, 0.015, 0.1))
    ac_distance = _signature_distance(pull, ac_off)
    ac_cooling_delta = pull['cabin_cooling_degC'] - ac_off['cabin_cooling_degC']
    ac_compressor_delta = pull['actuator_rms'][1] - ac_off['actuator_rms'][1]
    ac_u = min(high(ac_distance, 0.005, 0.04), high(ac_cooling_delta, 0.3, 1.5), high(ac_compressor_delta, 0.03, 0.2))
    recirc_distance = _signature_distance(pull, fresh)
    recirc_temperature_margin = fresh['cabin_final_degC'] - pull['cabin_final_degC']
    recirc_u = min(high(recirc_distance, 0.003, 0.015), high(recirc_temperature_margin, 0.01, 0.15))
    occupancy_distance = _signature_distance(low_occ, high_occ)
    occupancy_temperature_margin = high_occ['cabin_final_degC'] - low_occ['cabin_final_degC']
    occupancy_u = min(high(occupancy_distance, 0.001, 0.008), high(occupancy_temperature_margin, 0.005, 0.06))
    speed_copy_guard = min((low(row['speed_copy_fraction'], 0.02, 0.98) for row in metrics_by_id.values()))
    cabin_copy_guard = min((low(row['cabin_copy_fraction'], 0.02, 0.98) for row in metrics_by_id.values()))
    copy_guard = min(speed_copy_guard, cabin_copy_guard)
    causal_u = min(setpoint_u, ac_u, recirc_u, occupancy_u, copy_guard)
    return {'setpoint_pair_u': setpoint_u, 'setpoint_signature_distance': setpoint_distance, 'setpoint_cooling_delta_degC': setpoint_cooling_delta, 'setpoint_blower_rms_delta': setpoint_blower_delta, 'ac_enable_pair_u': ac_u, 'ac_signature_distance': ac_distance, 'ac_cooling_delta_degC': ac_cooling_delta, 'ac_compressor_rms_delta': ac_compressor_delta, 'recirculation_pair_u': recirc_u, 'recirculation_signature_distance': recirc_distance, 'recirculation_temperature_margin_degC': recirc_temperature_margin, 'occupancy_pair_u': occupancy_u, 'occupancy_signature_distance': occupancy_distance, 'occupancy_temperature_margin_degC': occupancy_temperature_margin, 'speed_command_copy_guard_u': speed_copy_guard, 'cabin_command_copy_guard_u': cabin_copy_guard, 'causal_u': causal_u}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    scenarios = evidence.get('scenarios', [])
    ids = [str(item.get('id', '')) for item in scenarios if isinstance(item, dict)]
    stages = evidence.get('stages', {})
    gate_checks = {'schema': evidence.get('schema') == EVIDENCE_SCHEMA, 'task_id': evidence.get('task_id') == TASK_ID, 'lifecycle': all((stages.get(name) is True for name in ('setup', 'load', 'update', 'compile', 'smoke'))), 'six_unique_scenarios': len(scenarios) == 6 and set(ids) == set(EXPECTED_IDS) and (len(ids) == len(set(ids))), 'all_official_simulations_valid': len(scenarios) == 6 and all((item.get('simulation_valid') is True for item in scenarios)), 'evidence_complete': evidence.get('evidence_complete') is True}
    gate = int(all(gate_checks.values()))
    failure_reasons = [name for name, passed in gate_checks.items() if not passed]
    metrics_by_id: dict[str, dict[str, Any]] = {}
    if gate_checks['six_unique_scenarios']:
        for item in scenarios:
            row = scenario_metrics(item)
            metrics_by_id[row['id']] = row
            for output, available in (('bev_vehicle_response', row['vehicle_available']), ('bev_temperature_response', row['temperature_available']), ('bev_heat_flow_response', row['heat_available']), ('bev_actuator_response', row['actuator_available'])):
                if not available:
                    failure_reasons.append(f"{row['id']}:missing_or_malformed:{output}")
            if not row['time_valid']:
                failure_reasons.append(f"{row['id']}:invalid_time_contract")
            if row['input_contract_u'] == 0.0:
                failure_reasons.append(f"{row['id']}:official_input_binding_mismatch")
    if gate and set(metrics_by_id) == set(EXPECTED_IDS):
        rows = [metrics_by_id[name] for name in EXPECTED_IDS]
        enabled = [row for row in rows if int(round(OFFICIAL_INPUTS[row['id']][4])) == 1]
        causal = causal_metrics(metrics_by_id)
        for name in ('setpoint_pair_u', 'ac_enable_pair_u', 'recirculation_pair_u', 'occupancy_pair_u'):
            if causal[name] == 0.0:
                failure_reasons.append(f'causal_pair_zero:{name}')
        for row in rows:
            if row['vehicle_reference_u'] < 0.999999:
                failure_reasons.append(f"{row['id']}:vehicle_reference_contract_bottleneck")
        heat_and_actuator_available = float(all((row['heat_available'] and row['actuator_available'] for row in rows)))
        global_heat_dynamic_guard = high(mean([row['heat_max_std_W'] for row in rows]), 0.1, 10.0)
        global_actuator_dynamic_guard = high(mean([row['actuator_max_std'] for row in rows]), 0.0001, 0.005)
        mechanism_u = min(heat_and_actuator_available, global_heat_dynamic_guard, global_actuator_dynamic_guard, mean([row['mechanism_magnitude_u'] for row in rows]))
        groups = {'A': weighted([(0.45, mean([row['vehicle_tracking_u'] for row in rows])), (0.55, mean([row['thermal_progress_u'] for row in enabled]))]), 'Q': min((row['interface_u'] for row in rows)), 'M': mechanism_u, 'C': causal['causal_u'], 'R': min((row['robustness_u'] for row in rows)), 'D': min((row['dynamic_u'] for row in rows))}
    else:
        causal = {}
        groups = {name: 0.0 for name in WEIGHTS}
    raw_score = strict_weighted_geometric(gate, groups, WEIGHTS)
    return {'schema': 'simuverity.ext-offline-score.v1', 'task_id': TASK_ID, 'evaluation_policy_id': 'simuverity-101-v1:ext-xtherm-bev-multiloop-01:scoring', 'G': gate, 'gate_checks': gate_checks, 'groups': {name: round(100.0 * groups[name], 6) for name in WEIGHTS}, 'groups_normalized': {name: groups[name] for name in WEIGHTS}, 'group_weights': WEIGHTS, 'raw_score': round(raw_score, 6), 'raw_reference_admission_threshold': 90.0, 'normalize_threshold_to_100': False, 'admission_pass': bool(gate and raw_score >= 90.0), 'across_groups': 'strict_weighted_geometric_mean', 'strict_zero_rule': True, 'epsilon_floor': False, 'post_total_cap': False, 'scenario_metrics': metrics_by_id, 'causal_metrics': causal, 'partial_output_policy': 'missing or malformed logs zero only dependent metrics; no reconstruction', 'implementation_neutral': True, 'failure_reasons': failure_reasons}

def shortcut_sanity(evidence: dict[str, Any]) -> dict[str, Any]:
    base = score_evidence(evidence)
    checks: dict[str, bool] = {}
    missing_heat = copy.deepcopy(evidence)
    for item in missing_heat['scenarios']:
        item.pop('bev_heat_flow_response', None)
    result = score_evidence(missing_heat)
    checks['missing_heat_flow_collapses_M'] = result['G'] == 1 and result['groups']['M'] == 0.0
    missing_actuator = copy.deepcopy(evidence)
    for item in missing_actuator['scenarios']:
        item.pop('bev_actuator_response', None)
    result = score_evidence(missing_actuator)
    checks['missing_applied_actuator_collapses_M'] = result['G'] == 1 and result['groups']['M'] == 0.0
    replay = copy.deepcopy(evidence)
    source = replay['scenarios'][0]
    for item in replay['scenarios'][1:]:
        for name in ('bev_vehicle_response', 'bev_temperature_response', 'bev_heat_flow_response', 'bev_actuator_response'):
            item[name] = copy.deepcopy(source[name])
    result = score_evidence(replay)
    checks['cross_scenario_replay_collapses_C'] = result['groups']['C'] == 0.0
    copied = copy.deepcopy(evidence)
    for item in copied['scenarios']:
        vehicle = np.asarray(item['bev_vehicle_response'], dtype=float)
        vehicle[:, 1] = vehicle[:, 0]
        item['bev_vehicle_response'] = vehicle.tolist()
        temperature = np.asarray(item['bev_temperature_response'], dtype=float)
        temperature[:, 0] = temperature[:, 1]
        item['bev_temperature_response'] = temperature.tolist()
    result = score_evidence(copied)
    checks['command_copy_collapses_C'] = result['groups']['C'] == 0.0
    constant = copy.deepcopy(evidence)
    for item in constant['scenarios']:
        for name in ('bev_vehicle_response', 'bev_temperature_response', 'bev_heat_flow_response', 'bev_actuator_response'):
            data = np.asarray(item[name], dtype=float)
            item[name] = np.repeat(data[[0], :], data.shape[0], axis=0).tolist()
    result = score_evidence(constant)
    checks['constant_outputs_collapse_key_group'] = result['groups']['M'] == 0.0 or result['groups']['C'] == 0.0
    return {'task_id': TASK_ID, 'baseline_raw_score': base['raw_score'], 'checks': checks, 'pass': all(checks.values())}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--shortcut-output', type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding='utf-8'))
    result = score_evidence(evidence)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    if args.shortcut_output:
        args.shortcut_output.parent.mkdir(parents=True, exist_ok=True)
        args.shortcut_output.write_text(json.dumps(shortcut_sanity(evidence), indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return 0
if __name__ == '__main__':
    raise SystemExit(main())

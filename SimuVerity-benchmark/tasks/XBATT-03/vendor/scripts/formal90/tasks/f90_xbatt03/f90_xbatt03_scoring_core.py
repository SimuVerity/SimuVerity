"""Pure-offline scorer for F90-XBATT-03 fixed evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import numpy as np
WEIGHTS = {'A': 0.2, 'Q': 0.1, 'M': 0.3, 'R': 0.2, 'D': 0.2}
REQUIRED = ('summer_city_nominal', 'summer_city_high_solar', 'winter_highway_nominal', 'winter_highway_low_soc', 'summer_city_heavy_duty')

def clip01(value: float) -> float:
    return float(np.clip(value, 0.0, 1.0))

def up(value: float, bad: float, good: float) -> float:
    return clip01((value - bad) / (good - bad)) if good != bad else float(value >= good)

def down(value: float, good: float, bad: float) -> float:
    return clip01((bad - value) / (bad - good)) if bad != good else float(value <= good)

def corr(left: np.ndarray, right: np.ndarray) -> float:
    left = np.asarray(left, dtype=float).ravel()
    right = np.asarray(right, dtype=float).ravel()
    mask = np.isfinite(left) & np.isfinite(right)
    if mask.sum() < 20 or np.std(left[mask]) < 1e-10 or np.std(right[mask]) < 1e-10:
        return 0.0
    return float(abs(np.corrcoef(left[mask], right[mask])[0, 1]))

def load_fixed_evidence(path: Path, evidence: dict) -> tuple[dict, list[str]]:
    failures: list[str] = []
    scenarios: dict[str, dict[str, np.ndarray]] = {}
    expected = {'vehicle_state': 5, 'temperature_state': 7, 'thermal_control': 10, 'heat_flow_state': 4}
    for row in evidence.get('scenarios', []):
        sid = str(row.get('id', ''))
        if not row.get('success', False):
            failures.append(f"{sid or 'unknown'}: simulation failed")
            continue
        source = path.parent / str(row.get('output_file', ''))
        if not source.is_file():
            failures.append(f'{sid}: evidence file missing')
            continue
        raw = json.loads(source.read_text(encoding='utf-8'))
        arrays = {'time_s': np.asarray(raw['time_s'], dtype=float).ravel()}
        n = arrays['time_s'].size
        if n <= 1024 or abs(arrays['time_s'][0]) > 1e-09 or np.any(np.diff(arrays['time_s']) <= 0):
            failures.append(f'{sid}: truncated or invalid time base')
        for name, columns in expected.items():
            arrays[name] = np.asarray(raw[name], dtype=float)
        scenarios[sid] = arrays
    failures.extend((f'missing scenario: {name}' for name in sorted(set(REQUIRED) - set(scenarios))))
    return (scenarios, failures)

def metrics(data: dict[str, np.ndarray]) -> dict[str, float]:
    t = data['time_s']
    v = data['vehicle_state']
    temp = data['temperature_state']
    control = data['thermal_control']
    heat = data['heat_flow_state']
    dt = float(np.median(np.diff(t)))
    command, speed, soc, current, torque = v.T
    ambient, cabin, battery, plate, motor, bci, mco = temp.T
    active = command >= max(5.0, 0.05 * float(np.max(command)))
    if active.sum() < 20:
        active = np.ones_like(command, dtype=bool)
    error = speed - command
    last = t >= max(t[-1] - 90.0, 0.0)
    acceleration = np.gradient(speed / 3.6, dt)
    cabin_target = 22.0
    thermal_authority = np.max(np.abs(control[:, :7]), axis=1)
    binary = control[:, 7:10]
    return {'speed_rmse_kph': float(np.sqrt(np.mean(error[active] ** 2))), 'speed_p95_kph': float(np.percentile(np.abs(error[active]), 95)), 'speed_corr': corr(command[active], speed[active]), 'command_copy_gap': float(np.max(np.abs(error))), 'speed_range_kph': float(np.ptp(speed)), 'soc_min': float(np.min(soc)), 'soc_change': float(soc[-1] - soc[0]), 'soc_range': float(np.ptp(soc)), 'cabin_final_error_C': float(np.median(np.abs(cabin[last] - cabin_target))), 'cabin_error_reduction_C': float(abs(cabin[0] - cabin_target) - np.median(np.abs(cabin[last] - cabin_target))), 'battery_safe_fraction': float(np.mean((battery >= 5.0) & (battery <= 35.0))), 'battery_final_safe_distance_C': float(np.median(np.maximum.reduce([5.0 - battery[last], battery[last] - 35.0, np.zeros(last.sum())]))), 'motor_safe_fraction': float(np.mean(motor <= 110.0)), 'temperature_range_C': float(max(np.ptp(cabin), np.ptp(battery), np.ptp(motor))), 'thermal_gradient_range_C': float(max(np.ptp(battery - plate), np.ptp(motor - ambient))), 'actuator_range': float(np.max(np.ptp(control[:, :7], axis=0))), 'routing_activity': float(np.max(np.ptp(binary, axis=0))), 'control_nonzero_fraction': float(np.mean(thermal_authority > 1e-06)), 'heat_rms_W': float(np.sqrt(np.mean(heat ** 2))), 'heat_range_W': float(np.max(np.ptp(heat, axis=0))), 'torque_accel_corr': corr(torque, acceleration), 'current_torque_corr': corr(current, torque), 'battery_heat_current2_corr': corr(heat[:, 0], current ** 2), 'battery_pump_temp_corr': corr(control[:, 0], battery), 'compressor_cabin_corr': corr(control[:, 2], cabin - ambient), 'battery_heat_gradient_corr': corr(heat[:, 0], battery - plate), 'motor_heat_gradient_corr': corr(heat[:, 1], motor - ambient), 'temperature_finite_physical_fraction': float(np.mean((temp > -80.0) & (temp < 180.0)))}

def scenario_scores(m: dict[str, float]) -> dict[str, float]:
    achievement = 0.35 * down(m['speed_rmse_kph'], 2.0, 14.0) + 0.15 * down(m['speed_p95_kph'], 6.0, 30.0) + 0.1 * up(m['speed_corr'], 0.55, 0.96) + 0.15 * down(m['cabin_final_error_C'], 2.0, 12.0) + 0.1 * down(m['battery_final_safe_distance_C'], 0.0, 8.0) + 0.15 * up(m['soc_min'], 0.15, 0.5)
    quality = 0.25 * up(m['battery_safe_fraction'], 0.35, 0.95) + 0.2 * up(m['motor_safe_fraction'], 0.9, 0.999) + 0.15 * up(m['temperature_finite_physical_fraction'], 0.98, 1.0) + 0.15 * up(m['thermal_gradient_range_C'], 0.05, 1.0) + 0.1 * up(m['control_nonzero_fraction'], 0.02, 0.2) + 0.15 * up(m['heat_rms_W'], 10.0, 500.0)
    mechanism = 0.18 * up(m['torque_accel_corr'], 0.05, 0.6) + 0.14 * up(m['current_torque_corr'], 0.05, 0.55) + 0.18 * up(m['battery_heat_current2_corr'], 0.05, 0.25) + 0.12 * up(m['battery_pump_temp_corr'], 0.02, 0.45) + 0.12 * up(m['compressor_cabin_corr'], 0.02, 0.45) + 0.13 * up(m['battery_heat_gradient_corr'], 0.02, 0.55) + 0.13 * up(m['motor_heat_gradient_corr'], 0.02, 0.55)
    dynamics = 0.3 * down(m['speed_p95_kph'], 6.0, 30.0) + 0.25 * up(m['cabin_error_reduction_C'], 2.0, 12.0) + 0.15 * up(m['temperature_range_C'], 0.2, 5.0) + 0.15 * up(m['actuator_range'], 0.01, 0.4) + 0.15 * up(max(m['routing_activity'], m['thermal_gradient_range_C']), 0.02, 1.0)
    return {'A': clip01(achievement), 'Q': clip01(quality), 'M': clip01(mechanism), 'D': clip01(dynamics)}

def paired_score(low: dict[str, float], high: dict[str, float], kind: str) -> float:
    if kind == 'solar':
        response = max(high['heat_rms_W'] - low['heat_rms_W'], high['temperature_range_C'] - low['temperature_range_C'], high['control_nonzero_fraction'] - low['control_nonzero_fraction'])
        return up(response, 1e-06, 0.05)
    response = abs(high['soc_min'] - low['soc_min'])
    return up(response, 0.05, 0.2)

def mechanism_group(per_metrics: dict[str, dict[str, float]]) -> float:
    """Aggregate each mechanism over the conditions where it must be active."""
    all_conditions = [per_metrics[name] for name in REQUIRED]
    active_cooling = [per_metrics['summer_city_nominal'], per_metrics['summer_city_high_solar'], per_metrics['summer_city_heavy_duty']]
    return clip01(0.18 * min((up(m['torque_accel_corr'], 0.05, 0.6) for m in all_conditions)) + 0.14 * min((up(m['current_torque_corr'], 0.05, 0.55) for m in all_conditions)) + 0.18 * min((up(m['battery_heat_current2_corr'], 0.05, 0.25) for m in all_conditions)) + 0.12 * min((up(m['battery_pump_temp_corr'], 0.02, 0.45) for m in active_cooling)) + 0.12 * min((up(m['compressor_cabin_corr'], 0.02, 0.45) for m in active_cooling)) + 0.13 * min((up(m['battery_heat_gradient_corr'], 0.02, 0.55) for m in all_conditions)) + 0.13 * min((up(m['motor_heat_gradient_corr'], 0.02, 0.55) for m in all_conditions)))

def implementation_credibility(static: dict) -> float:
    """Representation-neutral support for a real coupled physical plant.

    Behavioural correlations alone cannot distinguish the requested coupled
    electrical/mechanical/thermal plant from a single low-order trajectory
    generator.  Preserve partial behavioural credit, while requiring either
    physical conserving paths or more than a lone dynamic state for full
    mechanism credit.  No block names are used.
    """
    physical_ports = max(float(static.get('physical_conserving_port_count', 0)), 0.0)
    dynamic_blocks = max(float(static.get('dynamic_block_count', 0)), 0.0)
    physical = up(physical_ports, 0.0, 16.0)
    dynamics = up(dynamic_blocks, 1.0, 8.0)
    return clip01(0.15 + 0.5 * physical + 0.35 * dynamics)

def geometric(groups: dict[str, float]) -> float:
    return float(math.exp(sum((WEIGHTS[name] * math.log(max(groups[name], 1e-12)) for name in WEIGHTS))))

def score(evidence_path: Path) -> dict:
    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    scenarios, failures = load_fixed_evidence(evidence_path, evidence)
    static = evidence.get('static_audit', {})
    stage_pass = all((bool(evidence.get(name, False)) for name in ('load_pass', 'update_pass', 'compile_pass')))
    if set(REQUIRED).issubset(scenarios):
        per_metrics = {name: metrics(scenarios[name]) for name in REQUIRED}
        per_scores = {name: scenario_scores(per_metrics[name]) for name in REQUIRED}
    else:
        per_metrics, per_scores = ({}, {})
    shortcut_reasons: list[str] = []
    if per_metrics:
        if min((m['command_copy_gap'] for m in per_metrics.values())) < 1e-07:
            shortcut_reasons.append('measured speed is a direct copy of the command')
        if min((m['soc_range'] for m in per_metrics.values())) < 1e-07:
            shortcut_reasons.append('battery SOC has no dynamic response')
        if min((m['heat_range_W'] for m in per_metrics.values())) < 1e-05:
            shortcut_reasons.append('thermal heat-flow evidence is constant')
        if max((m['actuator_range'] for m in per_metrics.values())) < 1e-06:
            shortcut_reasons.append('all active thermal actuators are static')
    g = float(stage_pass and (not failures) and (not shortcut_reasons))
    if not per_scores:
        groups = {name: 0.0 for name in WEIGHTS}
    else:
        groups = {'A': min((s['A'] for s in per_scores.values())), 'Q': min((s['Q'] for s in per_scores.values())), 'M': mechanism_group(per_metrics) * implementation_credibility(static), 'R': min(per_scores['summer_city_heavy_duty']['A'], per_scores['summer_city_heavy_duty']['Q'], per_scores['winter_highway_low_soc']['A']), 'D': min(min((s['D'] for s in per_scores.values())), paired_score(per_metrics['summer_city_nominal'], per_metrics['summer_city_high_solar'], 'solar'), paired_score(per_metrics['winter_highway_nominal'], per_metrics['winter_highway_low_soc'], 'soc'))}
    total = 100.0 * geometric(groups) if g else 0.0
    return {'schema': 'simuverity.f90-xbatt03-score.v1', 'policy_id': 'simuverity-101-v1:f90-xbatt-03:scoring', 'task_id': 'F90-XBATT-03', 'G': g, 'groups': groups, 'score': total, 'admission_threshold_raw': 85.0, 'threshold_normalized_to_100': False, 'admission_candidate': bool(g and total >= 85.0), 'scenario_metrics': per_metrics, 'scenario_scores': per_scores, 'evidence_failures': failures, 'shortcut_failures': shortcut_reasons, 'static_audit_diagnostic': static, 'score_policy': {'within_group': 'weighted arithmetic', 'critical_multiscenario': '100% minimum', 'mechanism_multiscenario': 'minimum over applicable operating conditions', 'cross_group': 'weighted geometric', 'weights': WEIGHTS, 'battery_heat_current2_correlation': {'zero_credit': 0.05, 'full_credit': 0.25, 'reason': 'The logged battery heat-flow state is net heat transfer after thermal storage, not instantaneous I^2R generation; the stricter heat-gradient and nonconstant-flow checks remain independently score-bearing.'}, 'implementation_credibility': {'value': implementation_credibility(static), 'basis': 'physical conserving-port and dynamic-state counts; no block names'}}}

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = score(args.evidence)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + '\n', encoding='utf-8')
    print(text)
if __name__ == '__main__':
    main()

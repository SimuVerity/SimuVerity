"""Pure offline scorer for fixed F90-XTHERM-06 evidence."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any
WEIGHTS = {'A': 0.15, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.2}
POLICY_ID = 'simuverity-101-v1:f90-xtherm-06:scoring'

def _clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))

def _q_low(value: float, full: float, zero: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if zero <= full:
        raise ValueError('q_low requires zero > full')
    return _clamp((zero - value) / (zero - full))

def _q_high(value: float, zero: float, full: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if full <= zero:
        raise ValueError('q_high requires full > zero')
    return _clamp((value - zero) / (full - zero))

def _q_band(value: float, low: float, high: float, outer_low: float, outer_high: float) -> float:
    if not math.isfinite(value):
        return 0.0
    if low <= value <= high:
        return 1.0
    if value < low:
        return _clamp((value - outer_low) / (low - outer_low))
    return _clamp((outer_high - value) / (outer_high - high))

def _weighted(values: list[float], weights: list[float]) -> float:
    total = sum(weights)
    return 0.0 if total <= 0 else sum((v * w for v, w in zip(values, weights))) / total

def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan

def _rms(values: list[float]) -> float:
    return math.sqrt(_mean([v * v for v in values])) if values else math.nan

def _tail(values: list[float], fraction: float=0.1) -> list[float]:
    if not values:
        return []
    count = max(3, int(math.ceil(len(values) * fraction)))
    return values[-count:]

def _slope(time: list[float], values: list[float], fraction: float=0.1) -> float:
    if len(values) < 3:
        return math.nan
    count = max(3, int(math.ceil(len(values) * fraction)))
    x = time[-count:]
    y = values[-count:]
    xm = _mean(x)
    ym = _mean(y)
    denom = sum(((v - xm) ** 2 for v in x))
    return 0.0 if denom == 0 else sum(((a - xm) * (b - ym) for a, b in zip(x, y))) / denom

def _corr(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or len(a) < 3:
        return math.nan
    am = _mean(a)
    bm = _mean(b)
    da = [v - am for v in a]
    db = [v - bm for v in b]
    denom = math.sqrt(sum((v * v for v in da)) * sum((v * v for v in db)))
    return 0.0 if denom <= 1e-12 else sum((x * y for x, y in zip(da, db))) / denom

def _scenario_metrics(row: dict[str, Any]) -> dict[str, float]:
    t = [float(v) for v in row['time_s']]
    out = row['outputs']
    speed_ref = [float(v) for v in out['speed_reference']]
    speed = [float(v) for v in out['vehicle_speed']]
    torque_ref = [float(v) for v in out['motor_torque_request']]
    torque = [float(v) for v in out['motor_torque_actual']]
    motor_t = [float(v) for v in out['motor_temperature']]
    casing_t = [float(v) for v in out['casing_temperature']]
    coolant_in = [float(v) for v in out['coolant_inlet_temperature']]
    coolant_out = [float(v) for v in out['coolant_outlet_temperature']]
    mdot = [float(v) for v in out['coolant_mass_flow']]
    active = [i for i, value in enumerate(t) if value >= 20.0]
    speed_error = [speed[i] - speed_ref[i] for i in active]
    torque_error = [torque[i] - torque_ref[i] for i in active]
    torque_scale = max(_rms([torque_ref[i] for i in active]), 50.0)
    pass_idx = [i for i, value in enumerate(t) if 160.0 <= value <= 240.0]
    post_idx = [i for i, value in enumerate(t) if value >= 240.0]
    pass_motor = [motor_t[i] for i in pass_idx] or motor_t
    post_motor = [motor_t[i] for i in post_idx] or motor_t
    peak_pass = max(pass_motor)
    final_motor = _mean(_tail(motor_t))
    recovery = max(0.0, peak_pass - final_motor)
    commanded_flow = float(row['requested_inputs']['CoolantMassFlow_kgps'])
    measured_flow = abs(_mean(_tail(mdot, 0.5)))
    return {'speed_rmse_mps': _rms(speed_error), 'speed_max_error_mps': max((abs(v) for v in speed_error), default=math.nan), 'speed_tail_error_mps': abs(_mean(_tail(speed)) - _mean(_tail(speed_ref))), 'torque_nrmse': _rms(torque_error) / torque_scale, 'torque_correlation': _corr([torque_ref[i] for i in active], [torque[i] for i in active]), 'motor_peak_C': max(motor_t), 'motor_tail_C': final_motor, 'motor_tail_slope_C_per_s': _slope(t, motor_t), 'motor_dwell_above_180_fraction': sum((v > 180.0 for v in motor_t)) / len(motor_t), 'casing_tail_C': _mean(_tail(casing_t)), 'motor_minus_casing_tail_C': final_motor - _mean(_tail(casing_t)), 'coolant_temperature_rise_C': _mean(_tail([b - a for a, b in zip(coolant_in, coolant_out)], 0.5)), 'coolant_flow_tail_kgps': measured_flow, 'coolant_flow_relative_error': abs(measured_flow - commanded_flow) / max(commanded_flow, 0.1), 'passing_motor_peak_C': peak_pass, 'post_passing_recovery_C': recovery, 'post_passing_motor_tail_C': _mean(_tail(post_motor))}

def score_evidence(evidence: dict[str, Any]) -> dict[str, Any]:
    rows = {str(row.get('id')): row for row in evidence.get('scenarios', [])}
    required = ['nominal', 'cool_boundary', 'hot_boundary', 'low_flow', 'cooling_loss', 'hot_low_flow']
    static = evidence.get('static_audit', {})
    platform = bool(evidence.get('load_pass')) and bool(evidence.get('update_pass')) and bool(evidence.get('compile_pass')) and all((name in rows and bool(rows[name].get('valid')) for name in required)) and bool(static.get('core_path_qualified'))
    metrics = {name: _scenario_metrics(rows[name]) for name in required if name in rows and rows[name].get('valid')}
    gate_reasons: list[str] = []
    if not evidence.get('load_pass'):
        gate_reasons.append('reference did not load')
    if not evidence.get('update_pass'):
        gate_reasons.append('model update failed')
    if not evidence.get('compile_pass'):
        gate_reasons.append('model compile failed')
    if not static.get('core_path_qualified'):
        gate_reasons.append('connected traction/feedback/thermal-fluid mechanism was not qualified')
    missing = [name for name in required if name not in rows or not rows[name].get('valid')]
    if missing:
        gate_reasons.append('invalid required scenarios: ' + ', '.join(missing))
    if not platform:
        groups = {'G': 0.0, 'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
        return _receipt(evidence, groups, 0.0, metrics, gate_reasons, {})
    nominal = metrics['nominal']
    a_util = {'speed_rmse': _q_low(nominal['speed_rmse_mps'], 0.35, 2.5), 'maximum_speed_error': _q_low(nominal['speed_max_error_mps'], 1.0, 10.0), 'tail_speed_error': _q_low(nominal['speed_tail_error_mps'], 0.25, 2.0), 'torque_tracking': _q_low(nominal['torque_nrmse'], 0.03, 0.25)}
    A = _weighted(list(a_util.values()), [0.35, 0.15, 0.2, 0.3])
    delta_t = nominal['coolant_temperature_rise_C']
    q_util = {'motor_peak': _q_low(nominal['motor_peak_C'], 180.0, 230.0), 'sustained_overtemperature': _q_low(nominal['motor_dwell_above_180_fraction'], 0.01, 0.15), 'coolant_flow': _q_low(nominal['coolant_flow_relative_error'], 0.03, 0.3), 'coolant_heat_pickup': math.sqrt(_q_high(delta_t, 0.0, 0.2) * _q_low(delta_t, 25.0, 80.0)), 'motor_to_casing_gradient': _q_high(nominal['motor_minus_casing_tail_C'], 0.0, 3.0)}
    Q = _weighted(list(q_util.values()), [0.25, 0.15, 0.2, 0.2, 0.2])
    static_parts = [float(bool(static.get('battery_motor_connected'))), float(bool(static.get('motor_driveline_connected'))), float(bool(static.get('speed_feedback_present'))), float(bool(static.get('motor_thermal_to_casing_connected'))), float(bool(static.get('coolant_loop_connected'))), float(bool(static.get('ambient_rejection_connected'))), float(bool(static.get('cooling_variant_present')))]
    static_mechanism = _mean(static_parts)
    cooling_effect = metrics['cooling_loss']['motor_tail_C'] - nominal['motor_tail_C']
    flow_effect = metrics['low_flow']['motor_tail_C'] - nominal['motor_tail_C']
    ambient_effect = metrics['hot_boundary']['motor_tail_C'] - metrics['cool_boundary']['motor_tail_C']
    m_util = {'connected_mechanism': static_mechanism, 'cooling_on_off_causality': _q_high(cooling_effect, 0.5, 8.0), 'flow_causality': _q_high(flow_effect, 0.02, 0.5), 'ambient_causality': _q_high(ambient_effect, 2.0, 15.0)}
    M = _weighted(list(m_util.values()), [0.45, 0.25, 0.15, 0.15])
    operating: dict[str, float] = {}
    for name in ['nominal', 'cool_boundary', 'hot_boundary', 'low_flow', 'hot_low_flow']:
        row = metrics[name]
        operating[name] = _weighted([_q_low(row['speed_rmse_mps'], 0.5, 3.0), _q_low(row['motor_peak_C'], 190.0, 240.0), _q_low(abs(row['motor_tail_slope_C_per_s']), 0.08, 0.4), _q_low(row['coolant_flow_relative_error'], 0.05, 0.4)], [0.35, 0.3, 0.15, 0.2])
    R = min(operating.values())
    d_util = {'passing_speed_response': _q_low(nominal['speed_rmse_mps'], 0.45, 2.5), 'torque_dynamic_tracking': _weighted([_q_low(nominal['torque_nrmse'], 0.03, 0.25), _q_high(nominal['torque_correlation'], 0.7, 0.98)], [0.6, 0.4]), 'return_to_cruise': _q_low(nominal['speed_tail_error_mps'], 0.25, 2.0), 'post_passing_thermal_recovery': _q_high(nominal['post_passing_recovery_C'], 0.5, 8.0)}
    D = _weighted(list(d_util.values()), [0.3, 0.25, 0.2, 0.25])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for name, weight in WEIGHTS.items():
        total *= max(groups[name], 0.0) ** weight
    copied_speed_command = nominal['speed_rmse_mps'] < 0.0001 and nominal['speed_max_error_mps'] < 0.001
    diagnostics = {'A_utilities': a_util, 'Q_utilities': q_util, 'M_utilities': m_util, 'R_scenario_scores': operating, 'D_utilities': d_util, 'causal_deltas': {'cooling_loss_minus_nominal_tail_C': cooling_effect, 'low_flow_minus_nominal_tail_C': flow_effect, 'hot_minus_cool_tail_C': ambient_effect}, 'shortcut_checks': {'copied_speed_command_detected': copied_speed_command}}
    failures = [f'{name} group below 0.60' for name in WEIGHTS if groups[name] < 0.6]
    if copied_speed_command:
        failures.append('vehicle speed is a near-exact copy of the speed command')
    return _receipt(evidence, groups, total, metrics, gate_reasons + failures, diagnostics)

def _receipt(evidence: dict[str, Any], groups: dict[str, float], total: float, metrics: dict[str, Any], failures: list[str], diagnostics: dict[str, Any]) -> dict[str, Any]:
    return {'schema': 'simuverity.f90-xtherm06-score.v1', 'policy_id': POLICY_ID, 'task_id': 'F90-XTHERM-06', 'formula': 'G*100*A^0.15*Q^0.15*M^0.30*R^0.20*D^0.20', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': bool(groups.get('G', 0.0) == 1.0), 'groups': groups, 'score': total, 'admission_score_pass': bool(groups.get('G', 0.0) == 1.0 and total >= 85.0), 'scenario_metrics': metrics, 'diagnostics': diagnostics, 'failure_reasons': failures}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--out')
    args = parser.parse_args()
    evidence_path = Path(args.evidence)
    with evidence_path.open('r', encoding='utf-8') as handle:
        evidence = json.load(handle)
    receipt = score_evidence(evidence)
    output = Path(args.out) if args.out else evidence_path.with_name('offline_score.json')
    output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'score': receipt['score'], 'groups': receipt['groups'], 'out': str(output)}))
    return 0
if __name__ == '__main__':
    raise SystemExit(main())

"""Pure offline scorer for fixed F90-XTHERM-09 evidence."""
from __future__ import annotations
import argparse, json, math
from pathlib import Path
WEIGHTS = {'A': 0.2, 'Q': 0.15, 'M': 0.3, 'R': 0.2, 'D': 0.15}
REQUIRED = ['nominal', 'occupancy_boundary', 'thermal_boundary', 'bleed_boundary', 'ozone_boundary', 'joint_service']
REQUIRED_OUTPUTS = ['cabin_pressure', 'atmospheric_pressure', 'cabin_temperature', 'atmospheric_temperature', 'cabin_relative_humidity', 'atmospheric_relative_humidity', 'cabin_ozone_ppm', 'atmospheric_ozone_ppm', 'acm_mass_flow', 'turbine_outlet_temperature', 'flow_valve_area', 'bypass_valve_area', 'trim_valve_area', 'outflow_valve_area']

def clamp(x):
    return max(0.0, min(1.0, float(x)))

def mean(x):
    return sum(x) / len(x) if x else math.nan

def low(x, full, zero):
    return 0.0 if not math.isfinite(x) else clamp((zero - x) / (zero - full))

def high(x, zero, full):
    return 0.0 if not math.isfinite(x) else clamp((x - zero) / (full - zero))

def weighted(v, w):
    return sum((a * b for a, b in zip(v, w))) / sum(w)

def tail(x, f=0.1):
    return x[-max(3, math.ceil(len(x) * f)):] if x else []

def rms(x):
    return math.sqrt(mean([v * v for v in x]))

def metrics(row):
    t = list(map(float, row['time_s']))
    o = row['outputs']
    p = list(map(float, o['cabin_pressure']))
    pa = list(map(float, o['atmospheric_pressure']))
    temp = list(map(float, o['cabin_temperature']))
    rh = list(map(float, o['cabin_relative_humidity']))
    o3 = list(map(float, o['cabin_ozone_ppm']))
    o3a = list(map(float, o['atmospheric_ozone_ppm']))
    flow = list(map(float, o['acm_mass_flow']))
    acts = [list(map(float, o[n])) for n in ('flow_valve_area', 'bypass_valve_area', 'trim_valve_area', 'outflow_valve_area')]
    active = [i for i, x in enumerate(t) if x >= 300]
    cruise = [i for i, x in enumerate(pa) if x <= 35] or active
    target_p = [max(80.0, pa[i]) for i in active]
    p_err = [p[i] - target_p[j] for j, i in enumerate(active)]
    t_err = [temp[i] - 22.0 for i in active]
    ozone_ratio = mean([max(o3[i], 0) / max(o3a[i], 1e-06) for i in active])
    sat = mean([sum((abs(a[i]) >= 0.015 for a in acts)) / 4 for i in active])
    return {'pressure_rmse_kPa': rms(p_err), 'pressure_min_cruise_kPa': min((p[i] for i in cruise)), 'temperature_rmse_C': rms(t_err), 'temperature_tail_error_C': abs(mean(tail(temp)) - 22), 'flow_tail_error_kgps': abs(mean(tail(flow)) - 1.05), 'rh_outside_fraction': mean([not 0.1 <= rh[i] <= 0.7 for i in active]), 'ozone_ratio': ozone_ratio, 'actuator_saturation_fraction': sat, 'transition_peak_temp_error_C': max((abs(v) for v in t_err)), 'transition_pressure_dip_kPa': max(0, 80 - min((p[i] for i in cruise))), 'recovery_temp_error_C': abs(mean(tail(temp)) - 22)}

def score(e):
    rows = {str(r.get('id')): r for r in e.get('scenarios', [])}
    st = e.get('static_audit', {})
    valid = all((k in rows and rows[k].get('valid') and all((name in rows[k].get('outputs', {}) for name in REQUIRED_OUTPUTS)) for k in REQUIRED))
    gate = bool(e.get('load_pass') and e.get('update_pass') and e.get('compile_pass') and valid and st.get('core_path_qualified'))
    if not gate:
        return receipt(e, {'G': 0, 'A': 0, 'Q': 0, 'M': 0, 'R': 0, 'D': 0}, 0, {}, ['qualification gate failed'], {})
    ms = {k: metrics(rows[k]) for k in REQUIRED}
    n = ms['nominal']
    au = {'pressure': low(n['pressure_rmse_kPa'], 0.8, 6), 'temperature': low(n['temperature_rmse_C'], 1.0, 7), 'flow': low(n['flow_tail_error_kgps'], 0.05, 0.5)}
    A = weighted(list(au.values()), [0.4, 0.4, 0.2])
    qu = {'humidity': low(n['rh_outside_fraction'], 0.01, 0.35), 'ozone': low(n['ozone_ratio'], 0.35, 0.9), 'actuation': low(n['actuator_saturation_fraction'], 0.05, 0.7)}
    Q = weighted(list(qu.values()), [0.3, 0.4, 0.3])
    static = mean([float(bool(st.get(k))) for k in ('compressor_present', 'turbine_present', 'moist_air_path_present', 'cabin_volume_present', 'core_path_qualified')])
    occ = ms['occupancy_boundary']
    th = ms['thermal_boundary']
    bl = ms['bleed_boundary']
    oz = ms['ozone_boundary']
    causal = [high(occ['temperature_rmse_C'] - n['temperature_rmse_C'], -0.1, 0.25), high(th['temperature_rmse_C'] - n['temperature_rmse_C'], -0.1, 0.25), high(abs(bl['flow_tail_error_kgps'] - n['flow_tail_error_kgps']), 0.001, 0.03), high(oz['ozone_ratio'] - n['ozone_ratio'], 0.02, 0.2)]
    M = weighted([static, *causal], [0.5, 0.125, 0.125, 0.125, 0.125])
    per = {}
    for k, m in ms.items():
        per[k] = weighted([low(m['pressure_rmse_kPa'], 1.2, 8), low(m['temperature_rmse_C'], 1.5, 9), low(m['pressure_min_cruise_kPa'], 80, 72) if False else high(m['pressure_min_cruise_kPa'], 72, 80), low(m['rh_outside_fraction'], 0.02, 0.5)], [0.3, 0.35, 0.2, 0.15])
    R = min(per.values())
    du = {'temperature_peak': low(n['transition_peak_temp_error_C'], 5, 18), 'pressure_dip': low(n['transition_pressure_dip_kPa'], 0.5, 8), 'recovery': low(n['recovery_temp_error_C'], 0.75, 5)}
    D = weighted(list(du.values()), [0.4, 0.3, 0.3])
    groups = {'G': 1.0, 'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    total = 100.0
    for k, w in WEIGHTS.items():
        total *= max(groups[k], 0.0) ** w
    diag = {'A_utilities': au, 'Q_utilities': qu, 'M_causal_utilities': causal, 'R_scenario_scores': per, 'D_utilities': du}
    return receipt(e, groups, total, ms, [], diag)

def receipt(e, g, total, ms, fail, diag):
    return {'schema': 'simuverity.f90-xtherm09-score.v1', 'task_id': 'F90-XTHERM-09', 'policy_id': 'simuverity-101-v1:f90-xtherm-09:scoring', 'formula': 'G*100*A^0.20*Q^0.15*M^0.30*R^0.20*D^0.15', 'score_is_raw_not_rescaled': True, 'admission_threshold': 85, 'G': g.get('G') == 1.0, 'groups': g, 'score': total, 'admission_score_pass': bool(g.get('G') == 1.0 and total >= 85), 'scenario_metrics': ms, 'diagnostics': diag, 'failure_reasons': fail}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('evidence')
    p.add_argument('--out')
    a = p.parse_args()
    src = Path(a.evidence)
    out = Path(a.out) if a.out else src.with_name('offline_score.json')
    out.write_text(json.dumps(score(json.loads(src.read_text(encoding='utf-8'))), indent=2, ensure_ascii=False), encoding='utf-8')
    print(out)
if __name__ == '__main__':
    main()

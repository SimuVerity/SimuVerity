"""Pure-offline dedicated scorer for F90-XAERO-09."""
from __future__ import annotations
import argparse, copy, json, math
from pathlib import Path
from typing import Any
TASK = 'F90-XAERO-09'
IDS = ('nominal_yaw_step', 'multiaxis_four_jet', 'low_authority_mode_one', 'high_authority_recovery', 'yaw_dominant_mixed_rate')
WIDTHS = {'attitude_state': 6, 'phase_plane_state': 6, 'rcs_state': 6}
W = {'A': 0.24, 'Q': 0.1, 'M': 0.22, 'C': 0.18, 'R': 0.14, 'D': 0.12}

def read(p: Path) -> dict[str, Any]:
    return json.loads(p.read_text(encoding='utf-8'))

def write(p: Path, x: Any) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(x, indent=2, sort_keys=True, allow_nan=False) + '\n', encoding='utf-8')

def finite(x: Any) -> bool:
    return isinstance(x, (int, float)) and (not isinstance(x, bool)) and math.isfinite(float(x))

def matrix(x: Any, w: int) -> list[list[float]]:
    if not isinstance(x, list) or not x:
        raise ValueError('not a nonempty matrix')
    if not all((isinstance(r, list) and len(r) == w and all((finite(v) for v in r)) for r in x)):
        raise ValueError(f'not finite width-{w}')
    return [[float(v) for v in r] for r in x]

def validate(e: dict[str, Any]) -> tuple[bool, list[str]]:
    f = []
    if e.get('task_id') != TASK:
        f.append('wrong_task_id')
    for k in ('load_pass', 'update_pass', 'compile_pass', 'simulate_pass', 'all_scenarios_valid', 'evidence_complete'):
        if e.get(k) is not True:
            f.append(k)
    rows = e.get('scenarios', [])
    if not isinstance(rows, list) or [r.get('id') for r in rows] != list(IDS):
        return (False, f + ['scenario_set_or_order'])
    for r in rows:
        sid = r.get('id', '?')
        t = r.get('time_s', [])
        if r.get('valid') is not True or not isinstance(t, list) or len(t) != 601 or (not all((finite(v) for v in t))) or (abs(t[0]) > 1e-09) or (abs(t[-1] - 30) > 1e-06) or any((b <= a for a, b in zip(t, t[1:]))):
            f.append(f'{sid}:time_or_valid')
        for name, w in WIDTHS.items():
            try:
                m = matrix(r.get(name), w)
            except ValueError:
                f.append(f'{sid}:{name}')
                continue
            if len(m) != len(t):
                f.append(f'{sid}:{name}_length')
    return (not f, f)

def mean(x: list[float]) -> float:
    return sum(x) / max(1, len(x))

def rms(x: list[float]) -> float:
    return math.sqrt(mean([v * v for v in x]))

def col(m: list[list[float]], i: int) -> list[float]:
    return [r[i] for r in m]

def sim1(r: list[float], c: list[float], floor: float, sharp: float=2.0) -> float:
    scale = max(rms(r), 0.1 * max((abs(v) for v in r)), floor)
    return 100 * math.exp(-sharp * rms([a - b for a, b in zip(r, c)]) / scale)

def simm(r: list[list[float]], c: list[list[float]], ix: tuple[int, ...], floor: float, sharp: float=2.0) -> float:
    return mean([sim1(col(r, i), col(c, i), floor, sharp) for i in ix])

def smap(e: dict[str, Any]) -> dict[str, Any]:
    return {r['id']: r for r in e['scenarios']}

def per(r: dict[str, Any], c: dict[str, Any]) -> dict[str, float]:
    ra, ca = (matrix(r['attitude_state'], 6), matrix(c['attitude_state'], 6))
    rp, cp = (matrix(r['phase_plane_state'], 6), matrix(c['phase_plane_state'], 6))
    rr, cr = (matrix(r['rcs_state'], 6), matrix(c['rcs_state'], 6))
    return {'attitude': simm(ra, ca, (0, 1, 2), 0.05), 'rate': simm(ra, ca, (3, 4, 5), 0.01), 'tracking': simm(rp, cp, (3, 4, 5), 0.05), 'jet': simm(rr, cr, (0, 1, 2), 0.05, 2.4), 'authority': simm(rr, cr, (3, 4, 5), 0.5)}

def effects(s: dict[str, Any]) -> dict[str, float]:

    def metric(sid: str, k: str) -> float:
        return float(s[sid].get('metrics', {}).get(k, 0))
    return {'command_rate_final_span': max((math.dist(s[i]['metrics']['final_relative_attitude_rad'], s[IDS[0]]['metrics']['final_relative_attitude_rad']) for i in IDS[1:])), 'jet_mode_activity_delta': metric(IDS[1], 'jet_activity_mean') - metric(IDS[0], 'jet_activity_mean'), 'low_high_force_activity_delta': metric(IDS[3], 'jet_activity_mean') - metric(IDS[2], 'jet_activity_mean'), 'low_high_force_tail_rate_delta': metric(IDS[3], 'tail_rate_rms_rad_s') - metric(IDS[2], 'tail_rate_rms_rad_s')}

def scalar(r: float, c: float) -> float:
    return 100 * math.exp(-2.5 * abs(c - r) / max(abs(r), 1e-07))

def score(ref: dict[str, Any], cand: dict[str, Any]) -> dict[str, Any]:
    rv, rf = validate(ref)
    cv, cf = validate(cand)
    if not rv:
        raise ValueError('invalid reference: ' + ';'.join(rf))
    out = {'schema': 'simuverity.f90-xaero09-score.v1', 'task_id': TASK, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if cv else 0, 'failures': cf}
    if not cv:
        out.update(group_scores={k: 0.0 for k in W}, per_scenario={}, raw_total=0.0, total=0.0)
        return out
    rs, cs = (smap(ref), smap(cand))
    ps = {i: per(rs[i], cs[i]) for i in IDS}
    acc = [mean([ps[i]['attitude'], ps[i]['rate'], ps[i]['tracking']]) for i in IDS]
    mech = [mean([ps[i]['tracking'], ps[i]['jet'], ps[i]['authority']]) for i in IDS]
    dyn = [mean([ps[i]['rate'], ps[i]['tracking'], ps[i]['jet']]) for i in IDS]
    re, ce = (effects(rs), effects(cs))
    es = {k: scalar(v, ce[k]) for k, v in re.items()}
    causal = all((abs(ce[k]) >= 0.05 * max(abs(re[k]), 1e-07) and (abs(re[k]) < 1e-07 or ce[k] * re[k] > 0) for k in re))
    active = all((float(cs[i]['metrics'].get('jet_switch_count', 0)) > 0 and float(cs[i]['metrics'].get('jet_activity_mean', 0)) > 1e-06 for i in IDS))
    g = {'A': 0.75 * mean(acc) + 0.25 * min(acc), 'Q': 100.0, 'M': 0.7 * mean(mech) + 0.3 * min(mech), 'C': 0.7 * mean(list(es.values())) + 0.3 * min(es.values()), 'R': min((0.6 * acc[j] + 0.4 * mech[j] for j in range(5))), 'D': 0.7 * mean(dyn) + 0.3 * min(dyn)}
    if not causal:
        g['C'] = 0.0
    if not active:
        g['M'] = 0.0
    raw = 0.0 if any((v <= 0 for v in g.values())) else 100 * math.prod(((g[k] / 100) ** W[k] for k in W))
    out.update(group_scores={k: round(v, 9) for k, v in g.items()}, weights=W, per_scenario=ps, causal_metrics={'reference': re, 'candidate': ce, 'scores': es, 'causal_gate': causal, 'active_rcs_gate': active}, raw_total=round(raw, 9), total=round(raw, 9))
    return out

def shortcuts(ref: dict[str, Any]) -> dict[str, Any]:
    cases = []

    def add(n, x):
        s = score(ref, x)
        cases.append({'id': n, 'G': s['G'], 'raw_total': s['raw_total'], 'below_85': s['raw_total'] < 85})
    x = copy.deepcopy(ref)
    del x['scenarios'][0]['attitude_state']
    add('missing_required_output', x)
    x = copy.deepcopy(ref)
    base = x['scenarios'][0]
    for r in x['scenarios'][1:]:
        for k in WIDTHS:
            r[k] = copy.deepcopy(base[k])
        r['metrics'] = copy.deepcopy(base['metrics'])
    add('one_scenario_replayed_for_all', x)
    x = copy.deepcopy(ref)
    for r in x['scenarios']:
        r['attitude_state'] = [[0.0] * 6 for _ in r['time_s']]
    add('zero_attitude_and_rate', x)
    x = copy.deepcopy(ref)
    for r in x['scenarios']:
        r['rcs_state'] = [[0, 0, 0, *q[3:]] for q in r['rcs_state']]
        r['metrics']['jet_activity_mean'] = 0
        r['metrics']['jet_switch_count'] = 0
    add('zero_jet_commands', x)
    x = copy.deepcopy(ref)
    for r in x['scenarios']:
        r['attitude_state'] = [[*p[:3], 0, 0, 0] for p in r['phase_plane_state']]
    add('command_copied_as_attitude', x)
    x = copy.deepcopy(ref)
    x['scenarios'][3]['metrics'] = copy.deepcopy(x['scenarios'][2]['metrics'])
    add('force_scale_ignored', x)
    x = copy.deepcopy(ref)
    r = x['scenarios'][-1]
    for k in ('time_s', *WIDTHS):
        r[k] = r[k][:20]
    add('truncated_run', x)
    return {'schema': 'simuverity.f90-xaero09-shortcut-sanity.v1', 'task_id': TASK, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': max((x['raw_total'] for x in cases)), 'all_shortcuts_below_threshold': all((x['below_85'] for x in cases))}

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True, type=Path)
    p.add_argument('--candidate', type=Path)
    p.add_argument('--score-output', type=Path)
    p.add_argument('--shortcut-sanity', type=Path)
    a = p.parse_args()
    r = read(a.reference)
    if a.score_output:
        c = a.candidate or a.reference
        o = score(r, read(c))
        write(a.score_output, o)
    if a.shortcut_sanity:
        write(a.shortcut_sanity, shortcuts(r))
if __name__ == '__main__':
    main()

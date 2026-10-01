"""Pure-offline dedicated scorer for F90-XAERO-10."""
from __future__ import annotations
import argparse, copy, json, math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XAERO-10'
SCENARIO_IDS = ('nominal_zero_command', 'small_command', 'large_command', 'high_measurement_noise', 'combined_command_noise')
WEIGHTS = {'A': 0.24, 'Q': 0.1, 'M': 0.2, 'C': 0.2, 'R': 0.14, 'D': 0.12}
FLOORS = (0.05, 0.05, 0.5, 0.5)

def read(p: Path) -> dict[str, Any]:
    return json.loads(p.read_text(encoding='utf-8'))

def write(p: Path, v: dict[str, Any]) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(v, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def finite(x: Any) -> bool:
    return isinstance(x, (int, float)) and (not isinstance(x, bool)) and math.isfinite(float(x))

def matrix(v: Any, w: int) -> list[list[float]]:
    if not isinstance(v, list):
        raise ValueError('data is not an array')
    out = []
    for row in v:
        if not isinstance(row, list) or len(row) != w or (not all((finite(x) for x in row))):
            raise ValueError(f'data is not finite width-{w}')
        out.append([float(x) for x in row])
    return out

def validate(e: dict[str, Any]) -> tuple[bool, list[str]]:
    f = []
    if e.get('task_id') != TASK_ID:
        f.append('task_id mismatch')
    if e.get('evidence_complete') is not True:
        f.append('evidence_complete is not true')
    if e.get('simulate_pass') is not True or e.get('all_scenarios_valid') is not True:
        f.append('top-level evidence invalid')
    rows = e.get('scenarios')
    if not isinstance(rows, list):
        return (False, f + ['scenarios is not an array'])
    ids = [r.get('id') for r in rows if isinstance(r, dict)]
    if len(ids) != 5 or sorted(ids) != sorted(SCENARIO_IDS):
        f.append('scenario identifiers invalid')
    for r in rows:
        if not isinstance(r, dict):
            f.append('scenario is not an object')
            continue
        sid = str(r.get('id', '<missing>'))
        t = r.get('time_s')
        if not isinstance(t, list) or len(t) != 501 or (not all((finite(x) for x in t))):
            f.append(f'{sid}: invalid time')
            continue
        tt = [float(x) for x in t]
        if abs(tt[0]) > 1e-09 or abs(tt[-1] - 10) > 1e-06 or any((b <= a for a, b in zip(tt, tt[1:]))):
            f.append(f'{sid}: coverage/order invalid')
        try:
            noisy = matrix(r.get('noisy_closed_loop_state'), 4)
            clean = matrix(r.get('noise_free_closed_loop_state'), 4)
            commands = matrix(r.get('command_noise_state'), 2)
        except ValueError as ex:
            f.append(f'{sid}: {ex}')
            continue
        if any((len(x) != 501 for x in (noisy, clean, commands))):
            f.append(f'{sid}: signal length mismatch')
            continue
        inp = r.get('inputs', {})
        targets = (float(inp.get('attitude_command_rad', math.nan)), float(inp.get('measurement_noise_covariance', math.nan)))
        for i, target in enumerate(targets):
            if not math.isfinite(target) or max((abs(row[i] - target) for row in commands)) > 1e-06:
                f.append(f'{sid}: command channel {i} mismatch')
    return (not f, f)

def mean(v: list[float]) -> float:
    return sum(v) / max(len(v), 1)

def rms(v: list[float]) -> float:
    return math.sqrt(mean([x * x for x in v]))

def col(m: list[list[float]], i: int) -> list[float]:
    return [r[i] for r in m]

def sim1(r: list[float], c: list[float], floor: float, sharp: float=2.0) -> float:
    scale = max(rms(r), 0.1 * max((abs(x) for x in r)), floor)
    err = rms([a - b for a, b in zip(r, c)]) / scale
    return 100 * math.exp(-sharp * err)

def simm(r: list[list[float]], c: list[list[float]], idx: tuple[int, ...] | None=None, sharp: float=2.0) -> float:
    use = idx if idx is not None else (0, 1, 2, 3)
    return mean([sim1(col(r, i), col(c, i), FLOORS[i], sharp) for i in use])

def scalar(c: float, r: float, floor: float=1e-08) -> float:
    return 100 * math.exp(-2.5 * abs(c - r) / max(abs(r), floor))

def smap(e: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(r['id']): r for r in e['scenarios']}

def scenario_score(r: dict[str, Any], c: dict[str, Any]) -> dict[str, float]:
    rn, cn = (matrix(r['noisy_closed_loop_state'], 4), matrix(c['noisy_closed_loop_state'], 4))
    rf, cf = (matrix(r['noise_free_closed_loop_state'], 4), matrix(c['noise_free_closed_loop_state'], 4))
    rd = [[a - b for a, b in zip(x, y)] for x, y in zip(rn, rf)]
    cd = [[a - b for a, b in zip(x, y)] for x, y in zip(cn, cf)]
    return {'noisy': simm(rn, cn), 'noise_free': simm(rf, cf), 'branch_divergence': simm(rd, cd, sharp=2.2), 'rates': 0.5 * simm(rn, cn, (2, 3), 2.2) + 0.5 * simm(rf, cf, (2, 3), 2.2), 'terminal': mean([scalar(cn[-1][i], rn[-1][i], FLOORS[i]) + scalar(cf[-1][i], rf[-1][i], FLOORS[i]) for i in range(4)]) / 2}

def effects(s: dict[str, dict[str, Any]]) -> dict[str, float]:

    def final(sid: str, key: str, i: int) -> float:
        return matrix(s[sid][key], 4)[-1][i]

    def drms(sid: str, i: int) -> float:
        a = matrix(s[sid]['noisy_closed_loop_state'], 4)
        b = matrix(s[sid]['noise_free_closed_loop_state'], 4)
        return rms([x[i] - y[i] for x, y in zip(a, b)])
    return {'command_clean_pitch': final('large_command', 'noise_free_closed_loop_state', 0) - final('nominal_zero_command', 'noise_free_closed_loop_state', 0), 'command_clean_yaw': final('large_command', 'noise_free_closed_loop_state', 1) - final('nominal_zero_command', 'noise_free_closed_loop_state', 1), 'command_noisy_pitch': final('large_command', 'noisy_closed_loop_state', 0) - final('nominal_zero_command', 'noisy_closed_loop_state', 0), 'noise_pitch_divergence': drms('high_measurement_noise', 0) - drms('nominal_zero_command', 0), 'noise_yaw_rate_divergence': drms('high_measurement_noise', 3) - drms('nominal_zero_command', 3)}

def score(ref: dict[str, Any], cand: dict[str, Any]) -> dict[str, Any]:
    rv, rf = validate(ref)
    cv, cf = validate(cand)
    if not rv:
        raise ValueError('reference invalid: ' + '; '.join(rf))
    out = {'schema': 'simuverity.f90-xaero10-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'G': 1 if cv else 0, 'failures': cf}
    if not cv:
        out.update({'group_scores': {k: 0.0 for k in WEIGHTS}, 'per_scenario': {}, 'metrics': {}, 'raw_total': 0.0, 'total': 0.0})
        return out
    r, c = (smap(ref), smap(cand))
    per = {sid: scenario_score(r[sid], c[sid]) for sid in SCENARIO_IDS}
    acc = [0.5 * per[s]['noisy'] + 0.5 * per[s]['noise_free'] for s in SCENARIO_IDS]
    mech = [0.55 * per[s]['branch_divergence'] + 0.45 * per[s]['rates'] for s in SCENARIO_IDS]
    dyn = [0.65 * per[s]['rates'] + 0.35 * per[s]['terminal'] for s in SCENARIO_IDS]
    re, ce = (effects(r), effects(c))
    es = {k: scalar(ce[k], v) for k, v in re.items()}
    causal = all((abs(ce[k]) >= 0.05 * max(abs(re[k]), 1e-08) and ce[k] * re[k] > 0 for k in re))
    rn = matrix(c['nominal_zero_command']['noisy_closed_loop_state'], 4)
    rc = matrix(c['nominal_zero_command']['noise_free_closed_loop_state'], 4)
    div = max((rms([x[i] - y[i] for x, y in zip(rn, rc)]) for i in range(4)))
    mechanism = div > 0.0001
    groups = {'A': 0.75 * mean(acc) + 0.25 * min(acc), 'Q': 100.0, 'M': 0.7 * mean(mech) + 0.3 * min(mech), 'C': 0.7 * mean(list(es.values())) + 0.3 * min(es.values()), 'R': min((0.55 * acc[i] + 0.45 * mech[i] for i in range(5))), 'D': 0.7 * mean(dyn) + 0.3 * min(dyn)}
    if not mechanism:
        groups['M'] = 0.0
    if not causal:
        groups['C'] = 0.0
    raw = 0.0 if any((v <= 0 for v in groups.values())) else 100 * math.prod(((groups[k] / 100) ** w for k, w in WEIGHTS.items()))
    out.update({'group_scores': {k: round(v, 9) for k, v in groups.items()}, 'per_scenario': {sid: {k: round(v, 9) for k, v in row.items()} for sid, row in per.items()}, 'metrics': {'reference_intervention_effects': re, 'candidate_intervention_effects': ce, 'intervention_scores': es, 'causal_gate': causal, 'mechanism_gate': mechanism, 'worst_official_condition': groups['R']}, 'raw_total': round(raw, 9), 'total': round(raw, 9)})
    return out

def shortcuts(ref: dict[str, Any]) -> dict[str, Any]:
    cases = []
    m = copy.deepcopy(ref)
    del m['scenarios'][0]['noisy_closed_loop_state']
    cases.append(('missing_required_output', m))
    r = copy.deepcopy(ref)
    base = r['scenarios'][0]
    for row in r['scenarios'][1:]:
        for k in ('noisy_closed_loop_state', 'noise_free_closed_loop_state'):
            row[k] = copy.deepcopy(base[k])
    cases.append(('one_scenario_replayed_for_all_interventions', r))
    z = copy.deepcopy(ref)
    for row in z['scenarios']:
        row['noisy_closed_loop_state'] = [[0.0] * 4 for _ in row['time_s']]
        row['noise_free_closed_loop_state'] = [[0.0] * 4 for _ in row['time_s']]
    cases.append(('zero_state', z))
    cp = copy.deepcopy(ref)
    for row in cp['scenarios']:
        row['noisy_closed_loop_state'] = copy.deepcopy(row['noise_free_closed_loop_state'])
    cases.append(('noisy_branch_copied_from_noise_free', cp))
    cmd = copy.deepcopy(ref)
    for row in cmd['scenarios']:
        row['noisy_closed_loop_state'] = [[x[0], x[0], x[1], x[1]] for x in row['command_noise_state']]
    cases.append(('commands_copied_as_states', cmd))
    ign = copy.deepcopy(ref)
    nom = ign['scenarios'][0]
    high = ign['scenarios'][3]
    for k in ('noisy_closed_loop_state', 'noise_free_closed_loop_state'):
        high[k] = copy.deepcopy(nom[k])
    cases.append(('noise_covariance_ignored', ign))
    tr = copy.deepcopy(ref)
    target = tr['scenarios'][2]
    for k in ('time_s', 'noisy_closed_loop_state', 'noise_free_closed_loop_state', 'command_noise_state'):
        target[k] = target[k][:20]
    cases.append(('truncated_run', tr))
    rows = []
    for name, candidate in cases:
        s = score(ref, candidate)
        rows.append({'id': name, 'G': s['G'], 'raw_total': s['raw_total'], 'passed_below_admission_threshold': s['raw_total'] < 85})
    return {'schema': 'simuverity.f90-xaero10-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'admission_threshold_raw': 85.0, 'cases': rows, 'maximum_shortcut_raw_score': max((x['raw_total'] for x in rows)), 'all_shortcuts_below_threshold': all((x['passed_below_admission_threshold'] for x in rows))}

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--reference', required=True, type=Path)
    p.add_argument('--candidate', type=Path)
    p.add_argument('--score-output', type=Path)
    p.add_argument('--shortcut-sanity', type=Path)
    a = p.parse_args()
    r = read(a.reference)
    if a.shortcut_sanity:
        write(a.shortcut_sanity, shortcuts(r))
    if a.score_output:
        cp = a.candidate or a.reference
        o = score(r, read(cp))
        write(a.score_output, o)
if __name__ == '__main__':
    main()

"""Pure-offline dedicated scorer for F90-XCOMM-07 complete evidence."""
from __future__ import annotations
import argparse, copy, json, math
from pathlib import Path
from typing import Any
TASK_ID = 'F90-XCOMM-07'
SCENARIOS = ('bcc_nominal', 'bcc_low_snr', 'bcc_cfo_stress', 'ldpc_negative_cfo')
LOG_SPEC = {'channel_waveform': (['real', 'imag'], ['normalized amplitude', 'normalized amplitude']), 'bit_recovery': (['tx_bit', 'decoded_bit', 'bit_error'], ['1', '1', '1']), 'header_constellation': (['in_phase', 'quadrature'], ['normalized amplitude', 'normalized amplitude']), 'data_constellation': (['in_phase', 'quadrature'], ['normalized amplitude', 'normalized amplitude']), 'packet_detection': (['detected'], ['1']), 'cfo_estimation': (['normalized_frequency', 'estimated_frequency_Hz'], ['cycles/sample', 'Hz'])}
WEIGHTS = {'A': 0.25, 'Q': 0.1, 'M': 0.2, 'C': 0.2, 'R': 0.15, 'D': 0.1}

def load(p: Path) -> dict[str, Any]:
    return json.loads(p.read_text(encoding='utf-8'))

def write(p: Path, x: dict[str, Any]) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(x, indent=2, sort_keys=True, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')

def num(x: Any) -> bool:
    return isinstance(x, (int, float)) and (not isinstance(x, bool)) and math.isfinite(float(x))

def rows(x: Any, w: int) -> list[list[float]]:
    if not isinstance(x, list):
        raise ValueError('data is not an array')
    if w == 1 and (not x or num(x[0])):
        return [[float(v)] for v in x]
    out = []
    for r in x:
        if not isinstance(r, list) or len(r) != w or (not all((num(v) for v in r))):
            raise ValueError('row width or finiteness mismatch')
        out.append([float(v) for v in r])
    return out

def validate(e: dict[str, Any]) -> tuple[bool, list[str]]:
    f = []
    if e.get('task_id') != TASK_ID:
        f.append('task_id mismatch')
    s = e.get('scenarios')
    if not isinstance(s, list):
        return (False, f + ['scenarios is not an array'])
    ids = [x.get('id') for x in s if isinstance(x, dict)]
    if len(ids) != 4 or sorted(ids) != sorted(SCENARIOS):
        f.append('scenario identifiers mismatch')
    for x in s:
        if not isinstance(x, dict):
            f.append('scenario is not an object')
            continue
        sid = str(x.get('id', 'missing'))
        if x.get('valid') is not True:
            f.append(f'{sid}: validity flag is not true')
        logs = x.get('logs')
        if not isinstance(logs, dict) or set(logs) != set(LOG_SPEC):
            f.append(f'{sid}: log set mismatch')
            continue
        for name, (channels, units) in LOG_SPEC.items():
            log = logs[name]
            if log.get('channels') != channels:
                f.append(f'{sid}/{name}: channel order mismatch')
            if log.get('units') != units:
                f.append(f'{sid}/{name}: units mismatch')
            t = log.get('time')
            if not isinstance(t, list) or not t or (not all((num(v) for v in t))):
                f.append(f'{sid}/{name}: invalid time')
                continue
            tt = [float(v) for v in t]
            if tt[0] != 0 or any((b <= a for a, b in zip(tt, tt[1:]))):
                f.append(f'{sid}/{name}: time must be strictly increasing from zero')
            try:
                m = rows(log.get('data'), len(channels))
            except ValueError as ex:
                f.append(f'{sid}/{name}: {ex}')
                continue
            if len(m) != len(tt):
                f.append(f'{sid}/{name}: data/time length mismatch')
    return (not f, f)

def smap(e: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {x['id']: x for x in e['scenarios']}

def col(log: dict[str, Any], i: int) -> list[float]:
    return [r[i] for r in rows(log['data'], len(log['channels']))]

def mean(x: list[float]) -> float:
    return sum(x) / max(len(x), 1)

def rms(x: list[float]) -> float:
    return math.sqrt(mean([v * v for v in x]))

def ratio(r: float, c: float) -> float:
    if r <= 1e-12 or c <= 1e-12:
        return 100.0 if r <= 1e-12 and c <= 1e-12 else 0.0
    q = c / r
    return 100 * min(q, 1 / q)

def scalar_similarity(r: float, c: float, scale: float) -> float:
    return 100 * math.exp(-abs(c - r) / max(scale, 1e-12))

def mcs_order(m: int) -> int:
    return 2 if m == 0 else 4 if m <= 2 else 16 if m <= 4 else 64

def nearest_evm(i: list[float], q: list[float], M: int) -> float:
    levels = list(range(-(int(math.sqrt(M)) - 1), int(math.sqrt(M)), 2))
    pts = [complex(a, b) for a in levels for b in levels]
    norm = math.sqrt(mean([abs(z) ** 2 for z in pts]))
    pts = [z / norm for z in pts]
    x = [complex(a, b) for a, b in zip(i, q)]
    gain = math.sqrt(mean([abs(z) ** 2 for z in x]))
    if gain <= 1e-12:
        return 1000000000.0
    return 100 * math.sqrt(mean([min((abs(z / gain - p) ** 2 for p in pts)) for z in x]))

def metrics(s: dict[str, Any]) -> dict[str, float]:
    logs = s['logs']
    tx = col(logs['bit_recovery'], 0)
    rx = col(logs['bit_recovery'], 1)
    err = col(logs['bit_recovery'], 2)
    xor = [float(bool(round(a)) != bool(round(b))) for a, b in zip(tx, rx)]
    wave_i, wave_q = (col(logs['channel_waveform'], 0), col(logs['channel_waveform'], 1))
    di, dq = (col(logs['data_constellation'], 0), col(logs['data_constellation'], 1))
    det = col(logs['packet_detection'], 0)
    cfo = col(logs['cfo_estimation'], 1)
    first = next((i for i, v in enumerate(det) if v > 0.5), -1)
    return {'bits': float(len(tx)), 'ber': mean(err), 'xor_consistency': 100.0 if err == xor else 0.0, 'wave_rms': math.sqrt(mean([a * a + b * b for a, b in zip(wave_i, wave_q)])), 'const_rms': math.sqrt(mean([a * a + b * b for a, b in zip(di, dq)])), 'evm': nearest_evm(di, dq, mcs_order(int(s['mcs']))), 'detect_count': sum((1 for v in det if v > 0.5)), 'first_detect': float(first), 'cfo': cfo[-1], 'cfo_error': abs(cfo[-1] - float(s['carrier_frequency_offset_Hz']))}

def pair(ref: dict[str, dict[str, float]], cand: dict[str, dict[str, float]], a: str, b: str, keys: tuple[str, ...]) -> tuple[float, dict[str, float]]:
    rd = []
    cd = []
    for k in keys:
        scale = max(abs(ref[a][k]), abs(ref[b][k]), 1e-09)
        rd.append((ref[b][k] - ref[a][k]) / scale)
        cd.append((cand[b][k] - cand[a][k]) / scale)
    rs, cs = (rms(rd), rms(cd))
    mag = ratio(rs, cs)
    shape = 100 * math.exp(-2 * rms([x - y for x, y in zip(rd, cd)]) / max(rs, 1e-09))
    score = math.sqrt(mag * shape)
    return (score, {'reference_separation': rs, 'candidate_separation': cs, 'magnitude_utility': mag, 'score': score})

def score(ref_e: dict[str, Any], cand_e: dict[str, Any]) -> dict[str, Any]:
    ok, fail = validate(cand_e)
    out = {'schema': 'simuverity.f90-xcomm07-offline-score.v1', 'task_id': TASK_ID, 'offline_only': True, 'matlab_invoked': False, 'weights': WEIGHTS, 'gate': {'G': 1 if ok else 0, 'passed': ok, 'failures': fail}}
    if not ok:
        out.update(group_scores={g: 0.0 for g in WEIGHTS}, scenario_scores=[], causal_pairs={}, raw_score=0.0, score_eligible=False, failure_reasons=fail)
        return out
    ref_s, cand_s = (smap(ref_e), smap(cand_e))
    rm = {k: metrics(v) for k, v in ref_s.items()}
    cm = {k: metrics(v) for k, v in cand_s.items()}
    scenario = []
    for sid in SCENARIOS:
        r, c = (rm[sid], cm[sid])
        pieces = {'ber': scalar_similarity(r['ber'], c['ber'], max(r['ber'], 0.01)), 'evm': ratio(r['evm'], c['evm']), 'cfo': scalar_similarity(r['cfo'], c['cfo'], max(abs(float(ref_s[sid]['carrier_frequency_offset_Hz'])), 1000)), 'bit_count': ratio(r['bits'], c['bits']), 'packet_detection': ratio(r['detect_count'], c['detect_count'])}
        scenario.append({'id': sid, 'score': mean(list(pieces.values())), 'metrics': c, 'utilities': pieces})
    accuracy = mean([x['score'] for x in scenario])
    activity = []
    for sid in SCENARIOS:
        activity += [ratio(rm[sid]['wave_rms'], cm[sid]['wave_rms']), ratio(rm[sid]['const_rms'], cm[sid]['const_rms']), cm[sid]['xor_consistency'], 100.0 if cm[sid]['detect_count'] > 0 else 0.0]
    mechanism = mean(activity)
    pairs = {}
    for name, a, b, keys in (('snr', 'bcc_nominal', 'bcc_low_snr', ('ber', 'evm', 'wave_rms')), ('cfo', 'bcc_nominal', 'bcc_cfo_stress', ('cfo', 'cfo_error', 'evm')), ('channel_coding', 'bcc_nominal', 'ldpc_negative_cfo', ('bits', 'evm', 'cfo'))):
        _, details = pair(rm, cm, a, b, keys)
        pairs[name] = details
    pv = [x['score'] for x in pairs.values()]
    causal = 0.7 * min(pv) + 0.3 * mean(pv)
    robustness = min((x['score'] for x in scenario))
    dyn = []
    for sid in SCENARIOS:
        dyn += [ratio(rm[sid]['first_detect'], cm[sid]['first_detect']), scalar_similarity(rm[sid]['cfo_error'], cm[sid]['cfo_error'], max(rm[sid]['cfo_error'], 500))]
    dynamics = mean(dyn)
    groups = {'A': accuracy, 'Q': 100.0, 'M': mechanism, 'C': causal, 'R': robustness, 'D': dynamics}
    raw = 0.0 if any((v <= 0 for v in groups.values())) else 100 * math.exp(sum((WEIGHTS[g] * math.log(groups[g] / 100) for g in WEIGHTS)))
    reasons = [f'{k} input lacks adequate causal effect' for k, v in pairs.items() if v['score'] < 20]
    if mechanism < 30:
        reasons.append('connected waveform/synchronization/equalization/bit-recovery mechanism is absent')
    out.update(group_scores={g: round(v, 9) for g, v in groups.items()}, scenario_scores=scenario, causal_pairs=pairs, raw_score=round(raw, 9), score_eligible=True, failure_reasons=reasons)
    return out

def replace(dst: dict[str, Any], src: dict[str, Any]) -> None:
    dst['logs'] = copy.deepcopy(src['logs'])

def variants(ref: dict[str, Any]) -> dict[str, dict[str, Any]]:
    v = {}
    x = copy.deepcopy(ref)
    del x['scenarios'][0]['logs']['bit_recovery']
    v['missing_bit_recovery'] = x
    x = copy.deepcopy(ref)
    m = smap(x)
    for sid in SCENARIOS[1:]:
        replace(m[sid], m['bcc_nominal'])
    v['fixed_outputs_across_scenarios'] = x
    for name, a, b in (('snr_without_effect', 'bcc_nominal', 'bcc_low_snr'), ('cfo_without_effect', 'bcc_nominal', 'bcc_cfo_stress'), ('coding_without_effect', 'bcc_nominal', 'ldpc_negative_cfo')):
        x = copy.deepcopy(ref)
        m = smap(x)
        replace(m[b], m[a])
        v[name] = x
    x = copy.deepcopy(ref)
    for s in x['scenarios']:
        log = s['logs']['bit_recovery']
        mat = rows(log['data'], 3)
        for r in mat:
            r[1] = r[0]
            r[2] = 0.0
        log['data'] = mat
    v['copied_tx_bits_as_rx'] = x
    x = copy.deepcopy(ref)
    for s in x['scenarios']:
        for name in ('channel_waveform', 'header_constellation', 'data_constellation'):
            log = s['logs'][name]
            log['data'] = [[0.0] * len(log['channels']) for _ in log['time']]
    v['disconnected_waveform_or_constellation'] = x
    return v

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('reference', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--shortcut-sanity', type=Path)
    a = p.parse_args()
    ref = load(a.reference)
    ok, f = validate(ref)
    if not ok:
        raise SystemExit('invalid reference: ' + '; '.join(f))
    result = score(ref, load(a.candidate))
    write(a.output, result)
    if a.shortcut_sanity:
        cases = []
        for name, x in variants(ref).items():
            s = score(ref, x)
            cases.append({'id': name, 'raw_score': s['raw_score'], 'gate': s['gate'], 'group_scores': s['group_scores'], 'failure_reasons': s['failure_reasons'], 'passed_below_admission_threshold': s['raw_score'] < 85})
        write(a.shortcut_sanity, {'schema': 'simuverity.f90-xcomm07-shortcut-sanity.v1', 'task_id': TASK_ID, 'offline_only': True, 'admission_threshold_raw': 85.0, 'cases': cases, 'maximum_shortcut_raw_score': max((x['raw_score'] for x in cases)), 'all_shortcuts_below_threshold': all((x['passed_below_admission_threshold'] for x in cases))})
if __name__ == '__main__':
    main()

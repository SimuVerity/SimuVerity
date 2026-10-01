"""Post-lock Python reproduction of XP9 XAERO01 score semantics."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import base_receipt, group, load_evidence, parser, tail, total, utility, weights, write_receipt
TASK_ID = 'F90-XAERO-01'

def score(e):
    f = e['facts']
    rows = f.get('scenario_rows', [])
    flight = f.get('flight_evidence', {})
    angular = f.get('angular_evidence', {})
    prop = f.get('propulsion_evidence', {})
    gate = bool(f.get('score_inputs_valid', False))
    if not gate:
        groups = {'A': 0.0, 'Q': 0.0, 'M': 0.0, 'R': 0.0, 'D': 0.0}
        return (groups, 0.0, {'range': [], 'dynamic': []})
    if rows:
        n = rows[0]
        A = group([utility(n['hover_error'], [0, 0.08, 0.2, 0.48, 1.2, 3.0], [1, 1, 0.94, 0.73, 0.27, 0]), utility(n['hover_speed'], [0, 0.04, 0.1, 0.24, 0.62, 1.5], [1, 1, 0.94, 0.73, 0.27, 0]), utility(n['hover_attitude'], [0, 0.025, 0.06, 0.14, 0.34, 0.75], [1, 1, 0.94, 0.73, 0.27, 0])], [0.5, 0.28, 0.22])
        Q = group([utility(n['max_tilt'], [0, 0.35, 0.55, 0.65, 0.72, 0.9], [1, 1, 0.97, 0.9, 0.65, 0]), utility(n['motor_saturation_fraction'], [0, 0.003, 0.015, 0.06, 0.2, 0.55], [1, 1, 0.94, 0.72, 0.25, 0]), utility(max(n['path_overshoot'], n['path_orthogonal_deviation']), [0, 0.02, 0.06, 0.14, 0.34, 0.8], [1, 1, 0.94, 0.72, 0.25, 0]), utility(max((r['propulsion_rating_violation'] for r in rows)), [0, 0.0005, 0.002, 0.01, 0.04, 0.15, 0.45], [1, 0.995, 0.98, 0.94, 0.72, 0.25, 0])], [0.31, 0.29, 0.25, 0.15])
        M = group([utility(flight['error'], [0, 0.015, 0.045, 0.12, 0.3, 0.7], [1, 1, 0.95, 0.74, 0.28, 0]), utility(flight['euler_kinematic_error'], [0, 0.004, 0.015, 0.05, 0.16, 0.5], [1, 1, 0.95, 0.74, 0.28, 0]), utility(angular['error'], [0, 0.02, 0.05, 0.12, 0.25, 0.38], [1, 1, 0.95, 0.74, 0.28, 0]), utility(prop['error'], [0, 0.02, 0.06, 0.14, 0.32, 0.7], [1, 1, 0.95, 0.74, 0.28, 0]), utility(max((r['energy_balance_residual'] for r in rows)), [0, 0.0005, 0.002, 0.008, 0.03, 0.1], [1, 1, 0.95, 0.74, 0.28, 0]), utility(max((r['event_consistency_error'] for r in rows)), [0, 0.015, 0.05, 0.14, 0.32, 0.7], [1, 1, 0.95, 0.74, 0.28, 0]), utility(max((max(r['initial_position_error'], r['initial_speed_error']) for r in rows)), [0, 0.005, 0.02, 0.07, 0.25, 0.8], [1, 1, 0.95, 0.74, 0.28, 0]), utility(max((r['baseline_wind_error'] for r in rows)), [0, 0.005, 0.02, 0.06, 0.18, 0.5], [1, 1, 0.95, 0.74, 0.28, 0]), utility(max((r['payload_schedule_error'] for r in rows)), [0, 0.002, 0.008, 0.025, 0.1, 0.35], [1, 1, 0.95, 0.74, 0.28, 0])], [0.18, 0.1, 0.16, 0.14, 0.1, 0.1, 0.08, 0.07, 0.07])
        if not angular.get('core_dynamics_supported', False):
            M = min(M, 0.35)
    else:
        A = Q = M = 0
    rq = []
    dq = []
    for r in rows:
        rq.append(group([utility(r['hover_error'], [0, 0.14, 0.35, 0.8, 1.9, 4.5], [1, 1, 0.92, 0.69, 0.23, 0]), utility(r['hover_speed'], [0, 0.07, 0.16, 0.38, 0.9, 2.1], [1, 1, 0.92, 0.69, 0.23, 0]), utility(r['max_tilt'], [0, 0.45, 0.6, 0.67, 0.75, 0.95], [1, 1, 0.95, 0.85, 0.5, 0]), utility(r['motor_saturation_fraction'], [0, 0.008, 0.03, 0.1, 0.3, 0.7], [1, 1, 0.92, 0.68, 0.22, 0])], [0.38, 0.24, 0.21, 0.17]))
        dq.append(group([utility(r['gust_recovery_time'], [0, 0.25, 0.6, 1.2, 2.5, 5.0], [1, 1, 0.92, 0.7, 0.26, 0]), utility(r['payload_recovery_time'], [0, 0.25, 0.65, 1.4, 2.8, 5.5], [1, 1, 0.92, 0.7, 0.26, 0]), utility(r['event_consistency_error'], [0, 0.015, 0.05, 0.14, 0.32, 0.7], [1, 1, 0.93, 0.71, 0.25, 0])], [0.42, 0.42, 0.16]))
    R = tail(rq)
    D = tail(dq)
    groups = {'A': A, 'Q': Q, 'M': M, 'R': R, 'D': D}
    return (groups, total(gate, [A, Q, M, R, D], weights(e)), {'range': rq, 'dynamic': dq})

def main():
    a = parser(TASK_ID).parse_args()
    e = load_evidence(a.evidence, TASK_ID)
    g, v, u = score(e)
    r = base_receipt(a.evidence, e, g, v, policy_id='simuverity-101-v1:p9-xaero01:scoring')
    r.update({'scenario_rows': e['facts'].get('scenario_rows', []), 'utility_metrics': u})
    write_receipt(a.output, r)
if __name__ == '__main__':
    main()

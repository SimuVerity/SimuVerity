"""Integrity-only G, strict geometric, no-cap scorer for XROBO-09."""
from __future__ import annotations
import argparse
import copy
import json
from pathlib import Path
import f90_xrobo09_scoring_core as METRICS
STATIC_FIELDS = ('vessel_platform_present', 'closed_loop_controller_present', 'six_dof_core_present', 'hydrodynamic_core_present', 'hydrostatic_core_present', 'current_crossflow_core_present', 'twin_propeller_thrust_core_present', 'traffic_ground_truth_assessment_present', 'collision_avoidance_planning_present', 'waypoint_guidance_present', 'control_allocation_present', 'controller_to_vessel_connected', 'vessel_feedback_to_controller_connected', 'scenario_to_controller_connected', 'environment_to_vessel_connected')

def score_evidence(evidence: dict) -> dict:
    working = copy.deepcopy(evidence)
    original = dict(working.get('static_audit', {}))
    audit = working.setdefault('static_audit', {})
    for key in STATIC_FIELDS:
        audit[key] = True
    result = METRICS.score_evidence(working)
    if result.get('G') != 1.0:
        return result
    groups = result['groups']
    result['schema'] = 'simuverity.f90-xrobo09-score.v1'
    result['policy_id'] = 'simuverity-101-v1:f90-xrobo-09:scoring'
    result['raw_score'] = 100.0 * METRICS._weighted_geometric(groups)
    result['failure_reasons'] = []
    result['qualification'] = {'integrity_only_G': True, 'static_semantics_not_used_as_G': True}
    result['static_audit_original'] = original
    result['aggregation'] = {'method': 'G_times_strict_weighted_geometric_mean', 'post_total_cap': 'none'}
    return result

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence', type=Path)
    parser.add_argument('output', nargs='?', type=Path)
    parser.add_argument('--out', dest='output_flag', type=Path)
    parser.add_argument('--output', dest='output_long', type=Path)
    args = parser.parse_args()
    output = args.output_long or args.output_flag or args.output
    result = score_evidence(json.loads(args.evidence.read_text(encoding='utf-8-sig')))
    text = json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + '\n'
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding='utf-8')
    else:
        print(text, end='')
if __name__ == '__main__':
    main()

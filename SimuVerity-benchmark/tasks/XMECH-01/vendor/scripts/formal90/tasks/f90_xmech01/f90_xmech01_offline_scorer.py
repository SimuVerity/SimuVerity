#!/usr/bin/env python3
"""Active fixed-probe, six-domain offline scorer for P9-XMECH01."""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from formal90_offline_common import (  # noqa: E402
    base_receipt,
    finite,
    group,
    load_evidence,
    parser,
    tail,
    total,
    utility,
    write_receipt,
)

TASK_ID = "F90-XMECH-01"
POLICY_ID = "simuverity-101-v1:p9-xmech01:scoring"
POLICY_STATUS = "ACTIVE"
DOMAIN_WEIGHTS = {"A": .35, "Q": .10, "M": .25, "C": .10, "R": .10, "D": .10}
TRACK_POWER_ANCHORS = [0, .01, .03, .07, .15, .30, .55]
TRACK_POWER_UTILITIES = [1, 1, .95, .75, .40, .15, 0]
CHASSIS_POWER_ANCHORS = [0, .01, .03, .07, .13, .30, .70]
CHASSIS_POWER_UTILITIES = [1, 1, .95, .75, .45, .15, 0]
BINDING_ANCHORS = [0, .2, .4, .6, .8, 1]
BINDING_UTILITIES = [0, .50, .70, .85, .95, 1]
EVENT_ANCHORS = [0, .001, .003, .008, .022, .060]
EVENT_UTILITIES = [0, .20, .58, .86, 1, 1]
RECOVERY_ANCHORS = [0, .30, .65, 1.20, 2.30, 4.0]
RECOVERY_UTILITIES = [1, 1, .92, .70, .25, 0]


def _fixed_pair(suite: dict) -> tuple[dict, bool]:
    pair = suite.get("fixed_probe_pair")
    if not isinstance(pair, dict):
        return {}, False
    values = [
        finite(pair.get("binding"), math.nan),
        finite(pair.get("effect_strength"), math.nan),
        finite(pair.get("recovery_time"), math.nan),
        finite(pair.get("no_loss_degradation"), math.nan),
    ]
    recovery_observed = pair.get("recovery_observed")
    valid = (
        bool(pair.get("valid", False))
        and pair.get("loss_scenario") == "traction_binding_probe"
        and pair.get("control_scenario") == "traction_binding_probe_no_loss"
        and isinstance(recovery_observed, bool)
        and all(math.isfinite(value) for value in values)
        and (recovery_observed or values[2] >= RECOVERY_ANCHORS[-1])
    )
    return pair, valid


def score(evidence):
    facts = evidence["facts"]
    rows = facts.get("scenario_rows", [])
    suite = facts.get("suite_metrics", {})
    pair, pair_valid = _fixed_pair(suite)
    gate = bool(facts.get("score_inputs_valid", False)) and pair_valid
    reasons = [str(value) for value in facts.get("gate_reasons", []) if str(value)]
    if not pair_valid and "FIXED_TRACTION_BINDING_PROBE_PAIR_MISSING_OR_INVALID" not in reasons:
        reasons.append("FIXED_TRACTION_BINDING_PROBE_PAIR_MISSING_OR_INVALID")

    if rows:
        nominal = rows[0]
        A = group([
            utility(nominal["track_error"], [0, .025, .06, .13, .28, .55], [1, 1, .94, .75, .28, 0]),
            utility(nominal["forward_response_error"], [0, .015, .05, .14, .32, .70], [1, 1, .94, .72, .25, 0]),
            utility(nominal["turn_response_error"], [0, .015, .05, .14, .32, .70], [1, 1, .94, .72, .25, 0]),
        ], [.48, .27, .25])
        Q = group([
            utility(nominal["slip95"], [0, .025, .06, .13, .26, .55], [1, 1, .93, .70, .25, 0]),
            utility(nominal["track_ripple"], [0, .008, .02, .05, .12, .25], [1, 1, .93, .72, .25, 0]),
            utility(nominal["force_ripple"], [0, .015, .04, .09, .20, .45], [1, 1, .92, .68, .22, 0]),
        ], [.45, .25, .30])

        q_slip_activity = (
            utility(suite["slip_activity"], [0, .002, .006, .015, .035, .075], [0, .25, .60, .88, 1, 1])
            if suite.get("slip_activity_required", False)
            else 1
        )
        q_contact = group([
            utility(max(row["normal_balance_residual"] for row in rows), [0, .004, .012, .035, .10, .25], [1, 1, .94, .72, .25, 0]),
            utility(max(row["friction_excess"] for row in rows), [0, .002, .008, .025, .08, .25], [1, 1, .95, .75, .28, 0]),
            utility(suite["contact_power_direction_violation"], [0, .002, .01, .04, .15, .45], [1, 1, .94, .72, .25, 0]),
            utility(max(row["slip_definition_residual"] for row in rows), [0, .001, .004, .012, .04, .14], [1, 1, .96, .78, .30, 0]),
            utility(max(row["slip_sign_violation"] for row in rows), [0, .002, .01, .035, .12, .40], [1, 1, .95, .75, .28, 0]),
            q_slip_activity,
            utility(max(row["negative_normal_violation"] for row in rows), [0, .001, .004, .015, .06, .25], [1, 1, .95, .75, .28, 0]),
        ], [.13, .15, .15, .18, .14, .13, .12])
        q_kinematic_passivity = group([
            float(bool(suite.get("track_passive")) and bool(suite.get("chassis_passive"))),
            utility(suite["planar_kinematic_residual"], [0, .004, .012, .035, .10, .30], [1, 1, .95, .75, .28, 0]),
            utility(suite["yaw_kinematic_residual"], [0, .004, .012, .035, .10, .30], [1, 1, .95, .75, .28, 0]),
        ], [.16, .20, .16])
        q_drive = utility(suite["drive_activity"], [0, .003, .008, .018, .045, .10], [0, .35, .70, .92, 1, 1])
        M_phys = group([q_contact, q_kinematic_passivity, q_drive], [.40, .45, .15])
        q_track_energy = utility(suite["track_power_residual"], TRACK_POWER_ANCHORS, TRACK_POWER_UTILITIES)
        q_chassis_energy = utility(suite["chassis_power_residual"], CHASSIS_POWER_ANCHORS, CHASSIS_POWER_UTILITIES)
        q_energy = min(q_track_energy, q_chassis_energy)
        M = .10 * M_phys + .90 * q_energy
        if not suite.get("core_vehicle_contact", False):
            M = 0
    else:
        A = Q = M = q_contact = q_kinematic_passivity = q_drive = M_phys = 0
        q_track_energy = q_chassis_energy = q_energy = 0

    range_utilities = []
    for row in rows:
        range_utilities.append(group([
            utility(row["track_error"], [0, .035, .08, .17, .34, .65], [1, 1, .93, .70, .25, 0]),
            utility(row["forward_response_error"], [0, .025, .07, .18, .40, .80], [1, 1, .93, .70, .25, 0]),
            utility(row["turn_response_error"], [0, .025, .07, .18, .40, .80], [1, 1, .93, .70, .25, 0]),
            utility(row["slip95"], [0, .04, .09, .20, .42, .80], [1, 1, .92, .67, .20, 0]),
        ], [.38, .22, .20, .20]))
    R = tail(range_utilities)

    if pair_valid:
        C = utility(pair["binding"], BINDING_ANCHORS, BINDING_UTILITIES)
        q_event = utility(pair["effect_strength"], EVENT_ANCHORS, EVENT_UTILITIES)
        q_recovery = utility(pair["recovery_time"], RECOVERY_ANCHORS, RECOVERY_UTILITIES)
        D = group([q_event, q_recovery], [.60, .40])
    else:
        C = q_event = q_recovery = D = 0

    groups = {"A": A, "Q": Q, "M": M, "C": C, "R": R, "D": D}
    value = total(gate, list(groups.values()), [DOMAIN_WEIGHTS[name] for name in groups])
    details = {
        "gate": gate,
        "gate_reasons": reasons,
        "range": range_utilities,
        "mechanism": {
            "contact": q_contact,
            "kinematic_passivity": q_kinematic_passivity,
            "drive_activity": q_drive,
            "M_phys": M_phys,
            "track_energy": q_track_energy,
            "chassis_energy": q_chassis_energy,
            "q_energy": q_energy,
        },
        "causal": {"binding": pair.get("binding") if pair_valid else None},
        "dynamic": {
            "effect_strength": pair.get("effect_strength") if pair_valid else None,
            "recovery_time": pair.get("recovery_time") if pair_valid else None,
            "event_utility": q_event,
            "recovery_utility": q_recovery,
        },
    }
    return groups, value, details


def main():
    args = parser(TASK_ID).parse_args()
    evidence = load_evidence(args.evidence, TASK_ID)
    groups, value, details = score(evidence)
    receipt = base_receipt(
        args.evidence,
        evidence,
        groups,
        value,
        policy_id=POLICY_ID,
        gate_reasons=details["gate_reasons"],
        gate_override=details["gate"],
    )
    receipt["policy_status"] = POLICY_STATUS
    receipt["groups"] = {"G": int(details["gate"]), **groups}
    receipt["C"] = groups["C"]
    receipt["group_weights"] = DOMAIN_WEIGHTS
    receipt["cross_group_aggregation"] = "G_times_strict_weighted_geometric_mean"
    receipt["post_total_cap_floor_or_override"] = "none"
    receipt["scenario_rows"] = evidence["facts"].get("scenario_rows", [])
    receipt["suite_metrics"] = evidence["facts"].get("suite_metrics", {})
    receipt["utility_metrics"] = details
    write_receipt(args.output, receipt)


if __name__ == "__main__":
    main()

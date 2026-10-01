"""D007 scorer with exact VI feedback and a protected robustness tail."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, boolean, bottleneck, finite, geometric, make_result, nominal,
    scenario_map, semantic_gate, suite, task_measurements, vector,
    worst_anchor, run_cli,
)

TASK_ID = "D007"
POLICY_ID = "simuverity-101-v1:d007:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = (
    "id_less", "id_more", "iq_positive", "iq_negative", "id_iq_joint",
    "id_iq_interior_pos", "id_iq_interior_neg", "grid_low", "grid_high",
    "joint_grid_low_pos", "joint_grid_high_neg",
    "joint_grid_low_endpoint_pos", "joint_grid_high_endpoint_neg",
)
ID_COMMAND = (-.8, -1.2, -1, -1, -1.2, -.91, -1.11, -1, -1, -.91, -1.11, -1.2, -.8)
IQ_COMMAND = (0, 0, .5, -.5, .5, .27, -.31, 0, 0, .27, -.31, .5, -.5)
GRID_COMMAND = (1, 1, 1, 1, 1, 1, 1, .9, 1.1, .93, 1.07, .9, 1.1)


def _row3(metrics, field):
    return vector(metrics.get(field), 3)


def _frequency_q(metrics):
    return worst_anchor(
        [abs(value - 50) for value in _row3(metrics, "Vout_freq")],
        (0, .05, .2, .5, 1, 3), (1, 1, .95, .75, .3, 0),
    )


def _sequence_quality(metrics):
    voltage = finite(metrics.get("Vout_sequence_index"))
    current = finite(metrics.get("Igrid_sequence_index"))
    curve_x = (0, .4, .7, .85, .95, 1)
    curve_y = (0, .15, .45, .75, 1, 1)
    q_voltage = anchor(abs(voltage), curve_x, curve_y)
    q_current = anchor(abs(current), curve_x, curve_y)
    q_order = float(
        math.isfinite(voltage)
        and math.isfinite(current)
        and voltage * current > 0
        and boolean(metrics.get("sequence_order_consistent"))
    )
    return bottleneck(
        (q_voltage, q_current, q_order), (25, 55, 20)
    ), (q_voltage, q_current, q_order)


def _quality(metrics, include_frequency=False):
    q_frequency = _frequency_q(metrics)
    q_vthd = worst_anchor(
        [100 * value for value in _row3(metrics, "Vout_thd")],
        (0, 3, 5, 8, 12, 25), (1, 1, .95, .75, .35, 0),
    )
    q_ithd = worst_anchor(
        [100 * value for value in _row3(metrics, "Igrid_thd")],
        (0, 3, 5, 8, 12, 25), (1, 1, .95, .75, .35, 0),
    )
    q_vimb = anchor(
        100 * finite(metrics.get("Vout_imbalance")),
        (0, .2, .5, 1, 2, 8), (1, 1, .95, .8, .45, 0),
    )
    q_iimb = anchor(
        100 * finite(metrics.get("Igrid_imbalance")),
        (0, .5, 1, 2, 5, 15), (1, 1, .95, .8, .4, 0),
    )
    q_fundamental = worst_anchor(
        _row3(metrics, "fundamental_current_fraction"),
        (.5, .75, .9, .95, .98, 1), (0, .3, .7, .9, 1, 1),
    )
    q_sequence, sequence_detail = _sequence_quality(metrics)
    values = [q_vthd, q_ithd, q_vimb, q_iimb, q_fundamental, q_sequence]
    weights = [5, 40, 5, 15, 15, 20]
    if include_frequency:
        values = [q_frequency, *values]
        weights = [5, 5, 35, 5, 15, 15, 20]
    return bottleneck(values, weights), {
        "frequency_q": q_frequency,
        "voltage_thd_q": q_vthd, "current_thd_q": q_ithd,
        "voltage_imbalance_q": q_vimb, "current_imbalance_q": q_iimb,
        "fundamental_fraction_q": q_fundamental,
        "sequence_q": q_sequence,
        "sequence_components": list(sequence_detail),
    }


def _tracking_q(values):
    return worst_anchor(
        values, (0, .02, .05, .10, .20, .40),
        (1, 1, .97, .85, .50, 0),
    )


def _cross_q(values):
    return worst_anchor(
        values, (0, .01, .03, .06, .12, .30),
        (1, 1, .97, .85, .45, 0),
    )


def _grid_scale_q(values):
    return worst_anchor(
        values, (0, .005, .015, .03, .06, .20),
        (1, 1, .95, .75, .3, 0),
    )


def _response_gain(actual_rows, expected):
    result = []
    for row, denominator in zip(actual_rows, expected):
        if math.isfinite(denominator) and abs(denominator) > sys.float_info.epsilon:
            result.append([value / denominator for value in row])
        else:
            result.append([math.nan] * 3)
    return result


def _gain_spread_q(matrix_values):
    flat = [value for row in matrix_values for value in row]
    if not flat or any(not math.isfinite(value) for value in flat):
        return 0.0
    spread = [
        max(row[index] for row in matrix_values)
        - min(row[index] for row in matrix_values)
        for index in range(3)
    ]
    return worst_anchor(
        spread, (0, .05, .10, .20, .40, 1),
        (1, 1, .97, .82, .40, 0),
    )


def _gain_direction_q(*matrices):
    values = [
        value for matrix_values in matrices
        for row in matrix_values for value in row
    ]
    return worst_anchor(
        values, (-.1, 0, .2, .5, .8), (0, 0, .3, .8, 1)
    )


def _current_presence_q(metrics, id_command, iq_command, current_base):
    target = math.hypot(id_command, iq_command) * current_base
    ratios = [
        value / max(abs(target), sys.float_info.epsilon)
        for value in _row3(metrics, "fundamental_current_rms")
    ]
    return worst_anchor(
        ratios, (0, .2, .5, .65, .75), (0, .1, .5, .85, 1)
    )


def _cycle_response(metrics):
    response = metrics.get("cycle_response")
    if not isinstance(response, dict) or not boolean(response.get("valid")):
        return 0.0, False
    time_fraction = finite(response.get("settling_time_fraction"))
    iae = finite(response.get("normalized_iae"))
    if not all(math.isfinite(value) for value in (time_fraction, iae)):
        return 0.0, False
    quality = (
        math.exp(-math.log(10) * time_fraction)
        * math.exp(-(math.log(10) / .20) * iae)
    )
    return quality, True


def score_evidence(evidence):
    sv = suite(evidence)
    gate, gate_reasons = semantic_gate(evidence, SCENARIOS)
    spec_contract = evidence["task_spec"].get("physical_contract")
    spec_contract = spec_contract if isinstance(spec_contract, dict) else {}
    current_base = finite(spec_contract.get("current_base_rms_a"), 7.0)
    line_voltage = finite(spec_contract.get("grid_line_line_rms_v"), 230.0)
    phase_voltage = line_voltage / math.sqrt(3)
    nom = task_measurements(nominal(sv))
    nom_active = _row3(nom, "active_current")
    nom_quadrature = _row3(nom, "quadrature_lag_current")
    q_active = worst_anchor(
        [abs(value - current_base) / current_base for value in nom_active],
        (0, .01, .02, .05, .10, .25, .50),
        (1, 1, .98, .92, .70, .25, 0),
    )
    q_quadrature = worst_anchor(
        [abs(value) / current_base for value in nom_quadrature],
        (0, .005, .01, .03, .07, .15, .35),
        (1, 1, .98, .90, .65, .25, 0),
    )
    q_voltage = worst_anchor(
        [
            abs(value - phase_voltage) / phase_voltage
            for value in _row3(nom, "fundamental_voltage_rms")
        ],
        (0, .005, .01, .02, .05, .15), (1, 1, .98, .90, .50, 0),
    )
    q_frequency = _frequency_q(nom)
    A = bottleneck(
        (q_active, q_quadrature, q_voltage, q_frequency),
        (50, 15, 25, 10),
    )
    Q, quality_detail = _quality(nom)

    scenarios = scenario_map(sv)
    metrics = [
        task_measurements(scenarios.get(scenario_id, {}))
        for scenario_id in SCENARIOS
    ]
    active = [_row3(item, "active_current") for item in metrics]
    quadrature = [_row3(item, "quadrature_lag_current") for item in metrics]
    expected_active = [-value * current_base for value in ID_COMMAND]
    expected_quadrature = [value * current_base for value in IQ_COMMAND]
    active_errors = [
        [abs(value - expected_active[index]) / current_base for value in row]
        for index, row in enumerate(active)
    ]
    quadrature_errors = [
        [
            abs(value - expected_quadrature[index]) / current_base
            for value in row
        ]
        for index, row in enumerate(quadrature)
    ]
    active_tracking = [_tracking_q(row) for row in active_errors]
    quadrature_tracking = [_tracking_q(row) for row in quadrature_errors]
    id_indices = (0, 1, 4, 5, 6)
    iq_indices = (2, 3, 4, 5, 6)
    id_tracking = bottleneck(
        [active_tracking[index] for index in id_indices], [1] * 5
    )
    iq_tracking = bottleneck(
        [quadrature_tracking[index] for index in iq_indices], [1] * 5
    )
    id_cross_errors = [
        [
            abs(quadrature[index][phase] - nom_quadrature[phase])
            / current_base
            for phase in range(3)
        ]
        for index in (0, 1)
    ]
    iq_cross_errors = [
        [
            abs(active[index][phase] - nom_active[phase]) / current_base
            for phase in range(3)
        ]
        for index in (2, 3)
    ]
    cross_scores = [
        *[_cross_q(row) for row in id_cross_errors],
        *[_cross_q(row) for row in iq_cross_errors],
    ]
    cross_coupling = bottleneck(cross_scores, [1] * 4)
    active_delta = [
        [
            (active[index][phase] - nom_active[phase]) / current_base
            for phase in range(3)
        ]
        for index in range(len(SCENARIOS))
    ]
    quadrature_delta = [
        [
            (quadrature[index][phase] - nom_quadrature[phase]) / current_base
            for phase in range(3)
        ]
        for index in range(len(SCENARIOS))
    ]
    id_gain = _response_gain(
        [active_delta[index] for index in id_indices],
        [-ID_COMMAND[index] - 1 for index in id_indices],
    )
    iq_gain = _response_gain(
        [quadrature_delta[index] for index in iq_indices],
        [IQ_COMMAND[index] for index in iq_indices],
    )
    id_spread = _gain_spread_q(id_gain)
    iq_spread = _gain_spread_q(iq_gain)
    direction = _gain_direction_q(id_gain, iq_gain)
    consistency = bottleneck(
        (id_spread, iq_spread, direction), (35, 35, 30)
    )
    C = bottleneck(
        (id_tracking, iq_tracking, cross_coupling, consistency),
        (30, 30, 20, 20),
    )

    scenario_rows = []
    r_values = []
    metrics_valid = boolean(nom.get("valid"))
    for index, scenario_id in enumerate(SCENARIOS):
        one_quality, one_quality_detail = _quality(
            metrics[index], include_frequency=True
        )
        presence = _current_presence_q(
            metrics[index], ID_COMMAND[index], IQ_COMMAND[index], current_base
        )
        tracking = bottleneck(
            (
                _tracking_q(active_errors[index]),
                _tracking_q(quadrature_errors[index]),
            ),
            (55, 45),
        )
        measured_voltage = _row3(metrics[index], "fundamental_voltage_rms")
        grid_errors = [
            abs(value - phase_voltage * GRID_COMMAND[index]) / phase_voltage
            for value in measured_voltage
        ]
        grid_quality = _grid_scale_q(grid_errors)
        weights = (45, 5, 40, 10) if abs(
            GRID_COMMAND[index] - 1
        ) > sys.float_info.epsilon else (50, 5, 40, 5)
        one = bottleneck(
            (one_quality, presence, tracking, grid_quality), weights
        )
        valid = bool(scenarios.get(scenario_id)) and boolean(
            metrics[index].get("valid")
        )
        metrics_valid = metrics_valid and valid
        r_values.append(one if valid else 0.0)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid,
            "score": one if valid else 0.0,
            "quality_q": one_quality, "quality": one_quality_detail,
            "current_presence_q": presence, "tracking_q": tracking,
            "active_error_per_phase": active_errors[index],
            "quadrature_error_per_phase": quadrature_errors[index],
            "grid_scale_error_per_phase": grid_errors,
            "grid_scale_q": grid_quality,
        })
    R = min(r_values, default=0.0)
    recovery = []
    d_values = []
    for scenario_id, measurement in [("nominal", nom), *list(
        zip(SCENARIOS, metrics)
    )]:
        value, valid = _cycle_response(measurement)
        d_values.append(value if valid else 0.0)
        metrics_valid = metrics_valid and valid
        recovery.append({
            "scenario": scenario_id, "valid": valid,
            "score": value if valid else 0.0,
        })
    D = min(d_values, default=0.0)
    groups = {"A": A, "Q": Q, "C": C, "R": R, "D": D}
    total = geometric(
        groups, {"A": .20, "Q": .10, "C": .20, "R": .20, "D": .30}
    )
    reasons = gate_reasons + ([] if metrics_valid else [
        "D007_REQUIRED_PHYSICAL_OR_COLD_START_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "C", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "active_current_target_q": q_active,
             "quadrature_current_target_q": q_quadrature,
             "grid_voltage_target_q": q_voltage,
             "frequency_q": q_frequency},
            {"group": "Q", **quality_detail},
            {"group": "C", "id_tracking_q": id_tracking,
             "iq_tracking_q": iq_tracking,
             "cross_coupling_q": cross_coupling,
             "id_gain_spread_q": id_spread,
             "iq_gain_spread_q": iq_spread,
             "direction_q": direction,
             "sign_interior_consistency_q": consistency},
            {"group": "D", "recovery": recovery},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

"""D011 causal-drive pure-offline scorer."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, boolean, bottleneck, finite, geometric, make_result, nominal,
    oracle_pass, oracle_row, scenario_map, semantic_gate, suite,
    task_measurements, vector, worst_anchor, run_cli,
)

TASK_ID = "D011"
POLICY_ID = "simuverity-101-v1:d011:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = ("frequency_low", "frequency_high")
REQUIRED_ORACLE_IDS = (
    "D011.active_svpwm_gate_ownership",
    "D011.dc_link_rectifier_ownership",
    "D011.mechanical_causality",
)


def _row3(metrics, field):
    return vector(metrics.get(field), 3)


def _frequency_q(values, target):
    return worst_anchor(
        [abs(value - target) for value in values],
        (0, .05, .2, .5, 1, 3, 6), (1, 1, .97, .85, .55, .15, 0),
    )


def _sequence_q(metrics):
    voltage = abs(finite(metrics.get("Vabc_sequence_index")))
    current = abs(finite(metrics.get("Iabc_sequence_index")))
    curve_x = (0, .5, .8, .95, 1)
    curve_y = (0, .2, .65, 1, 1)
    return bottleneck((
        anchor(voltage, curve_x, curve_y),
        anchor(current, curve_x, curve_y),
    ), (40, 60))


def _quality(metrics):
    q_vthd = worst_anchor(
        [100 * value for value in _row3(metrics, "Vabc_thd")],
        (0, 5, 10, 15, 25, 50), (1, 1, .98, .90, .60, 0),
    )
    q_ithd = worst_anchor(
        [100 * value for value in _row3(metrics, "Iabc_thd")],
        (0, 5, 8, 12, 20, 40), (1, 1, .95, .75, .35, 0),
    )
    q_vimb = anchor(
        100 * finite(metrics.get("Vabc_imbalance")),
        (0, .5, 1, 2, 5, 15), (1, 1, .95, .8, .35, 0),
    )
    q_iimb = anchor(
        100 * finite(metrics.get("Iabc_imbalance")),
        (0, .5, 1, 2, 5, 15), (1, 1, .95, .8, .35, 0),
    )
    q_sequence = _sequence_q(metrics)
    values = (q_vthd, q_ithd, q_vimb, q_iimb, q_sequence)
    return bottleneck(values, (15, 30, 15, 15, 25)), values


def _direction_q(values):
    if len(values) != 3 or any(not math.isfinite(value) for value in values):
        return 0.0
    differences = (values[1] - values[0], values[2] - values[1])
    scale = max(abs(values[2] - values[0]), sys.float_info.epsilon)
    return worst_anchor(
        [value / scale for value in differences],
        (0, .05, .2, .4, .5), (0, .2, .65, .95, 1),
    )


def score_evidence(evidence):
    sv = suite(evidence)
    gate, gate_reasons = semantic_gate(evidence, SCENARIOS)
    for oracle_id in REQUIRED_ORACLE_IDS:
        if not oracle_pass(oracle_row(sv, oracle_id)):
            gate_reasons.append("REQUIRED_TASK_ORACLE_FAIL:" + oracle_id)
    gate = not gate_reasons
    nom = task_measurements(nominal(sv))
    scenarios = scenario_map(sv)
    low = task_measurements(scenarios.get("frequency_low", {}))
    high = task_measurements(scenarios.get("frequency_high", {}))
    q_nominal_frequency = _frequency_q(_row3(nom, "Vabc_freq"), 50)
    A = q_nominal_frequency
    Q, q_detail = _quality(nom)
    q_tracking = (
        _frequency_q(_row3(low, "Vabc_freq"), 45),
        q_nominal_frequency,
        _frequency_q(_row3(high, "Vabc_freq"), 55),
    )
    measured_frequency = [
        sum(_row3(item, "Vabc_freq")) / 3 for item in (low, nom, high)
    ]
    rotor_speed = [
        finite(item.get("Wm_ss")) for item in (low, nom, high)
    ]
    speed_direction = _direction_q(rotor_speed)
    frequency_direction = _direction_q(measured_frequency)
    C = bottleneck((
        min(q_tracking), speed_direction, frequency_direction
    ), (55, 25, 20))
    low_quality, low_detail = _quality(low)
    high_quality, high_detail = _quality(high)
    low_r = bottleneck((q_tracking[0], low_quality), (60, 40))
    high_r = bottleneck((q_tracking[2], high_quality), (60, 40))
    R = min(low_r, high_r)
    metrics_valid = (
        boolean(nom.get("valid"))
        and boolean(low.get("valid"))
        and boolean(high.get("valid"))
    )
    groups = {"A": A, "Q": Q, "C": C, "R": R}
    total = geometric(groups, {"A": .25, "Q": .25, "C": .30, "R": .20})
    reasons = gate_reasons + ([] if metrics_valid else [
        "D011_REQUIRED_PHYSICAL_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "C", "R"), total_score=total,
        metrics=(
            {"group": "A", "frequency_q": A},
            {"group": "Q", "component_q": list(q_detail)},
            {"group": "C", "command_hz": [45, 50, 55],
             "measured_hz": measured_frequency, "rotor_speed": rotor_speed,
             "tracking_q": list(q_tracking),
             "speed_direction_q": speed_direction,
             "frequency_direction_q": frequency_direction},
        ),
        scenarios=(
            {"scenario": "frequency_low", "valid": boolean(low.get("valid")),
             "score": low_r, "frequency_q": q_tracking[0],
             "quality_q": low_quality, "quality_components": list(low_detail)},
            {"scenario": "frequency_high", "valid": boolean(high.get("valid")),
             "score": high_r, "frequency_q": q_tracking[2],
             "quality_q": high_quality, "quality_components": list(high_detail)},
        ),
        failure_reasons=reasons, score_inputs_valid=metrics_valid,
        policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

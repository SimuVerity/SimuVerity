"""D014 SPS continuous-average-VSC scoring helper."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, boolean, finite, make_result, nominal, scenario_map,
    semantic_gate, suite, task_measurements, vector, weighted, run_cli,
)

TASK_ID = "D014"
POLICY_ID = "simuverity-101-v1:d014:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = (
    "source_up", "source_down", "load_up", "load_down",
    "joint_low_source_high_load", "joint_high_source_low_load",
    "joint_interior_a", "joint_interior_b",
)


def _row3(metrics, field):
    return vector(metrics.get(field), 3)


def _duplicate_quality(correlation):
    if not math.isfinite(correlation):
        return 0.0
    error = max(0.0, correlation - .55)
    if error <= 0:
        return 1.0
    if error <= .12:
        return .4 + .6 * (1 - error / .12)
    if error < .42:
        return .4 * (.42 - error) / .30
    return 0.0


def _cycle_response(metrics):
    response = metrics.get("cycle_response")
    if not isinstance(response, dict) or not boolean(response.get("valid")):
        return 0.0, False, {}
    time_fraction = finite(response.get("settling_time_fraction"))
    iae = finite(response.get("normalized_iae"))
    if not all(math.isfinite(value) for value in (time_fraction, iae)):
        return 0.0, False, {}
    q_settling = math.exp(-math.log(10) * time_fraction)
    q_iae = math.exp(-(math.log(10) / .05) * iae)
    return q_settling * q_iae, True, {
        "settling_time_fraction": time_fraction, "normalized_iae": iae,
        "q_settling": q_settling, "q_iae": q_iae,
    }


def score_evidence(evidence):
    sv = suite(evidence)
    gate, gate_reasons = semantic_gate(
        evidence, SCENARIOS, include_scenario_oracles=True
    )
    nom = task_measurements(nominal(sv))
    rms = _row3(nom, "Vabc_rms")
    frequency = _row3(nom, "Vabc_freq")
    vthd = _row3(nom, "Vabc_thd")
    ithd = _row3(nom, "Iabc_thd")
    q_rms = anchor(
        max((abs(value - 222) for value in rms), default=math.nan),
        (0, .3, .5, 1, 1.5, 2.22, 4.44),
        (1, 1, .97, .90, .75, .30, 0),
    )
    q_frequency = anchor(
        max((abs(value - 50) for value in frequency), default=math.nan),
        (0, .02, .1, .5, 1, 2), (1, 1, .95, .70, .30, 0),
    )
    q_vimb = anchor(
        100 * finite(nom.get("Vabc_imbalance")),
        (0, .2, .5, 1, 2, 5), (1, 1, .85, .60, .20, 0),
    )
    q_vthd = anchor(
        100 * max(vthd, default=math.nan),
        (0, 3, 5, 8, 12, 20), (1, 1, .95, .75, .40, 0),
    )
    q_ithd = anchor(
        100 * max(ithd, default=math.nan),
        (0, 3, 5, 8, 12, 20), (1, 1, .95, .75, .40, 0),
    )
    q_ripple = anchor(
        100 * finite(nom.get("Vdc_ripple_pp_frac")),
        (0, .2, .5, 2, 5, 10), (1, 1, .95, .70, .25, 0),
    )
    q_independence = _duplicate_quality(
        finite(nom.get("Vabc_duplicate_corr"))
    )
    A = weighted((q_rms, q_frequency, q_vimb), (6, 1, 3))
    Q = weighted(
        (q_vthd, q_ithd, q_ripple, q_independence), (15, 5, 3, 2)
    )

    scenarios = scenario_map(sv)
    nominal_a_rms = rms[0] if rms else math.nan
    robustness = []
    r_values = []
    diagnostic_valid = boolean(nom.get("valid"))
    for scenario_id in SCENARIOS:
        metrics = task_measurements(scenarios.get(scenario_id, {}))
        scenario_rms = _row3(metrics, "Vabc_rms")
        valid = (
            boolean(metrics.get("Vabc_rms_valid"))
            and math.isfinite(nominal_a_rms)
            and nominal_a_rms > sys.float_info.epsilon
            and math.isfinite(scenario_rms[0])
        )
        change = (
            100 * abs(scenario_rms[0] - nominal_a_rms) / abs(nominal_a_rms)
            if valid else math.nan
        )
        quality = anchor(
            change, (0, .2, .5, 1, 2, 5), (1, 1, .90, .70, .30, 0)
        )
        r_values.append(quality)
        diagnostic_valid = diagnostic_valid and valid
        robustness.append({
            "scenario": scenario_id, "valid": valid,
            "A_phase_rms": scenario_rms[0],
            "relative_change_pct": change, "score": quality,
        })
    R = min(r_values, default=0.0)

    recovery = []
    for scenario_id, metrics in [("nominal", nom), *[
        (scenario_id, task_measurements(scenarios.get(scenario_id, {})))
        for scenario_id in SCENARIOS
    ]]:
        value, valid, detail = _cycle_response(metrics)
        diagnostic_valid = diagnostic_valid and valid
        recovery.append({
            "scenario": scenario_id, "valid": valid, "score": value, **detail
        })
    D = min((row["score"] for row in recovery), default=0.0)
    groups = {"A": A, "Q": Q, "R": R, "D": D}
    total = 100 * A ** .50 * Q ** .30 * R ** .20
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "R"), total_score=total,
        metrics=(
            {"group": "A", "rms_q": q_rms, "frequency_q": q_frequency,
             "voltage_unbalance_q": q_vimb},
            {"group": "Q", "voltage_thd_q": q_vthd,
             "current_thd_q": q_ithd, "dc_ripple_q": q_ripple,
             "three_phase_independence_q": q_independence},
            {"group": "D_DIAGNOSTIC_ONLY", "score": D,
             "valid": diagnostic_valid, "recovery": recovery},
        ),
        scenarios=robustness, failure_reasons=gate_reasons,
        # D014 deliberately has no second global metric gate: invalid
        # numerical atoms map to their own zero utility.
        score_inputs_valid=True, policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

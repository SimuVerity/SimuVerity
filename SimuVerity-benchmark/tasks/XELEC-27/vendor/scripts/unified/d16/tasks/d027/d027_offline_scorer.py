"""D027 NPC-aggregate feedback compatibility scorer."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, band_value, boolean, bottleneck, finite, geometric, make_result,
    nominal, scenario_map, semantic_gate, suite, task_measurements, run_cli,
)

TASK_ID = "D027"
POLICY_ID = "simuverity-101-v1:d027:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = ("reference_up", "reference_down")
ORACLE_ID = "D027.active_current_feedback_ownership"


def _current_q(value, amplitude):
    target = amplitude / math.sqrt(2)
    return anchor(
        abs(value - target) / target,
        (0, .005, .01, .02, .05, .15, .4),
        (1, 1, .98, .93, .75, .3, 0),
    )


def _frequency_q(value):
    return anchor(
        abs(value - 50), (0, .05, .2, .5, 1.5, 4, 6),
        (1, 1, .98, .9, .55, .15, 0),
    )


def _voltage_q(value):
    return anchor(
        abs(value - 1200) / 1200, (0, .01, .025, .05, .12, .3, .5),
        (1, 1, .98, .9, .65, .2, 0),
    )


def _levels_q(levels, plateau):
    return bottleneck((
        anchor(abs(levels - 5), (0, .25, .75, 1.5, 3), (1, 1, .9, .5, 0)),
        anchor(plateau, (0, .35, .55, .7, .85, 1), (0, .25, .6, .85, 1, 1)),
    ), (70, 30))


def _gain_q(value):
    if not math.isfinite(value) or value <= 0:
        return 0.0
    return anchor(
        abs(value - 1), (0, .05, .15, .35, .75, 1.5),
        (1, 1, .97, .85, .45, 0),
    )


def _cold(row):
    cold = task_measurements(row).get("cold_start")
    if not isinstance(cold, dict) or not boolean(cold.get("valid")):
        return 0.0, False
    tf = finite(cold.get("settling_time_fraction"))
    iae = finite(cold.get("normalized_iae"))
    if not all(math.isfinite(x) for x in (tf, iae)):
        return 0.0, False
    q_time = anchor(
        tf, (0, 1 / 15, 2 / 15, 3 / 15, 1), (1, 1, .30, .10, 0)
    )
    q_iae = anchor(
        iae, (0, .01, .01815, .03, .05), (1, 1, .35, .10, 0)
    )
    return bottleneck((q_time, q_iae), (1, 1)), True


def score_evidence(evidence):
    sv = suite(evidence)
    gate, gate_reasons = semantic_gate(
        evidence, SCENARIOS, required_oracle_id=ORACLE_ID
    )
    nom = nominal(sv)
    nominal_ids = (
        "vout_pp_nom", "vout_freq_nom", "vout_levels_nom",
        "vout_plateau_nom", "iabc_rms_nom", "iabc_freq_nom",
        "iabc_balance_nom", "vout_mean_nom", "iabc_thd_nom",
        "iabc_duplicate_guard", "iabc_phase_sequence_nom",
    )
    values = {band_id: band_value(nom, band_id) for band_id in nominal_ids}
    q_current = _current_q(values["iabc_rms_nom"][0], 5)
    q_current_freq = _frequency_q(values["iabc_freq_nom"][0])
    q_voltage = _voltage_q(values["vout_pp_nom"][0])
    q_voltage_freq = _frequency_q(values["vout_freq_nom"][0])
    q_levels = _levels_q(
        values["vout_levels_nom"][0], values["vout_plateau_nom"][0]
    )
    q_sequence = anchor(
        abs(values["iabc_phase_sequence_nom"][0]),
        (0, .4, .7, .85, .95, 1), (0, .15, .45, .75, 1, 1),
    )
    q_balance = anchor(
        values["iabc_balance_nom"][0],
        (0, .005, .02, .05, .1, .25), (1, 1, .98, .9, .55, 0),
    )
    A = bottleneck((
        q_current, q_current_freq, q_voltage, q_voltage_freq,
        q_levels, q_sequence, q_balance,
    ), (35, 10, 15, 5, 15, 10, 10))
    q_thd = anchor(
        values["iabc_thd_nom"][0], (0, .03, .05, .08, .15, .25),
        (1, 1, .97, .85, .45, 0),
    )
    q_mean = anchor(
        abs(values["vout_mean_nom"][0]) / 1200,
        (0, .002, .005, .01, .03, .1), (1, 1, .98, .9, .5, 0),
    )
    q_independence = anchor(
        values["iabc_duplicate_guard"][0],
        (0, .55, .7, .85, .95, 1), (1, 1, .95, .7, .25, 0),
    )
    Q = bottleneck(
        (q_thd, q_mean, q_independence, q_balance), (50, 15, 20, 15)
    )

    scenarios = scenario_map(sv)
    tracking = []
    gains = []
    gain_scores = []
    response_valid = values["iabc_rms_nom"][1]
    for scenario_id, command in zip(SCENARIOS, (6, 4)):
        row = scenarios.get(scenario_id, {})
        measured = band_value(row, f"iabc_rms_{scenario_id}")
        tracking.append(_current_q(measured[0], command))
        gain = (
            (measured[0] - values["iabc_rms_nom"][0])
            / ((command - 5) / math.sqrt(2))
        )
        gains.append(gain)
        gain_scores.append(_gain_q(gain))
        response_valid = response_valid and measured[1]
    if not response_valid:
        tracking = [0.0, 0.0]
        gain_scores = [0.0, 0.0]
    C = bottleneck((*tracking, *gain_scores), (30, 30, 20, 20))

    scenario_rows = []
    r_values = []
    metrics_valid = all(ok for _, ok in values.values()) and response_valid
    for scenario_id, command in zip(SCENARIOS, (6, 4)):
        row = scenarios.get(scenario_id, {})
        raw = {
            "current": band_value(row, f"iabc_rms_{scenario_id}"),
            "frequency": band_value(row, f"iabc_freq_{scenario_id}"),
            "balance": band_value(row, f"iabc_balance_{scenario_id}"),
            "voltage": band_value(row, f"vout_pp_{scenario_id}"),
            "levels": band_value(row, f"vout_levels_{scenario_id}"),
        }
        scores = (
            _current_q(raw["current"][0], command),
            _frequency_q(raw["frequency"][0]),
            anchor(raw["balance"][0], (0, .005, .02, .05, .1, .25),
                   (1, 1, .98, .9, .55, 0)),
            _voltage_q(raw["voltage"][0]),
            _levels_q(raw["levels"][0], 1),
        )
        valid = bool(row) and all(pair[1] for pair in raw.values())
        if not valid:
            scores = (0.0,) * 5
        one = bottleneck(scores, (40, 10, 15, 20, 15))
        metrics_valid = metrics_valid and valid
        r_values.append(one)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid, "score": one,
            "current_q": scores[0], "frequency_q": scores[1],
            "balance_q": scores[2], "voltage_q": scores[3],
            "levels_q": scores[4],
        })
    R = min(r_values, default=0.0)
    recovery = []
    d_values = []
    for scenario_id, row in (
        ("nominal", nom),
        ("reference_up", scenarios.get("reference_up", {})),
        ("reference_down", scenarios.get("reference_down", {})),
    ):
        value, valid = _cold(row)
        d_values.append(value)
        metrics_valid = metrics_valid and valid
        recovery.append({
            "scenario": scenario_id, "valid": valid, "score": value
        })
    D = min(d_values, default=0.0)
    metrics_valid = metrics_valid and boolean(
        sv.get("required_witnesses_ok")
    )
    groups = {"A": A, "Q": Q, "C": C, "R": R, "D": D}
    total = geometric(
        groups, {"A": .175, "Q": .105, "C": .21, "R": .21, "D": .30}
    )
    reasons = gate_reasons + ([] if metrics_valid else [
        "D027_REQUIRED_PHYSICAL_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "C", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "scores": [
                q_current, q_current_freq, q_voltage, q_voltage_freq,
                q_levels, q_sequence, q_balance
            ]},
            {"group": "Q", "scores": [
                q_thd, q_mean, q_independence, q_balance
            ]},
            {"group": "C", "endpoint_tracking_q": tracking,
             "response_gain": gains, "gain_q": gain_scores},
            {"group": "D", "recovery": recovery},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

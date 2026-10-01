"""D023 shunt active-power-filter dedicated pure-offline scorer."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, band_value, boolean, bottleneck, finite, geometric, make_result,
    nominal, required_scenario_ids, scenario_map, semantic_gate, suite,
    task_measurements, run_cli,
)

TASK_ID = "D023"
POLICY_ID = "simuverity-101-v1:d023:scoring"
ORACLE_ID = "D023.active_vsc_compensation_ownership"


def _cold_component(component):
    if not isinstance(component, dict) or not boolean(component.get("valid")):
        return 0.0, False
    tf = finite(component.get("settling_time_fraction"))
    iae = finite(component.get("normalized_iae"))
    if not all(math.isfinite(x) for x in (tf, iae)):
        return 0.0, False
    q_time = anchor(
        tf, (0, .10, .25, .50, .75, 1), (1, 1, .97, .90, .75, 0)
    )
    q_excess = anchor(
        iae, (0, .10, .25, .50, 1, 2, 4),
        (1, 1, .98, .93, .82, .55, 0),
    )
    return bottleneck((q_time, q_excess), (1, 1)), True


def _cold(row):
    measurement = task_measurements(row)
    cold = measurement.get("cold_start")
    if not isinstance(cold, dict) or not boolean(cold.get("valid")):
        return 0.0, False
    components = cold.get("components")
    if not isinstance(components, dict):
        return 0.0, False
    pairs = [
        _cold_component(components.get("dc_link_sum")),
        _cold_component(components.get("dc_link_balance")),
        _cold_component(components.get("compensation_current")),
    ]
    return bottleneck([pair[0] for pair in pairs], (1, 1, 1)), all(
        pair[1] for pair in pairs
    )


def score_evidence(evidence):
    sv = suite(evidence)
    expected = tuple(required_scenario_ids(evidence["task_spec"]))
    gate, gate_reasons = semantic_gate(
        evidence, expected, required_oracle_id=ORACLE_ID
    )
    nom = nominal(sv)
    nominal_ids = (
        "thd_improvement", "pcc_kcl", "vdc_sum", "vdc_balance",
        "source_thd", "source_balance", "vac_balance",
    )
    values = {band_id: band_value(nom, band_id) for band_id in nominal_ids}
    q_ratio = anchor(
        values["thd_improvement"][0], (0, .05, .1, .2, .4, .7),
        (1, 1, .98, .9, .5, 0),
    )
    q_kcl = anchor(
        abs(values["pcc_kcl"][0]), (0, .005, .02, .05, .1, .25, .45),
        (1, 1, .98, .9, .7, .25, 0),
    )
    q_vdc = anchor(
        abs(values["vdc_sum"][0] - 1160) / 1160,
        (0, .005, .01, .03, .08, .2, .45),
        (1, 1, .98, .92, .65, .25, 0),
    )
    q_balance = anchor(
        values["vdc_balance"][0], (0, .01, .025, .05, .1, .25),
        (1, 1, .98, .9, .55, 0),
    )
    A = bottleneck((q_ratio, q_kcl, q_vdc, q_balance), (35, 25, 25, 15))
    q_thd = anchor(
        values["source_thd"][0], (0, .03, .05, .08, .15, .3),
        (1, 1, .95, .8, .4, 0),
    )
    imbalance_x = (0, .01, .02, .05, .1, .25)
    imbalance_y = (1, 1, .97, .85, .5, 0)
    q_source_balance = anchor(
        values["source_balance"][0], imbalance_x, imbalance_y
    )
    q_voltage_balance = anchor(
        values["vac_balance"][0], imbalance_x, imbalance_y
    )
    Q = bottleneck(
        (q_thd, q_source_balance, q_voltage_balance), (55, 30, 15)
    )

    scenarios = scenario_map(sv)
    scenario_rows = []
    r_values = []
    metrics_valid = all(ok for _, ok in values.values())
    for scenario_id in expected:
        row = scenarios.get(scenario_id, {})
        raw = {
            "ratio": band_value(row, f"thd_ratio_{scenario_id}"),
            "kcl": band_value(row, f"kcl_{scenario_id}"),
            "vdc": band_value(row, f"vdc_sum_{scenario_id}"),
            "balance": band_value(row, f"vdc_balance_{scenario_id}"),
        }
        scores = (
            anchor(raw["ratio"][0], (0, .05, .1, .2, .4, .7),
                   (1, 1, .98, .9, .5, 0)),
            anchor(abs(raw["kcl"][0]), (0, .005, .02, .05, .1, .25, .45),
                   (1, 1, .98, .9, .7, .25, 0)),
            anchor(abs(raw["vdc"][0] - 1160) / 1160,
                   (0, .005, .01, .03, .08, .2, .45),
                   (1, 1, .98, .92, .65, .25, 0)),
            anchor(raw["balance"][0], (0, .01, .025, .05, .1, .25),
                   (1, 1, .98, .9, .55, 0)),
        )
        one = bottleneck(scores, (35, 25, 25, 15))
        valid = bool(row) and all(pair[1] for pair in raw.values())
        metrics_valid = metrics_valid and valid
        r_values.append(one)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid, "score": one,
            "thd_improvement_q": scores[0], "kcl_q": scores[1],
            "vdc_q": scores[2], "balance_q": scores[3],
        })
    R = min(r_values, default=0.0)
    recovery = []
    d_values = []
    for scenario_id, row in [("nominal", nom), *[
        (scenario_id, scenarios.get(scenario_id, {}))
        for scenario_id in expected
    ]]:
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
    groups = {"A": A, "Q": Q, "R": R, "D": D}
    total = geometric(
        groups, {"A": .34, "Q": .2125, "R": .2975, "D": .15}
    )
    reasons = gate_reasons + ([] if metrics_valid else [
        "D023_REQUIRED_PHYSICAL_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "scores": [q_ratio, q_kcl, q_vdc, q_balance]},
            {"group": "Q", "scores": [
                q_thd, q_source_balance, q_voltage_balance
            ]},
            {"group": "D", "recovery": recovery},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status="CURRENT",
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

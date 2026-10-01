"""D006 STATCOM dedicated pure-offline scorer."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, band_value, boolean, bottleneck, finite, geometric, make_result,
    nominal, required_scenario_ids, scenario_map, semantic_gate, suite,
    task_measurements, run_cli,
)

TASK_ID = "D006"
POLICY_ID = "simuverity-101-v1:d006:scoring"
ORACLE_ID = "D006.vdc_vsc_terminal_ownership"


def _cold_component(component):
    if not isinstance(component, dict) or not boolean(component.get("valid")):
        return 0.0, False
    tf = finite(component.get("settling_time_fraction"))
    iae = finite(component.get("normalized_iae"))
    if not all(math.isfinite(x) for x in (tf, iae)):
        return 0.0, False
    return (
        math.exp(-math.log(10) * min(max(tf, 0.0), 1.0))
        * math.exp(-(math.log(10) / .25) * max(iae, 0.0)),
        True,
    )


def _cold(row):
    measurement = task_measurements(row)
    cold = measurement.get("cold_start")
    if not isinstance(cold, dict) or not boolean(cold.get("valid")):
        return 0.0, False, {}
    components = cold.get("components")
    if not isinstance(components, dict):
        return 0.0, False, {}
    q_dc, ok_dc = _cold_component(components.get("dc_link"))
    q_current, ok_current = _cold_component(
        components.get("compensation_current")
    )
    return (
        bottleneck((q_dc, q_current), (1, 1)),
        ok_dc and ok_current,
        {"dc_link_q": q_dc, "compensation_current_q": q_current},
    )


def _vdc_q(value):
    return anchor(
        abs(value - 700) / 700,
        (0, .002, .005, .01, .025, .05, .15, .25),
        (1, 1, .98, .92, .65, .35, .05, 0),
    )


def _freq_q(value):
    return anchor(
        abs(value - 50), (0, .05, .2, .5, 1, 3, 5),
        (1, 1, .98, .9, .65, .2, 0),
    )


def _reactive_q(value):
    return anchor(
        abs(abs(value) - 90), (0, 1, 3, 8, 20, 45, 70),
        (1, 1, .98, .9, .65, .2, 0),
    )


def score_evidence(evidence):
    sv = suite(evidence)
    spec = evidence["task_spec"]
    expected = tuple(required_scenario_ids(spec))
    gate, gate_reasons = semantic_gate(
        evidence, expected, required_oracle_id=ORACLE_ID
    )
    nom = nominal(sv)
    nominal_ids = (
        "vdc_nom", "vac_freq", "icomp_freq", "icomp_phase",
        "vdc_ripple", "icomp_thd",
    )
    values = {band_id: band_value(nom, band_id) for band_id in nominal_ids}
    q_vdc = _vdc_q(values["vdc_nom"][0])
    q_freq = min(
        _freq_q(values["vac_freq"][0]), _freq_q(values["icomp_freq"][0])
    )
    q_reactive = _reactive_q(values["icomp_phase"][0])
    A = bottleneck((q_vdc, q_freq, q_reactive), (50, 20, 30))
    q_ripple = anchor(
        values["vdc_ripple"][0], (0, .002, .005, .01, .03, .08),
        (1, 1, .98, .9, .5, 0),
    )
    q_thd = anchor(
        values["icomp_thd"][0], (0, .03, .05, .08, .15, .25),
        (1, 1, .95, .75, .35, 0),
    )
    Q = bottleneck((q_ripple, q_thd), (35, 65))

    scenarios = scenario_map(sv)
    scenario_rows = []
    r_values = []
    metrics_valid = all(ok for _, ok in values.values())
    for scenario_id in expected:
        row = scenarios.get(scenario_id, {})
        vdc_value, vdc_valid = band_value(row, f"vdc_{scenario_id}")
        phase_value, phase_valid = band_value(row, f"phase_{scenario_id}")
        q1, q2 = _vdc_q(vdc_value), _reactive_q(phase_value)
        one = bottleneck((q1, q2), (65, 35))
        valid = bool(row) and vdc_valid and phase_valid
        metrics_valid = metrics_valid and valid
        r_values.append(one)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid, "score": one,
            "vdc_q": q1, "reactive_q": q2,
        })
    R = min(r_values, default=0.0)
    recovery = []
    d_values = []
    for scenario_id, row in [("nominal", nom), *[
        (scenario_id, scenarios.get(scenario_id, {}))
        for scenario_id in expected
    ]]:
        value, valid, detail = _cold(row)
        d_values.append(value)
        metrics_valid = metrics_valid and valid
        recovery.append({
            "scenario": scenario_id, "valid": valid, "score": value, **detail
        })
    D = min(d_values, default=0.0)
    metrics_valid = metrics_valid and boolean(
        sv.get("required_witnesses_ok")
    )
    groups = {"A": A, "Q": Q, "R": R, "D": D}
    total = geometric(groups, {"A": .32, "Q": .16, "R": .32, "D": .20})
    reasons = gate_reasons + ([] if metrics_valid else [
        "D006_REQUIRED_PHYSICAL_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "vdc": q_vdc, "frequency": q_freq,
             "reactive_orthogonality": q_reactive},
            {"group": "Q", "vdc_ripple": q_ripple,
             "compensation_current_thd": q_thd},
            {"group": "D", "recovery": recovery},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status="CURRENT",
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

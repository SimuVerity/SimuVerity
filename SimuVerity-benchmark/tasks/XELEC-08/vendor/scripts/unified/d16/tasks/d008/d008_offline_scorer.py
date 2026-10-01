"""D008 protected-curve and active-response pure-offline scorer."""
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, band_value, boolean, bottleneck, finite, geometric, make_result,
    nominal, required_scenario_ids, scenario_map, semantic_gate, suite,
    task_measurements, vector, witness_q, run_cli,
)

TASK_ID = "D008"
POLICY_ID = "simuverity-101-v1:d008:scoring"
POLICY_STATUS = "CURRENT"
ORACLE_ID = "D008.q_load_response_witness_group"
P_LOAD_SCENARIOS = ("p_load_up", "p_load_down")
P_LOAD_RESPONSE_MIN_FRACTION = .02


def _vdc_q(value):
    return anchor(
        abs(value - 399) / 399, (0, .002, .005, .01, .03, .08, .25),
        (1, 1, .98, .92, .65, .25, 0),
    )


def _freq_q(value):
    return anchor(
        abs(value - 50), (0, .05, .2, .5, 1.5, 4, 7),
        (1, 1, .98, .9, .55, .15, 0),
    )


def _phase_q(value):
    if not math.isfinite(value):
        return 0.0
    distance = min(
        abs((value - 90 + 180) % 360 - 180),
        abs((value + 90 + 180) % 360 - 180),
    )
    return anchor(
        distance, (0, 1, 3, 8, 20, 45, 85),
        (1, 1, .98, .9, .65, .25, 0),
    )


def _kcl_q(value):
    return anchor(
        abs(value), (0, .005, .02, .05, .10, .20, .40),
        (1, 1, .98, .9, .7, .3, 0),
    )


def _gain(value, base, direction):
    if not all(math.isfinite(x) for x in (value, base)) or base <= 0:
        return math.nan
    return direction * (value / base - 1) / .1


def _gain_q(value):
    if not math.isfinite(value) or value <= 0:
        return 0.0
    return anchor(
        abs(value - 1), (0, .1, .25, .5, 1, 2),
        (1, 1, .95, .8, .4, 0),
    )


def _cold_component(component):
    if not isinstance(component, dict) or not boolean(component.get("valid")):
        return 0.0, False
    tf = finite(component.get("settling_time_fraction"))
    iae = finite(component.get("normalized_iae"))
    if not all(math.isfinite(x) for x in (tf, iae)):
        return 0.0, False
    q_time = anchor(
        tf, (0, .10, .25, .50, .75, 1), (1, 1, .97, .90, .65, 0)
    )
    q_excess = anchor(
        iae, (0, .02, .05, .10, .25, .50, 1, 2),
        (1, 1, .98, .95, .88, .75, .40, 0),
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
    q_dc, ok_dc = _cold_component(components.get("dc_link"))
    q_current, ok_current = _cold_component(
        components.get("compensation_current")
    )
    return bottleneck((q_dc, q_current), (1, 1)), ok_dc and ok_current


def _thd_q(worst_thd):
    # Current anchor/value pairs are unchanged through the protected 12%
    # anchor. Only the low-quality interval is extended from 20% to 30%.
    return anchor(
        worst_thd, (0, .05, .08, .10, .12, .30),
        (1, 1, .80, .30, .05, 0),
    )


def _grid_quality(row):
    measurement = task_measurements(row)
    quality = measurement.get("grid_current_quality")
    if not isinstance(quality, dict) or not boolean(quality.get("valid")):
        return 0.0, 0.0, False, {}
    thd = vector(quality.get("thd"), 3)
    ranges = vector(quality.get("steady_rel_range"), 3)
    drifts = vector(quality.get("steady_rel_drift"), 3)
    valid = (
        boolean(quality.get("thd_valid"))
        and all(math.isfinite(x) for x in thd + ranges + drifts)
    )
    if not valid:
        return 0.0, 0.0, False, {}
    worst_thd = max(thd)
    thd_q = _thd_q(worst_thd)
    stationarity_phase = [
        anchor(
            max(ranges[index], drifts[index]),
            (0, .10, .15, .25, .50, 1, 2),
            (1, 1, .95, .85, .60, .20, 0),
        )
        for index in range(3)
    ]
    return thd_q, min(stationarity_phase), True, {
        "worst_phase_thd": worst_thd,
        "thd": thd,
        "stationarity_phase_q": stationarity_phase,
        "steady_declared": boolean(quality.get("steady")),
    }


def _active_grid_current_proxy(row):
    """Return a three-phase fundamental active-current proxy and validity."""
    quality = task_measurements(row).get("grid_current_quality")
    if not isinstance(quality, dict) or not boolean(quality.get("valid")):
        return math.nan, False
    currents = vector(quality.get("Igrid_fundamental_peak"), 3)
    displacement_pf_abs = finite(quality.get("displacement_pf_abs"))
    valid = (
        all(math.isfinite(value) and value >= 0 for value in currents)
        and math.isfinite(displacement_pf_abs)
        and 0 <= displacement_pf_abs <= 1
    )
    diagnostics_valid = quality.get("phase_a_diagnostics_valid")
    if diagnostics_valid is not None:
        valid = valid and boolean(diagnostics_valid)
    if not valid:
        return math.nan, False
    proxy = sum(currents) / 3 * displacement_pf_abs
    return proxy, math.isfinite(proxy) and proxy > 0


def _active_power_response(suite_value):
    scenarios = scenario_map(suite_value)
    nominal_proxy, nominal_valid = _active_grid_current_proxy(
        nominal(suite_value)
    )
    up_proxy, up_valid = _active_grid_current_proxy(
        scenarios.get("p_load_up", {})
    )
    down_proxy, down_valid = _active_grid_current_proxy(
        scenarios.get("p_load_down", {})
    )
    valid = nominal_valid and up_valid and down_valid
    if valid:
        up_fraction = up_proxy / nominal_proxy - 1
        down_fraction = 1 - down_proxy / nominal_proxy
    else:
        up_fraction = math.nan
        down_fraction = math.nan
    passed = valid and (
        up_fraction >= P_LOAD_RESPONSE_MIN_FRACTION
        and down_fraction >= P_LOAD_RESPONSE_MIN_FRACTION
    )
    return passed, valid, {
        "method": "mean_three_phase_Igrid_fundamental_peak_times_abs_displacement_pf",
        "minimum_fraction": P_LOAD_RESPONSE_MIN_FRACTION,
        "nominal_active_current_proxy": nominal_proxy,
        "p_load_up_active_current_proxy": up_proxy,
        "p_load_down_active_current_proxy": down_proxy,
        "p_load_up_fraction": up_fraction,
        "p_load_down_fraction": down_fraction,
        "valid": valid,
        "ok": passed,
    }


def _required_non_p_witnesses_ok(suite_value, expected):
    scenarios = scenario_map(suite_value)
    details = []
    all_valid = True
    for scenario_id in expected:
        if scenario_id in P_LOAD_SCENARIOS:
            continue
        row = scenarios.get(scenario_id, {})
        _, reports_ok = witness_q(row)
        valid = bool(row) and boolean(row.get("witness_ok")) and reports_ok
        all_valid = all_valid and valid
        details.append({"scenario": scenario_id, "valid": valid})
    return all_valid, details


def score_evidence(evidence):
    sv = suite(evidence)
    spec = evidence["task_spec"]
    expected = tuple(required_scenario_ids(spec))
    gate, gate_reasons = semantic_gate(
        evidence, expected, required_oracle_id=ORACLE_ID
    )
    nom = nominal(sv)
    nominal_ids = (
        "vdc_nom", "vpcc_freq", "reactive_phase", "pcc_kcl",
        "vdc_ripple", "icomp_balance", "iload_rms_diag", "icomp_rms_diag",
    )
    values = {band_id: band_value(nom, band_id) for band_id in nominal_ids}
    q_vdc = _vdc_q(values["vdc_nom"][0])
    q_freq = _freq_q(values["vpcc_freq"][0])
    q_phase = _phase_q(values["reactive_phase"][0])
    q_kcl = _kcl_q(values["pcc_kcl"][0])
    A = bottleneck((q_vdc, q_freq, q_phase, q_kcl), (40, 15, 20, 25))
    q_ripple = anchor(
        values["vdc_ripple"][0], (0, .004, .01, .02, .05, .10),
        (1, 1, .97, .85, .4, 0),
    )
    q_balance = anchor(
        values["icomp_balance"][0], (0, .01, .025, .05, .10, .30),
        (1, 1, .97, .85, .45, 0),
    )
    Q = bottleneck((q_ripple, q_balance), (55, 45))

    scenarios = scenario_map(sv)
    up = scenarios.get("q_load_up", {})
    down = scenarios.get("q_load_down", {})
    up_load = band_value(up, "iload_rms_q_up")
    down_load = band_value(down, "iload_rms_q_down")
    up_comp = band_value(up, "icomp_rms_q_up")
    down_comp = band_value(down, "icomp_rms_q_down")
    gains = (
        _gain(up_load[0], values["iload_rms_diag"][0], 1),
        _gain(down_load[0], values["iload_rms_diag"][0], -1),
        _gain(up_comp[0], values["icomp_rms_diag"][0], 1),
        _gain(down_comp[0], values["icomp_rms_diag"][0], -1),
    )
    gain_scores = [_gain_q(value) for value in gains]
    response_valid = all(pair[1] for pair in (
        up_load, down_load, up_comp, down_comp,
        values["iload_rms_diag"], values["icomp_rms_diag"],
    ))
    if not response_valid:
        gain_scores = [0.0] * 4
    C = bottleneck(gain_scores, (1, 1, 1, 1))

    scenario_rows = []
    base_r_values = []
    metrics_valid = all(ok for _, ok in values.values()) and response_valid
    all_rows = [("nominal", nom)] + [
        (scenario_id, scenarios.get(scenario_id, {}))
        for scenario_id in expected
    ]
    grid_thd_scores = []
    stationarity_scores = []
    recovery = []
    for scenario_id in expected:
        row = scenarios.get(scenario_id, {})
        ids = (
            f"vdc_{scenario_id}", f"phase_{scenario_id}",
            f"kcl_{scenario_id}",
        )
        raw = [band_value(row, band_id) for band_id in ids]
        q_values = (_vdc_q(raw[0][0]), _phase_q(raw[1][0]), _kcl_q(raw[2][0]))
        one = bottleneck(q_values, (45, 25, 30))
        valid = bool(row) and all(item[1] for item in raw)
        metrics_valid = metrics_valid and valid
        base_r_values.append(one)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid,
            "base_operating_point_q": one,
            "vdc_q": q_values[0], "reactive_q": q_values[1],
            "kcl_q": q_values[2],
        })
    for scenario_id, row in all_rows:
        cold_q, cold_valid = _cold(row)
        thd_q, stationarity_q, quality_valid, quality_detail = _grid_quality(row)
        metrics_valid = metrics_valid and cold_valid and quality_valid
        grid_thd_scores.append(thd_q)
        stationarity_scores.append(stationarity_q)
        recovery.append({
            "scenario": scenario_id, "cold_start_q": cold_q,
            "cold_start_valid": cold_valid,
            "stationarity_q": stationarity_q,
            "quality_valid": quality_valid, **quality_detail,
        })
    base_R = min(base_r_values, default=0.0)
    cross_thd = min(grid_thd_scores, default=0.0)
    R = bottleneck((base_R, cross_thd), (40, 60))
    base_D = min(
        (row["cold_start_q"] for row in recovery), default=0.0
    )
    cross_stationarity = min(stationarity_scores, default=0.0)
    D = min(base_D, cross_stationarity)
    non_p_witnesses_ok, non_p_witness_details = (
        _required_non_p_witnesses_ok(sv, expected)
    )
    p_response_ok, p_response_valid, p_response_detail = (
        _active_power_response(sv)
    )
    metrics_valid = (
        metrics_valid and non_p_witnesses_ok
        and p_response_valid and p_response_ok
    )
    groups = {"A": A, "Q": Q, "C": C, "R": R, "D": D}
    total = geometric(
        groups, {"A": .20, "Q": .10, "C": .20, "R": .30, "D": .20}
    )
    reasons = gate_reasons + ([] if metrics_valid else [
        "D008_REQUIRED_PHYSICAL_OR_GRID_QUALITY_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "C", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "scores": [q_vdc, q_freq, q_phase, q_kcl]},
            {"group": "Q", "vdc_ripple": q_ripple,
             "compensation_balance": q_balance},
            {"group": "C", "response_gain": list(gains),
             "response_q": gain_scores},
            {"group": "R", "base_q": base_R, "grid_thd_q": cross_thd,
             "active_power_response": p_response_detail,
             "non_p_required_witnesses_ok": non_p_witnesses_ok,
             "non_p_required_witnesses": non_p_witness_details},
            {"group": "D", "cold_start_q": base_D,
             "stationarity_q": cross_stationarity, "recovery": recovery},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

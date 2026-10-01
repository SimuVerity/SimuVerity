"""Current D014 unified-domain-weight scorer."""

from pathlib import Path
import importlib.util
import math
import sys


HERE = Path(__file__).resolve()
CORE_PATH = HERE.with_name("d014_scoring_core.py")
SPEC = importlib.util.spec_from_file_location("d014_scoring_core", CORE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load D014 numerical scoring helper")
BASE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BASE
SPEC.loader.exec_module(BASE)

TASK_ID = "D014"
POLICY_ID = "simuverity-101-v1:d014:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = BASE.SCENARIOS

RMS_X = (0, .15, .35, .70, 1.20, 2.22, 4.44)
RMS_Y = (1, 1, .95, .75, .30, .15, 0)
VIMB_X = (0, .10, .25, .50, 1, 2, 5)
VIMB_Y = (1, 1, .95, .75, .40, .10, 0)
THD_X = (0, 3, 5, 8, 12, 20)
THD_Y = (1, 1, .95, .75, .40, 0)
RIPPLE_X = (0, .5, 1.5, 3, 6, 10, 15)
RIPPLE_Y = (1, 1, .90, .75, .65, .30, 0)
ROBUSTNESS_X = (0, .2, .5, .75, 1, 1.5, 3)
ROBUSTNESS_Y = (1, 1, 1, .85, .45, .20, 0)


def score_evidence(evidence):
    sv = BASE.suite(evidence)
    gate, gate_reasons = BASE.semantic_gate(
        evidence, SCENARIOS, include_scenario_oracles=True
    )
    nom = BASE.task_measurements(BASE.nominal(sv))
    rms = BASE._row3(nom, "Vabc_rms")
    frequency = BASE._row3(nom, "Vabc_freq")
    vthd = BASE._row3(nom, "Vabc_thd")
    ithd = BASE._row3(nom, "Iabc_thd")

    rms_error_v = max(
        (abs(value - 222) for value in rms), default=math.nan
    )
    frequency_error_hz = max(
        (abs(value - 50) for value in frequency), default=math.nan
    )
    voltage_unbalance_pct = 100 * BASE.finite(nom.get("Vabc_imbalance"))
    voltage_thd_pct = 100 * max(vthd, default=math.nan)
    current_thd_pct = 100 * max(ithd, default=math.nan)
    dc_ripple_pct = 100 * BASE.finite(nom.get("Vdc_ripple_pp_frac"))
    duplicate_correlation = BASE.finite(nom.get("Vabc_duplicate_corr"))

    q_rms = BASE.anchor(rms_error_v, RMS_X, RMS_Y)
    q_frequency = BASE.anchor(
        frequency_error_hz,
        (0, .02, .1, .5, 1, 2),
        (1, 1, .95, .70, .30, 0),
    )
    q_vimb = BASE.anchor(voltage_unbalance_pct, VIMB_X, VIMB_Y)
    q_vthd = BASE.anchor(voltage_thd_pct, THD_X, THD_Y)
    q_ithd = BASE.anchor(current_thd_pct, THD_X, THD_Y)
    q_independence = BASE._duplicate_quality(duplicate_correlation)
    q_ripple = BASE.anchor(dc_ripple_pct, RIPPLE_X, RIPPLE_Y)

    A = BASE.weighted((q_rms, q_frequency, q_vimb), (.60, .10, .30))
    Q = BASE.weighted((q_vthd, q_ithd, q_independence), (.45, .35, .20))
    M = q_ripple

    scenarios = BASE.scenario_map(sv)
    nominal_a_rms = rms[0] if rms else math.nan
    robustness = []
    r_values = []
    for scenario_id in SCENARIOS:
        metrics = BASE.task_measurements(scenarios.get(scenario_id, {}))
        scenario_rms = BASE._row3(metrics, "Vabc_rms")
        valid = (
            BASE.boolean(metrics.get("Vabc_rms_valid"))
            and math.isfinite(nominal_a_rms)
            and nominal_a_rms > sys.float_info.epsilon
            and math.isfinite(scenario_rms[0])
        )
        change = (
            100 * abs(scenario_rms[0] - nominal_a_rms) / abs(nominal_a_rms)
            if valid else math.nan
        )
        quality = BASE.anchor(change, ROBUSTNESS_X, ROBUSTNESS_Y)
        r_values.append(quality)
        robustness.append({
            "scenario": scenario_id,
            "valid": valid,
            "A_phase_rms": scenario_rms[0],
            "relative_change_pct": change,
            "score": quality,
        })
    R = min(r_values, default=0.0)

    groups = {"A": A, "Q": Q, "M": M, "R": R}
    total = 100 * A ** .45 * Q ** .10 * M ** .10 * R ** .35
    return BASE.make_result(
        task_id=TASK_ID,
        policy_id=POLICY_ID,
        gate=gate,
        groups=groups,
        applicable=("A", "Q", "M", "R"),
        total_score=total,
        metrics=(
            {
                "group": "A",
                "rms_error_v": rms_error_v,
                "rms_q": q_rms,
                "frequency_error_hz": frequency_error_hz,
                "frequency_q": q_frequency,
                "voltage_unbalance_pct": voltage_unbalance_pct,
                "voltage_unbalance_q": q_vimb,
            },
            {
                "group": "Q",
                "voltage_thd_pct": voltage_thd_pct,
                "voltage_thd_q": q_vthd,
                "current_thd_pct": current_thd_pct,
                "current_thd_q": q_ithd,
                "three_phase_duplicate_correlation": duplicate_correlation,
                "three_phase_independence_q": q_independence,
            },
            {
                "group": "M",
                "dc_ripple_pct": dc_ripple_pct,
                "dc_ripple_q": q_ripple,
            },
        ),
        scenarios=robustness,
        failure_reasons=gate_reasons,
        # Invalid numerical atoms map to their own zero utility.
        score_inputs_valid=True,
        policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    BASE.run_cli(score_evidence, TASK_ID, __file__)

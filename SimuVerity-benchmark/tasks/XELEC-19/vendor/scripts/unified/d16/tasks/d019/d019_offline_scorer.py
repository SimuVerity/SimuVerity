"""D019 structure-compatible scorer with a protected THD tail."""
from collections.abc import Mapping
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    band_row, band_utility, bottleneck, geometric, make_result, nominal,
    oracle_pass, oracle_row, scenario_map, semantic_gate, suite, witness_q,
    run_cli,
)

TASK_ID = "D019"
POLICY_ID = "simuverity-101-v1:d019:scoring"
POLICY_STATUS = "CURRENT"
SCENARIOS = ("load_up", "load_down")
LEVEL_ORACLE = "D019.internal_multilevel_stage_level_count"
THD_TARGET = 0.03
THD_PASS_TOLERANCE = 0.04
THD_EXISTING_ZERO_TOLERANCE = 0.20
THD_ZERO_TOLERANCE = 0.50


def protected_thd_utility(row):
    """Apply only the policy's protected zero-tail extension, fail closed."""
    item = band_row(row, "vout_thd")
    if item is None or not isinstance(item.get("band_contract"), Mapping):
        return 0.0, False
    contract = item["band_contract"]
    expected = (
        contract.get("sided") == "lower",
        contract.get("target") == THD_TARGET,
        contract.get("tol_pass") == THD_PASS_TOLERANCE,
        contract.get("tol_zero") == THD_EXISTING_ZERO_TOLERANCE,
        contract.get("curve_p", 1) == 1,
    )
    if not all(expected):
        return 0.0, False
    adjusted_item = dict(item)
    adjusted_contract = dict(contract)
    adjusted_contract["tol_zero"] = THD_ZERO_TOLERANCE
    adjusted_item["band_contract"] = adjusted_contract
    return band_utility(
        {"band_measurements": [adjusted_item]}, "vout_thd"
    )


def score_evidence(evidence):
    sv = suite(evidence)
    nom = nominal(sv)
    gate, gate_reasons = semantic_gate(evidence, SCENARIOS)
    q_pp, v_pp = band_utility(nom, "vout_pp")
    q_freq, v_freq = band_utility(nom, "vout_freq")
    level_report = oracle_row(sv, LEVEL_ORACLE)
    q_level = float(oracle_pass(level_report))
    v_level = level_report is not None and all((
        bool(level_report.get("evaluated")),
        bool(level_report.get("valid")),
    ))
    A = bottleneck((q_pp, q_freq, q_level), (45, 25, 30))
    q_thd, v_thd = protected_thd_utility(nom)
    q_mean, v_mean = band_utility(nom, "vout_mean")
    Q = bottleneck((q_thd, q_mean), (70, 30))

    scenarios = scenario_map(sv)
    scenario_rows = []
    r_values = []
    metrics_valid = all((v_pp, v_freq, v_level, v_thd, v_mean))
    for scenario_id in SCENARIOS:
        row = scenarios.get(scenario_id, {})
        q1, ok1 = band_utility(row, f"vout_pp_{scenario_id}")
        q2, ok2 = band_utility(row, f"vout_freq_{scenario_id}")
        qw, okw = witness_q(row)
        one = bottleneck((q1, q2, qw), (50, 25, 25))
        valid = bool(row) and ok1 and ok2 and okw
        metrics_valid = metrics_valid and valid
        r_values.append(one)
        scenario_rows.append({
            "scenario": scenario_id, "valid": valid, "score": one,
            "voltage_retention": q1, "frequency": q2,
            "load_intervention": qw,
        })
    R = min(r_values, default=0.0)
    groups = {"A": A, "Q": Q, "R": R}
    total = geometric(groups, {"A": .45, "Q": .25, "R": .30})
    reasons = gate_reasons + ([] if metrics_valid else [
        "D019_REQUIRED_PHYSICAL_EVIDENCE_INCOMPLETE"
    ])
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "R"), total_score=total,
        metrics=(
            {"group": "A", "ids": ["phase_voltage_pp", "frequency",
             "internal_multilevel_stage"], "scores": [q_pp, q_freq, q_level]},
            {"group": "Q", "ids": ["voltage_thd", "dc_offset"],
             "scores": [q_thd, q_mean]},
        ),
        scenarios=scenario_rows, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status=POLICY_STATUS,
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

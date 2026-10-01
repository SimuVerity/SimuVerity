#!/usr/bin/env python3
"""Pure offline scorer for F90-XBATT-07 complete JSON evidence."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

STATE = ["log_bms_state", "log_charger_state", "log_inverter_state"]
COMMAND = [
    "log_cmd_PosCntctChgrCmd", "log_cmd_PreChrgRelayChgrCmd", "log_cmd_NegCntctChgrCmd",
    "log_cmd_PosCntctInvtrCmd", "log_cmd_PreChrgRelayInvtrCmd", "log_cmd_NegCntctInvtrCmd",
]
LIMIT = ["log_limit_DischargeCurrentLimit", "log_limit_ChargeCurrentLimit"]
EXTREMA = ["log_extrema_MinCellVolt", "log_extrema_MaxCellVolt", "log_extrema_MinCellTemp", "log_extrema_MaxCellTemp"]
FAULT_HEAD = ["log_critical_fault", "log_limp_mode"]
FAULT = [
    "log_fault_PackOverCurrFlt", "log_fault_CellHighTempFlt", "log_fault_CellLowTempFlt",
    "log_fault_VoltSensorFlt", "log_fault_CellOverVoltFlt", "log_fault_CellUnderVoltFlt",
    "log_fault_ChrgCntctFlt", "log_fault_InvtrCntctFlt",
]
ALL = STATE + COMMAND + LIMIT + EXTREMA + FAULT_HEAD + FAULT


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def values(item: dict[str, Any], name: str) -> list[float] | None:
    try:
        data = item["logs"][name]["data"]
        return [float(x) for x in data]
    except (KeyError, TypeError, ValueError):
        return None


def utility(actual: list[float] | None, expected: list[float] | None, discrete: bool) -> float:
    if actual is None or expected is None or len(actual) != len(expected) or not actual:
        return 0.0
    if not all(math.isfinite(x) for x in actual):
        return 0.0
    if discrete:
        return 100.0 * sum(abs(a - b) < 0.5 for a, b in zip(actual, expected)) / len(expected)
    scale = max(max(expected) - min(expected), max(abs(x) for x in expected), 1.0)
    rmse = math.sqrt(sum((a - b) ** 2 for a, b in zip(actual, expected)) / len(expected))
    return max(0.0, 100.0 * (1.0 - rmse / (0.08 * scale)))


def evidence_map(evidence: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(s.get("id")): s for s in evidence.get("scenarios", [])}


def compare_group(actual: dict[str, Any], reference: dict[str, Any], names: list[str]) -> tuple[float, list[float]]:
    am, rm = evidence_map(actual), evidence_map(reference)
    per_scenario: list[float] = []
    for sid, rs in rm.items():
        a = am.get(sid, {})
        channel_scores = [utility(values(a, n), values(rs, n), n in STATE + COMMAND + FAULT_HEAD + FAULT) for n in names]
        per_scenario.append(sum(channel_scores) / len(channel_scores))
    return (sum(per_scenario) / len(per_scenario) if per_scenario else 0.0), per_scenario


def separation(actual: dict[str, Any], reference: dict[str, Any], names: list[str], pairs: list[tuple[str, str]] | None = None) -> float:
    """Reward preservation of source-observed cross-scenario causal differences."""
    am, rm = evidence_map(actual), evidence_map(reference)
    ids = list(rm)
    pairs = pairs or [(ids[i], ids[j]) for i in range(len(ids)) for j in range(i + 1, len(ids))]
    scores: list[float] = []
    for left, right in pairs:
        if left not in am or right not in am or left not in rm or right not in rm:
            return 0.0
        for name in names:
            ra, rb = values(rm[left], name), values(rm[right], name)
            aa, ab = values(am[left], name), values(am[right], name)
            if ra is None or rb is None or len(ra) != len(rb):
                continue
            ref_delta = math.sqrt(sum((x - y) ** 2 for x, y in zip(ra, rb)) / len(ra))
            if ref_delta <= 1e-8:
                continue
            if aa is None or ab is None or len(aa) != len(ab):
                scores.append(0.0)
                continue
            act_delta = math.sqrt(sum((x - y) ** 2 for x, y in zip(aa, ab)) / len(aa))
            scores.append(100.0 * min(1.0, act_delta / ref_delta))
    return sum(scores) / len(scores) if scores else 100.0


def quality(actual: dict[str, Any]) -> float:
    scenarios = actual.get("scenarios", [])
    if len(scenarios) != 6:
        return 0.0
    checks = []
    for sc in scenarios:
        ok = bool(sc.get("valid", False))
        for name in ALL:
            try:
                t = [float(x) for x in sc["logs"][name]["time"]]
                d = [float(x) for x in sc["logs"][name]["data"]]
                ok = ok and len(t) == len(d) and len(t) >= 200 and t[0] <= 1e-9 and t[-1] >= 24.9
                ok = ok and all(math.isfinite(x) for x in t + d)
            except (KeyError, TypeError, ValueError):
                ok = False
        checks.append(ok)
    return 100.0 * sum(checks) / len(checks)


def geometric(groups: dict[str, float], weights: dict[str, float]) -> float:
    if any(groups[k] <= 0 for k in weights):
        return 0.0
    return math.exp(sum(weights[k] * math.log(groups[k] / 100.0) for k in weights)) * 100.0


def score(actual: dict[str, Any], reference: dict[str, Any]) -> dict[str, Any]:
    am, rm = evidence_map(actual), evidence_map(reference)
    gate = len(am) == len(rm) == 6 and all(bool(am[s].get("valid")) for s in rm if s in am)
    a, a_per = compare_group(actual, reference, STATE + COMMAND + LIMIT)
    m, m_per = compare_group(actual, reference, EXTREMA + LIMIT + FAULT_HEAD + FAULT)
    c, c_per = compare_group(actual, reference, STATE + COMMAND + FAULT_HEAD + FAULT)
    d, d_per = compare_group(actual, reference, STATE + COMMAND)
    all_mean, robust = compare_group(actual, reference, ALL)
    q = quality(actual)
    state_sep = separation(actual, reference, STATE)
    command_sep = separation(actual, reference, COMMAND)
    limit_sep = separation(actual, reference, LIMIT)
    extrema_sep = separation(actual, reference, EXTREMA)
    fault_sep = separation(actual, reference, FAULT_HEAD + FAULT)
    precharge_pair = separation(actual, reference, STATE + COMMAND + FAULT_HEAD + FAULT,
                                [("drive_precharge_ready", "drive_precharge_incomplete")])
    groups = {
        "A": min(a, state_sep, command_sep, limit_sep),
        "Q": q,
        "M": min(m, limit_sep, extrema_sep, fault_sep),
        "C": min(c, state_sep, command_sep, fault_sep, precharge_pair),
        "R": min(robust) if robust else 0.0,
        "D": min(d, state_sep, command_sep, precharge_pair),
    }
    weights = {"A": .25, "Q": .10, "M": .25, "C": .20, "R": .10, "D": .10}
    raw = geometric(groups, weights) if gate else 0.0
    return {
        "schema": "simuverity.f90-xbatt07-score.v1", "task_id": "F90-XBATT-07", "G": 1.0 if gate else 0.0,
        "groups": {k: round(v, 6) for k, v in groups.items()}, "raw_total": round(raw, 6),
        "normalized_from_admission_threshold": False, "scenario_similarity": [round(v, 6) for v in robust],
        "metric_detail": {"A_per_scenario": a_per, "M_per_scenario": m_per, "C_per_scenario": c_per, "D_per_scenario": d_per,
                          "all_mean": all_mean, "state_separation": state_sep, "command_separation": command_sep,
                          "limit_separation": limit_sep, "extrema_separation": extrema_sep,
                          "fault_separation": fault_sep, "precharge_pair_separation": precharge_pair},
        "failure_reasons": [] if gate else ["qualification gate failed: six complete finite scenarios are required"],
    }


def clone_log(dst: dict[str, Any], src: dict[str, Any], names: list[str]) -> None:
    for name in names:
        if name in src.get("logs", {}):
            dst.setdefault("logs", {})[name] = copy.deepcopy(src["logs"][name])


def shortcuts(reference: dict[str, Any]) -> dict[str, Any]:
    cases: dict[str, dict[str, Any]] = {}
    rmap = evidence_map(reference)
    nominal = rmap["nominal_standby"]
    x = copy.deepcopy(reference)
    for sc in x["scenarios"]:
        for n in FAULT_HEAD + FAULT:
            sc["logs"].pop(n, None)
    cases["missing_fault_state"] = score(x, reference)
    x = copy.deepcopy(reference)
    for sc in x["scenarios"]:
        clone_log(sc, nominal, LIMIT)
    cases["fixed_nominal_limits"] = score(x, reference)
    x = copy.deepcopy(reference)
    for sc in x["scenarios"]:
        clone_log(sc, nominal, ALL)
    cases["copied_nominal_outputs"] = score(x, reference)
    x = copy.deepcopy(reference)
    ready = rmap["drive_precharge_ready"]
    incomplete = evidence_map(x)["drive_precharge_incomplete"]
    clone_log(incomplete, ready, STATE + COMMAND + FAULT_HEAD + FAULT)
    cases["precharge_without_voltage_feedback"] = score(x, reference)
    x = copy.deepcopy(reference)
    for sc in x["scenarios"]:
        clone_log(sc, nominal, COMMAND)
    cases["commands_disconnected_from_state"] = score(x, reference)
    x = copy.deepcopy(reference)
    for sc in x["scenarios"]:
        clone_log(sc, nominal, EXTREMA)
    cases["reported_extrema_not_from_cell_vectors"] = score(x, reference)
    return {"pass": all(v["raw_total"] < 85.0 for v in cases.values()),
            "maximum_shortcut_score": max(v["raw_total"] for v in cases.values()),
            "case_scores": {k: v["raw_total"] for k, v in cases.items()}}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--shortcut-sanity", action="store_true")
    args = parser.parse_args()
    actual = load(args.evidence)
    reference = load(args.reference or args.evidence)
    result = shortcuts(reference) if args.shortcut_sanity else score(actual, reference)
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()

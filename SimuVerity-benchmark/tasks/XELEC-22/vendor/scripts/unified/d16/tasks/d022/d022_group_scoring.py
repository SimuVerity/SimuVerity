"""D022 ELC dedicated pure-offline group scorer."""
from bisect import bisect_right
from pathlib import Path
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "shared"))
from d16_offline_common import (  # noqa: E402
    anchor, band_utilities, boolean, bottleneck, finite, make_result,
    nominal, scenario_map, semantic_gate, suite, task_measurements, vector,
    weighted, witness_row, worst_anchor, run_cli,
)

TASK_ID = "D022"
POLICY_ID = "simuverity-101-v1:d022:scoring"
SCENARIOS = (
    "light_load", "heavy_load", "private_light_load", "private_heavy_load"
)


def _row3(metrics, field):
    return vector(metrics.get(field), 3)


def _sequence_q(metrics, purity_field, phase_field):
    q_purity = anchor(
        100 * finite(metrics.get(purity_field)),
        (0, .2, .5, 1, 2, 5, 15), (1, 1, .98, .95, .85, .45, 0),
    )
    q_phase = anchor(
        finite(metrics.get(phase_field)),
        (0, .2, .5, 1, 2, 5, 15), (1, 1, .98, .95, .85, .4, 0),
    )
    return bottleneck((q_purity, q_phase), (60, 40))


def _measurement_quality(metrics, include_frequency):
    q_frequency = worst_anchor(
        [abs(value - 50) for value in _row3(metrics, "Vabc_freq")],
        (0, .05, .2, .5, 1, 3), (1, 1, .95, .75, .3, 0),
    )
    q_vthd = worst_anchor(
        [100 * value for value in _row3(metrics, "Vabc_thd")],
        (0, 3, 5, 8, 12, 25), (1, 1, .95, .75, .35, 0),
    )
    q_ithd = worst_anchor(
        [100 * value for value in _row3(metrics, "Iabc_thd")],
        (0, 5, 8, 12, 20, 40), (1, 1, .95, .75, .35, 0),
    )
    q_vimb = anchor(
        100 * finite(metrics.get("Vabc_imbalance")),
        (0, .2, .5, 1, 2, 8), (1, 1, .95, .8, .45, 0),
    )
    q_iimb = anchor(
        100 * finite(metrics.get("Iabc_imbalance")),
        (0, .5, 1, 2, 5, 15), (1, 1, .95, .8, .4, 0),
    )
    q_vseq = _sequence_q(
        metrics, "Vabc_sequence_minor_frac", "Vabc_phase_step_error_deg"
    )
    q_iseq = _sequence_q(
        metrics, "Iabc_sequence_minor_frac", "Iabc_phase_step_error_deg"
    )
    q_order = float(boolean(metrics.get("VI_sequence_consistent")))
    q_sequence = bottleneck((q_vseq, q_iseq, q_order), (40, 40, 20))
    q_vdc_ripple = anchor(
        100 * finite(metrics.get("Vdc_ripple_pp_frac")),
        (0, .2, .5, 1, 2, 8), (1, 1, .95, .85, .6, 0),
    )
    q_speed_ripple = anchor(
        100 * finite(metrics.get("Speed_ripple_pp_frac")),
        (0, .02, .05, .1, .3, 1), (1, 1, .95, .8, .4, 0),
    )
    q_source_ripple = anchor(
        100 * finite(metrics.get("Psource_cycle_mean_ripple_pp_frac")),
        (0, .05, .2, .5, 1, 3), (1, 1, .95, .8, .4, 0),
    )
    if include_frequency:
        ac_values = (
            q_frequency, q_vthd, q_ithd, q_vimb, q_iimb, q_sequence
        )
        ac_weights = (12, 20, 20, 12, 12, 24)
    else:
        ac_values = (q_vthd, q_ithd, q_vimb, q_iimb, q_sequence)
        ac_weights = (22, 22, 14, 14, 28)
    ac_quality = bottleneck(ac_values, ac_weights)
    ripple_values = (q_vdc_ripple, q_speed_ripple, q_source_ripple)
    ripple_quality = weighted(ripple_values, (40, 25, 35))
    total = weighted((ac_quality, ripple_quality), (60, 40))
    return total, {
        "frequency_q": q_frequency, "voltage_thd_q": q_vthd,
        "current_thd_q": q_ithd, "voltage_imbalance_q": q_vimb,
        "current_imbalance_q": q_iimb, "voltage_sequence_q": q_vseq,
        "current_sequence_q": q_iseq, "sequence_order_q": q_order,
        "sequence_q": q_sequence, "dc_ripple_q": q_vdc_ripple,
        "speed_ripple_q": q_speed_ripple,
        "source_power_ripple_q": q_source_ripple,
        "ac_core_q": ac_quality, "ripple_q": ripple_quality,
    }


def _control_ids(scenario_id):
    return {
        "light_load": (
            "lighter_load_reduces_user_power",
            "ballast_absorbs_more_under_light_load",
            "generator_power_stays_regulated_light", .10,
        ),
        "heavy_load": (
            "heavier_load_increases_user_power",
            "ballast_absorbs_less_under_heavy_load",
            "generator_power_stays_regulated_heavy", .10,
        ),
        "private_light_load": (
            "private_lighter_load_reduces_user_power",
            "private_ballast_absorbs_more_under_light_load",
            "private_generator_power_stays_regulated_light", .064,
        ),
        "private_heavy_load": (
            "private_heavier_load_increases_user_power",
            "private_ballast_absorbs_less_under_heavy_load",
            "private_generator_power_stays_regulated_heavy", .063,
        ),
    }.get(scenario_id, ("", "", "", math.nan))


def _control_scenario(row, scenario_id):
    load_id, ballast_id, source_id, input_delta = _control_ids(scenario_id)
    load = witness_row(row, load_id)
    ballast = witness_row(row, ballast_id)
    source = witness_row(row, source_id)
    valid = (
        load["found"] and ballast["found"] and source["found"]
        and math.isfinite(input_delta) and input_delta > 0
    )
    load_gain = load["observed"] / max(input_delta, sys.float_info.epsilon)
    ballast_gain = ballast["observed"] / max(
        input_delta, sys.float_info.epsilon
    )
    q_load = anchor(
        load_gain, (0, .10, .25, .35, .60), (0, .2, .7, 1, 1)
    )
    q_ballast = anchor(
        ballast_gain, (0, .10, .25, .35, .60), (0, .2, .7, 1, 1)
    )
    delta_load = load["scenario_value"] - load["nominal_value"]
    delta_dump = ballast["scenario_value"] - ballast["nominal_value"]
    delta_source = source["scenario_value"] - source["nominal_value"]
    scale = max(
        abs(delta_load), .01 * abs(load["nominal_value"]),
        sys.float_info.epsilon,
    )
    closure_error = abs(delta_dump - delta_load) / scale
    source_increment_error = abs(delta_source) / scale
    q_delta_direction = float(
        all(math.isfinite(value) for value in (delta_load, delta_dump))
        and abs(delta_load) > sys.float_info.epsilon
        and abs(delta_dump) > sys.float_info.epsilon
        and delta_load * delta_dump > 0
    )
    dump_export = max(ballast["scenario_value"], 0) / max(
        abs(source["nominal_value"]), sys.float_info.epsilon
    )
    q_non_generating = anchor(
        dump_export, (0, .01, .03, .10), (1, 1, .7, 0)
    )
    q_direction = min(q_load, q_ballast, q_delta_direction, q_non_generating)
    q_source = anchor(
        100 * abs(source["observed"] - 1),
        (0, .1, .5, 1, 2, 5), (1, 1, .95, .8, .4, 0),
    )
    eta = min(max(1 - source_increment_error, 0), 1)
    q_compensation = anchor(
        eta, (0, .25, .5, .75, .9, .97, 1),
        (0, .1, .35, .65, .85, .97, 1),
    )
    valid = valid and all(math.isfinite(value) for value in (
        delta_load, delta_dump, delta_source,
        closure_error, source_increment_error,
    ))
    if not valid:
        q_direction = q_source = q_compensation = eta = 0.0
    quality = bottleneck(
        (q_direction, q_compensation, q_source), (15, 60, 25)
    )
    return quality, valid, {
        "scenario": scenario_id, "load_witness": load_id,
        "ballast_witness": ballast_id, "source_witness": source_id,
        "input_delta_fraction": input_delta,
        "load_response_fraction": load["observed"],
        "ballast_response_fraction": ballast["observed"],
        "source_ratio": source["observed"],
        "load_normalized_gain": load_gain,
        "ballast_normalized_gain": ballast_gain,
        "delta_Pload": delta_load, "delta_Pdump": delta_dump,
        "delta_Psource": delta_source, "increment_scale": scale,
        "closure_error_frac": closure_error,
        "source_increment_error_frac": source_increment_error,
        "compensation_eta": eta, "dump_export_fraction": dump_export,
        "direction_q": q_direction,
        "non_generating_ballast_q": q_non_generating,
        "compensation_q": q_compensation,
        "source_absolute_q": q_source,
    }


def _dose_response(control_rows):
    by_id = {row["scenario"]: row for row in control_rows}
    items = []
    valid = True
    for endpoint_id, private_id in (
        ("light_load", "private_light_load"),
        ("heavy_load", "private_heavy_load"),
    ):
        endpoint = by_id.get(endpoint_id)
        private = by_id.get(private_id)
        valid = valid and bool(endpoint) and bool(private)
        if not endpoint or not private:
            continue
        for signal, field in (("load", "delta_Pload"), ("dump", "delta_Pdump")):
            endpoint_delta = abs(finite(endpoint.get(field)))
            private_delta = abs(finite(private.get(field)))
            endpoint_input = finite(endpoint.get("input_delta_fraction"))
            private_input = finite(private.get("input_delta_fraction"))
            one_valid = (
                all(math.isfinite(value) for value in (
                    endpoint_delta, private_delta, endpoint_input, private_input
                ))
                and endpoint_delta > 0 and private_delta > 0
                and endpoint_input > 0 and private_input > 0
            )
            valid = valid and one_valid
            if one_valid:
                margin = (endpoint_delta - private_delta) / endpoint_delta
                slope_endpoint = endpoint_delta / endpoint_input
                slope_private = private_delta / private_input
                mismatch = abs(slope_endpoint - slope_private) / max(
                    slope_endpoint, slope_private, sys.float_info.epsilon
                )
                q_order = anchor(
                    margin, (0, .05, .15, .25, .35),
                    (0, .2, .6, .9, 1),
                )
                q_slope = anchor(
                    mismatch, (0, .05, .10, .20, .35, .75),
                    (1, 1, .95, .8, .4, 0),
                )
                quality = bottleneck((q_order, q_slope), (40, 60))
            else:
                margin = mismatch = math.nan
                q_order = q_slope = quality = 0.0
            items.append({
                "direction": endpoint_id, "signal": signal,
                "endpoint_delta": endpoint_delta, "private_delta": private_delta,
                "endpoint_input_delta": endpoint_input,
                "private_input_delta": private_input,
                "endpoint_margin_frac": margin,
                "normalized_slope_mismatch_frac": mismatch,
                "order_q": q_order, "slope_q": q_slope, "score": quality,
            })
    valid = valid and len(items) == 4
    return min((item["score"] for item in items), default=0.0), valid, items


def _control_group(control_rows):
    valid = len(control_rows) == 4 and all(row["valid"] for row in control_rows)
    direction = min(
        (row["detail"]["direction_q"] for row in control_rows), default=0.0
    )
    compensation = min(
        (row["detail"]["compensation_q"] for row in control_rows), default=0.0
    )
    source = min(
        (row["detail"]["source_absolute_q"] for row in control_rows),
        default=0.0,
    )
    eta = min(
        (row["detail"]["compensation_eta"] for row in control_rows),
        default=0.0,
    )
    dose, dose_valid, dose_items = _dose_response([
        {"scenario": row["scenario"], **row["detail"]} for row in control_rows
    ])
    valid = valid and dose_valid
    quality = bottleneck(
        (direction, compensation, source, dose), (15, 45, 25, 15)
    ) if valid else 0.0
    return quality, valid, {
        "direction_q": direction, "compensation_q": compensation,
        "source_regulation_q": source, "dose_response_q": dose,
        "dose_response": dose_items, "min_compensation_eta": eta,
    }


def _scenario_prefix(scenario_id):
    return {
        "light_load": "light_load",
        "heavy_load": "heavy_load",
        "private_light_load": "private_light_load",
        "private_heavy_load": "private_heavy_load",
    }.get(scenario_id, "unknown")


def _robust_state(row, metrics, scenario_id):
    prefix = _scenario_prefix(scenario_id)
    band_ids = (
        f"balance_{prefix}", f"speed_{prefix}", f"vdc_{prefix}"
    )
    state_scores, state_valid = band_utilities(row, band_ids)
    quality, quality_detail = _measurement_quality(metrics, True)
    valid = all(state_valid) and boolean(metrics.get("valid"))
    if not valid:
        quality = 0.0
    total = bottleneck((*state_scores, quality), (35, 20, 20, 25))
    return total, valid, {
        "band_ids": list(band_ids), "state_q": state_scores,
        "quality_q": quality, "quality": quality_detail,
    }


def _trajectory(metrics):
    value = metrics.get("power_cycle_trajectory")
    if not isinstance(value, dict) or not boolean(value.get("valid")):
        return [], [], False
    time = vector(value.get("cycle_end_time"))
    source = vector(value.get("Psource_mean"))
    load = vector(value.get("Pload_mean"))
    dump = vector(value.get("Pdump_mean"))
    valid = (
        len(time) >= 10
        and len(source) == len(load) == len(dump) == len(time)
        and all(math.isfinite(item) for item in time + source + load + dump)
        and all(time[index + 1] > time[index] for index in range(len(time) - 1))
    )
    return time, list(zip(source, load, dump)), valid


def _interp_rows(source_time, source_rows, target_time):
    result = []
    for target in target_time:
        if target < source_time[0] - 1e-9 or target > source_time[-1] + 1e-9:
            return [], False
        if target <= source_time[0]:
            result.append(list(source_rows[0]))
            continue
        if target >= source_time[-1]:
            result.append(list(source_rows[-1]))
            continue
        index = bisect_right(source_time, target) - 1
        lo, hi = source_time[index], source_time[index + 1]
        fraction = (target - lo) / (hi - lo)
        result.append([
            source_rows[index][column] + fraction * (
                source_rows[index + 1][column] - source_rows[index][column]
            )
            for column in range(3)
        ])
    return result, True


def _dynamic_scenario(nominal_metrics, scenario_metrics, scenario_id):
    nominal_time, nominal_rows, nominal_valid = _trajectory(nominal_metrics)
    scenario_time, scenario_rows, scenario_valid = _trajectory(scenario_metrics)
    base = {
        "scenario": scenario_id, "valid": False, "score": 0.0,
        "detail": "TRAJECTORY_INVALID", "settling_time_s": math.nan,
        "terminal_delta_power": [math.nan] * 3,
        "terminal_load_scale": math.nan,
        "terminal_compensation_eta": math.nan,
        "normalized_iae": math.nan,
    }
    if not (nominal_valid and scenario_valid):
        return base
    low = max(nominal_time[0], scenario_time[0])
    high = min(nominal_time[-1], scenario_time[-1])
    selected = [
        index for index, value in enumerate(nominal_time)
        if value >= low - 1e-9 and value <= high + 1e-9
    ]
    time = [nominal_time[index] for index in selected]
    nominal_selected = [nominal_rows[index] for index in selected]
    scenario_selected, interpolation_valid = _interp_rows(
        scenario_time, scenario_rows, time
    )
    if len(time) < 10 or not interpolation_valid:
        return base
    delta = [
        [
            scenario_selected[index][column]
            - nominal_selected[index][column]
            for column in range(3)
        ]
        for index in range(len(time))
    ]
    terminal_cycles = min(5, len(delta))
    terminal = [
        sum(row[column] for row in delta[-terminal_cycles:]) / terminal_cycles
        for column in range(3)
    ]
    scale = abs(terminal[1])
    nominal_load = abs(sum(
        row[1] for row in nominal_selected[-terminal_cycles:]
    ) / terminal_cycles)
    if not math.isfinite(scale) or scale <= max(
        1e-6 * nominal_load, sys.float_info.epsilon
    ):
        base["detail"] = "TERMINAL_LOAD_DELTA_TOO_SMALL"
        return base
    error = [
        max(abs(row[column] - terminal[column]) for column in range(3)) / scale
        for row in delta
    ]
    settle_index = next((
        index for index in range(len(error))
        if all(value <= .10 for value in error[index:])
    ), None)
    tau = time[settle_index] if settle_index is not None else time[-1]
    quality = anchor(
        tau, (0, .25, .5, 1, 1.5, 2, 2.5, 3),
        (1, 1, .95, .8, .6, .4, .2, 0),
    )
    if settle_index is None:
        quality = 0.0
    return {
        "scenario": scenario_id, "valid": True, "score": quality,
        "detail": "OK", "settling_time_s": tau,
        "terminal_delta_power": terminal, "terminal_load_scale": scale,
        "terminal_compensation_eta": 1 - abs(terminal[0]) / scale,
        "normalized_iae": sum(min(value, 5) for value in error) / len(error),
    }


def score_evidence(evidence):
    sv = suite(evidence)
    gate, gate_reasons = semantic_gate(evidence, SCENARIOS)
    nom_row = nominal(sv)
    nom = task_measurements(nom_row)
    accuracy_ids = ("power_balance", "speed", "vdc")
    accuracy_scores, accuracy_valid = band_utilities(nom_row, accuracy_ids)
    q_frequency = worst_anchor(
        [abs(value - 50) for value in _row3(nom, "Vabc_freq")],
        (0, .05, .2, .5, 1, 3), (1, 1, .95, .75, .3, 0),
    )
    A = bottleneck((*accuracy_scores, q_frequency), (40, 25, 20, 15))
    Q, quality_detail = _measurement_quality(nom, False)

    scenarios = scenario_map(sv)
    control_rows = []
    robustness_rows = []
    scenario_metrics = []
    scenario_metrics_valid = True
    for scenario_id in SCENARIOS:
        row = scenarios.get(scenario_id, {})
        metrics = task_measurements(row)
        scenario_metrics.append(metrics)
        control_q, control_valid, control_detail = _control_scenario(
            row, scenario_id
        )
        robust_q, robust_valid, robust_detail = _robust_state(
            row, metrics, scenario_id
        )
        control_rows.append({
            "scenario": scenario_id, "valid": bool(row) and control_valid,
            "score": control_q, "detail": control_detail,
        })
        robustness_rows.append({
            "scenario": scenario_id, "valid": bool(row) and robust_valid,
            "score": robust_q, "detail": robust_detail,
        })
        scenario_metrics_valid = (
            scenario_metrics_valid and bool(row)
            and boolean(metrics.get("valid"))
            and control_valid and robust_valid
        )
    C, control_valid, control_summary = _control_group(control_rows)
    R = min((row["score"] for row in robustness_rows), default=0.0)
    dynamic_rows = [
        _dynamic_scenario(nom, metrics, scenario_id)
        for scenario_id, metrics in zip(SCENARIOS, scenario_metrics)
    ]
    dynamic_valid = all(row["valid"] for row in dynamic_rows)
    D = min((row["score"] for row in dynamic_rows), default=0.0)
    metrics_valid = (
        boolean(nom.get("valid")) and all(accuracy_valid)
        and scenario_metrics_valid and control_valid and dynamic_valid
    )
    groups = {"A": A, "Q": Q, "C": C, "R": R, "D": D}
    unconstrained = (
        100
        * A ** (14 / 85)
        * Q ** (21 / 170)
        * C ** (7 / 34)
        * R ** (7 / 34)
        * D ** .30
    )
    total = unconstrained
    reasons = gate_reasons + ([] if metrics_valid else [
        "D022_REQUIRED_PHYSICAL_CONTROL_OR_DYNAMIC_EVIDENCE_INCOMPLETE"
    ])
    scenario_output = []
    for index, scenario_id in enumerate(SCENARIOS):
        scenario_output.append({
            "scenario": scenario_id,
            "valid": (
                control_rows[index]["valid"]
                and robustness_rows[index]["valid"]
                and dynamic_rows[index]["valid"]
            ),
            "control_q": control_rows[index]["score"],
            "control": control_rows[index]["detail"],
            "robustness_q": robustness_rows[index]["score"],
            "robustness": robustness_rows[index]["detail"],
            "dynamic_q": dynamic_rows[index]["score"],
            "dynamic": dynamic_rows[index],
        })
    return make_result(
        task_id=TASK_ID, policy_id=POLICY_ID, gate=gate, groups=groups,
        applicable=("A", "Q", "C", "R", "D"), total_score=total,
        metrics=(
            {"group": "A", "ids": [*accuracy_ids, "three_phase_frequency"],
             "scores": [*accuracy_scores, q_frequency]},
            {"group": "Q", **quality_detail},
            {"group": "C", **control_summary},
             {"group": "TOTAL_SCORE", "unconstrained_score": unconstrained},
        ),
        scenarios=scenario_output, failure_reasons=reasons,
        score_inputs_valid=metrics_valid, policy_status="CURRENT",
    )


if __name__ == "__main__":
    run_cli(score_evidence, TASK_ID, __file__)

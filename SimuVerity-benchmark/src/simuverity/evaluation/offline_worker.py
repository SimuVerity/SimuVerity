from __future__ import annotations

import argparse
import importlib.util
import json
import os
import socket
import subprocess
import urllib.request
import http.client
import copy
from pathlib import Path
from typing import Any, Mapping


def _blocked(*_args, **_kwargs):
    raise RuntimeError("Offline scorers may not start child processes, MATLAB, MCP, simulations, or network I/O")


def _deny_child_processes() -> None:
    subprocess.Popen = _blocked  # type: ignore[assignment]
    subprocess.run = _blocked  # type: ignore[assignment]
    subprocess.call = _blocked  # type: ignore[assignment]
    subprocess.check_call = _blocked  # type: ignore[assignment]
    subprocess.check_output = _blocked  # type: ignore[assignment]
    os.system = _blocked  # type: ignore[assignment]
    for name in tuple(dir(os)):
        if name.startswith("spawn"):
            setattr(os, name, _blocked)


def _deny_network() -> None:
    socket.socket = _blocked  # type: ignore[assignment]
    socket.create_connection = _blocked  # type: ignore[assignment]
    socket.getaddrinfo = _blocked  # type: ignore[assignment]
    socket.gethostbyname = _blocked  # type: ignore[assignment]
    socket.gethostbyname_ex = _blocked  # type: ignore[assignment]
    urllib.request.urlopen = _blocked  # type: ignore[assignment]
    http.client.HTTPConnection.connect = _blocked  # type: ignore[assignment]
    http.client.HTTPSConnection.connect = _blocked  # type: ignore[assignment]


def _validate_evidence_sidecars(context: Any) -> None:
    if not isinstance(context, Mapping) or "evidence_sidecars" not in context:
        return
    rows = context.get("evidence_sidecars")
    if not isinstance(rows, Mapping) or not rows:
        raise RuntimeError("evidence_sidecars must be a non-empty mapping")
    for role, item in rows.items():
        if not isinstance(role, str) or not isinstance(item, Mapping):
            raise RuntimeError("evidence sidecar binding is invalid")
        path = Path(str(item.get("path", "")))
        expected_size = item.get("size_bytes")
        if (
            not path.is_file()
            or not isinstance(expected_size, int)
            or isinstance(expected_size, bool)
            or path.stat().st_size != expected_size
        ):
            raise RuntimeError(f"evidence sidecar binding mismatch: {role}")
    structure_path = context.get("structure_audit_path")
    if structure_path:
        structure = rows.get("structure_audit")
        if not isinstance(structure, Mapping) or Path(str(structure.get("path", ""))).resolve() != Path(str(structure_path)).resolve():
            raise RuntimeError("structure_audit_path is not the declared structure sidecar")


def _validate_evidence_artifacts(context: Any) -> None:
    if not isinstance(context, Mapping) or "evidence_artifacts" not in context:
        return
    rows = context.get("evidence_artifacts")
    if not isinstance(rows, Mapping) or not rows:
        raise RuntimeError("evidence_artifacts must be a non-empty mapping")
    for relative, item in rows.items():
        if not isinstance(relative, str) or not isinstance(item, Mapping):
            raise RuntimeError("evidence artifact binding is invalid")
        path = Path(str(item.get("path", "")))
        expected_size = item.get("size_bytes")
        if (
            not path.is_file()
            or not isinstance(expected_size, int)
            or isinstance(expected_size, bool)
            or path.stat().st_size != expected_size
        ):
            raise RuntimeError(f"evidence artifact binding mismatch: {relative}")


def _canonicalize_evidence_artifact_paths(evidence: Any, context: Any) -> Any:
    """Route stale producer paths only to identically named evidence artifacts."""
    if not isinstance(evidence, Mapping) or not isinstance(context, Mapping):
        return evidence
    raw = evidence.get("raw_artifact")
    rows = context.get("evidence_artifacts")
    if not isinstance(raw, Mapping) or not isinstance(rows, Mapping):
        return evidence
    declared = raw.get("path")
    if not isinstance(declared, str) or not declared or Path(declared).is_file():
        return evidence
    basename = Path(declared.replace("\\", "/")).name
    matches = [
        item
        for relative, item in rows.items()
        if isinstance(relative, str)
        and Path(relative.replace("\\", "/")).name == basename
        and isinstance(item, Mapping)
    ]
    if len(matches) != 1:
        return evidence
    routed = copy.deepcopy(dict(evidence))
    routed["raw_artifact"] = dict(raw)
    routed["raw_artifact"]["path"] = str(matches[0]["path"])
    return routed


def _load_entrypoint(path: Path, name: str):
    spec = importlib.util.spec_from_file_location("simuverity_task_scorer", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load scorer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    entrypoint = getattr(module, name, None)
    if not callable(entrypoint):
        raise RuntimeError(f"Scorer entrypoint is not callable: {name}")
    return entrypoint


def _coerce_score_result(value: Any) -> dict[str, Any]:
    """Normalize the small set of native scorer return conventions.

    Some final scorers expose their pure computation as
    ``(groups, total, reasons, diagnostics)`` and reserve their JSON mapping
    for the file-oriented CLI.  Keeping that computation in-process avoids
    changing the current scorer while still presenting one public interface.
    """

    if isinstance(value, Mapping):
        return dict(value)
    if isinstance(value, (tuple, list)) and len(value) >= 2:
        native_groups, native_total = value[0], value[1]
        if isinstance(native_groups, Mapping) and isinstance(native_total, (int, float)) and not isinstance(native_total, bool):
            result: dict[str, Any] = {
                "groups": dict(native_groups),
                "total": native_total,
            }
            if len(value) >= 3 and isinstance(value[2], (tuple, list)):
                result["failure_reasons"] = list(value[2])
            if len(value) >= 4:
                result["diagnostics"] = value[3]
            result["native_return_convention"] = "groups_total_reasons_diagnostics_tuple"
            return result
    raise RuntimeError("score() must return a mapping or a groups/total tuple")


def _validate(value: Any, evidence: Any | None = None) -> dict[str, Any]:
    result = _coerce_score_result(value)
    total = result.get("total")
    if total is None:
        total = result.get("total_score")
    if total is None:
        total = result.get("score")
    if total is None:
        total = result.get("total_raw")
    if total is None:
        total = result.get("raw_score")
    if total is None:
        total = result.get("score_raw")
    if total is None:
        total = result.get("raw_total_score")
    if total is None:
        total = result.get("strict_geometric_total")
    if total is None:
        total = result.get("raw_total")
    if not isinstance(total, (int, float)) or isinstance(total, bool):
        raise RuntimeError("Score result must contain numeric score, total_score, or total")
    result["total"] = total
    result.setdefault("status", "SCORED")
    if "protocol_zero" not in result:
        result["protocol_zero"] = bool(result.get("protocol_zero_applied", False))

    native_groups = result.get("groups")
    if not isinstance(native_groups, Mapping):
        native_groups = result.get("groups_normalized")
    if not isinstance(native_groups, Mapping):
        native_groups = result.get("group_scores")
    if not isinstance(native_groups, Mapping):
        native_groups = result.get("raw_group_scores")
    if not isinstance(native_groups, Mapping):
        top_level_groups = {
            name: result[name]
            for name in ("G", "A", "Q", "M", "C", "R", "D")
            if name in result
        }
        native_groups = top_level_groups
    groups: dict[str, float] = {}
    gate: Any = result.get("G")
    for name, item in native_groups.items():
        if name not in {"G", "A", "Q", "M", "C", "R", "D"}:
            continue
        number = item.get("score") if isinstance(item, Mapping) else item
        if not isinstance(number, (int, float)) or isinstance(number, bool):
            if name == "G" and isinstance(number, bool):
                gate = number
            continue
        if name == "G":
            gate = number
        else:
            groups[name] = float(number)
    # Scorers use either utility units [0, 1] or percentage units
    # [0, 100].  A value above one unambiguously identifies the latter;
    # convert the complete group vector together so fields such as 1.0 keep
    # their intended meaning as one percent, not full credit.
    if groups and any(number > 1.0 for number in groups.values()):
        if any(number < 0.0 or number > 100.0 for number in groups.values()):
            raise RuntimeError("Score groups use an invalid mixed or out-of-range scale")
        groups = {name: number / 100.0 for name, number in groups.items()}
        normalization = result.setdefault("normalization", {})
        if isinstance(normalization, dict):
            normalization["groups_scale"] = "percent_to_unit_interval"
            normalization["scorer_total_or_metrics_modified"] = False
    if gate is None:
        for name in ("qualification_gate", "qualification_gate_pass", "qualification_pass", "gate"):
            if name in result:
                gate = result[name]
                break
    if isinstance(gate, Mapping):
        for name in ("G", "passed", "qualified", "pass"):
            if name in gate:
                gate = gate[name]
                break
    if gate is None:
        gate = True
    if not isinstance(gate, (bool, int, float)):
        raise RuntimeError("Score result qualification gate G has an invalid type")
    if native_groups != groups:
        result.setdefault("native_groups", native_groups)
    result["G"] = bool(gate)
    result["groups"] = groups
    result.setdefault("metrics", result.get("diagnostics", {}))
    result.setdefault("scenarios", result.get("scenario_results", []))
    if not result["scenarios"] and isinstance(evidence, Mapping):
        evidence_rows = evidence.get("scenarios")
        scenarios_source = "evidence"
        if not isinstance(evidence_rows, list) or not evidence_rows:
            evidence_rows = evidence.get("scenario_rows")
        if not isinstance(evidence_rows, list) or not evidence_rows:
            facts = evidence.get("facts")
            if isinstance(facts, Mapping):
                evidence_rows = facts.get("scenario_rows")
                scenarios_source = "evidence.facts.scenario_rows"
        if isinstance(evidence_rows, list) and evidence_rows:
            result["scenarios"] = evidence_rows
            normalization = result.setdefault("normalization", {})
            if isinstance(normalization, dict):
                normalization["scenarios_source"] = scenarios_source
                normalization["scorer_total_or_metrics_modified"] = False
    result.setdefault("failure_reasons", [])
    if not isinstance(result["groups"], Mapping) or not isinstance(result["failure_reasons"], list):
        raise RuntimeError("Score groups/failure_reasons have invalid types")
    return result


def _normalize_public_policy(result: dict[str, Any], context: Any) -> dict[str, Any]:
    if not isinstance(context, Mapping):
        return result
    public_policy = context.get("evaluation_policy_id")
    if not isinstance(public_policy, str) or not public_policy:
        return result
    for name in (
        "policy_id",
        "evaluation_policy_id",
        "policy_status",
        "inactive_proposal",
        "active",
        "freeze_ready",
    ):
        result.pop(name, None)
    result["policy_id"] = public_policy
    result["evaluation_policy_id"] = public_policy
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scorer", type=Path, required=True)
    parser.add_argument("--entrypoint", required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--context", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    _deny_child_processes()
    _deny_network()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8-sig"))
    context = json.loads(args.context.read_text(encoding="utf-8-sig"))
    _validate_evidence_sidecars(context)
    _validate_evidence_artifacts(context)
    evidence = _canonicalize_evidence_artifact_paths(evidence, context)
    score = _load_entrypoint(args.scorer, args.entrypoint)(evidence, context)
    result = _normalize_public_policy(_validate(score, evidence), context)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

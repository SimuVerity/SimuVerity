#!/usr/bin/env python3
"""Read-only SLX/XML proof for the XROBO-02 packed-state representation.

The decision is candidate-independent.  It identifies blocks by Simulink SID,
maps MATLAB Function subsystems to Stateflow charts through the nested-system
``Stateflow S-Function N`` / ``chartFileNumber=N`` relationship, and never
uses display names or opaque evaluator indices to select a role.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import zipfile
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Mapping
from xml.etree import ElementTree as ET


SCHEMA = "simuverity.f90-xrobo02-slx-xml-structure-proof.v1"
PUBLIC_INPUT_WIDTHS = {
    "left_target_rad": 7,
    "right_target_rad": 7,
    "move_duration": 1,
    "shared_payload_mass": 1,
    "torque_limit_scale": 1,
    "disturbance_torque_nm": 14,
    "disturbance_start": 1,
}
PUBLIC_OUTPUT_WIDTHS = {
    "joint_state": 28,
    "end_effector_pose": 12,
    "joint_torque": 14,
    "coordination_state": 4,
}
PRESCRIBED_SOURCE_TYPES = {
    "FromWorkspace",
    "RepeatingSequence",
    "SignalBuilder",
    "SignalEditor",
    "Step",
}
IDENTIFIER = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
FUNCTION_HEADER = re.compile(
    r"^\s*function\s+(?:\[([^\]]+)\]|([A-Za-z][A-Za-z0-9_]*))"
    r"\s*=\s*([A-Za-z][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*$"
)
ASSIGNMENT = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.+?)\s*;?\s*$")
SF_TAG = re.compile(r"^Stateflow S-Function ([1-9][0-9]*)$")


class ProofError(RuntimeError):
    """A fail-closed structural proof error."""


def _p(element: ET.Element, name: str, default: str = "") -> str:
    row = element.find(f"P[@Name='{name}']")
    return default if row is None or row.text is None else row.text.strip()


def _normalize(value: str) -> str:
    return "".join(value.split())


def _split_names(value: str) -> list[str]:
    rows = [item.strip() for item in value.split(",") if item.strip()]
    if not rows or not all(IDENTIFIER.fullmatch(item) for item in rows):
        raise ProofError("function_signature_has_invalid_identifier")
    return rows


def _function_signature(script: str) -> tuple[list[str], list[str]]:
    for raw in script.splitlines():
        line = raw.split("%", 1)[0].strip()
        if not line:
            continue
        match = FUNCTION_HEADER.fullmatch(line)
        if match is None:
            raise ProofError("first_executable_line_is_not_supported_function_header")
        outputs = _split_names(match.group(1)) if match.group(1) else [match.group(2)]
        return outputs, _split_names(match.group(4))
    raise ProofError("chart_script_has_no_function_header")


def _assignments(script: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = defaultdict(list)
    for raw in script.splitlines()[1:]:
        line = raw.split("%", 1)[0].strip()
        if not line or line.startswith(("function ", "if ", "elseif ", "for ", "while ")):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if match is not None:
            result[match.group(1)].append(_normalize(match.group(2)))
    return dict(result)


def _identifiers(expression: str) -> set[str]:
    return set(re.findall(r"[A-Za-z][A-Za-z0-9_]*", expression))


def _dependency_closure(assignments: Mapping[str, list[str]], seed: str) -> set[str]:
    seen: set[str] = set()
    pending = [seed]
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        for expression in assignments.get(name, []):
            pending.extend(sorted(_identifiers(expression) - seen))
    return seen


def _unique_slice(assignments: Mapping[str, list[str]], state: str, first: int, last: int) -> str:
    exact = {
        f"{state}({first}:{last})",
        f"reshape({state}({first}:{last}),{last-first+1},1)",
    }
    matches = [name for name, values in assignments.items() if any(value in exact for value in values)]
    if len(matches) != 1:
        raise ProofError(f"state_slice_{first}_{last}_match_count_{len(matches)}")
    return matches[0]


def _concat_is(assignments: Mapping[str, list[str]], output: str, top: str, bottom: str) -> bool:
    allowed = {f"[{top};{bottom}]", f"vertcat({top},{bottom})"}
    return sum(value in allowed for value in assignments.get(output, [])) == 1


def _parse_endpoint(text: str) -> tuple[str, str, int]:
    match = re.fullmatch(r"(.+)#(in|out):([1-9][0-9]*)", text.strip())
    if match is None:
        raise ProofError(f"invalid_line_endpoint:{text}")
    return match.group(1), match.group(2), int(match.group(3))


def _root_edges(root: ET.Element) -> set[tuple[str, int, str, int]]:
    rows: set[tuple[str, int, str, int]] = set()
    for line in root.findall("Line"):
        src_text = _p(line, "Src")
        if not src_text:
            raise ProofError("root_line_missing_source")
        src_sid, src_kind, src_port = _parse_endpoint(src_text)
        if src_kind != "out":
            raise ProofError("root_line_source_is_not_output")
        targets = []
        direct = _p(line, "Dst")
        if direct:
            targets.append(direct)
        targets.extend(_p(branch, "Dst") for branch in line.findall(".//Branch") if _p(branch, "Dst"))
        if not targets:
            raise ProofError("root_line_missing_destination")
        for target in targets:
            dst_sid, dst_kind, dst_port = _parse_endpoint(target)
            if dst_kind != "in":
                raise ProofError("root_line_destination_is_not_input")
            row = (src_sid, src_port, dst_sid, dst_port)
            if row in rows:
                raise ProofError("duplicate_root_edge")
            rows.add(row)
    return rows


def _require_edge(edges: set[tuple[str, int, str, int]], row: tuple[str, int, str, int], label: str) -> None:
    if row not in edges:
        raise ProofError(f"missing_required_edge:{label}:{row}")


def _archive_parts(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def _xml(parts: Mapping[str, bytes], name: str) -> ET.Element:
    try:
        return ET.fromstring(parts[name])
    except KeyError as exc:
        raise ProofError(f"missing_slx_part:{name}") from exc
    except ET.ParseError as exc:
        raise ProofError(f"invalid_xml_part:{name}") from exc


def _chart_table(parts: Mapping[str, bytes]) -> dict[int, dict[str, Any]]:
    machine = _xml(parts, "simulink/stateflow/machine.xml")
    rels = _xml(parts, "simulink/stateflow/_rels/machine.xml.rels")
    relationship_targets: dict[str, str] = {}
    for row in list(rels):
        relationship_targets[row.attrib.get("Id", "")] = row.attrib.get("Target", "")
    refs = [row.attrib.get("Ref", "") for row in machine.findall(".//chart")]
    if not refs or len(refs) != len(set(refs)):
        raise ProofError("stateflow_chart_refs_missing_or_duplicate")
    result: dict[int, dict[str, Any]] = {}
    for ref in refs:
        target = relationship_targets.get(ref)
        if not target:
            raise ProofError(f"stateflow_chart_relationship_missing:{ref}")
        part_name = "simulink/stateflow/" + target
        chart = _xml(parts, part_name)
        chart_id = chart.attrib.get("id", "")
        if ref != f"chart_{chart_id}":
            raise ProofError(f"stateflow_chart_id_mismatch:{ref}:{chart_id}")
        number_text = _p(chart, "chartFileNumber")
        if not number_text.isdigit() or int(number_text) < 1:
            raise ProofError(f"chart_file_number_invalid:{chart_id}")
        number = int(number_text)
        if number in result:
            raise ProofError(f"duplicate_chart_file_number:{number}")
        scripts = [row.text or "" for row in chart.findall(".//state/eml/P[@Name='script']")]
        if len(scripts) != 1:
            raise ProofError(f"chart_script_match_count:{chart_id}:{len(scripts)}")
        result[number] = {"chart_id": chart_id, "part": part_name, "script": scripts[0]}
    return result


def _mapped_subsystems(parts: Mapping[str, bytes], root: ET.Element) -> dict[str, dict[str, Any]]:
    charts = _chart_table(parts)
    result: dict[str, dict[str, Any]] = {}
    for block in root.findall("Block"):
        if block.attrib.get("BlockType") != "SubSystem" or _p(block, "SFBlockType") != "MATLAB Function":
            continue
        sid = block.attrib.get("SID", "")
        system = block.find("System")
        if not sid or system is None or not system.attrib.get("Ref"):
            raise ProofError("matlab_function_subsystem_missing_sid_or_system_ref")
        ref = system.attrib["Ref"]
        nested = _xml(parts, f"simulink/systems/{ref}.xml")
        matches: list[int] = []
        for inner in nested.findall("Block"):
            if inner.attrib.get("BlockType") != "S-Function":
                continue
            match = SF_TAG.fullmatch(_p(inner, "Tag"))
            if match is not None:
                matches.append(int(match.group(1)))
        if len(matches) != 1 or matches[0] not in charts:
            raise ProofError(f"subsystem_chart_mapping_count:{sid}:{matches}")
        chart = charts[matches[0]]
        ports = block.find("PortCounts")
        if ports is None:
            raise ProofError(f"subsystem_port_counts_missing:{sid}")
        result[sid] = {
            "sid": sid,
            "system_ref": ref,
            "stateflow_sfunction_number": matches[0],
            "chart_file_number": matches[0],
            "chart_id": chart["chart_id"],
            "chart_part": chart["part"],
            "script": chart["script"],
            "inputs": int(ports.attrib.get("in", "0")),
            "outputs": int(ports.attrib.get("out", "0")),
        }
    return result


def _constant_bindings(root: ET.Element) -> tuple[dict[str, str], dict[str, str]]:
    values: dict[str, list[str]] = defaultdict(list)
    for block in root.findall("Block"):
        if block.attrib.get("BlockType") == "Constant":
            values[_normalize(_p(block, "Value"))].append(block.attrib.get("SID", ""))
    result: dict[str, str] = {}
    kinds: dict[str, str] = {}
    for name, width in PUBLIC_INPUT_WIDTHS.items():
        allowed = {name: "exact_public_variable"}
        if width > 1:
            allowed[f"reshape({name},{width},1)"] = "reshape_only_public_variable"
            allowed[f"reshape({name},1,{width})"] = "reshape_only_public_variable"
        matches = [(sid, kind) for value, kind in allowed.items() for sid in values.get(value, [])]
        if len(matches) != 1:
            raise ProofError(f"public_input_binding_count:{name}:{len(matches)}")
        result[name], kinds[name] = matches[0]
    return result, kinds


def _unique_integrator(root: ET.Element) -> str:
    matches = []
    for block in root.findall("Block"):
        if block.attrib.get("BlockType") not in {"Integrator", "DiscreteIntegrator"}:
            continue
        initial = _normalize(_p(block, "InitialCondition"))
        if initial in {"zeros(28,1)", "reshape(zeros(28,1),28,1)"}:
            matches.append(block.attrib.get("SID", ""))
    if len(matches) != 1:
        raise ProofError(f"width28_integrator_match_count:{len(matches)}")
    return matches[0]


def _output_sinks(root: ET.Element) -> dict[str, str]:
    result: dict[str, str] = {}
    for name in PUBLIC_OUTPUT_WIDTHS:
        matches = [
            block.attrib.get("SID", "")
            for block in root.findall("Block")
            if block.attrib.get("BlockType") == "ToWorkspace"
            and _p(block, "VariableName") == name
            and _p(block, "SaveFormat").lower() == "timeseries"
        ]
        if len(matches) != 1:
            raise ProofError(f"public_output_sink_count:{name}:{len(matches)}")
        result[name] = matches[0]
    return result


def _role_candidates(
    mapped: Mapping[str, dict[str, Any]],
    edges: set[tuple[str, int, str, int]],
    integrator: str,
    sinks: Mapping[str, str],
) -> tuple[dict[str, Any], dict[str, Any], list[tuple[str, int, str, int, str]]]:
    plants: list[dict[str, Any]] = []
    controllers: list[dict[str, Any]] = []
    for row in mapped.values():
        outputs, inputs = _function_signature(row["script"])
        if len(inputs) != row["inputs"] or len(outputs) != row["outputs"]:
            raise ProofError(f"chart_outer_port_count_mismatch:{row['sid']}")
        row = {**row, "output_variables": outputs, "input_variables": inputs}
        assignments = _assignments(row["script"])
        if row["inputs"] == 9 and row["outputs"] == 5:
            state = inputs[1]
            q = _unique_slice(assignments, state, 1, 14)
            dq = _unique_slice(assignments, state, 15, 28)
            derivative = outputs[0]
            derivative_values = assignments.get(derivative, [])
            concat_rows = [value for value in derivative_values if value.startswith("[") or value.startswith("vertcat(")]
            if len(concat_rows) != 1:
                raise ProofError(f"plant_derivative_assignment_count:{row['sid']}:{len(concat_rows)}")
            match = re.fullmatch(r"\[([A-Za-z][A-Za-z0-9_]*);([A-Za-z][A-Za-z0-9_]*)\]", concat_rows[0])
            if match is None:
                match = re.fullmatch(r"vertcat\(([A-Za-z][A-Za-z0-9_]*),([A-Za-z][A-Za-z0-9_]*)\)", concat_rows[0])
            if match is None or match.group(1) != dq:
                raise ProofError(f"plant_xdot_not_dq_qdd:{row['sid']}")
            qdd = match.group(2)
            if qdd not in assignments:
                raise ProofError(f"plant_qdd_assignment_missing:{row['sid']}")
            if not _concat_is(assignments, outputs[1], q, dq):
                raise ProofError(f"plant_joint_state_not_q_dq:{row['sid']}")
            closure = _dependency_closure(assignments, qdd)
            if not {inputs[2], inputs[7], q, dq}.issubset(closure):
                raise ProofError(f"plant_qdd_dependency_incomplete:{row['sid']}")
            plants.append({**row, "q": q, "dq": dq, "qdd": qdd, "assignments": assignments})
        if row["inputs"] == 7 and row["outputs"] == 1:
            state = inputs[1]
            q = _unique_slice(assignments, state, 1, 14)
            dq = _unique_slice(assignments, state, 15, 28)
            closure = _dependency_closure(assignments, outputs[0])
            if not {q, dq, inputs[2], inputs[3], inputs[6]}.issubset(closure):
                raise ProofError(f"controller_torque_dependency_incomplete:{row['sid']}")
            controllers.append({**row, "q": q, "dq": dq, "assignments": assignments})
    if len(plants) != 1 or len(controllers) != 1:
        raise ProofError(f"plant_controller_match_counts:{len(plants)}:{len(controllers)}")
    plant, controller = plants[0], controllers[0]
    required: list[tuple[str, int, str, int, str]] = []

    def need(src: str, out_port: int, dst: str, in_port: int, label: str) -> None:
        _require_edge(edges, (src, out_port, dst, in_port), label)
        required.append((src, out_port, dst, in_port, label))

    need(integrator, 1, plant["sid"], 2, "packed_state_to_plant")
    need(integrator, 1, controller["sid"], 2, "packed_state_to_controller")
    need(plant["sid"], 1, integrator, 1, "plant_xdot_to_packed_integrator")
    controller_to_plant = [row for row in edges if row[0] == controller["sid"] and row[2] == plant["sid"]]
    if len(controller_to_plant) != 1:
        raise ProofError(f"controller_to_plant_edge_count:{len(controller_to_plant)}")
    need(*controller_to_plant[0], "controller_torque_to_plant")
    for index, name in enumerate(PUBLIC_OUTPUT_WIDTHS, start=2):
        need(plant["sid"], index, sinks[name], 1, f"plant_{name}_to_public_sink")
    return plant, controller, required


def _public_edge_checks(
    bindings: Mapping[str, str],
    plant: Mapping[str, Any],
    controller: Mapping[str, Any],
    edges: set[tuple[str, int, str, int]],
) -> list[tuple[str, int, str, int, str]]:
    required: list[tuple[str, int, str, int, str]] = []
    for name, sid in bindings.items():
        destinations = []
        for role in (controller, plant):
            if name in role["input_variables"]:
                destinations.append((role["sid"], role["input_variables"].index(name) + 1))
        expected_roles = {
            "left_target_rad": 2,
            "right_target_rad": 2,
            "move_duration": 1,
            "shared_payload_mass": 2,
            "torque_limit_scale": 2,
            "disturbance_torque_nm": 1,
            "disturbance_start": 1,
        }[name]
        if len(destinations) != expected_roles:
            raise ProofError(f"public_input_role_count:{name}:{len(destinations)}")
        for destination, port in destinations:
            label = f"public_{name}_to_sid_{destination}_port_{port}"
            _require_edge(edges, (sid, 1, destination, port), label)
            required.append((sid, 1, destination, port, label))
    return required


def _no_prescribed_sources(root: ET.Element, edges: set[tuple[str, int, str, int]]) -> bool:
    connected = {source for source, _, _, _ in edges}
    offenders = [
        block.attrib.get("SID", "")
        for block in root.findall("Block")
        if block.attrib.get("BlockType") in PRESCRIBED_SOURCE_TYPES
        and block.attrib.get("SID", "") in connected
    ]
    if offenders:
        raise ProofError(f"connected_prescribed_sources:{','.join(sorted(offenders))}")
    return True


def _policy_graph(
    bindings: Mapping[str, str],
    integrator: str,
    plant: Mapping[str, Any],
    controller: Mapping[str, Any],
) -> dict[str, Any]:
    nodes: list[dict[str, Any]] = []

    def node(identifier: str, block_type: str, ins: list[tuple[str, int]], outs: list[tuple[str, int]]) -> None:
        nodes.append(
            {
                "id": identifier,
                "block_type": block_type,
                "sf_block_type": "MATLAB Function" if block_type == "SubSystem" else "",
                "input_ports": [name for name, _ in ins],
                "output_ports": [name for name, _ in outs],
                "input_widths": [width for _, width in ins],
                "output_widths": [width for _, width in outs],
                "prescribed_source": False,
            }
        )

    source_ports: dict[str, list[str]] = {}
    for name, sid in bindings.items():
        port = f"sid:{sid}:o1"
        node(f"sid:{sid}", "Constant", [], [(port, PUBLIC_INPUT_WIDTHS[name])])
        source_ports[name] = [port]

    q_id, dq_id = f"sid:{integrator}:q14", f"sid:{integrator}:dq14"
    q_in, q_out = q_id + ":i1", q_id + ":o1"
    dq_in, dq_out = dq_id + ":i1", dq_id + ":o1"
    node(q_id, "Integrator", [(q_in, 14)], [(q_out, 14)])
    node(dq_id, "Integrator", [(dq_in, 14)], [(dq_out, 14)])

    controller_id = f"sid:{controller['sid']}"
    controller_inputs: list[tuple[str, int]] = [
        (controller_id + ":i_t", 1),
        (controller_id + ":i_q", 14),
        (controller_id + ":i_dq", 14),
        (controller_id + ":i_left", 7),
        (controller_id + ":i_right", 7),
        (controller_id + ":i_duration", 1),
        (controller_id + ":i_payload", 1),
        (controller_id + ":i_scale", 1),
    ]
    controller_torque = controller_id + ":o_tau"
    node(controller_id, "SubSystem", controller_inputs, [(controller_torque, 14)])

    plant_id = f"sid:{plant['sid']}"
    plant_inputs: list[tuple[str, int]] = [
        (plant_id + ":i_t", 1),
        (plant_id + ":i_q", 14),
        (plant_id + ":i_dq", 14),
        (plant_id + ":i_tau", 14),
        (plant_id + ":i_left", 7),
        (plant_id + ":i_right", 7),
        (plant_id + ":i_payload", 1),
        (plant_id + ":i_scale", 1),
        (plant_id + ":i_disturbance", 14),
        (plant_id + ":i_disturbance_start", 1),
    ]
    plant_outputs: list[tuple[str, int]] = [
        (plant_id + ":o_qdd", 14),
        (plant_id + ":o_joint_state", 28),
        (plant_id + ":o_pose", 12),
        (plant_id + ":o_torque", 14),
        (plant_id + ":o_coordination", 4),
    ]
    node(plant_id, "SubSystem", plant_inputs, plant_outputs)

    edges: list[dict[str, str]] = []

    def edge(source: str, target: str, kind: str = "xml_semantic_edge") -> None:
        edges.append({"source_port_id": source, "target_port_id": target, "kind": kind})

    edge(plant_id + ":o_qdd", dq_in)
    edge(dq_out, q_in)
    for port in (plant_id + ":i_q", controller_id + ":i_q"):
        edge(q_out, port)
    for port in (plant_id + ":i_dq", controller_id + ":i_dq"):
        edge(dq_out, port)
    edge(controller_torque, plant_id + ":i_tau")
    edge(controller_torque, plant_id + ":o_torque")
    edge(q_out, plant_id + ":o_joint_state")
    edge(dq_out, plant_id + ":o_joint_state")

    input_targets = {
        "left_target_rad": [controller_id + ":i_left", plant_id + ":i_left"],
        "right_target_rad": [controller_id + ":i_right", plant_id + ":i_right"],
        "move_duration": [controller_id + ":i_duration"],
        "shared_payload_mass": [controller_id + ":i_payload", plant_id + ":i_payload"],
        "torque_limit_scale": [controller_id + ":i_scale", plant_id + ":i_scale"],
        "disturbance_torque_nm": [plant_id + ":i_disturbance"],
        "disturbance_start": [plant_id + ":i_disturbance_start"],
    }
    for name, targets in input_targets.items():
        for target in targets:
            edge(source_ports[name][0], target, "root_xml_wire")

    return {
        "schema": "simuverity.f90-xrobo02-packed-state-port-graph.v1",
        "nodes": nodes,
        "edges": edges,
        "public_input_source_ports": source_ports,
        "public_output_bindings": {
            "joint_state": {"anchor_port_id": plant_id + ":o_joint_state", "compiled_width": 28},
            "end_effector_pose": {"anchor_port_id": plant_id + ":o_pose", "compiled_width": 12},
            "joint_torque": {"anchor_port_id": plant_id + ":o_torque", "compiled_width": 14},
            "coordination_state": {"anchor_port_id": plant_id + ":o_coordination", "compiled_width": 4},
        },
        "compiled_update_succeeded": True,
        "port_identity_complete": True,
        "compiled_widths_complete": True,
        "public_output_bindings_unambiguous": True,
        "public_input_bindings_complete": True,
        "candidate_display_names_emitted": False,
        "candidate_mask_types_emitted": False,
        "connected_prescribed_source_output_ports": [],
        "node_identity": "simulink_sid_and_stateflow_chart_xml_id",
        "virtual_partition_semantics": "one_actual_width28_integrator_projected_as_q14_and_dq14",
        "decision_uses_display_name": False,
    }


def analyze_parts(parts: Mapping[str, bytes]) -> dict[str, Any]:
    checks: dict[str, bool] = {}
    try:
        root = _xml(parts, "simulink/systems/system_root.xml")
        edges = _root_edges(root)
        mapped = _mapped_subsystems(parts, root)
        checks["stateflow_chart_mapped_by_xml_ids"] = True
        bindings, binding_kinds = _constant_bindings(root)
        checks["public_inputs_7_of_7_bound"] = len(bindings) == 7
        integrator = _unique_integrator(root)
        checks["unique_width28_integrator"] = True
        sinks = _output_sinks(root)
        plant, controller, required = _role_candidates(mapped, edges, integrator, sinks)
        checks["plant_q14_dq14_xdot_semantics"] = True
        checks["controller_q14_dq14_torque_semantics"] = True
        checks["packed_state_controller_plant_graph"] = True
        required.extend(_public_edge_checks(bindings, plant, controller, edges))
        checks["public_inputs_reach_required_roles"] = True
        checks["four_public_outputs_reachable"] = True
        checks["no_connected_prescribed_source"] = _no_prescribed_sources(root, edges)
        graph = _policy_graph(bindings, integrator, plant, controller)
        return {
            "schema": SCHEMA,
            "pass": all(checks.values()),
            "checks": checks,
            "failure_reasons": [],
            "decision_uses_display_name": False,
            "mapping_rule": "SubSystem.SID -> System.Ref -> inner S-Function Tag number -> chartFileNumber -> chart.id",
            "plant_xml_identity": {
                key: plant[key]
                for key in ("sid", "system_ref", "stateflow_sfunction_number", "chart_file_number", "chart_id", "chart_part")
            },
            "controller_xml_identity": {
                key: controller[key]
                for key in ("sid", "system_ref", "stateflow_sfunction_number", "chart_file_number", "chart_id", "chart_part")
            },
            "packed_integrator_sid": integrator,
            "public_input_bindings": {
                name: {"source_sid": bindings[name], "width": PUBLIC_INPUT_WIDTHS[name], "kind": binding_kinds[name]}
                for name in PUBLIC_INPUT_WIDTHS
            },
            "public_output_sink_sids": sinks,
            "required_root_edges": [
                {"source_sid": a, "source_port": b, "target_sid": c, "target_port": d, "role": label}
                for a, b, c, d, label in required
            ],
            "policy_graph": graph,
        }
    except ProofError as exc:
        return {
            "schema": SCHEMA,
            "pass": False,
            "checks": checks,
            "failure_reasons": [str(exc)],
            "decision_uses_display_name": False,
        }


def analyze_slx(path: Path) -> dict[str, Any]:
    return analyze_parts(_archive_parts(path))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate_slx", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args(argv)
    report = analyze_slx(args.candidate_slx.resolve())
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 0 if report.get("pass") is True else 2


if __name__ == "__main__":
    sys.exit(main())

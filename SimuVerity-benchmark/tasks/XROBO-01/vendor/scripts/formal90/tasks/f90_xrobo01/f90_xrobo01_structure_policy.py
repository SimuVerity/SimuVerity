#!/usr/bin/env python3
"""Public-contract structure policy for XROBO-01 evidence GROUP_SCORING.

GROUP_SCORING fixes two representation defects in the SCORING_CORE offline policy: MATLAB
``jsonencode`` emits singleton string arrays as scalars and flattens Nx3 cell
edge tables in column-major order.  It also recognizes resolved SimscapeBlock
instances and Spatial Contact Force as their actual product identities.  The
gate remains connection based: product presence alone never proves an
actuator, contact, supply, feedback, or output-provenance path.
"""

from __future__ import annotations

import copy
import importlib.util
from itertools import combinations
from pathlib import Path
from types import ModuleType
from typing import Any, Iterable


TASK_DIR = Path(__file__).resolve().parent
current_POLICY = TASK_DIR / "f90_xrobo01_structure_policy_core.py"
EXPECTED_OUTPUTS = {
    "body_state": 6,
    "contact_state": 4,
    "gait_state": 3,
    "electrical_state": 3,
}


def _load_policy_core() -> ModuleType:
    if not current_POLICY.is_file():
        raise RuntimeError("XROBO01 SCORING_CORE policy is missing")
    spec = importlib.util.spec_from_file_location("xrobo01_policy", current_POLICY)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load XROBO01 SCORING_CORE policy")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SCORING_CORE = _load_policy_core()


def _ports(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value] if value else []
    if isinstance(value, (list, tuple)):
        return [str(item) for item in value]
    return []


def _edge_rows(value: Any) -> list[list[str]]:
    if not isinstance(value, list) or not value:
        return []
    if all(isinstance(row, dict) for row in value):
        return [
            [str(row.get("source", "")), str(row.get("target", "")), str(row.get("kind", ""))]
            for row in value
        ]
    if all(isinstance(row, (list, tuple)) and len(row) >= 2 for row in value):
        return [
            [str(row[0]), str(row[1]), str(row[2]) if len(row) > 2 else ""]
            for row in value
        ]
    if all(isinstance(item, str) for item in value) and len(value) % 3 == 0:
        count = len(value) // 3
        return [
            [value[index], value[index + count], value[index + 2 * count]]
            for index in range(count)
        ]
    return []


def normalize_graph(graph: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(graph if isinstance(graph, dict) else {})
    for node in result.get("nodes", []):
        if not isinstance(node, dict):
            continue
        for key in ("signal_input_ports", "signal_output_ports", "domain_ports"):
            node[key] = _ports(node.get(key, []))
    result["signal_edges"] = _edge_rows(result.get("signal_edges", []))
    result["physical_edges"] = _edge_rows(result.get("physical_edges", []))
    return result


def _trusted(node: dict[str, Any]) -> bool:
    source = SCORING_CORE._text(node.get("source_block"))
    root = SCORING_CORE._text(node.get("library_root"))
    return (
        SCORING_CORE._text(node.get("block_type")).lower()
        in {"reference", "simscapeblock", "simscapemultibodyblock"}
        and SCORING_CORE._text(node.get("link_status")).lower() in {"resolved", "implicit"}
        and bool(source)
        and bool(root)
        and source.split("/", 1)[0] == root
        and node.get("resolved_library_under_matlabroot") is True
        and node.get("source_block_exists") is True
        and bool(SCORING_CORE._text(node.get("resolved_library_file")))
        and node.get("port_interface_complete") is True
    )


def _roles(nodes: dict[str, dict[str, Any]]) -> dict[str, list[str]]:
    result = {
        role: []
        for role in (
            "joint", "solid", "motor", "torque_sensor", "contact",
            "transform_sensor", "battery", "capacitor", "current_sensor",
            "voltage_sensor",
        )
    }
    for node_id, node in nodes.items():
        if not _trusted(node):
            continue
        source = SCORING_CORE._text(node.get("source_block"))
        lower = source.lower()
        leaf = lower.rsplit("/", 1)[-1]
        root = SCORING_CORE._text(node.get("library_root")).lower()
        if source == "sm_lib/Joints/Revolute Joint":
            result["joint"].append(node_id)
        if root == "sm_lib" and source.startswith("sm_lib/Body Elements/") and (
            leaf == "solid" or leaf.endswith(" solid")
        ):
            result["solid"].append(node_id)
        if (
            "rotational electromechanical converter" in leaf
            or (root == "ee_lib" and "motor" in leaf)
        ):
            result["motor"].append(node_id)
        if leaf.endswith("torque sensor"):
            result["torque_sensor"].append(node_id)
        if source in {
            "sm_lib/Forces and Torques/Spatial Contact Force",
            "sm_lib/Forces and Torques/External Force and Torque",
        }:
            result["contact"].append(node_id)
        if source == "sm_lib/Frames and Transforms/Transform Sensor":
            result["transform_sensor"].append(node_id)
        if leaf == "battery" and root in {"batteryecm_lib", "fl_lib", "ee_lib"}:
            result["battery"].append(node_id)
        if leaf == "capacitor" and root in {"fl_lib", "ee_lib"}:
            result["capacitor"].append(node_id)
        if leaf == "current sensor" and root in {"fl_lib", "ee_lib"}:
            result["current_sensor"].append(node_id)
        if leaf == "voltage sensor" and root in {"fl_lib", "ee_lib"}:
            result["voltage_sensor"].append(node_id)
    return result


def _port_family(node: dict[str, Any], port: str, labels: dict[str, str]) -> str:
    source = SCORING_CORE._text(node.get("source_block")).lower()
    label = labels.get(port, "").lower()
    if "rotational electromechanical converter" in source or (
        source.startswith("ee_lib/electromechanical/") and "motor" in source
    ):
        if label in {"c", "r", "s", "o"}:
            return "mechanical"
        if label in {"+", "-", "vp", "vm"}:
            return "electrical"
        return ""
    if source.startswith("sm_lib/"):
        return "multibody"
    if source.startswith("batteryecm_lib/") or source.startswith("fl_lib/electrical/"):
        return "electrical"
    if source.startswith("fl_lib/mechanical/"):
        return "mechanical"
    return ""


def _physical_adjacency(parsed: dict[str, Any]) -> dict[str, set[str]]:
    adjacency = {port: set(targets) for port, targets in parsed["physical"].items()}
    for node in parsed["nodes"].values():
        if not _trusted(node):
            continue
        ports = list(node.get("domain_ports", []))
        groups: dict[str, list[str]] = {}
        for port in ports:
            family = _port_family(node, port, parsed["labels"])
            if family:
                groups.setdefault(family, []).append(port)
        for values in groups.values():
            for left, right in combinations(values, 2):
                adjacency[left].add(right)
                adjacency[right].add(left)
    return adjacency


def _path(
    parsed: dict[str, Any], starts: Iterable[str], targets: Iterable[str], *, physical: bool = False
) -> list[str]:
    adjacency = parsed["physical"] if physical else parsed["signal"]
    return SCORING_CORE._path(starts, targets, adjacency, parsed["owners"])


def _owner_path(parsed: dict[str, Any], left: str, right: str) -> list[str]:
    witness = _path(
        parsed,
        parsed["nodes"][left].get("domain_ports", []),
        parsed["nodes"][right].get("domain_ports", []),
        physical=True,
    )
    result: list[str] = []
    for port in witness:
        owner = parsed["owners"].get(port, "")
        if owner and (not result or result[-1] != owner):
            result.append(owner)
    return result


def _connected(parsed: dict[str, Any], left: str, right: str) -> bool:
    return bool(_owner_path(parsed, left, right))


def _public_outputs(graph: dict[str, Any], parsed: dict[str, Any]) -> tuple[dict[str, str], bool]:
    raw = graph.get("public_outputs")
    anchors: dict[str, str] = {}
    valid = isinstance(raw, dict)
    for name, channels in EXPECTED_OUTPUTS.items():
        row = raw.get(name) if isinstance(raw, dict) else None
        node_id = row.get("node_id") if isinstance(row, dict) else None
        anchor = row.get("anchor_port_id") if isinstance(row, dict) else None
        node = parsed["nodes"].get(node_id) if isinstance(node_id, str) else None
        passed = (
            node is not None
            and SCORING_CORE._text(node.get("block_type")).lower() == "toworkspace"
            and isinstance(anchor, str)
            and anchor in node.get("signal_input_ports", [])
            and row.get("candidate_count") == 1
            and row.get("timeseries") is True
            and row.get("max_data_points_inf") is True
            and row.get("expected_channels") == channels
            and anchor in parsed["signal_incident"]
        )
        valid = valid and passed
        if passed:
            anchors[name] = anchor
    return anchors, valid and len(anchors) == len(EXPECTED_OUTPUTS)


def _all_sources(parsed: dict[str, Any], source_ids: Iterable[str], target: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for node_id in source_ids:
        witness = _path(parsed, parsed["nodes"][node_id].get("signal_output_ports", []), [target])
        if witness:
            result[node_id] = witness
    return result


def evaluate_structure_graph(graph: dict[str, Any]) -> dict[str, Any]:
    normalized = normalize_graph(graph)
    parsed = SCORING_CORE._parse_graph(normalized)
    parsed["physical"] = _physical_adjacency(parsed)
    roles = _roles(parsed["nodes"])

    active_joints: list[str] = []
    passive_joints: list[str] = []
    joint_physics: dict[str, bool] = {}
    joint_feedback: dict[str, bool] = {}
    for joint in roles["joint"]:
        node = parsed["nodes"][joint]
        config = node.get("joint_configuration", {})
        active = SCORING_CORE._text(config.get("torque_actuation_mode")).lower() == "inputtorque"
        (active_joints if active else passive_joints).append(joint)
        inputs = list(node.get("signal_input_ports", []))
        outputs = list(node.get("signal_output_ports", []))
        joint_physics[joint] = (
            active
            and bool(inputs)
            and all(port in parsed["signal_incident"] for port in inputs)
            and len(node.get("domain_ports", [])) >= 2
        )
        joint_feedback[joint] = (
            SCORING_CORE._text(config.get("sense_position")).lower() == "on"
            and SCORING_CORE._text(config.get("sense_velocity")).lower() == "on"
            and len(outputs) >= 2
            and all(port in parsed["signal_incident"] for port in outputs[:2])
        )

    contact_to_knee: dict[str, list[str]] = {}
    used_knees: set[str] = set()
    for contact in roles["contact"]:
        candidates = [
            (len(path), knee, path)
            for knee in passive_joints
            if (path := _owner_path(parsed, contact, knee))
        ]
        for _, knee, path in sorted(candidates):
            if knee not in used_knees:
                used_knees.add(knee)
                contact_to_knee[contact] = path
                break

    actuator_rows: list[dict[str, Any]] = []
    used_motors: set[str] = set()
    used_sensors: set[str] = set()
    for joint in active_joints:
        joint_inputs = parsed["nodes"][joint].get("signal_input_ports", [])
        for sensor in roles["torque_sensor"]:
            signal_path = _path(
                parsed, parsed["nodes"][sensor].get("signal_output_ports", []), joint_inputs
            )
            if not signal_path:
                continue
            for motor in roles["motor"]:
                physical_path = _owner_path(parsed, motor, sensor)
                if not physical_path:
                    continue
                actuator_rows.append(
                    {
                        "joint": joint,
                        "motor": motor,
                        "torque_sensor": sensor,
                        "motor_to_sensor_path": physical_path,
                        "sensor_to_joint_path": signal_path,
                    }
                )
                used_motors.add(motor)
                used_sensors.add(sensor)
                break
            if actuator_rows and actuator_rows[-1]["joint"] == joint:
                break

    feedback_rows: list[dict[str, Any]] = []
    contact_feedback_rows: list[dict[str, Any]] = []
    for row in actuator_rows:
        joint = row["joint"]
        motor = row["motor"]
        controller_target = parsed["nodes"][motor].get("signal_input_ports", [])
        actuation_target = parsed["nodes"][joint].get("signal_input_ports", [])
        target = controller_target or actuation_target
        outputs = parsed["nodes"][joint].get("signal_output_ports", [])
        q_path = _path(parsed, outputs[:1], target)
        w_path = _path(parsed, outputs[1:2], target)
        if q_path and w_path:
            feedback_rows.append({"joint": joint, "q_path": q_path, "w_path": w_path})
        contact_paths = _all_sources(
            parsed,
            roles["contact"] + roles["transform_sensor"],
            target[0],
        ) if target else {}
        if contact_paths:
            contact_feedback_rows.append({"joint": joint, "paths": contact_paths})

    battery = roles["battery"][0] if roles["battery"] else ""
    supply_paths: dict[str, list[str]] = {}
    if battery:
        for target in (
            roles["capacitor"]
            + roles["current_sensor"]
            + roles["voltage_sensor"]
            + roles["motor"]
        ):
            witness = _owner_path(parsed, battery, target)
            if witness:
                supply_paths[target] = witness
    electrical_pass = (
        bool(battery)
        and bool(set(supply_paths).intersection(roles["capacitor"]))
        and len(set(supply_paths).intersection(roles["current_sensor"])) >= 2
        and bool(set(supply_paths).intersection(roles["voltage_sensor"]))
        and len(set(supply_paths).intersection(roles["motor"])) >= 4
    )

    anchors, output_contract = _public_outputs(normalized, parsed)
    body_paths = (
        _all_sources(parsed, roles["transform_sensor"], anchors["body_state"])
        if "body_state" in anchors
        else {}
    )
    contact_signal_sources = list(roles["contact"])
    contact_signal_sources.extend(
        node_id
        for node_id in roles["transform_sensor"]
        if node_id not in body_paths
    )
    contact_paths = (
        _all_sources(parsed, contact_signal_sources, anchors["contact_state"])
        if "contact_state" in anchors
        else {}
    )
    gait_paths = (
        _all_sources(parsed, contact_signal_sources, anchors["gait_state"])
        if "gait_state" in anchors
        else {}
    )
    voltage_paths = (
        _all_sources(parsed, roles["voltage_sensor"], anchors["electrical_state"])
        if "electrical_state" in anchors
        else {}
    )
    current_paths = (
        _all_sources(parsed, roles["current_sensor"], anchors["electrical_state"])
        if "electrical_state" in anchors
        else {}
    )
    provenance = {
        "body_state": bool(body_paths),
        "contact_state": len(contact_paths) >= 4,
        "gait_state": len(gait_paths) >= 4,
        "electrical_state": bool(voltage_paths) and len(current_paths) >= 2,
    }

    identity_policy = (
        parsed["valid"]
        and normalized.get("port_identity_complete") is True
        and normalized.get("candidate_display_names_emitted") is False
        and normalized.get("candidate_mask_or_component_identity_emitted") is False
        and normalized.get("candidate_source_type_used_for_identity") is False
        and normalized.get("unresolved_reference_metadata_used_for_identity") is False
    )
    mechanism_checks = {
        "articulated_four_leg_plant": (
            identity_policy
            and len(roles["joint"]) >= 8
            and len(roles["solid"]) >= 9
            and len(contact_to_knee) >= 4
        ),
        "connected_hip_torque_actuation": (
            len(active_joints) >= 4 and sum(joint_physics.values()) >= 4
        ),
        "measured_hip_feedback": (
            len(active_joints) >= 4 and sum(joint_feedback.values()) >= 4
        ),
        "finite_electromechanical_actuator_chain": (
            len(actuator_rows) >= 4
            and len(used_motors) >= 4
            and len(used_sensors) >= 4
        ),
        "four_physical_foot_contacts": (
            len(roles["contact"]) >= 4 and len(contact_to_knee) >= 4
        ),
        "shared_measured_electrical_supply": electrical_pass,
        "physical_energy_buffer": (
            electrical_pass and bool(set(supply_paths).intersection(roles["capacitor"]))
        ),
        "sensor_logic_actuator_branch_ownership": (
            len(feedback_rows) >= 4 and len(contact_feedback_rows) >= 4
        ),
    }
    other_checks = {
        "source_registered": True,
        "complete_timeseries_contract": output_contract,
        "physical_output_provenance": all(provenance.values()),
        "self_contained_initialization": normalized.get("self_contained_callback") is True,
    }
    checks_by_id = {
        "source_registered": other_checks["source_registered"],
        **mechanism_checks,
        "complete_timeseries_contract": other_checks["complete_timeseries_contract"],
        "physical_output_provenance": other_checks["physical_output_provenance"],
        "self_contained_initialization": other_checks["self_contained_initialization"],
    }
    checks = [
        {"id": key, "pass": bool(value), "detail": "GROUP_SCORING resolved-product and actual-port predicate"}
        for key, value in checks_by_id.items()
    ]
    return {
        "schema": "simuverity.f90-xrobo01-structure-decision.v1",
        "pass": all(row["pass"] for row in checks),
        "mechanism_fraction": sum(bool(value) for value in mechanism_checks.values()) / 8.0,
        "checks": checks,
        "checks_by_id": checks_by_id,
        "identity_policy_pass": identity_policy,
        "counts": {key: len(value) for key, value in roles.items()},
        "active_joints": active_joints,
        "passive_joints": passive_joints,
        "contact_to_knee_paths": contact_to_knee,
        "actuator_path_witnesses": actuator_rows,
        "feedback_path_witnesses": feedback_rows,
        "contact_feedback_witnesses": contact_feedback_rows,
        "electrical_supply_paths": supply_paths,
        "output_contract_pass": output_contract,
        "output_provenance": provenance,
        "output_path_witnesses": {
            "body_state": body_paths,
            "contact_state": contact_paths,
            "gait_state": gait_paths,
            "electrical_voltage": voltage_paths,
            "electrical_current": current_paths,
        },
        "hierarchy_global_complete": normalized.get(
            "hierarchy_bridges_preserve_port_ordinals"
        ) is True,
        "hierarchy_global_flag_is_not_an_all_or_nothing_gate": True,
        "normalized_singleton_port_fields": True,
        "normalized_column_major_edge_tables": True,
        "failure_reasons": [row["id"] for row in checks if not row["pass"]],
        "display_name_used_for_identity": False,
        "candidate_source_type_used_for_identity": False,
        "unresolved_reference_metadata_used_for_identity": False,
    }

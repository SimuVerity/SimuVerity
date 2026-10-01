from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping


@dataclass(frozen=True)
class ExtractorSidecar:
    role: str
    kind: str
    producer_path: Path
    arguments: tuple[str, ...]
    output_name: str
    expected_schema: str


@dataclass(frozen=True)
class TaskDefinition:
    task_id: str
    collection: str
    root: Path
    manifest_path: Path
    public_spec_path: Path
    system_profile_path: Path
    scenarios_path: Path
    scorer_path: Path
    scorer_entrypoint: str
    extractor_path: Path
    extractor_kind: str
    extractor_entrypoint: str
    extractor_sidecars: tuple[ExtractorSidecar, ...]
    evaluation_policy_id: str
    required_model_file: str
    public_input_names: tuple[str, ...]
    reference: Mapping[str, Any]
    raw: Mapping[str, Any] = field(repr=False)


@dataclass(frozen=True)
class AgentEvent:
    event_type: str
    timestamp: str
    call_id: str = ""
    tool_name: str = ""
    text: str = ""
    simulation: bool = False
    raw_type: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {
            "schema": "simuverity.agent-event.v1",
            "type": self.event_type,
            "timestamp": self.timestamp,
            "call_id": self.call_id,
            "tool_name": self.tool_name,
            "text": self.text,
            "simulation": self.simulation,
            "raw_type": self.raw_type,
        }


@dataclass(frozen=True)
class ProcessResult:
    exit_code: int
    status: str
    simulation_timeout: bool
    terminal_failure: bool
    observed_matlab_tool_calls: int
    forbidden_tool_calls: tuple[str, ...]
    trace_parse_errors: int
    event_count: int
    started_at: str
    ended_at: str

from __future__ import annotations

import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..adapters import AgentRequest, get_adapter
from ..candidate_closure import run_clean_replay, seal_submission
from ..errors import ContractError, InfrastructureError
from ..evaluation import evaluate_submission
from ..jsonutil import write_json_exclusive
from ..repository import TaskRepository
from ..runtime.process import run_streaming_process
from ..runtime.identity import reserve_identity
from ..runtime.windows.isolation import build_isolated_environment, create_runtime_layout


def new_identity(prefix: str) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{prefix}_{timestamp}_{uuid.uuid4().hex[:10]}"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def generate_task(
    repository: TaskRepository,
    task_id: str,
    *,
    agent: str,
    model: str,
    mcp_config: Path,
    output_parent: Path,
    generation_run_id: str | None = None,
    source_agent_home: Path | None = None,
    simulation_timeout_seconds: int = 1800,
) -> dict[str, Any]:
    task = repository.get(task_id)
    generation_run_id = generation_run_id or new_identity("generation")
    reserve_identity(
        repository.root,
        kind="generation",
        identity=generation_run_id,
        task_id=task.task_id,
    )
    layout = create_runtime_layout(output_parent.resolve(), generation_run_id)
    if not mcp_config.is_file():
        raise ContractError(f"MCP configuration is missing: {mcp_config}")
    runtime_mcp_config = layout.root / "mcp.json"
    shutil.copy2(mcp_config.resolve(), runtime_mcp_config)
    prompt = repository.prompt_bytes(task)
    prompt_path = layout.root / "prompt.txt"
    prompt_path.write_bytes(prompt)
    adapter = get_adapter(agent)
    request = AgentRequest(
        model=model,
        workspace=layout.workspace,
        agent_home=layout.agent_home,
        claude_config=layout.claude_config,
        mcp_config=runtime_mcp_config,
        last_message_path=layout.root / "last_message.txt",
        source_agent_home=source_agent_home,
    )
    credential_paths = (
        layout.agent_home / "auth.json",
        layout.claude_config / ".credentials.json",
    )
    credential_cleanup_verified = False
    try:
        environment = build_isolated_environment(layout, allow_credentials=True)
        environment = adapter.prepare(request, environment)
        executable = adapter.command(request)[0]
        if shutil.which(executable, path=environment.get("PATH")) is None:
            raise InfrastructureError(f"Agent CLI is not installed or not on PATH: {executable}")
        process = run_streaming_process(
            adapter.command(request),
            cwd=layout.workspace,
            environment=environment,
            stdin_bytes=prompt,
            raw_stdout_path=layout.root / "agent_trace.jsonl",
            stderr_path=layout.root / "agent_stderr.log",
            normalized_events_path=layout.root / "events.jsonl",
            parse_events=adapter.parse_events,
            simulation_timeout_seconds=simulation_timeout_seconds,
        )
    finally:
        for credential in credential_paths:
            try:
                credential.unlink(missing_ok=True)
            except OSError:
                pass
        credential_cleanup_verified = all(not credential.exists() for credential in credential_paths)
        if not credential_cleanup_verified:
            raise InfrastructureError("Run-local agent credential cleanup could not be verified")
    closure: dict[str, Any] | None = None
    sealed: dict[str, Any] | None = None
    clean_replay: dict[str, Any] | None = None
    status = process.status
    failure_attribution = ""
    failure_reasons: list[str] = []
    if process.status == "COMPLETED" and (
        process.trace_parse_errors > 0
        or process.forbidden_tool_calls
        or process.observed_matlab_tool_calls == 0
    ):
        status = "PROTOCOL_INVALID"
        failure_attribution = "candidate"
        if process.trace_parse_errors:
            failure_reasons.append(f"AGENT_TRACE_UNPARSEABLE_LINES:{process.trace_parse_errors}")
        if process.forbidden_tool_calls:
            failure_reasons.append("FORBIDDEN_TOOL_CALLS:" + ",".join(process.forbidden_tool_calls))
        if process.observed_matlab_tool_calls == 0:
            failure_reasons.append("MATLAB_MCP_TOOL_CALL_NOT_OBSERVED")
    elif process.status == "COMPLETED":
        try:
            sealed = seal_submission(
                layout.workspace,
                required_model_file=task.required_model_file,
                closure_root=layout.root / "candidate_closure",
                task_id=task.task_id,
                generation_run_id=generation_run_id,
            )
        except ContractError as exc:
            status = "CANDIDATE_INVALID"
            failure_attribution = "candidate"
            failure_reasons.append(str(exc))
        if sealed is not None:
            try:
                replay_environment = build_isolated_environment(layout, allow_credentials=False)
                clean_replay = run_clean_replay(
                    task,
                    sealed_candidate=Path(sealed["sealed_candidate"]),
                    output_root=layout.root / "clean_replay",
                    environment=replay_environment,
                    simulation_timeout_seconds=simulation_timeout_seconds,
                )
            except (ContractError, OSError, ValueError) as exc:
                status = "GENERATION_INFRA_ERROR"
                failure_attribution = "generation_infrastructure"
                failure_reasons.append(f"CLEAN_REPLAY_RUNTIME_CONTRACT:{exc}")
                clean_replay = None
        if sealed is not None and clean_replay is not None:
            if clean_replay["status"] == "CANDIDATE_CLOSURE_PASSED":
                closure = sealed
                status = "GENERATION_COMPLETED"
            elif clean_replay["status"] == "CANDIDATE_TIMEOUT":
                status = "CANDIDATE_TIMEOUT"
                failure_attribution = "candidate"
                failure_reasons.append(str(clean_replay.get("failure_reason", "NOMINAL_SIMULATION_EXCEEDED_TIMEOUT")))
            elif clean_replay["status"] == "GENERATION_INFRA_ERROR":
                status = "GENERATION_INFRA_ERROR"
                failure_attribution = "generation_infrastructure"
                failure_reasons.append(str(clean_replay.get("failure_reason", "CLEAN_REPLAY_INFRA_ERROR")))
            else:
                status = "CANDIDATE_INVALID"
                failure_attribution = "candidate"
                failure_reasons.append(
                    "CLEAN_REPLAY_FAILED:" + str(clean_replay.get("failed_phase", "unknown"))
                )
    elif process.status == "CANDIDATE_TIMEOUT":
        failure_attribution = "candidate"
        failure_reasons.append("REAL_SIMULATION_CALL_EXCEEDED_TIMEOUT")
    else:
        failure_attribution = "generation_infrastructure"
        failure_reasons.append(
            "AGENT_TURN_FAILED" if process.terminal_failure else f"AGENT_CLI_EXIT_NONZERO:{process.exit_code}"
        )
    receipt = {
        "schema": "simuverity.generation-receipt.v1",
        "status": status,
        "failure_attribution": failure_attribution,
        "failure_reasons": failure_reasons,
        "task_id": task.task_id,
        "generation_run_id": generation_run_id,
        "agent": adapter.name,
        "model": model,
        "prompt_bytes": len(prompt),
        "simulation_timeout_seconds": simulation_timeout_seconds,
        "simulation_timeout_triggered": process.simulation_timeout,
        "agent_exit_code": process.exit_code,
        "normalized_event_count": process.event_count,
        "observed_matlab_tool_calls": process.observed_matlab_tool_calls,
        "forbidden_tool_calls": list(process.forbidden_tool_calls),
        "trace_parse_errors": process.trace_parse_errors,
        "credential_cleanup_verified": credential_cleanup_verified,
        "clean_replay_status": clean_replay.get("status", "NOT_RUN") if clean_replay else "NOT_RUN",
        "started_at": process.started_at,
        "ended_at": process.ended_at,
        "score_eligible": closure is not None,
        "candidate_file": task.required_model_file if sealed else "",
        "candidate_file_count": sealed["file_count"] if sealed else 0,
    }
    receipt_path = layout.root / "generation_receipt.json"
    write_json_exclusive(receipt_path, receipt)
    result = {**receipt, "receipt_path": str(receipt_path), "run_root": str(layout.root)}
    if sealed:
        result["sealed_submission"] = sealed["sealed_submission"]
        result["sealed_candidate"] = sealed["sealed_candidate"]
    return result


def run_task(
    repository: TaskRepository,
    task_id: str,
    *,
    agent: str,
    model: str,
    mcp_config: Path,
    generations_parent: Path,
    evaluations_parent: Path,
    generation_run_id: str | None = None,
    scoring_run_id: str | None = None,
    source_agent_home: Path | None = None,
    simulation_timeout_seconds: int = 1800,
) -> dict[str, Any]:
    generation = generate_task(
        repository,
        task_id,
        agent=agent,
        model=model,
        mcp_config=mcp_config,
        output_parent=generations_parent,
        generation_run_id=generation_run_id,
        source_agent_home=source_agent_home,
        simulation_timeout_seconds=simulation_timeout_seconds,
    )
    if not generation["score_eligible"]:
        return {"schema": "simuverity.run-result.v1", "generation": generation, "evaluation": None}
    scoring_run_id = scoring_run_id or new_identity("scoring")
    evaluation = evaluate_submission(
        repository.get(task_id),
        submission_root=Path(generation["sealed_submission"]),
        output_parent=evaluations_parent,
        generation_run_id=generation["generation_run_id"],
        scoring_run_id=scoring_run_id,
        simulation_timeout_seconds=simulation_timeout_seconds,
    )
    return {"schema": "simuverity.run-result.v1", "generation": generation, "evaluation": evaluation}

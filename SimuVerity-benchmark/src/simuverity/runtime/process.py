from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Sequence

from ..types import AgentEvent, ProcessResult
from ..adapters.base import is_allowed_matlab_tool


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _reader(stream, channel: str, output: queue.Queue[tuple[str, str | None]]) -> None:
    try:
        for line in iter(stream.readline, ""):
            output.put((channel, line.rstrip("\r\n")))
    finally:
        output.put((channel, None))


def terminate_owned_tree(process: subprocess.Popen[str]) -> None:
    """Terminate only the still-live process tree rooted at this Popen handle."""

    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill.exe", "/F", "/T", "/PID", str(process.pid)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    else:
        process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()


def run_streaming_process(
    command: Sequence[str],
    *,
    cwd: Path,
    environment: dict[str, str],
    stdin_bytes: bytes,
    raw_stdout_path: Path,
    stderr_path: Path,
    normalized_events_path: Path,
    parse_events: Callable[[str], Iterable[AgentEvent]],
    simulation_timeout_seconds: int = 1800,
) -> ProcessResult:
    raw_stdout_path.parent.mkdir(parents=True, exist_ok=True)
    stderr_path.parent.mkdir(parents=True, exist_ok=True)
    normalized_events_path.parent.mkdir(parents=True, exist_ok=True)
    creationflags = 0
    if os.name == "nt":
        creationflags |= getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        creationflags |= getattr(subprocess, "CREATE_NO_WINDOW", 0)
    started_at = utc_now()
    process = subprocess.Popen(
        list(command),
        cwd=cwd,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
    )
    assert process.stdin is not None and process.stdout is not None and process.stderr is not None
    process.stdin.write(stdin_bytes.decode("utf-8"))
    process.stdin.close()
    messages: queue.Queue[tuple[str, str | None]] = queue.Queue()
    threading.Thread(target=_reader, args=(process.stdout, "stdout", messages), daemon=True).start()
    threading.Thread(target=_reader, args=(process.stderr, "stderr", messages), daemon=True).start()
    closed: set[str] = set()
    active_simulations: dict[str, float] = {}
    event_count = 0
    simulation_timeout = False
    terminal_failure = False
    observed_matlab_tool_calls = 0
    forbidden_tool_calls: set[str] = set()
    trace_parse_errors = 0
    with raw_stdout_path.open("w", encoding="utf-8", newline="\n") as raw_out, stderr_path.open(
        "w", encoding="utf-8", newline="\n"
    ) as err_out, normalized_events_path.open("w", encoding="utf-8", newline="\n") as event_out:
        while len(closed) < 2 or process.poll() is None:
            try:
                channel, line = messages.get(timeout=0.2)
            except queue.Empty:
                channel, line = "", ""
            if line is None:
                closed.add(channel)
            elif channel == "stdout":
                raw_out.write(line + "\n")
                raw_out.flush()
                try:
                    json.loads(line)
                except json.JSONDecodeError:
                    trace_parse_errors += 1
                for event in parse_events(line):
                    event_count += 1
                    event_out.write(json.dumps(event.as_dict(), ensure_ascii=False, separators=(",", ":")) + "\n")
                    event_out.flush()
                    if event.simulation and event.call_id and event.event_type == "tool_started":
                        active_simulations[event.call_id] = time.monotonic()
                    if event.event_type == "tool_finished" and event.call_id:
                        active_simulations.pop(event.call_id, None)
                    if event.event_type == "terminal_failed":
                        terminal_failure = True
                    if event.event_type in {"tool_started", "tool_finished"} and (
                        event.event_type == "tool_started" or bool(event.tool_name)
                    ):
                        if is_allowed_matlab_tool(event.tool_name):
                            if event.event_type == "tool_started":
                                observed_matlab_tool_calls += 1
                        else:
                            forbidden_tool_calls.add(event.tool_name or "unknown")
            elif channel == "stderr":
                err_out.write(line + "\n")
                err_out.flush()
            if simulation_timeout_seconds > 0 and any(
                time.monotonic() - began >= simulation_timeout_seconds for began in active_simulations.values()
            ):
                simulation_timeout = True
                terminate_owned_tree(process)
                active_simulations.clear()
        exit_code = process.wait()
    ended_at = utc_now()
    if simulation_timeout:
        status = "CANDIDATE_TIMEOUT"
    elif exit_code == 0 and not terminal_failure:
        status = "COMPLETED"
    else:
        status = "GENERATION_INFRA_ERROR"
    return ProcessResult(
        exit_code=exit_code,
        status=status,
        simulation_timeout=simulation_timeout,
        terminal_failure=terminal_failure,
        observed_matlab_tool_calls=observed_matlab_tool_calls,
        forbidden_tool_calls=tuple(sorted(forbidden_tool_calls)),
        trace_parse_errors=trace_parse_errors,
        event_count=event_count,
        started_at=started_at,
        ended_at=ended_at,
    )

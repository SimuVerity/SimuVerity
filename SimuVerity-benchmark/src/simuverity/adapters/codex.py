from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any, Iterable

from ..errors import ContractError
from ..types import AgentEvent
from .base import (
    MODEL_AND_NETWORK_ENV,
    AgentAdapter,
    AgentRequest,
    is_simulation_call,
    load_mcp_config,
    now_utc,
    text_fragments,
)


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


class CodexAdapter(AgentAdapter):
    name = "codex"

    def prepare(self, request: AgentRequest, environment: dict[str, str]) -> dict[str, str]:
        config = load_mcp_config(request.mcp_config)["mcpServers"]["matlab"]
        configured_home = os.environ.get("CODEX_HOME")
        source = request.source_agent_home or (Path(configured_home) if configured_home else Path.home() / ".codex")
        auth_source = source / "auth.json"
        if auth_source.is_file():
            shutil.copy2(auth_source, request.agent_home / "auth.json")
        rows = ["[mcp_servers.matlab]", f"command = {_toml_string(config['command'])}"]
        args = config.get("args", [])
        if not isinstance(args, list) or not all(isinstance(value, str) for value in args):
            raise ContractError("matlab MCP args must be a string array")
        rows.append("args = [" + ", ".join(_toml_string(value) for value in args) + "]")
        mcp_environment = dict(config.get("env", {}))
        if not all(
                isinstance(key, str) and isinstance(value, str) for key, value in mcp_environment.items()
        ):
            raise ContractError("matlab MCP env must map strings to strings")
        for name in MODEL_AND_NETWORK_ENV:
            mcp_environment[name] = ""
        if mcp_environment:
            rows.append("[mcp_servers.matlab.env]")
            rows.extend(f"{_toml_string(key)} = {_toml_string(value)}" for key, value in sorted(mcp_environment.items()))
        (request.agent_home / "config.toml").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
        child = environment.copy()
        for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL"):
            child.pop(name, None)
        child["CODEX_HOME"] = str(request.agent_home)
        return child

    def command(self, request: AgentRequest) -> list[str]:
        return [
            "codex",
            "exec",
            "--strict-config",
            "--ephemeral",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--json",
            "--color",
            "never",
            "-C",
            str(request.workspace),
            "-m",
            request.model,
            "-s",
            "read-only",
            "-o",
            str(request.last_message_path),
            "-",
        ]

    def parse_events(self, line: str) -> Iterable[AgentEvent]:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            return []
        if not isinstance(row, dict):
            return []
        raw_type = str(row.get("type", ""))
        item = row.get("item") if isinstance(row.get("item"), dict) else row
        item_type = str(item.get("type", ""))
        call_id = str(item.get("id", item.get("call_id", "")))
        tool_name = str(item.get("tool", item.get("name", "")))
        server = str(item.get("server", ""))
        if server and tool_name and not tool_name.startswith(server):
            tool_name = f"{server}.{tool_name}"
        arguments: Any = item.get("arguments", item.get("input", {}))
        timestamp = now_utc()
        if item_type in {"command_execution", "file_change", "web_search", "reasoning"} and item_type != "reasoning":
            native_name = f"native.{item_type}"
            event_type = "tool_started" if raw_type == "item.started" else "tool_finished"
            if raw_type in {"item.started", "item.completed"}:
                return [AgentEvent(event_type, timestamp, call_id=call_id, tool_name=native_name, raw_type=raw_type)]
        if raw_type in {"item.started", "tool.started", "mcp_tool_call.started"} and (
            "tool" in item_type or tool_name
        ):
            return [
                AgentEvent(
                    "tool_started",
                    timestamp,
                    call_id=call_id,
                    tool_name=tool_name,
                    simulation=is_simulation_call(tool_name, arguments),
                    raw_type=raw_type,
                )
            ]
        if raw_type in {"item.completed", "tool.completed", "mcp_tool_call.completed"} and (
            "tool" in item_type or tool_name
        ):
            return [
                AgentEvent(
                    "tool_finished",
                    timestamp,
                    call_id=call_id,
                    tool_name=tool_name,
                    simulation=is_simulation_call(tool_name, arguments),
                    raw_type=raw_type,
                )
            ]
        if raw_type in {"turn.failed", "error"}:
            message = str(row.get("message", row.get("error", "")))
            if raw_type == "error" and any(word in message.lower() for word in ("retry", "rate limit", "429")):
                return [AgentEvent("api_retry", timestamp, text=message, raw_type=raw_type)]
            return [AgentEvent("terminal_failed", timestamp, text=message, raw_type=raw_type)]
        text = str(item.get("text", "")) or text_fragments(item.get("content"))
        if text and item_type in {"agent_message", "message", "assistant_message"}:
            return [AgentEvent("agent_message", timestamp, text=text, raw_type=raw_type)]
        return []

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Iterable, Mapping

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


class ClaudeCodeAdapter(AgentAdapter):
    name = "claude-code"

    def prepare(self, request: AgentRequest, environment: dict[str, str]) -> dict[str, str]:
        config = load_mcp_config(request.mcp_config)
        matlab_environment = dict(config["mcpServers"]["matlab"].get("env", {}))
        for name in MODEL_AND_NETWORK_ENV:
            matlab_environment[name] = ""
        config["mcpServers"]["matlab"]["env"] = matlab_environment
        request.mcp_config.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        configured_home = os.environ.get("CLAUDE_CONFIG_DIR")
        source = request.source_agent_home or (Path(configured_home) if configured_home else Path.home() / ".claude")
        credential = source / ".credentials.json"
        if credential.is_file():
            shutil.copy2(credential, request.claude_config / ".credentials.json")
        child = environment.copy()
        for name in ("OPENAI_API_KEY", "OPENAI_BASE_URL", "AZURE_OPENAI_API_KEY"):
            child.pop(name, None)
        child["CLAUDE_CONFIG_DIR"] = str(request.claude_config)
        return child

    def command(self, request: AgentRequest) -> list[str]:
        command = [
            "claude",
            "-p",
            "--output-format",
            "stream-json",
            "--verbose",
            "--strict-mcp-config",
            "--mcp-config",
            str(request.mcp_config),
            "--model",
            request.model,
            "--permission-mode",
            "bypassPermissions",
            "--dangerously-skip-permissions",
            "--no-session-persistence",
            "--disallowedTools",
            "Bash,Edit,Write,Read,Glob,Grep,WebFetch,WebSearch,Task,NotebookEdit",
        ]
        return command

    def parse_events(self, line: str) -> Iterable[AgentEvent]:
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            return []
        if not isinstance(row, dict):
            return []
        raw_type = str(row.get("type", ""))
        timestamp = now_utc()
        message = row.get("message") if isinstance(row.get("message"), Mapping) else {}
        content = message.get("content", row.get("content", []))
        events: list[AgentEvent] = []
        if isinstance(content, list):
            for item in content:
                if not isinstance(item, Mapping):
                    continue
                item_type = str(item.get("type", ""))
                if item_type == "tool_use":
                    tool_name = str(item.get("name", ""))
                    arguments = item.get("input", {})
                    events.append(
                        AgentEvent(
                            "tool_started",
                            timestamp,
                            call_id=str(item.get("id", "")),
                            tool_name=tool_name,
                            simulation=is_simulation_call(tool_name, arguments),
                            raw_type=raw_type,
                        )
                    )
                elif item_type == "tool_result":
                    tool_name = str(item.get("name", ""))
                    events.append(
                        AgentEvent(
                            "tool_finished",
                            timestamp,
                            call_id=str(item.get("tool_use_id", item.get("id", ""))),
                            tool_name=tool_name,
                            simulation=is_simulation_call(tool_name, item.get("content", "")),
                            raw_type=raw_type,
                        )
                    )
        text = text_fragments(content)
        if text and raw_type == "assistant":
            events.append(AgentEvent("agent_message", timestamp, text=text, raw_type=raw_type))
        if raw_type == "result":
            result_type = "terminal_failed" if row.get("is_error") is True else "terminal"
            events.append(AgentEvent(result_type, timestamp, text=str(row.get("result", "")), raw_type=raw_type))
        return events

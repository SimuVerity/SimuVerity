from __future__ import annotations

import abc
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from ..errors import ContractError
from ..types import AgentEvent

SIMULATION_TOOL_NAMES = {"model_test", "sim", "parsim", "batchsim"}
SIMULATION_COMMAND_RE = re.compile(r"SimulationCommand\s*['\"=:, ]+\s*(?:start|continue|step)\b", re.IGNORECASE)
INDIRECT_SIMULATION_RE = re.compile(r"\b(?:sim|parsim|batchsim)\s*\(", re.IGNORECASE)
SECRET_NAME_RE = re.compile(r"(?:token|secret|password|api[_-]?key|credential)", re.IGNORECASE)
MODEL_AND_NETWORK_ENV = (
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "AZURE_OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_BASE_URL",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
)


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def is_simulation_call(tool_name: str, arguments: Any) -> bool:
    short_name = tool_name.rsplit(".", 1)[-1].rsplit("__", 1)[-1].lower()
    if short_name in SIMULATION_TOOL_NAMES:
        return True
    if short_name in {"set_param", "execute", "matlab_execute", "execute_matlab", "run_matlab"}:
        try:
            text = json.dumps(arguments, ensure_ascii=False, sort_keys=True)
        except TypeError:
            text = str(arguments)
        return bool(SIMULATION_COMMAND_RE.search(text) or INDIRECT_SIMULATION_RE.search(text))
    return False


def is_allowed_matlab_tool(tool_name: str) -> bool:
    normalized = tool_name.strip().lower()
    return normalized.startswith("matlab.") or normalized.startswith("mcp__matlab__")


def load_mcp_config(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        raise ContractError(f"Cannot read MCP configuration: {exc}") from exc
    if not isinstance(value, dict):
        raise ContractError("MCP configuration must be a JSON object")
    servers = value.get("mcpServers", value.get("mcp_servers"))
    if not isinstance(servers, dict) or "matlab" not in servers:
        raise ContractError("MCP configuration must define a matlab server")
    if set(servers) != {"matlab"}:
        raise ContractError("Fail-closed benchmark runs permit exactly one MCP server named matlab")
    matlab = servers["matlab"]
    if not isinstance(matlab, dict) or not isinstance(matlab.get("command"), str):
        raise ContractError("The matlab MCP server must define command")
    for name in matlab.get("env", {}):
        if SECRET_NAME_RE.search(str(name)):
            raise ContractError("Credentials are forbidden in MCP configuration files")
    return {"mcpServers": {"matlab": matlab}}


@dataclass(frozen=True)
class AgentRequest:
    model: str
    workspace: Path
    agent_home: Path
    claude_config: Path
    mcp_config: Path
    last_message_path: Path
    source_agent_home: Path | None = None


class AgentAdapter(abc.ABC):
    name: str

    @abc.abstractmethod
    def prepare(self, request: AgentRequest, environment: dict[str, str]) -> dict[str, str]:
        """Prepare only run-local configuration and return the child environment."""

    @abc.abstractmethod
    def command(self, request: AgentRequest) -> Sequence[str]:
        pass

    @abc.abstractmethod
    def parse_events(self, line: str) -> Iterable[AgentEvent]:
        pass


def get_adapter(name: str) -> AgentAdapter:
    normalized = name.strip().lower().replace("_", "-")
    if normalized == "codex":
        from .codex import CodexAdapter

        return CodexAdapter()
    if normalized in {"claude", "claude-code"}:
        from .claude_code import ClaudeCodeAdapter

        return ClaudeCodeAdapter()
    raise ContractError(f"Unsupported agent adapter: {name}")


def text_fragments(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        values = []
        for item in content:
            if isinstance(item, Mapping) and item.get("type") in {"text", "output_text"}:
                values.append(str(item.get("text", "")))
        return "".join(values)
    return ""

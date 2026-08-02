#!/usr/bin/env python3
"""Validate and eventually measure the ChatNotifier renewal inventories.

Phase 0A implements the finite static guard inventory. Phase 0B adds a finite
telemetry-selection contract without changing production logging. Phase 1
validates immutable private corpus inputs and their effective tool-catalogue
snapshots. Dynamic measurement remains blocked until its own tested slice
completes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import subprocess
import sys
from typing import Any


SCHEMA_NAME = "caverno_chat_notifier_guard_inventory"
SCHEMA_VERSION = 1
ANALYZER_PATH = "tool/analyze_chat_notifier_inventory.py"
DOMAIN_ROOT = pathlib.PurePosixPath("lib/features/chat/domain/services")
NOTIFIER_ROOT = pathlib.PurePosixPath(
    "lib/features/chat/presentation/providers"
)
DISCOVERY_RULES = (
    {
        "id": "domain-guard-policy-recovery-types",
        "root": str(DOMAIN_ROOT),
        "glob": "*.dart",
        "description": (
            "Top-level production types whose names end in Guard, Policy, "
            "or Recovery."
        ),
    },
    {
        "id": "notifier-guard-recovery-members",
        "root": str(NOTIFIER_ROOT),
        "glob": "chat_notifier*.dart",
        "description": (
            "ChatNotifier members whose names contain guard, recovery, or "
            "repair."
        ),
    },
)
TYPE_PATTERN = re.compile(
    r"^(?:(?:abstract|base|final|sealed|interface)\s+)*"
    r"class\s+(\w*(?:Guard|Policy|Recovery))\b",
    re.MULTILINE,
)
MEMBER_PATTERN = re.compile(
    r"^ {2}(?! )(?!class\b)(?:[^\n=;{}]+?\s+)?"
    r"(_\w*(?:Guard|guard|Recovery|recovery|Repair|repair)\w*)\s*\(",
    re.MULTILINE,
)
ENTRY_FIELDS = {
    "id",
    "path",
    "symbol",
    "kind",
    "discoveryRule",
    "selectionRoots",
    "staticEdges",
    "reachabilityImpact",
    "telemetryEvent",
    "currentStaticState",
    "staticProof",
    "unresolvedEdges",
}
EXCLUSION_FIELDS = {
    "id",
    "path",
    "symbol",
    "kind",
    "discoveryRule",
    "reason",
}
TELEMETRY_SELECTION_SCHEMA_NAME = (
    "caverno_chat_notifier_guard_telemetry_selection"
)
TELEMETRY_SELECTION_SCHEMA_VERSION = 1
TELEMETRY_SELECTION_MANIFEST_FIELDS = {
    "schemaName",
    "schemaVersion",
    "sourceRevision",
    "guardManifest",
    "firstSliceLimit",
    "entries",
}
TELEMETRY_SELECTION_COMMON_FIELDS = {
    "id",
    "disposition",
    "question",
    "reason",
}
TELEMETRY_SELECTION_FIELDS = {
    "instrument": TELEMETRY_SELECTION_COMMON_FIELDS
    | {
        "event",
        "recordedValues",
        "dataClassification",
        "verification",
    },
    "covered": TELEMETRY_SELECTION_COMMON_FIELDS
    | {
        "event",
        "recordedValues",
        "dataClassification",
        "verification",
    },
    "defer": TELEMETRY_SELECTION_COMMON_FIELDS | {"prerequisite"},
}
FIRST_TELEMETRY_SLICE_ID = (
    "lib/features/chat/presentation/providers/"
    "chat_notifier_turn_finalization_recovery.dart::"
    "_shouldSkipCompletedToolResultFinalAnswerRecovery"
)
FIRST_TELEMETRY_SLICE_EVENT = (
    "turn_exit.guardDecisions.completedToolResultFinalAnswerRecovery"
)
FIRST_TELEMETRY_SLICE_VALUES = [
    "not_evaluated",
    "skip_recovery",
    "allow_recovery",
]
CORPUS_MANIFEST_SCHEMA_NAME = "caverno_chat_notifier_inventory_corpus"
CORPUS_MANIFEST_SCHEMA_VERSION = 1
CORPUS_SUMMARY_SCHEMA_NAME = "caverno_chat_notifier_inventory_corpus_summary"
CORPUS_SUMMARY_SCHEMA_VERSION = 2
CORPUS_MANIFEST_FIELDS = {
    "schemaName",
    "schemaVersion",
    "files",
}
CORPUS_FILE_FIELDS = {
    "path",
    "sha256",
    "buildRevision",
    "dirty",
    "segments",
}
CORPUS_SEGMENT_FIELDS = {
    "startTimestampInclusive",
    "endTimestampExclusive",
    "configurationFingerprint",
    "catalogueSnapshotPath",
    "catalogueSnapshotSha256",
    "snapshotCaptureCommand",
    "exporterRevision",
}
SESSION_LOG_SCHEMA_NAME = "caverno_llm_session_log_entry"
CATALOGUE_SNAPSHOT_SCHEMA_NAME = "caverno_chat_tool_catalogue_snapshot"
CATALOGUE_SNAPSHOT_SCHEMA_VERSION = 1
CATALOGUE_SNAPSHOT_EXPORTER_REVISION = "1"
CATALOGUE_SNAPSHOT_FIELDS = {
    "schema",
    "version",
    "exporterRevision",
    "capturedAt",
    "build",
    "configurationFingerprint",
    "toolCount",
    "toolDefinitions",
}
CATALOGUE_BUILD_REQUIRED_FIELDS = {"commit", "dirty"}
CATALOGUE_BUILD_OPTIONAL_FIELDS = {"builtAt"}
CATALOGUE_DEFINITION_REQUIRED_FIELDS = {"type", "function"}
SINGLE_TOOL_RESULT_OPERATIONS = {
    "streamWithToolResult",
    "createChatCompletionWithToolResult",
}
BATCH_TOOL_RESULT_OPERATION = "createChatCompletionWithToolResults"
SINGLE_TOOL_RESULT_REQUIRED_FIELDS = {
    "toolCallId",
    "toolName",
    "toolArguments",
    "toolResult",
}
BATCH_TOOL_RESULT_FIELDS = {"id", "name", "arguments", "result"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
FINGERPRINT_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")
GIT_COMMIT_PATTERN = re.compile(r"^[0-9a-fA-F]{4,40}$")
TOOL_MANIFEST_SCHEMA_NAME = "caverno_chat_notifier_tool_catalog_inventory"
TOOL_MANIFEST_SCHEMA_VERSION = 1
TOOL_DEFINITION_LITERAL_PATTERN = re.compile(
    r"['\"]name['\"]\s*:\s*['\"]([a-z][a-z0-9_]*)['\"]"
)
TOOL_NAME_CONSTANT_PATTERN = re.compile(
    r"static const(?: String)? toolName\s*=\s*"
    r"['\"]([a-z][a-z0-9_]*)['\"]"
)
TOOL_HANDLER_NAME_PATTERN = re.compile(r"['\"]([a-z][a-z0-9_]*)['\"]")
STABLE_TOOL_NAME_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
TOOL_DEFINITION_RULES = (
    {
        "id": "ble-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/ble_tools.dart",
        "symbol": "BleTools.allTools",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInBleToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "browser-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_browser_tool_handler.dart",
        "symbol": "BuiltInBrowserToolHandler.definitions",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInBrowserToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "computer-use-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_computer_use_tool_handler.dart",
        "symbol": "BuiltInComputerUseToolHandler.definitions",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInComputerUseToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "filesystem-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_filesystem_tool_definitions.dart",
        "symbol": "BuiltInFilesystemToolDefinitions",
        "matcher": "function-name-literal",
        "configurationGate": "inspection is cross-platform; mutation requires FilesystemTools.isDesktopPlatform; disabledBuiltInTools applies",
    },
    {
        "id": "local-command-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_local_command_tool_definitions.dart",
        "symbol": "BuiltInLocalCommandToolDefinitions",
        "matcher": "function-name-literal",
        "configurationGate": "LocalShellTools.isDesktopPlatform, process capability where applicable, and disabledBuiltInTools",
    },
    {
        "id": "network-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_network_tool_handler.dart",
        "symbol": "BuiltInNetworkToolHandler.definitions",
        "matcher": "function-name-literal",
        "configurationGate": "always registered subject to disabledBuiltInTools; runtime platform support may vary",
    },
    {
        "id": "ssh-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/built_in_ssh_tool_handler.dart",
        "symbol": "BuiltInSshToolHandler.definitions",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInSshToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "lan-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/lan_scan_tools.dart",
        "symbol": "LanScanTools.allTools",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInLanScanToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "goal-routine-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/mcp_goal_routine_tool_definitions.dart",
        "symbol": "McpGoalRoutineToolDefinitions",
        "matcher": "function-name-literal",
        "configurationGate": "always registered subject to disabledBuiltInTools",
    },
    {
        "id": "mcp-service-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/mcp_tool_service.dart",
        "symbol": "McpToolService.getOpenAiToolDefinitions",
        "matcher": "function-name-literal",
        "configurationGate": "McpToolService repository and feature availability plus disabledBuiltInTools",
    },
    {
        "id": "core-built-in-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/mcp_tool_service_builtin_tool_definitions.dart",
        "symbol": "McpToolService built-in definitions",
        "matcher": "function-name-literal",
        "configurationGate": "web_search requires SearXNG without connected MCP; other definitions are always registered; disabledBuiltInTools applies",
    },
    {
        "id": "os-log-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/os_log_tools.dart",
        "symbol": "OsLogTools.allTools",
        "matcher": "function-name-literal",
        "configurationGate": "OsLogTools platform capability and disabledBuiltInTools",
    },
    {
        "id": "python-tool-definition-literal",
        "path": "lib/features/chat/data/datasources/python_script_tools.dart",
        "symbol": "PythonScriptTools.toolDefinition",
        "matcher": "function-name-literal",
        "configurationGate": "scriptRuntimeRegistry is configured and disabledBuiltInTools",
    },
    {
        "id": "serial-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/serial_port_tools.dart",
        "symbol": "SerialPortTools.allTools",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInSerialToolHandler.canExposeDefinitions and disabledBuiltInTools",
    },
    {
        "id": "wifi-tool-definition-literals",
        "path": "lib/features/chat/data/datasources/wifi_tools.dart",
        "symbol": "WifiTools.allTools",
        "matcher": "function-name-literal",
        "configurationGate": "BuiltInWifiToolHandler.isAvailable and disabledBuiltInTools",
    },
    {
        "id": "conversation-search-tool-name",
        "path": "lib/features/chat/data/datasources/conversation_search_tool.dart",
        "symbol": "ConversationSearchTool.definition",
        "matcher": "tool-name-constant",
        "configurationGate": "conversationRepository is configured and disabledBuiltInTools",
    },
    {
        "id": "installed-dependency-tool-name",
        "path": "lib/features/chat/data/datasources/installed_dependency_grounding_service.dart",
        "symbol": "InstalledDependencyGroundingService.toolName",
        "matcher": "tool-name-constant",
        "configurationGate": "always registered subject to disabledBuiltInTools",
    },
    {
        "id": "git-command-tool-name",
        "path": "lib/features/chat/data/datasources/git_execute_command_tool.dart",
        "symbol": "GitExecuteCommandTool.toolDefinition",
        "matcher": "tool-name-constant",
        "configurationGate": "GitTools.isDesktopPlatform and disabledBuiltInTools",
    },
    {
        "id": "git-worktree-tool-name",
        "path": "lib/features/chat/data/datasources/git_finish_worktree_session_tool.dart",
        "symbol": "GitFinishWorktreeSessionTool.toolDefinition",
        "matcher": "tool-name-constant",
        "configurationGate": "GitTools.isDesktopPlatform and disabledBuiltInTools",
    },
    {
        "id": "tool-search-tool-name",
        "path": "lib/features/chat/domain/services/tool_definition_search_service.dart",
        "symbol": "ToolDefinitionSearchService.toolName",
        "matcher": "tool-name-constant",
        "configurationGate": "appended when the effective catalogue is useful for deferred discovery",
    },
)
TOOL_BINDING_RULES = (
    {
        "id": "named-handler-registry",
        "path": "lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart",
        "symbol": "ChatToolHandlerRegistry.fromModules",
        "bindingKind": "named_registry",
    },
    {
        "id": "computer-use-intercept",
        "path": "lib/core/services/macos_computer_use_tool_policy.dart",
        "symbol": "MacosComputerUseToolPolicy.allToolNames",
        "bindingKind": "intercepted_computer_use",
    },
    {
        "id": "browser-intercept",
        "path": "lib/core/services/browser_tool_policy.dart",
        "symbol": "BrowserToolPolicy.allTools",
        "bindingKind": "intercepted_browser",
    },
    {
        "id": "generic-mcp-fallback",
        "path": "lib/features/chat/domain/services/chat_tool_dispatcher.dart",
        "symbol": "ChatToolDispatcher.executeFallbackTool",
        "bindingKind": "generic_mcp_fallback",
    },
)
TOOL_MANIFEST_FIELDS = {
    "schemaName",
    "schemaVersion",
    "sourceRevision",
    "definitionDiscoveryRules",
    "bindingDiscoveryRules",
    "genericFallback",
    "definitions",
}
TOOL_DEFINITION_FIELDS = {
    "name",
    "path",
    "symbol",
    "registrationPath",
    "configurationGate",
    "discoveryEvidence",
    "discoveryRule",
    "bindingKind",
    "bindingSymbol",
    "genericMcpFallback",
}


class InventoryError(ValueError):
    """Raised when checked-in inventory evidence is incomplete or stale."""


def repository_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def _candidate(
    *, path: pathlib.Path, symbol: str, kind: str, discovery_rule: str
) -> dict[str, str]:
    relative = path.as_posix()
    return {
        "id": f"{relative}::{symbol}",
        "path": relative,
        "symbol": symbol,
        "kind": kind,
        "discoveryRule": discovery_rule,
    }


def discover_guard_candidates(root: pathlib.Path) -> list[dict[str, str]]:
    """Return the finite Phase 0A discovery set in deterministic order."""
    candidates: list[dict[str, str]] = []
    domain = root / DOMAIN_ROOT
    for path in sorted(domain.glob("*.dart")):
        relative = path.relative_to(root)
        for match in TYPE_PATTERN.finditer(path.read_text()):
            symbol = match.group(1)
            suffix = next(
                suffix
                for suffix in ("Guard", "Recovery", "Policy")
                if symbol.endswith(suffix)
            )
            candidates.append(
                _candidate(
                    path=relative,
                    symbol=symbol,
                    kind=f"{suffix.lower()}_type",
                    discovery_rule="domain-guard-policy-recovery-types",
                )
            )

    providers = root / NOTIFIER_ROOT
    for path in sorted(providers.glob("chat_notifier*.dart")):
        relative = path.relative_to(root)
        for match in MEMBER_PATTERN.finditer(path.read_text()):
            candidates.append(
                _candidate(
                    path=relative,
                    symbol=match.group(1),
                    kind="notifier_member",
                    discovery_rule="notifier-guard-recovery-members",
                )
            )

    return sorted(candidates, key=lambda item: item["id"])


def _read_required_source(root: pathlib.Path, relative_path: str) -> str:
    path = root / relative_path
    try:
        return path.read_text()
    except OSError as error:
        raise InventoryError(
            f"Could not read tool discovery source {relative_path}: {error}"
        ) from error


def _discover_names_for_rule(
    root: pathlib.Path, rule: dict[str, str]
) -> list[str]:
    text = _read_required_source(root, rule["path"])
    matcher = rule["matcher"]
    pattern = (
        TOOL_DEFINITION_LITERAL_PATTERN
        if matcher == "function-name-literal"
        else TOOL_NAME_CONSTANT_PATTERN
    )
    names = sorted(set(pattern.findall(text)))
    if not names:
        raise InventoryError(
            f"Tool definition rule {rule['id']} discovered no names"
        )
    return names


def discover_static_tool_definitions(
    root: pathlib.Path,
) -> list[dict[str, Any]]:
    """Discover finite built-in and local tool definitions."""
    definitions: list[dict[str, Any]] = []
    seen: dict[str, str] = {}
    for rule in TOOL_DEFINITION_RULES:
        for name in _discover_names_for_rule(root, rule):
            if name in seen:
                raise InventoryError(
                    f"Static tool definition {name} is discovered by both "
                    f"{seen[name]} and {rule['id']}"
                )
            seen[name] = rule["id"]
            definitions.append(
                {
                    "name": name,
                    "path": rule["path"],
                    "symbol": rule["symbol"],
                    "registrationPath": (
                        "McpToolService.getOpenAiToolDefinitions"
                    ),
                    "configurationGate": rule["configurationGate"],
                    "discoveryEvidence": (
                        f"{rule['matcher']} in {rule['path']}"
                    ),
                    "discoveryRule": rule["id"],
                }
            )
    return sorted(definitions, key=lambda item: item["name"])


def _discover_registry_bindings(root: pathlib.Path) -> dict[str, str]:
    rule = TOOL_BINDING_RULES[0]
    text = _read_required_source(root, rule["path"])
    bindings: dict[str, str] = {}
    modules = (
        "_ProjectScopedToolHandlerModule",
        "_OwnerToolHandlerModule",
        "_ConversationToolHandlerModule",
    )
    for module in modules:
        pattern = re.compile(
            rf"final class {re.escape(module)}\b.*?"
            r"Map<String, ChatToolHandler> get handlers => \{(.*?)\n  \};",
            re.DOTALL,
        )
        match = pattern.search(text)
        if match is None:
            raise InventoryError(
                f"Could not discover handlers for production module {module}"
            )
        for name in TOOL_HANDLER_NAME_PATTERN.findall(match.group(1)):
            if name in bindings:
                raise InventoryError(f"Duplicate named tool binding: {name}")
            bindings[name] = module
    return bindings


def _discover_const_set(
    root: pathlib.Path, relative_path: str, symbol: str
) -> set[str]:
    text = _read_required_source(root, relative_path)
    pattern = re.compile(
        rf"static const(?:\s+Set<String>)?\s+{re.escape(symbol)}\s*=\s*"
        r"\{(.*?)\};",
        re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        raise InventoryError(
            f"Could not discover tool-name set {symbol} in {relative_path}"
        )
    return set(TOOL_HANDLER_NAME_PATTERN.findall(match.group(1)))


def discover_static_tool_bindings(
    root: pathlib.Path,
) -> tuple[dict[str, dict[str, str]], dict[str, str]]:
    """Discover named and intercepted bindings plus the generic fallback."""
    bindings: dict[str, dict[str, str]] = {}
    registry_rule = TOOL_BINDING_RULES[0]
    for name, module in _discover_registry_bindings(root).items():
        bindings[name] = {
            "bindingKind": registry_rule["bindingKind"],
            "bindingSymbol": module,
        }

    computer_rule = TOOL_BINDING_RULES[1]
    computer_names = _discover_const_set(
        root, computer_rule["path"], "allToolNames"
    )
    browser_rule = TOOL_BINDING_RULES[2]
    browser_names = _discover_const_set(
        root, browser_rule["path"], "allTools"
    ) | _discover_const_set(root, browser_rule["path"], "sensitiveTools")
    for names, rule in (
        (computer_names, computer_rule),
        (browser_names, browser_rule),
    ):
        for name in names:
            if name in bindings:
                raise InventoryError(f"Tool has multiple static bindings: {name}")
            bindings[name] = {
                "bindingKind": rule["bindingKind"],
                "bindingSymbol": rule["symbol"],
            }

    fallback_rule = TOOL_BINDING_RULES[3]
    fallback_text = _read_required_source(root, fallback_rule["path"])
    if "return executeFallbackTool(toolCall);" not in fallback_text:
        raise InventoryError("Generic MCP fallback binding is not discoverable")
    fallback = {
        "bindingKind": fallback_rule["bindingKind"],
        "bindingSymbol": fallback_rule["symbol"],
        "path": fallback_rule["path"],
        "discoveryEvidence": "return executeFallbackTool(toolCall);",
        "dynamicMcpDefinitions": "private_catalogue_snapshots_only",
    }
    return bindings, fallback


def discover_tool_manifest_entries(root: pathlib.Path) -> dict[str, Any]:
    """Join finite static definitions to their current dispatch binding."""
    definitions = discover_static_tool_definitions(root)
    bindings, fallback = discover_static_tool_bindings(root)
    definition_names = {entry["name"] for entry in definitions}
    unknown_bindings = sorted(set(bindings) - definition_names)
    if unknown_bindings:
        raise InventoryError(
            "Static bindings have no discovered definitions: "
            + ", ".join(unknown_bindings)
        )
    for definition in definitions:
        binding = bindings.get(definition["name"])
        if binding is None:
            binding = {
                "bindingKind": fallback["bindingKind"],
                "bindingSymbol": fallback["bindingSymbol"],
            }
        definition.update(binding)
        definition["genericMcpFallback"] = (
            binding["bindingKind"] == "generic_mcp_fallback"
        )
    return {"genericFallback": fallback, "definitions": definitions}


def build_tool_manifest_candidate(root: pathlib.Path) -> dict[str, Any]:
    """Build the deterministic candidate that maintainers must review."""
    discovered = discover_tool_manifest_entries(root)
    return {
        "schemaName": TOOL_MANIFEST_SCHEMA_NAME,
        "schemaVersion": TOOL_MANIFEST_SCHEMA_VERSION,
        "sourceRevision": "HEAD",
        "definitionDiscoveryRules": [dict(rule) for rule in TOOL_DEFINITION_RULES],
        "bindingDiscoveryRules": [dict(rule) for rule in TOOL_BINDING_RULES],
        **discovered,
    }


def discover_lexical_selection_roots(
    root: pathlib.Path, candidate: dict[str, str]
) -> list[str]:
    """Find non-declaration lexical references for one discovered candidate."""
    symbol = candidate["symbol"]
    declaration_pattern = re.compile(rf"\bclass\s+{re.escape(symbol)}\b")
    member_declaration_pattern = re.compile(
        rf"^ {{2}}(?! ).*\b{re.escape(symbol)}\s*\("
    )
    references: list[str] = []
    chat_root = root / "lib/features/chat"
    for path in sorted(chat_root.rglob("*.dart")):
        for line_number, line in enumerate(path.read_text().splitlines(), 1):
            if symbol not in line:
                continue
            is_declaration = (
                bool(member_declaration_pattern.search(line))
                if candidate["kind"] == "notifier_member"
                else bool(declaration_pattern.search(line))
            )
            if is_declaration:
                continue
            relative = path.relative_to(root).as_posix()
            references.append(f"lexical reference at {relative}:{line_number}")
    return sorted(set(references))


def _load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text())
    except OSError as error:
        raise InventoryError(f"Could not read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise InventoryError(f"Invalid JSON in {path}: {error}") from error
    if not isinstance(decoded, dict):
        raise InventoryError(f"Expected a JSON object in {path}")
    return decoded


def _resolve_private_path(manifest_path: pathlib.Path, value: Any, label: str) -> pathlib.Path:
    if not isinstance(value, str) or not value.strip():
        raise InventoryError(f"{label} must be a non-empty path")
    path = pathlib.Path(value).expanduser()
    if not path.is_absolute():
        path = manifest_path.parent / path
    return path.resolve()


def _validate_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256_PATTERN.fullmatch(value) is None:
        raise InventoryError(f"{label} must be a lowercase SHA-256")
    return value


def _file_sha256(path: pathlib.Path, label: str) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError as error:
        raise InventoryError(f"Could not read {label}: {error}") from error


def _verify_file_hash(path: pathlib.Path, expected: str, label: str) -> None:
    if not path.is_file():
        raise InventoryError(f"{label} does not exist or is not a file")
    if _file_sha256(path, label) != expected:
        raise InventoryError(f"{label} SHA-256 does not match its manifest pin")


def _parse_timestamp(value: Any, label: str) -> dt.datetime:
    if not isinstance(value, str) or not value.strip():
        raise InventoryError(f"{label} must be a non-empty ISO-8601 timestamp")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise InventoryError(f"{label} must be a valid ISO-8601 timestamp") from error
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise InventoryError(f"{label} must include a UTC offset")
    return parsed.astimezone(dt.timezone.utc)


def _format_timestamp(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _canonical_commit(
    root: pathlib.Path,
    revision: Any,
    label: str,
    cache: dict[str, str],
) -> str:
    if (
        not isinstance(revision, str)
        or GIT_COMMIT_PATTERN.fullmatch(revision) is None
    ):
        raise InventoryError(f"{label} must be an unambiguous Git commit hash")
    normalized = revision.lower()
    if normalized not in cache:
        resolved = resolve_source_revision(root, normalized).lower()
        if not resolved.startswith(normalized):
            raise InventoryError(f"{label} does not prefix its resolved commit")
        cache[normalized] = resolved
    return cache[normalized]


def _load_session_records(path: pathlib.Path, label: str) -> list[dict[str, Any]]:
    try:
        lines = path.read_text().splitlines()
    except (OSError, UnicodeError) as error:
        raise InventoryError(f"Could not read {label}: {error}") from error
    if not lines:
        raise InventoryError(f"{label} must contain at least one JSONL record")
    records: list[dict[str, Any]] = []
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            raise InventoryError(f"{label} line {line_number} is blank")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise InventoryError(
                f"{label} line {line_number} is invalid JSON"
            ) from error
        if not isinstance(record, dict):
            raise InventoryError(f"{label} line {line_number} must be an object")
        if record.get("schemaName") != SESSION_LOG_SCHEMA_NAME:
            raise InventoryError(
                f"{label} line {line_number} is not a Caverno session-log entry"
            )
        if not isinstance(record.get("schemaVersion"), int) or record["schemaVersion"] < 2:
            raise InventoryError(
                f"{label} line {line_number} lacks schema-v2 build provenance"
            )
        records.append(record)
    return records


def _load_catalogue_snapshot(path: pathlib.Path, label: str) -> dict[str, Any]:
    try:
        decoded = json.loads(path.read_text())
    except (OSError, UnicodeError) as error:
        raise InventoryError(f"Could not read {label}") from error
    except json.JSONDecodeError as error:
        raise InventoryError(f"{label} is invalid JSON") from error
    if not isinstance(decoded, dict):
        raise InventoryError(f"{label} must be an object")
    return decoded


def _validate_catalogue_snapshot(
    path: pathlib.Path,
    label: str,
    source_root: pathlib.Path,
    expected_commit: str,
    expected_dirty: bool,
    expected_fingerprint: str,
    expected_exporter_revision: str,
    revision_cache: dict[str, str],
) -> dict[str, Any]:
    snapshot = _load_catalogue_snapshot(path, label)
    _require_exact_fields(snapshot, CATALOGUE_SNAPSHOT_FIELDS, label)
    if snapshot["schema"] != CATALOGUE_SNAPSHOT_SCHEMA_NAME:
        raise InventoryError(f"{label}.schema is unsupported")
    version = snapshot["version"]
    if (
        not isinstance(version, int)
        or isinstance(version, bool)
        or version != CATALOGUE_SNAPSHOT_SCHEMA_VERSION
    ):
        raise InventoryError(f"{label}.version is unsupported")

    exporter_revision = snapshot["exporterRevision"]
    if exporter_revision != CATALOGUE_SNAPSHOT_EXPORTER_REVISION:
        raise InventoryError(f"{label}.exporterRevision is unsupported")
    if exporter_revision != expected_exporter_revision:
        raise InventoryError(
            f"{label}.exporterRevision does not match its segment declaration"
        )
    _parse_timestamp(snapshot["capturedAt"], f"{label}.capturedAt")

    build = snapshot["build"]
    if not isinstance(build, dict):
        raise InventoryError(f"{label}.build must be an object")
    _require_fields(build, CATALOGUE_BUILD_REQUIRED_FIELDS, f"{label}.build")
    unexpected_build_fields = sorted(
        build.keys()
        - CATALOGUE_BUILD_REQUIRED_FIELDS
        - CATALOGUE_BUILD_OPTIONAL_FIELDS
    )
    if unexpected_build_fields:
        raise InventoryError(
            f"{label}.build has unexpected fields: "
            + ", ".join(unexpected_build_fields)
        )
    snapshot_commit = _canonical_commit(
        source_root,
        build["commit"],
        f"{label}.build.commit",
        revision_cache,
    )
    if snapshot_commit != expected_commit:
        raise InventoryError(
            f"{label}.build.commit does not match its corpus file declaration"
        )
    snapshot_dirty = build["dirty"]
    if not isinstance(snapshot_dirty, bool):
        raise InventoryError(f"{label}.build.dirty must be a boolean")
    if snapshot_dirty != expected_dirty:
        raise InventoryError(
            f"{label}.build.dirty does not match its corpus file declaration"
        )
    if "builtAt" in build:
        _parse_timestamp(build["builtAt"], f"{label}.build.builtAt")

    fingerprint = snapshot["configurationFingerprint"]
    if (
        not isinstance(fingerprint, str)
        or FINGERPRINT_PATTERN.fullmatch(fingerprint) is None
    ):
        raise InventoryError(
            f"{label}.configurationFingerprint must be a SHA-256 fingerprint"
        )
    if fingerprint != expected_fingerprint:
        raise InventoryError(
            f"{label}.configurationFingerprint does not match its segment declaration"
        )

    definitions = snapshot["toolDefinitions"]
    if not isinstance(definitions, list) or not definitions:
        raise InventoryError(f"{label}.toolDefinitions must be a non-empty list")
    names: list[str] = []
    for index, definition in enumerate(definitions):
        definition_label = f"{label}.toolDefinitions[{index}]"
        if not isinstance(definition, dict):
            raise InventoryError(f"{definition_label} must be an object")
        _require_fields(
            definition,
            CATALOGUE_DEFINITION_REQUIRED_FIELDS,
            definition_label,
        )
        if definition["type"] != "function":
            raise InventoryError(f"{definition_label}.type must be function")
        function = definition["function"]
        if not isinstance(function, dict):
            raise InventoryError(f"{definition_label}.function must be an object")
        name = function.get("name")
        if not isinstance(name, str) or not name.strip():
            raise InventoryError(
                f"{definition_label}.function.name must be non-empty"
            )
        names.append(name)
    if names != sorted(names):
        raise InventoryError(f"{label}.toolDefinitions must be sorted by name")
    if len(names) != len(set(names)):
        raise InventoryError(f"{label}.toolDefinitions names must be unique")

    tool_count = snapshot["toolCount"]
    if (
        not isinstance(tool_count, int)
        or isinstance(tool_count, bool)
        or tool_count != len(definitions)
    ):
        raise InventoryError(
            f"{label}.toolCount must match the toolDefinitions length"
        )
    fingerprint_payload = json.dumps(
        {"toolDefinitions": definitions},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    computed_fingerprint = "sha256:" + hashlib.sha256(
        fingerprint_payload
    ).hexdigest()
    if fingerprint != computed_fingerprint:
        raise InventoryError(
            f"{label}.configurationFingerprint does not match its definitions"
        )
    return {
        "definitionCount": tool_count,
        "definitionNames": frozenset(names),
        "configurationFingerprint": fingerprint,
        "exporterRevision": exporter_revision,
    }


def _extract_tool_result_submissions(
    record: dict[str, Any], label: str
) -> list[tuple[str, str]]:
    operation = record.get("operation")
    if not isinstance(operation, str) or not operation.strip():
        raise InventoryError(f"{label}.operation must be non-empty")
    request = record.get("request")
    result_fields = {
        "toolResults",
        "toolCallId",
        "toolName",
        "toolArguments",
        "toolResult",
    }
    present_result_fields = (
        result_fields & request.keys() if isinstance(request, dict) else set()
    )

    if operation in SINGLE_TOOL_RESULT_OPERATIONS:
        if not isinstance(request, dict):
            raise InventoryError(f"{label}.request must be an object")
        _require_fields(
            request,
            SINGLE_TOOL_RESULT_REQUIRED_FIELDS,
            f"{label}.request",
        )
        if "toolResults" in request:
            raise InventoryError(
                f"{label}.request has an incompatible batch result field"
            )
        call_id = request["toolCallId"]
        name = request["toolName"]
        if not isinstance(call_id, str) or not call_id.strip():
            raise InventoryError(f"{label}.request.toolCallId must be non-empty")
        if not isinstance(name, str) or not name.strip():
            raise InventoryError(f"{label}.request.toolName must be non-empty")
        return [(call_id, name)]

    if operation == BATCH_TOOL_RESULT_OPERATION:
        if not isinstance(request, dict):
            raise InventoryError(f"{label}.request must be an object")
        if present_result_fields - {"toolResults"}:
            raise InventoryError(
                f"{label}.request has incompatible singleton result fields"
            )
        raw_results = request.get("toolResults")
        if not isinstance(raw_results, list) or not raw_results:
            raise InventoryError(
                f"{label}.request.toolResults must be a non-empty list"
            )
        submissions: list[tuple[str, str]] = []
        seen_ids: set[str] = set()
        for index, raw_result in enumerate(raw_results):
            result_label = f"{label}.request.toolResults[{index}]"
            if not isinstance(raw_result, dict):
                raise InventoryError(f"{result_label} must be an object")
            _require_exact_fields(raw_result, BATCH_TOOL_RESULT_FIELDS, result_label)
            call_id = raw_result["id"]
            name = raw_result["name"]
            if not isinstance(call_id, str) or not call_id.strip():
                raise InventoryError(f"{result_label}.id must be non-empty")
            if call_id in seen_ids:
                raise InventoryError(f"{label}.request.toolResults has duplicate IDs")
            seen_ids.add(call_id)
            if not isinstance(name, str) or not name.strip():
                raise InventoryError(f"{result_label}.name must be non-empty")
            submissions.append((call_id, name))
        return submissions

    if present_result_fields:
        raise InventoryError(
            f"{label}.request has tool-result fields for an incompatible operation"
        )
    return []


def validate_corpus_manifest(
    manifest_path: pathlib.Path,
    root: pathlib.Path | None = None,
) -> dict[str, Any]:
    """Validate immutable private corpus inputs without exposing their paths."""
    source_root = root or repository_root()
    manifest = _load_json(manifest_path)
    _require_exact_fields(manifest, CORPUS_MANIFEST_FIELDS, "corpus manifest")
    if manifest["schemaName"] != CORPUS_MANIFEST_SCHEMA_NAME:
        raise InventoryError(f"Unexpected corpus manifest schema in {manifest_path}")
    if manifest["schemaVersion"] != CORPUS_MANIFEST_SCHEMA_VERSION:
        raise InventoryError(
            f"Unsupported corpus manifest version in {manifest_path}"
        )
    raw_files = manifest["files"]
    if not isinstance(raw_files, list) or not raw_files:
        raise InventoryError("Corpus manifest files must be a non-empty list")

    manifest_digest = _file_sha256(manifest_path, "corpus manifest")
    seen_files: set[pathlib.Path] = set()
    seen_snapshots: set[tuple[pathlib.Path, str]] = set()
    revision_cache: dict[str, str] = {}
    represented_builds: set[tuple[str, bool]] = set()
    catalogue_definition_count = 0
    catalogue_fingerprints: set[str] = set()
    catalogue_exporter_revisions: set[str] = set()
    tool_result_submission_count = 0
    observed_catalogue_definitions: set[tuple[int, int, str]] = set()
    record_count = 0
    segment_count = 0
    timestamps: list[dt.datetime] = []

    for file_index, raw_file in enumerate(raw_files):
        file_label = f"files[{file_index}]"
        if not isinstance(raw_file, dict):
            raise InventoryError(f"{file_label} must be an object")
        _require_exact_fields(raw_file, CORPUS_FILE_FIELDS, file_label)
        session_path = _resolve_private_path(
            manifest_path, raw_file["path"], f"{file_label}.path"
        )
        if session_path in seen_files:
            raise InventoryError(f"Duplicate corpus file at {file_label}.path")
        seen_files.add(session_path)
        session_hash = _validate_sha256(
            raw_file["sha256"], f"{file_label}.sha256"
        )
        _verify_file_hash(session_path, session_hash, file_label)
        build_commit = _canonical_commit(
            source_root,
            raw_file["buildRevision"],
            f"{file_label}.buildRevision",
            revision_cache,
        )
        dirty = raw_file["dirty"]
        if not isinstance(dirty, bool):
            raise InventoryError(f"{file_label}.dirty must be a boolean")
        represented_builds.add((build_commit, dirty))

        raw_segments = raw_file["segments"]
        if not isinstance(raw_segments, list) or not raw_segments:
            raise InventoryError(f"{file_label}.segments must be a non-empty list")
        segments: list[dict[str, Any]] = []
        for segment_index, raw_segment in enumerate(raw_segments):
            segment_label = f"{file_label}.segments[{segment_index}]"
            if not isinstance(raw_segment, dict):
                raise InventoryError(f"{segment_label} must be an object")
            _require_exact_fields(raw_segment, CORPUS_SEGMENT_FIELDS, segment_label)
            start = _parse_timestamp(
                raw_segment["startTimestampInclusive"],
                f"{segment_label}.startTimestampInclusive",
            )
            end = _parse_timestamp(
                raw_segment["endTimestampExclusive"],
                f"{segment_label}.endTimestampExclusive",
            )
            if start >= end:
                raise InventoryError(f"{segment_label} must have a positive range")
            if segments and start != segments[-1]["end"]:
                relation = "overlap" if start < segments[-1]["end"] else "gap"
                raise InventoryError(
                    f"{file_label}.segments contain a timestamp {relation}"
                )
            for field in (
                "configurationFingerprint",
                "snapshotCaptureCommand",
                "exporterRevision",
            ):
                value = raw_segment[field]
                if not isinstance(value, str) or not value.strip():
                    raise InventoryError(
                        f"{segment_label}.{field} must be a non-empty string"
                    )
            snapshot_path = _resolve_private_path(
                manifest_path,
                raw_segment["catalogueSnapshotPath"],
                f"{segment_label}.catalogueSnapshotPath",
            )
            snapshot_hash = _validate_sha256(
                raw_segment["catalogueSnapshotSha256"],
                f"{segment_label}.catalogueSnapshotSha256",
            )
            snapshot_pin = (snapshot_path, snapshot_hash)
            if snapshot_pin in seen_snapshots:
                raise InventoryError(
                    f"Duplicate catalogue snapshot pin at {segment_label}"
                )
            seen_snapshots.add(snapshot_pin)
            _verify_file_hash(snapshot_path, snapshot_hash, segment_label)
            snapshot_summary = _validate_catalogue_snapshot(
                snapshot_path,
                f"{segment_label}.catalogueSnapshot",
                source_root,
                build_commit,
                dirty,
                raw_segment["configurationFingerprint"],
                raw_segment["exporterRevision"],
                revision_cache,
            )
            catalogue_definition_count += snapshot_summary["definitionCount"]
            catalogue_fingerprints.add(
                snapshot_summary["configurationFingerprint"]
            )
            catalogue_exporter_revisions.add(
                snapshot_summary["exporterRevision"]
            )
            segments.append(
                {
                    "start": start,
                    "end": end,
                    "index": segment_index,
                    "definitionNames": snapshot_summary["definitionNames"],
                }
            )
            segment_count += 1

        records = _load_session_records(session_path, file_label)
        for line_index, record in enumerate(records, 1):
            record_label = f"{file_label} line {line_index}"
            timestamp = _parse_timestamp(record.get("timestamp"), f"{record_label}.timestamp")
            matching_segments = [
                segment
                for segment in segments
                if segment["start"] <= timestamp < segment["end"]
            ]
            if len(matching_segments) != 1:
                raise InventoryError(
                    f"{record_label} must match exactly one configuration segment"
                )
            matching_segment = matching_segments[0]
            build = record.get("build")
            if not isinstance(build, dict):
                raise InventoryError(f"{record_label}.build must be an object")
            record_commit = _canonical_commit(
                source_root,
                build.get("commit"),
                f"{record_label}.build.commit",
                revision_cache,
            )
            if record_commit != build_commit:
                raise InventoryError(
                    f"{record_label}.build.commit does not match its file declaration"
                )
            if not isinstance(build.get("dirty"), bool):
                raise InventoryError(f"{record_label}.build.dirty must be a boolean")
            if build["dirty"] != dirty:
                raise InventoryError(
                    f"{record_label}.build.dirty does not match its file declaration"
                )
            submissions = _extract_tool_result_submissions(record, record_label)
            for _, tool_name in submissions:
                if tool_name not in matching_segment["definitionNames"]:
                    raise InventoryError(
                        f"{record_label} submits a tool absent from its catalogue snapshot"
                    )
                observed_catalogue_definitions.add(
                    (file_index, matching_segment["index"], tool_name)
                )
            tool_result_submission_count += len(submissions)
            timestamps.append(timestamp)
            record_count += 1

    return {
        "schemaName": CORPUS_SUMMARY_SCHEMA_NAME,
        "schemaVersion": CORPUS_SUMMARY_SCHEMA_VERSION,
        "corpusManifestSha256": manifest_digest,
        "fileCount": len(raw_files),
        "recordCount": record_count,
        "configurationSegmentCount": segment_count,
        "catalogueSnapshotCount": len(seen_snapshots),
        "catalogueDefinitionCount": catalogue_definition_count,
        "catalogueConfigurationFingerprints": sorted(catalogue_fingerprints),
        "catalogueExporterRevisions": sorted(catalogue_exporter_revisions),
        "toolResultSubmissionCount": tool_result_submission_count,
        "observedCatalogueDefinitionCount": len(observed_catalogue_definitions),
        "unobservedCatalogueDefinitionCount": (
            catalogue_definition_count - len(observed_catalogue_definitions)
        ),
        "loggedRange": {
            "startTimestampInclusive": _format_timestamp(min(timestamps)),
            "endTimestampInclusive": _format_timestamp(max(timestamps)),
        },
        "representedBuilds": [
            {"commit": commit, "dirty": dirty}
            for commit, dirty in sorted(represented_builds)
        ],
    }


def _require_fields(
    item: dict[str, Any], required: set[str], label: str
) -> None:
    missing = sorted(required - item.keys())
    if missing:
        raise InventoryError(f"{label} is missing fields: {', '.join(missing)}")


def _require_exact_fields(
    item: dict[str, Any], required: set[str], label: str
) -> None:
    _require_fields(item, required, label)
    unexpected = sorted(item.keys() - required)
    if unexpected:
        raise InventoryError(
            f"{label} has unexpected fields: {', '.join(unexpected)}"
        )


def _validate_string_list(value: Any, label: str) -> None:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise InventoryError(f"{label} must be a list of non-empty strings")


def _candidate_key(item: dict[str, Any]) -> tuple[str, str, str, str]:
    return (
        str(item.get("path", "")),
        str(item.get("symbol", "")),
        str(item.get("kind", "")),
        str(item.get("discoveryRule", "")),
    )


def validate_tool_manifest(
    manifest_path: pathlib.Path,
    root: pathlib.Path | None = None,
    resolved_source_revision: str | None = None,
) -> dict[str, int]:
    """Validate the static tool definition and binding discovery contract."""
    source_root = root or repository_root()
    manifest = _load_json(manifest_path)
    _require_exact_fields(manifest, TOOL_MANIFEST_FIELDS, "tool manifest")
    if manifest["schemaName"] != TOOL_MANIFEST_SCHEMA_NAME:
        raise InventoryError(f"Unexpected tool manifest schema in {manifest_path}")
    if manifest["schemaVersion"] != TOOL_MANIFEST_SCHEMA_VERSION:
        raise InventoryError(
            f"Unsupported tool manifest version in {manifest_path}"
        )
    source_revision = manifest["sourceRevision"]
    if not isinstance(source_revision, str) or not source_revision.strip():
        raise InventoryError("Tool manifest sourceRevision must be non-empty")
    if resolved_source_revision is not None:
        manifest_revision = resolve_source_revision(source_root, source_revision)
        if manifest_revision != resolved_source_revision:
            raise InventoryError(
                "Tool manifest sourceRevision does not match the classified "
                "source revision"
            )
    if manifest["definitionDiscoveryRules"] != list(TOOL_DEFINITION_RULES):
        raise InventoryError(
            "Tool manifest definitionDiscoveryRules do not match the analyser contract"
        )
    if manifest["bindingDiscoveryRules"] != list(TOOL_BINDING_RULES):
        raise InventoryError(
            "Tool manifest bindingDiscoveryRules do not match the analyser contract"
        )

    definitions = manifest["definitions"]
    if not isinstance(definitions, list) or not definitions:
        raise InventoryError("Tool manifest definitions must be a non-empty list")
    names: list[str] = []
    for index, definition in enumerate(definitions):
        label = f"tool manifest definitions[{index}]"
        if not isinstance(definition, dict):
            raise InventoryError(f"{label} must be an object")
        _require_exact_fields(definition, TOOL_DEFINITION_FIELDS, label)
        name = definition["name"]
        if (
            not isinstance(name, str)
            or STABLE_TOOL_NAME_PATTERN.fullmatch(name) is None
        ):
            raise InventoryError(f"{label}.name must be a stable tool name")
        names.append(name)
        for field in (
            "path",
            "symbol",
            "registrationPath",
            "configurationGate",
            "discoveryEvidence",
            "discoveryRule",
            "bindingKind",
            "bindingSymbol",
        ):
            value = definition[field]
            if not isinstance(value, str) or not value.strip():
                raise InventoryError(f"{label}.{field} must be non-empty")
        generic = definition["genericMcpFallback"]
        if not isinstance(generic, bool):
            raise InventoryError(f"{label}.genericMcpFallback must be a boolean")
        if generic != (definition["bindingKind"] == "generic_mcp_fallback"):
            raise InventoryError(
                f"{label}.genericMcpFallback does not match bindingKind"
            )
    if names != sorted(names):
        raise InventoryError("Tool manifest definitions must be sorted by name")
    if len(names) != len(set(names)):
        raise InventoryError("Tool manifest definition names must be unique")

    discovered = discover_tool_manifest_entries(source_root)
    if manifest["genericFallback"] != discovered["genericFallback"]:
        raise InventoryError("Tool manifest generic fallback is stale")
    expected_by_name = {
        definition["name"]: definition
        for definition in discovered["definitions"]
    }
    actual_by_name = {definition["name"]: definition for definition in definitions}
    missing = sorted(set(expected_by_name) - set(actual_by_name))
    stale = sorted(set(actual_by_name) - set(expected_by_name))
    changed = sorted(
        name
        for name in set(expected_by_name) & set(actual_by_name)
        if expected_by_name[name] != actual_by_name[name]
    )
    if missing or stale or changed:
        details = []
        if missing:
            details.append("unrepresented: " + ", ".join(missing))
        if stale:
            details.append("stale: " + ", ".join(stale))
        if changed:
            details.append("changed evidence: " + ", ".join(changed))
        raise InventoryError("Tool manifest discovery mismatch; " + "; ".join(details))

    binding_counts = {
        definition["bindingKind"] for definition in discovered["definitions"]
    }
    return {
        "definitions": len(definitions),
        "bindingKinds": len(binding_counts),
        "genericFallbackDefinitions": sum(
            definition["genericMcpFallback"] for definition in definitions
        ),
    }


def validate_guard_manifest(
    manifest_path: pathlib.Path,
    root: pathlib.Path | None = None,
    resolved_source_revision: str | None = None,
) -> dict[str, int]:
    """Validate schema fields and exact discovery-set coverage."""
    source_root = root or repository_root()
    manifest = _load_json(manifest_path)
    if manifest.get("schemaName") != SCHEMA_NAME:
        raise InventoryError(f"Unexpected guard manifest schema in {manifest_path}")
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise InventoryError(
            f"Unsupported guard manifest version in {manifest_path}"
        )
    if not isinstance(manifest.get("sourceRevision"), str) or not manifest[
        "sourceRevision"
    ].strip():
        raise InventoryError("Guard manifest sourceRevision must be non-empty")
    if resolved_source_revision is not None:
        manifest_revision = resolve_source_revision(
            source_root, manifest["sourceRevision"]
        )
        if manifest_revision != resolved_source_revision:
            raise InventoryError(
                "Guard manifest sourceRevision does not match the classified "
                "source revision"
            )

    roots = manifest.get("auditedSourceRoots")
    expected_roots = [rule["root"] for rule in DISCOVERY_RULES]
    if roots != expected_roots:
        raise InventoryError(
            "Guard manifest auditedSourceRoots do not match the analyser contract"
        )
    if manifest.get("discoveryRules") != list(DISCOVERY_RULES):
        raise InventoryError(
            "Guard manifest discoveryRules do not match the analyser contract"
        )

    entries = manifest.get("entries")
    exclusions = manifest.get("explicitExclusions")
    if not isinstance(entries, list) or not isinstance(exclusions, list):
        raise InventoryError("Guard manifest entries and exclusions must be lists")

    represented: dict[tuple[str, str, str, str], str] = {}
    identifiers: set[str] = set()
    for index, raw in enumerate(entries):
        if not isinstance(raw, dict):
            raise InventoryError(f"entries[{index}] must be an object")
        _require_fields(raw, ENTRY_FIELDS, f"entries[{index}]")
        identifier = raw["id"]
        if not isinstance(identifier, str) or not identifier.strip():
            raise InventoryError(f"entries[{index}].id must be non-empty")
        if identifier in identifiers:
            raise InventoryError(f"Duplicate guard inventory id: {identifier}")
        expected_identifier = f"{raw['path']}::{raw['symbol']}"
        if identifier != expected_identifier:
            raise InventoryError(
                f"entries[{index}].id must be {expected_identifier}"
            )
        identifiers.add(identifier)
        _validate_string_list(
            raw["selectionRoots"], f"entries[{index}].selectionRoots"
        )
        _validate_string_list(raw["staticEdges"], f"entries[{index}].staticEdges")
        _validate_string_list(
            raw["unresolvedEdges"], f"entries[{index}].unresolvedEdges"
        )
        impact = raw["reachabilityImpact"]
        if not isinstance(impact, str) or not impact.strip():
            raise InventoryError(
                f"entries[{index}].reachabilityImpact must be non-empty"
            )
        telemetry = raw["telemetryEvent"]
        if telemetry is not None and (
            not isinstance(telemetry, str) or not telemetry.strip()
        ):
            raise InventoryError(
                f"entries[{index}].telemetryEvent must be null or non-empty"
            )
        static_state = raw["currentStaticState"]
        if static_state not in {"reachable", "unreachable", "unresolved"}:
            raise InventoryError(
                f"entries[{index}].currentStaticState must be reachable, "
                "unreachable, or unresolved"
            )
        static_proof = raw["staticProof"]
        if static_proof is not None and (
            not isinstance(static_proof, str) or not static_proof.strip()
        ):
            raise InventoryError(
                f"entries[{index}].staticProof must be null or non-empty"
            )
        if static_state == "unreachable":
            if static_proof is None:
                raise InventoryError(
                    f"entries[{index}] needs a proof for unreachable state"
                )
            if raw["selectionRoots"]:
                raise InventoryError(
                    f"entries[{index}] cannot be unreachable with selection roots"
                )
            if raw["unresolvedEdges"]:
                raise InventoryError(
                    f"entries[{index}] cannot be unreachable with unresolved edges"
                )
        key = _candidate_key(raw)
        if key in represented:
            raise InventoryError(f"Candidate represented twice: {key[0]}::{key[1]}")
        represented[key] = "entry"

    for index, raw in enumerate(exclusions):
        if not isinstance(raw, dict):
            raise InventoryError(f"explicitExclusions[{index}] must be an object")
        _require_fields(raw, EXCLUSION_FIELDS, f"explicitExclusions[{index}]")
        identifier = raw["id"]
        if not isinstance(identifier, str) or not identifier.strip():
            raise InventoryError(
                f"explicitExclusions[{index}].id must be non-empty"
            )
        if identifier in identifiers:
            raise InventoryError(f"Duplicate guard inventory id: {identifier}")
        expected_identifier = f"{raw['path']}::{raw['symbol']}"
        if identifier != expected_identifier:
            raise InventoryError(
                f"explicitExclusions[{index}].id must be {expected_identifier}"
            )
        identifiers.add(identifier)
        reason = raw["reason"]
        if not isinstance(reason, str) or not reason.strip():
            raise InventoryError(
                f"explicitExclusions[{index}].reason must be non-empty"
            )
        key = _candidate_key(raw)
        if key in represented:
            raise InventoryError(f"Candidate represented twice: {key[0]}::{key[1]}")
        represented[key] = "exclusion"

    discovered = discover_guard_candidates(source_root)
    discovered_keys = {_candidate_key(item) for item in discovered}
    represented_keys = set(represented)
    missing = sorted(discovered_keys - represented_keys)
    stale = sorted(represented_keys - discovered_keys)
    if missing or stale:
        details = []
        if missing:
            details.append(
                "unrepresented: "
                + ", ".join(f"{path}::{symbol}" for path, symbol, _, _ in missing)
            )
        if stale:
            details.append(
                "stale: "
                + ", ".join(f"{path}::{symbol}" for path, symbol, _, _ in stale)
            )
        raise InventoryError("Guard manifest discovery mismatch; " + "; ".join(details))

    discovered_by_key = {_candidate_key(item): item for item in discovered}
    for index, raw in enumerate(entries):
        candidate = discovered_by_key[_candidate_key(raw)]
        expected_roots = discover_lexical_selection_roots(source_root, candidate)
        if raw["selectionRoots"] != expected_roots:
            raise InventoryError(
                f"entries[{index}].selectionRoots are stale for {raw['symbol']}"
            )
        expected_edges = [
            f"{root_name} -> {raw['symbol']}" for root_name in expected_roots
        ]
        if raw["staticEdges"] != expected_edges:
            raise InventoryError(
                f"entries[{index}].staticEdges are stale for {raw['symbol']}"
            )

    return {
        "discovered": len(discovered),
        "entries": len(entries),
        "exclusions": len(exclusions),
    }


def validate_telemetry_selection(
    selection_path: pathlib.Path,
    guard_manifest_path: pathlib.Path,
    root: pathlib.Path | None = None,
    resolved_source_revision: str | None = None,
) -> dict[str, int]:
    """Validate the finite Phase 0B selection against the guard inventory."""
    source_root = root or repository_root()
    validate_guard_manifest(
        guard_manifest_path,
        source_root,
        resolved_source_revision=resolved_source_revision,
    )
    guard_manifest = _load_json(guard_manifest_path)
    selection = _load_json(selection_path)
    _require_exact_fields(
        selection,
        TELEMETRY_SELECTION_MANIFEST_FIELDS,
        "telemetry selection manifest",
    )
    if selection["schemaName"] != TELEMETRY_SELECTION_SCHEMA_NAME:
        raise InventoryError(
            f"Unexpected telemetry selection schema in {selection_path}"
        )
    if selection["schemaVersion"] != TELEMETRY_SELECTION_SCHEMA_VERSION:
        raise InventoryError(
            f"Unsupported telemetry selection version in {selection_path}"
        )
    selection_revision = selection["sourceRevision"]
    if not isinstance(selection_revision, str) or not selection_revision.strip():
        raise InventoryError(
            "Telemetry selection sourceRevision must be non-empty"
        )
    if resolved_source_revision is not None:
        if (
            resolve_source_revision(source_root, selection_revision)
            != resolved_source_revision
        ):
            raise InventoryError(
                "Telemetry selection sourceRevision does not match the "
                "classified source revision"
            )
    elif selection_revision != guard_manifest["sourceRevision"]:
        raise InventoryError(
            "Telemetry selection sourceRevision does not match the guard "
            "manifest revision"
        )

    try:
        expected_guard_path = guard_manifest_path.resolve().relative_to(
            source_root.resolve()
        ).as_posix()
    except ValueError:
        expected_guard_path = guard_manifest_path.name
    if selection["guardManifest"] != expected_guard_path:
        raise InventoryError(
            "Telemetry selection guardManifest does not match the validated "
            "guard manifest"
        )
    first_slice_limit = selection["firstSliceLimit"]
    if (
        not isinstance(first_slice_limit, int)
        or isinstance(first_slice_limit, bool)
        or first_slice_limit != 1
    ):
        raise InventoryError("Telemetry selection firstSliceLimit must be 1")

    raw_entries = selection["entries"]
    if not isinstance(raw_entries, list):
        raise InventoryError("Telemetry selection entries must be a list")
    guard_entries_by_id = {
        entry["id"]: entry for entry in guard_manifest["entries"]
    }
    target_ids = {
        identifier
        for identifier, entry in guard_entries_by_id.items()
        if entry["telemetryEvent"] is None
    }
    selected_ids: set[str] = set()
    disposition_counts = {
        "instrument": 0,
        "covered": 0,
        "defer": 0,
    }
    for index, raw in enumerate(raw_entries):
        label = f"telemetry selection entries[{index}]"
        if not isinstance(raw, dict):
            raise InventoryError(f"{label} must be an object")
        disposition = raw.get("disposition")
        if disposition not in TELEMETRY_SELECTION_FIELDS:
            raise InventoryError(
                f"{label}.disposition must be instrument, covered, or defer"
            )
        _require_exact_fields(
            raw,
            TELEMETRY_SELECTION_FIELDS[disposition],
            label,
        )
        identifier = raw["id"]
        if not isinstance(identifier, str) or not identifier.strip():
            raise InventoryError(f"{label}.id must be non-empty")
        if identifier in selected_ids:
            raise InventoryError(
                f"Duplicate telemetry selection id: {identifier}"
            )
        selected_ids.add(identifier)
        guard_entry = guard_entries_by_id.get(identifier)
        if guard_entry is None:
            raise InventoryError(
                f"Telemetry selection id is stale: {identifier}"
            )
        for field in ("question", "reason"):
            value = raw[field]
            if not isinstance(value, str) or not value.strip():
                raise InventoryError(f"{label}.{field} must be non-empty")

        if disposition in {"instrument", "covered"}:
            event = raw["event"]
            if not isinstance(event, str) or not event.strip():
                raise InventoryError(f"{label}.event must be non-empty")
            _validate_string_list(
                raw["recordedValues"], f"{label}.recordedValues"
            )
            if len(set(raw["recordedValues"])) != len(raw["recordedValues"]):
                raise InventoryError(
                    f"{label}.recordedValues must contain unique values"
                )
            if raw["dataClassification"] != "metadata_only":
                raise InventoryError(
                    f"{label}.dataClassification must be metadata_only"
                )
            _validate_string_list(raw["verification"], f"{label}.verification")
            mapped_event = guard_entry["telemetryEvent"]
            if disposition == "instrument" and mapped_event is not None:
                raise InventoryError(
                    f"{label} cannot instrument an already mapped event"
                )
            if disposition == "covered" and mapped_event != event:
                raise InventoryError(
                    f"{label}.event must match the guard inventory mapping"
                )
        else:
            prerequisite = raw["prerequisite"]
            if not isinstance(prerequisite, str) or not prerequisite.strip():
                raise InventoryError(f"{label}.prerequisite must be non-empty")
            if guard_entry["telemetryEvent"] is not None:
                raise InventoryError(
                    f"{label} cannot defer an already mapped event"
                )
        disposition_counts[disposition] += 1

    missing = sorted(target_ids - selected_ids)
    stale = sorted(selected_ids - set(guard_entries_by_id))
    if missing or stale:
        details = []
        if missing:
            details.append("missing: " + ", ".join(missing))
        if stale:
            details.append("stale: " + ", ".join(stale))
        raise InventoryError(
            "Telemetry selection coverage mismatch; " + "; ".join(details)
        )
    bounded_slice_count = (
        disposition_counts["instrument"] + disposition_counts["covered"]
    )
    if bounded_slice_count != selection["firstSliceLimit"]:
        raise InventoryError(
            "Telemetry selection must contain exactly one instrument or "
            "covered entry"
        )
    first_slice = next(
        entry
        for entry in raw_entries
        if entry["disposition"] in {"instrument", "covered"}
    )
    if first_slice["id"] != FIRST_TELEMETRY_SLICE_ID:
        raise InventoryError(
            "Telemetry selection first bounded entry must be "
            f"{FIRST_TELEMETRY_SLICE_ID}"
        )
    if first_slice["event"] != FIRST_TELEMETRY_SLICE_EVENT:
        raise InventoryError(
            "Telemetry selection first bounded event must be "
            f"{FIRST_TELEMETRY_SLICE_EVENT}"
        )
    if first_slice["recordedValues"] != FIRST_TELEMETRY_SLICE_VALUES:
        raise InventoryError(
            "Telemetry selection first bounded recordedValues must be "
            + ", ".join(FIRST_TELEMETRY_SLICE_VALUES)
        )
    return {
        "selected": len(raw_entries),
        **disposition_counts,
    }


def _git(root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        raise InventoryError(f"git {' '.join(arguments)} failed: {message}")
    return result.stdout.strip()


def resolve_source_revision(root: pathlib.Path, revision: str) -> str:
    return _git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")


def require_clean_source(
    root: pathlib.Path,
    source_revision: str,
    manifest_paths: list[pathlib.Path],
) -> None:
    paths = ["lib/features/chat", ANALYZER_PATH]
    paths.extend(
        str(path.resolve().relative_to(root.resolve()))
        for path in manifest_paths
        if path.exists() and path.resolve().is_relative_to(root.resolve())
    )
    changed = _git(
        root,
        "diff",
        "--name-only",
        source_revision,
        "--",
        *sorted(set(paths)),
    )
    if changed:
        raise InventoryError(
            "Classified source or measurement definitions differ from "
            f"{source_revision}: {', '.join(changed.splitlines())}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source-revision", default="HEAD")
    parser.add_argument("--require-clean-source", action="store_true")
    parser.add_argument("--corpus-manifest", type=pathlib.Path)
    parser.add_argument("--guard-manifest", type=pathlib.Path)
    parser.add_argument("--tool-manifest", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--check-guard-manifest", type=pathlib.Path)
    parser.add_argument("--check-tool-manifest", type=pathlib.Path)
    parser.add_argument("--check-telemetry-selection", type=pathlib.Path)
    parser.add_argument("--check-corpus-manifest", type=pathlib.Path)
    parser.add_argument("--print-guard-candidates", action="store_true")
    parser.add_argument("--print-tool-candidates", action="store_true")
    return parser


def main(arguments: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(arguments)
    root = repository_root()
    try:
        revision = resolve_source_revision(root, args.source_revision)
        manifests = [
            path
            for path in (
                args.guard_manifest,
                args.tool_manifest,
                args.check_guard_manifest,
                args.check_tool_manifest,
                args.check_telemetry_selection,
            )
            if path is not None
        ]
        if args.require_clean_source:
            require_clean_source(root, revision, manifests)

        if args.print_guard_candidates:
            print(json.dumps(discover_guard_candidates(root), indent=2))
            return 0
        if args.print_tool_candidates:
            print(json.dumps(build_tool_manifest_candidate(root), indent=2))
            return 0

        guard_path = args.check_guard_manifest or args.guard_manifest
        if guard_path is not None:
            counts = validate_guard_manifest(
                guard_path,
                root,
                resolved_source_revision=revision,
            )
            print(
                "Guard manifest valid: "
                f"{counts['discovered']} discovered, "
                f"{counts['entries']} entries, "
                f"{counts['exclusions']} exclusions; source {revision}"
            )

        if args.check_tool_manifest is not None:
            counts = validate_tool_manifest(
                args.check_tool_manifest,
                root,
                resolved_source_revision=revision,
            )
            print(
                "Tool manifest valid: "
                f"{counts['definitions']} definitions, "
                f"{counts['bindingKinds']} binding kinds, "
                f"{counts['genericFallbackDefinitions']} generic fallback "
                f"definitions; source {revision}"
            )
        if args.check_telemetry_selection is not None:
            if guard_path is None:
                raise InventoryError(
                    "--check-telemetry-selection requires --guard-manifest"
                )
            counts = validate_telemetry_selection(
                args.check_telemetry_selection,
                guard_path,
                root,
                resolved_source_revision=revision,
            )
            print(
                "Telemetry selection valid: "
                f"{counts['selected']} selected, "
                f"{counts['instrument']} instrument, "
                f"{counts['covered']} covered, "
                f"{counts['defer']} defer; source {revision}"
            )
        if args.check_corpus_manifest is not None:
            summary = validate_corpus_manifest(
                args.check_corpus_manifest,
                root,
            )
            print(json.dumps(summary, sort_keys=True, separators=(",", ":")))
        if args.corpus_manifest is not None or args.output is not None:
            raise InventoryError(
                "Dynamic corpus analysis is not implemented; validate the "
                "private input with --check-corpus-manifest first"
            )
        if (
            guard_path is None
            and args.check_tool_manifest is None
            and args.check_telemetry_selection is None
            and args.check_corpus_manifest is None
        ):
            parser.error("select a manifest check or candidate print command")
        return 0
    except InventoryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

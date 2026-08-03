#!/usr/bin/env python3
"""Select and measure a bounded ChatNotifier TurnRuntime prototype."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any


AUDIT_SCHEMA_NAME = "caverno_chat_notifier_turn_scope_audit"
AUDIT_SCHEMA_VERSION = 1
MANIFEST_SCHEMA_NAME = "caverno_chat_notifier_decomposition_manifest"
MANIFEST_SCHEMA_VERSION = 1
SELECTION_SCHEMA_NAME = "caverno_chat_notifier_turn_runtime_prototype_candidate"
SELECTION_SCHEMA_VERSION = 1
VERIFICATION_SCHEMA_NAME = (
    "caverno_chat_notifier_turn_runtime_prototype_verification"
)
VERIFICATION_SCHEMA_VERSION = 1
VALIDATED_SELECTION_SCHEMA_NAME = (
    "caverno_chat_notifier_turn_runtime_prototype_validated_selection"
)
VALIDATED_SELECTION_SCHEMA_VERSION = 1
COMPARISON_SCHEMA_NAME = (
    "caverno_chat_notifier_turn_runtime_prototype_comparison"
)
COMPARISON_SCHEMA_VERSION = 1
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
EXPLICIT_TURN_IDENTITY_PATTERN = re.compile(
    r"\bChatTurnOwner\??\b|\b(?:interactionGeneration|generation)\b"
)
PROVIDER_ROOT = pathlib.PurePosixPath(
    "lib/features/chat/presentation/providers"
)


class SelectionError(Exception):
    """Raised when prototype selection inputs are invalid or inconsistent."""


def repository_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def _git(root: pathlib.Path, *arguments: str, strip: bool = True) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        raise SelectionError(f"git {' '.join(arguments)} failed: {message}")
    # Porcelain status encodes the index state in column 1 and the worktree
    # state in column 2, so a worktree-only change begins with a space that
    # stripping would eat along with the newline, shifting the fixed-width
    # path offset by one for the first entry only.
    return result.stdout.strip() if strip else result.stdout


def resolve_source_revision(root: pathlib.Path, revision: str) -> str:
    resolved = _git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    head = _git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if resolved != head:
        raise SelectionError(
            "Source revision must resolve to the checked-out HEAD commit"
        )
    return resolved


def require_clean_worktree(root: pathlib.Path) -> None:
    changed = _git(
        root, "status", "--porcelain", "--untracked-files=all", strip=False
    )
    lines = [line for line in changed.splitlines() if line.strip()]
    if lines:
        paths = [line[3:] if len(line) > 3 else line for line in lines]
        raise SelectionError(
            "Prototype selection requires a clean worktree: "
            + ", ".join(sorted(paths))
        )


def _load_json(path: pathlib.Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError as error:
        raise SelectionError(f"{label} does not exist: {path}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise SelectionError(f"Could not read {label}: {error}") from error
    if not isinstance(value, dict):
        raise SelectionError(f"{label} must be a JSON object")
    return value


def _require_schema(
    value: dict[str, Any],
    *,
    label: str,
    schema_name: str,
    schema_version: int,
) -> None:
    if value.get("schemaName") != schema_name:
        raise SelectionError(f"{label} schemaName must be {schema_name}")
    if value.get("schemaVersion") != schema_version:
        raise SelectionError(f"{label} schemaVersion must be {schema_version}")


def _require_list(value: Any, context: str) -> list[Any]:
    if not isinstance(value, list):
        raise SelectionError(f"{context} must be a list")
    return value


def _require_object(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SelectionError(f"{context} must be an object")
    return value


def _require_string(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SelectionError(f"{context} must be a non-empty string")
    return value


def _unique_objects_by_string(
    values: list[Any], *, key: str, context: str
) -> dict[str, dict[str, Any]]:
    indexed: dict[str, dict[str, Any]] = {}
    for index, raw_value in enumerate(values):
        value = _require_object(raw_value, f"{context}[{index}]")
        identity = _require_string(value.get(key), f"{context}[{index}].{key}")
        if identity in indexed:
            raise SelectionError(f"{context} contains duplicate {key}: {identity}")
        indexed[identity] = value
    return indexed


def _display_path(root: pathlib.Path, path: pathlib.Path) -> str:
    resolved_root = root.resolve()
    resolved_path = path.resolve()
    try:
        return resolved_path.relative_to(resolved_root).as_posix()
    except ValueError:
        return resolved_path.as_posix()


def _sha256(path: pathlib.Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise SelectionError(f"Could not hash input {path}: {error}") from error


def _validate_part_path(part_path: str) -> pathlib.PurePosixPath:
    parsed = pathlib.PurePosixPath(part_path)
    if (
        parsed.name != part_path
        or not part_path.startswith("chat_notifier_")
        or not part_path.endswith(".dart")
    ):
        raise SelectionError(f"Invalid current part path: {part_path}")
    return PROVIDER_ROOT / parsed


def _production_line_count(path: pathlib.Path) -> int:
    try:
        return len(path.read_text().splitlines())
    except FileNotFoundError as error:
        raise SelectionError(f"Current part source does not exist: {path}") from error
    except OSError as error:
        raise SelectionError(
            f"Could not read current part source {path}: {error}"
        ) from error


def _is_explicit_turn_identity_parameter(parameter: str) -> bool:
    return EXPLICIT_TURN_IDENTITY_PATTERN.search(parameter) is not None


def _candidate_rows(
    *,
    root: pathlib.Path,
    audit: dict[str, Any],
    manifest: dict[str, Any],
) -> list[dict[str, Any]]:
    current_parts = _unique_objects_by_string(
        _require_list(audit.get("entrypoints"), "audit.entrypoints"),
        key="partPath",
        context="audit.entrypoints",
    )
    if not current_parts:
        raise SelectionError("audit.entrypoints must not be empty")

    manifest_parts = _unique_objects_by_string(
        _require_list(manifest.get("parts"), "manifest.parts"),
        key="partPath",
        context="manifest.parts",
    )
    methods = _require_list(audit.get("methods"), "audit.methods")
    reads = _require_list(audit.get("reads"), "audit.reads")

    methods_by_identity: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for index, raw_method in enumerate(methods):
        method = _require_object(raw_method, f"audit.methods[{index}]")
        path = _require_string(method.get("path"), f"audit.methods[{index}].path")
        declaration = _require_string(
            method.get("declaration"), f"audit.methods[{index}].declaration"
        )
        methods_by_identity.setdefault((path, declaration), []).append(method)

    reads_by_path: dict[str, list[dict[str, Any]]] = {}
    for index, raw_read in enumerate(reads):
        read = _require_object(raw_read, f"audit.reads[{index}]")
        path = _require_string(read.get("path"), f"audit.reads[{index}].path")
        if not isinstance(read.get("turnReachable"), bool):
            raise SelectionError(
                f"audit.reads[{index}].turnReachable must be a boolean"
            )
        reads_by_path.setdefault(path, []).append(read)

    candidates: list[dict[str, Any]] = []
    for part_path, current_part in current_parts.items():
        manifest_part = manifest_parts.get(part_path)
        if manifest_part is None:
            raise SelectionError(
                f"Current audit part is missing from manifest: {part_path}"
            )
        source_relative = _validate_part_path(part_path).as_posix()
        source_path = root / source_relative
        production_lines = _production_line_count(source_path)

        declarations = _require_list(
            current_part.get("declarations"),
            f"audit entrypoints for {part_path}.declarations",
        )
        declaration_names: list[str] = []
        for index, raw_declaration in enumerate(declarations):
            declaration_names.append(
                _require_string(
                    raw_declaration,
                    f"audit entrypoints for {part_path}.declarations[{index}]",
                )
            )
        if len(declaration_names) != len(set(declaration_names)):
            raise SelectionError(
                f"Current audit part contains duplicate declarations: {part_path}"
            )

        manifest_declarations = _require_list(
            manifest_part.get("entrypoints"),
            f"manifest part {part_path}.entrypoints",
        )
        if declaration_names != manifest_declarations:
            raise SelectionError(
                f"Current audit entrypoints do not match manifest part: {part_path}"
            )

        identity_entrypoints: list[str] = []
        resolved_entrypoints: list[str] = []
        unresolved_entrypoints: list[str] = []
        for declaration in declaration_names:
            matching_methods = methods_by_identity.get(
                (source_relative, declaration), []
            )
            if not matching_methods:
                unresolved_entrypoints.append(declaration)
                continue
            if len(matching_methods) != 1:
                raise SelectionError(
                    "Current entrypoint must join to exactly one audited method: "
                    f"{part_path}::{declaration}"
                )
            method = matching_methods[0]
            if method.get("entrypoint") is not True:
                raise SelectionError(
                    f"Audited method is not marked as an entrypoint: "
                    f"{part_path}::{declaration}"
                )
            resolved_entrypoints.append(declaration)
            if not isinstance(method.get("turnReachable"), bool):
                raise SelectionError(
                    f"Audited method turnReachable must be a boolean: "
                    f"{part_path}::{declaration}"
                )
            parameters = _require_list(
                method.get("turnIdentityParameters"),
                f"audited method {part_path}::{declaration}.turnIdentityParameters",
            )
            for parameter_index, parameter in enumerate(parameters):
                _require_string(
                    parameter,
                    "audited method "
                    f"{part_path}::{declaration}.turnIdentityParameters"
                    f"[{parameter_index}]",
                )
            if method["turnReachable"] and any(
                _is_explicit_turn_identity_parameter(parameter)
                for parameter in parameters
            ):
                identity_entrypoints.append(declaration)

        ambient_reads = [
            read
            for read in reads_by_path.get(source_relative, [])
            if read["turnReachable"]
        ]
        ambient_read_ids = sorted(
            _require_string(read.get("id"), f"ambient read in {part_path}.id")
            for read in ambient_reads
        )
        candidates.append(
            {
                "partPath": part_path,
                "sourcePath": source_relative,
                "declaredEntrypoints": len(declaration_names),
                "resolvedEntrypoints": len(resolved_entrypoints),
                "unresolvedEntrypoints": sorted(unresolved_entrypoints),
                "turnReachableIdentityEntrypoints": {
                    "count": len(identity_entrypoints),
                    "declarations": sorted(identity_entrypoints),
                },
                "turnReachableAmbientReads": {
                    "count": len(ambient_read_ids),
                    "ids": ambient_read_ids,
                },
                "productionLines": production_lines,
            }
        )

    candidates.sort(
        key=lambda candidate: (
            -candidate["turnReachableIdentityEntrypoints"]["count"],
            -candidate["turnReachableAmbientReads"]["count"],
            -candidate["productionLines"],
            candidate["partPath"],
        )
    )
    return [
        {"rank": index, **candidate}
        for index, candidate in enumerate(candidates, start=1)
    ]


def build_selection(
    *,
    root: pathlib.Path,
    audit_path: pathlib.Path,
    manifest_path: pathlib.Path,
    source_revision: str,
    require_clean: bool,
) -> dict[str, Any]:
    root = root.resolve()
    audit_path = audit_path.resolve()
    manifest_path = manifest_path.resolve()
    resolved_revision = resolve_source_revision(root, source_revision)
    if require_clean:
        require_clean_worktree(root)

    audit = _load_json(audit_path, "Turn-scope audit")
    manifest = _load_json(manifest_path, "Decomposition manifest")
    _require_schema(
        audit,
        label="Turn-scope audit",
        schema_name=AUDIT_SCHEMA_NAME,
        schema_version=AUDIT_SCHEMA_VERSION,
    )
    _require_schema(
        manifest,
        label="Decomposition manifest",
        schema_name=MANIFEST_SCHEMA_NAME,
        schema_version=MANIFEST_SCHEMA_VERSION,
    )
    expected_manifest_path = _display_path(root, manifest_path)
    if audit.get("manifestPath") != expected_manifest_path:
        raise SelectionError(
            "Turn-scope audit manifestPath does not match the selected manifest"
        )

    candidates = _candidate_rows(root=root, audit=audit, manifest=manifest)
    return {
        "schemaName": SELECTION_SCHEMA_NAME,
        "schemaVersion": SELECTION_SCHEMA_VERSION,
        "sourceRevision": resolved_revision,
        "inputs": {
            "audit": {
                "path": _display_path(root, audit_path),
                "sha256": _sha256(audit_path),
            },
            "manifest": {
                "path": expected_manifest_path,
                "sha256": _sha256(manifest_path),
            },
        },
        "ranking": [
            "turnReachableIdentityEntrypoints:descending",
            "turnReachableAmbientReads:descending",
            "productionLines:descending",
            "partPath:ascending",
        ],
        "selected": candidates[0],
        "candidates": candidates,
    }


def _repository_file(
    root: pathlib.Path, relative_path: str, context: str
) -> pathlib.Path:
    parsed = pathlib.PurePosixPath(relative_path)
    if (
        parsed.is_absolute()
        or ".." in parsed.parts
        or parsed.as_posix() != relative_path
    ):
        raise SelectionError(f"{context} must be a repository-relative path")
    path = root / parsed
    if not path.is_file():
        raise SelectionError(f"{context} does not exist: {relative_path}")
    return path


def _require_unique_strings(value: Any, context: str) -> list[str]:
    values = _require_list(value, context)
    strings = [
        _require_string(item, f"{context}[{index}]")
        for index, item in enumerate(values)
    ]
    if not strings:
        raise SelectionError(f"{context} must not be empty")
    if len(strings) != len(set(strings)):
        raise SelectionError(f"{context} must contain unique values")
    return strings


def _validate_selection_inputs(
    root: pathlib.Path, selection: dict[str, Any]
) -> dict[str, pathlib.Path]:
    inputs = _require_object(selection.get("inputs"), "selection.inputs")
    paths: dict[str, pathlib.Path] = {}
    for name in ("audit", "manifest"):
        binding = _require_object(
            inputs.get(name), f"selection.inputs.{name}"
        )
        relative_path = _require_string(
            binding.get("path"), f"selection.inputs.{name}.path"
        )
        expected_sha256 = _require_string(
            binding.get("sha256"), f"selection.inputs.{name}.sha256"
        )
        if SHA256_PATTERN.fullmatch(expected_sha256) is None:
            raise SelectionError(
                f"selection.inputs.{name}.sha256 must be a SHA-256 digest"
            )
        path = _repository_file(
            root, relative_path, f"selection.inputs.{name}.path"
        )
        if _sha256(path) != expected_sha256:
            raise SelectionError(f"Selection {name} input hash does not match")
        paths[name] = path
    return paths


def _validate_expected_evidence(
    *, root: pathlib.Path, value: Any, context: str
) -> list[dict[str, Any]]:
    entries = _require_list(value, context)
    if not entries:
        raise SelectionError(f"{context} must not be empty")
    validated: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for index, raw_entry in enumerate(entries):
        entry_context = f"{context}[{index}]"
        entry = _require_object(raw_entry, entry_context)
        evidence_id = _require_string(entry.get("id"), f"{entry_context}.id")
        if evidence_id in seen_ids:
            raise SelectionError(f"{context} contains duplicate id: {evidence_id}")
        seen_ids.add(evidence_id)
        description = _require_string(
            entry.get("description"), f"{entry_context}.description"
        )
        source_path = _require_string(
            entry.get("sourcePath"), f"{entry_context}.sourcePath"
        )
        required_text = _require_unique_strings(
            entry.get("requiredText"), f"{entry_context}.requiredText"
        )
        source = _repository_file(
            root, source_path, f"{entry_context}.sourcePath"
        ).read_text()
        for token in required_text:
            if token.strip().lower() in {"todo", "tbd", "placeholder"}:
                raise SelectionError(
                    f"{entry_context}.requiredText contains placeholder evidence"
                )
            if token not in source:
                raise SelectionError(
                    f"Evidence text for {evidence_id} is missing from {source_path}: "
                    f"{token}"
                )
        validated.append(
            {
                "id": evidence_id,
                "description": description,
                "sourcePath": source_path,
                "requiredText": required_text,
            }
        )
    return validated


def _validate_gate(
    *,
    root: pathlib.Path,
    gate: dict[str, Any],
    context: str,
    path_fields: tuple[str, ...],
) -> dict[str, Any]:
    command = _require_string(gate.get("command"), f"{context}.command")
    test_name = _require_string(gate.get("testName"), f"{context}.testName")
    contract = _require_string(gate.get("contract"), f"{context}.contract")
    paths: dict[str, str] = {}
    for field in path_fields:
        relative_path = _require_string(
            gate.get(field), f"{context}.{field}"
        )
        _repository_file(root, relative_path, f"{context}.{field}")
        paths[field] = relative_path
    evidence = _validate_expected_evidence(
        root=root,
        value=gate.get("expectedEvidence"),
        context=f"{context}.expectedEvidence",
    )
    return {
        "command": command,
        **paths,
        "testName": test_name,
        "contract": contract,
        "expectedEvidence": evidence,
    }


def validate_gates(
    *,
    root: pathlib.Path,
    selection_path: pathlib.Path,
    verification_manifest_path: pathlib.Path,
) -> dict[str, Any]:
    root = root.resolve()
    selection_path = selection_path.resolve()
    verification_manifest_path = verification_manifest_path.resolve()
    require_clean_worktree(root)
    selection = _load_json(selection_path, "Prototype selection")
    verification = _load_json(
        verification_manifest_path, "Prototype verification manifest"
    )
    _require_schema(
        selection,
        label="Prototype selection",
        schema_name=SELECTION_SCHEMA_NAME,
        schema_version=SELECTION_SCHEMA_VERSION,
    )
    _require_schema(
        verification,
        label="Prototype verification manifest",
        schema_name=VERIFICATION_SCHEMA_NAME,
        schema_version=VERIFICATION_SCHEMA_VERSION,
    )
    source_revision = _require_string(
        selection.get("sourceRevision"), "selection.sourceRevision"
    )
    if COMMIT_PATTERN.fullmatch(source_revision) is None:
        raise SelectionError("selection.sourceRevision must be a full Git SHA")
    resolve_source_revision(root, source_revision)
    selection_inputs = _validate_selection_inputs(root, selection)
    rebuilt_selection = build_selection(
        root=root,
        audit_path=selection_inputs["audit"],
        manifest_path=selection_inputs["manifest"],
        source_revision=source_revision,
        require_clean=False,
    )
    if selection != rebuilt_selection:
        raise SelectionError(
            "Prototype selection does not match the current audited ranking"
        )

    selected = _require_object(selection.get("selected"), "selection.selected")
    selected_part_path = _require_string(
        selected.get("partPath"), "selection.selected.partPath"
    )
    selected_source_path = _require_string(
        selected.get("sourcePath"), "selection.selected.sourcePath"
    )
    selected_source = _repository_file(
        root, selected_source_path, "selection.selected.sourcePath"
    ).read_text()
    selected_identity = _require_object(
        selected.get("turnReachableIdentityEntrypoints"),
        "selection.selected.turnReachableIdentityEntrypoints",
    )
    selected_declarations = set(
        _require_unique_strings(
            selected_identity.get("declarations"),
            "selection.selected.turnReachableIdentityEntrypoints.declarations",
        )
    )

    selected_part = _require_object(
        verification.get("selectedPart"), "verification.selectedPart"
    )
    manifest_part_path = _require_string(
        selected_part.get("partPath"), "verification.selectedPart.partPath"
    )
    manifest_source_path = _require_string(
        selected_part.get("sourcePath"), "verification.selectedPart.sourcePath"
    )
    if manifest_part_path != selected_part_path:
        raise SelectionError(
            "Verification manifest part does not match the selected part"
        )
    if manifest_source_path != selected_source_path:
        raise SelectionError(
            "Verification manifest source does not match the selected source"
        )
    migrated_symbols = _require_unique_strings(
        selected_part.get("migratedPathSymbols"),
        "verification.selectedPart.migratedPathSymbols",
    )
    for symbol in migrated_symbols:
        if symbol not in selected_declarations:
            raise SelectionError(
                f"Migrated-path symbol is not a selected identity entrypoint: {symbol}"
            )
        if symbol not in selected_source:
            raise SelectionError(
                f"Migrated-path symbol is missing from selected source: {symbol}"
            )

    focused = _validate_gate(
        root=root,
        gate=_require_object(
            verification.get("focusedTest"), "verification.focusedTest"
        ),
        context="verification.focusedTest",
        path_fields=("executablePath", "declarationPath"),
    )
    if focused["executablePath"] not in focused["command"]:
        raise SelectionError("Focused-test command must name its executable path")
    if (
        "--plain-name" not in focused["command"]
        or focused["testName"] not in focused["command"]
    ):
        raise SelectionError("Focused-test command must name its exact test")
    focused_declaration = _repository_file(
        root,
        focused["declarationPath"],
        "verification.focusedTest.declarationPath",
    ).read_text()
    if focused["testName"] not in focused_declaration:
        raise SelectionError("Focused test name is missing from its declaration source")

    live = _validate_gate(
        root=root,
        gate=_require_object(
            verification.get("liveCanary"), "verification.liveCanary"
        ),
        context="verification.liveCanary",
        path_fields=("runnerPath", "testPath"),
    )
    if live["runnerPath"] not in live["command"]:
        raise SelectionError("Live-canary command must name its runner path")
    runner_source = _repository_file(
        root, live["runnerPath"], "verification.liveCanary.runnerPath"
    ).read_text()
    if live["testPath"] not in runner_source or live["testName"] not in runner_source:
        raise SelectionError(
            "Live-canary runner must name its test path and exact test"
        )
    live_test_source = _repository_file(
        root, live["testPath"], "verification.liveCanary.testPath"
    ).read_text()
    if live["testName"] not in live_test_source:
        raise SelectionError("Live-canary test name is missing from its test source")

    validated_verification = {
        "selectedPart": {
            "partPath": manifest_part_path,
            "sourcePath": manifest_source_path,
            "migratedPathSymbols": migrated_symbols,
        },
        "focusedTest": focused,
        "liveCanary": live,
    }
    return {
        "schemaName": VALIDATED_SELECTION_SCHEMA_NAME,
        "schemaVersion": VALIDATED_SELECTION_SCHEMA_VERSION,
        "sourceRevision": source_revision,
        "selection": {
            "path": _display_path(root, selection_path),
            "sha256": _sha256(selection_path),
        },
        "verificationManifest": {
            "path": _display_path(root, verification_manifest_path),
            "sha256": _sha256(verification_manifest_path),
        },
        "selected": selected,
        "verification": validated_verification,
        "liveCanaryExecuted": False,
    }


def _resolve_commit(root: pathlib.Path, revision: str, context: str) -> str:
    resolved = _git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    if COMMIT_PATTERN.fullmatch(resolved) is None:
        raise SelectionError(f"{context} must resolve to a full Git SHA")
    return resolved


def _require_ancestor(
    root: pathlib.Path, ancestor: str, descendant: str, context: str
) -> None:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 1:
        raise SelectionError(context)
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        raise SelectionError(f"Could not compare revisions: {message}")


def _is_ancestor(root: pathlib.Path, ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode in {0, 1}:
        return result.returncode == 0
    message = result.stderr.strip() or result.stdout.strip()
    raise SelectionError(f"Could not compare revisions: {message}")


def _git_source(root: pathlib.Path, revision: str, relative_path: str) -> str:
    return _git(root, "show", f"{revision}:{relative_path}", strip=False)


def _is_generated_lib_path(relative_path: str) -> bool:
    return relative_path.endswith((".g.dart", ".freezed.dart"))


def _changed_production_paths(
    root: pathlib.Path, before_revision: str
) -> list[tuple[str, str | None, str]]:
    output = _git(
        root,
        "diff",
        "--name-status",
        "--find-renames",
        before_revision,
        "--",
        "lib",
        strip=False,
    )
    changed: list[tuple[str, str | None, str]] = []
    for line in output.splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        status = fields[0]
        if status.startswith("R"):
            if len(fields) != 3:
                raise SelectionError(f"Malformed renamed production path: {line}")
            before_path, after_path = fields[1], fields[2]
        else:
            if len(fields) != 2 or status not in {"A", "M", "D", "T"}:
                raise SelectionError(f"Unsupported production path change: {line}")
            before_path = None if status == "A" else fields[1]
            after_path = fields[1]
        effective_path = after_path if status != "D" else before_path
        if effective_path is None or _is_generated_lib_path(effective_path):
            continue
        changed.append((status, before_path, after_path))
    known_after_paths = {after_path for _, _, after_path in changed}
    untracked = _git(
        root,
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
        "lib",
        strip=False,
    )
    for relative_path in untracked.splitlines():
        if (
            relative_path
            and relative_path not in known_after_paths
            and not _is_generated_lib_path(relative_path)
        ):
            changed.append(("A", None, relative_path))
    return changed


def _line_count(source: str) -> int:
    return len(source.splitlines())


def _production_comparison(
    root: pathlib.Path, before_revision: str
) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for status, before_path, after_path in _changed_production_paths(
        root, before_revision
    ):
        before_source = (
            ""
            if before_path is None
            else _git_source(root, before_revision, before_path)
        )
        after_file = root / after_path
        after_source = "" if status == "D" else after_file.read_text()
        before_lines = _line_count(before_source)
        after_lines = _line_count(after_source)
        rows.append(
            {
                "status": status,
                "beforePath": before_path,
                "afterPath": after_path,
                "beforeLines": before_lines,
                "afterLines": after_lines,
                "delta": after_lines - before_lines,
            }
        )
    rows.sort(key=lambda row: (row["afterPath"], row["beforePath"] or ""))
    before_lines = sum(row["beforeLines"] for row in rows)
    after_lines = sum(row["afterLines"] for row in rows)
    return {
        "files": rows,
        "touchedFileCount": len(rows),
        "beforeLines": before_lines,
        "afterLines": after_lines,
        "delta": after_lines - before_lines,
    }


def _symbol_parameter_source(source: str, symbol: str) -> str | None:
    pattern = re.compile(rf"\b{re.escape(symbol)}\s*\(")
    for match in pattern.finditer(source):
        line_start = source.rfind("\n", 0, match.start()) + 1
        prefix = source[line_start : match.start()]
        declaration_prefix = prefix.strip()
        if (
            not declaration_prefix
            or declaration_prefix in {"await", "return"}
            or "=" in declaration_prefix
            or "." in declaration_prefix
        ):
            continue
        opening = source.find("(", match.start())
        depth = 0
        for index in range(opening, len(source)):
            character = source[index]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    return source[opening + 1 : index]
    return None


def _split_parameters(source: str) -> list[str]:
    parameters: list[str] = []
    start = 0
    depths = {"(": 0, "[": 0, "{": 0, "<": 0}
    closing = {")": "(", "]": "[", "}": "{", ">": "<"}
    for index, character in enumerate(source):
        if character in depths:
            depths[character] += 1
        elif character in closing:
            key = closing[character]
            depths[key] = max(0, depths[key] - 1)
        elif character == "," and not any(depths.values()):
            parameters.append(source[start:index].strip())
            start = index + 1
    tail = source[start:].strip()
    if tail:
        parameters.append(tail)
    return parameters


def _identity_parameters(source: str, symbol: str) -> list[str]:
    parameter_source = _symbol_parameter_source(source, symbol)
    if parameter_source is None:
        return []
    return [
        parameter
        for parameter in _split_parameters(parameter_source)
        if _is_explicit_turn_identity_parameter(parameter)
    ]


def _identity_comparison(
    *,
    root: pathlib.Path,
    before_revision: str,
    selected_source_path: str,
    migrated_symbols: list[str],
) -> dict[str, Any]:
    before_source = _git_source(root, before_revision, selected_source_path)
    after_source = _repository_file(
        root, selected_source_path, "selection.selected.sourcePath"
    ).read_text()
    rows: list[dict[str, Any]] = []
    for symbol in migrated_symbols:
        before_parameters = _identity_parameters(before_source, symbol)
        after_parameters = _identity_parameters(after_source, symbol)
        rows.append(
            {
                "symbol": symbol,
                "before": before_parameters,
                "after": after_parameters,
                "removed": max(0, len(before_parameters) - len(after_parameters)),
            }
        )
    before_count = sum(len(row["before"]) for row in rows)
    after_count = sum(len(row["after"]) for row in rows)
    return {
        "symbols": rows,
        "beforeCount": before_count,
        "afterCount": after_count,
        "removedCount": max(0, before_count - after_count),
    }


def _port_methods(source: str, relative_path: str) -> set[str]:
    methods: set[str] = set()
    class_pattern = re.compile(
        r"abstract\s+interface\s+class\s+(\w*Port)\s*\{"
    )
    for match in class_pattern.finditer(source):
        opening = source.find("{", match.start())
        depth = 0
        closing = None
        for index in range(opening, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    closing = index
                    break
        if closing is None:
            continue
        body = source[opening + 1 : closing]
        for method in re.finditer(r"\b(\w+)\s*\([^;{}]*\)\s*;", body):
            methods.add(
                f"{relative_path}::{match.group(1)}.{method.group(1)}"
            )
    return methods


def _callback_surfaces(source: str, relative_path: str) -> set[str]:
    surfaces = {
        f"{relative_path}::typedef:{match.group(1)}"
        for match in re.finditer(
            r"\btypedef\s+(\w+)\s*=\s*[^;]*\bFunction\s*\(", source
        )
    }
    for match in re.finditer(
        r"\bFunction\s*\([^)]*\)\s*(\w+)", source, re.MULTILINE
    ):
        surfaces.add(f"{relative_path}::value:{match.group(1)}")
    return surfaces


def _public_declarations(source: str, relative_path: str) -> set[str]:
    declarations: set[str] = set()
    pattern = re.compile(
        r"^\s*(?:abstract\s+interface\s+|abstract\s+|base\s+|final\s+|"
        r"sealed\s+)?(?:class|enum|mixin|extension|typedef)\s+(\w+)",
        re.MULTILINE,
    )
    for match in pattern.finditer(source):
        name = match.group(1)
        if not name.startswith("_"):
            declarations.add(f"{relative_path}::{name}")
    return declarations


def _surface_comparison(
    root: pathlib.Path,
    before_revision: str,
    production: dict[str, Any],
) -> dict[str, Any]:
    before_ports: set[str] = set()
    after_ports: set[str] = set()
    before_callbacks: set[str] = set()
    after_callbacks: set[str] = set()
    before_public: set[str] = set()
    after_public: set[str] = set()
    for row in production["files"]:
        before_path = row["beforePath"]
        after_path = row["afterPath"]
        if before_path is not None and before_path.endswith(".dart"):
            source = _git_source(root, before_revision, before_path)
            before_ports.update(_port_methods(source, before_path))
            before_callbacks.update(_callback_surfaces(source, before_path))
            before_public.update(_public_declarations(source, before_path))
        if row["status"] != "D" and after_path.endswith(".dart"):
            source = (root / after_path).read_text()
            after_ports.update(_port_methods(source, after_path))
            after_callbacks.update(_callback_surfaces(source, after_path))
            after_public.update(_public_declarations(source, after_path))
    return {
        "ports": {
            "introducedMethods": sorted(after_ports - before_ports),
            "removedMethods": sorted(before_ports - after_ports),
        },
        "callbacks": {
            "introducedSurfaces": sorted(after_callbacks - before_callbacks),
            "removedSurfaces": sorted(before_callbacks - after_callbacks),
        },
        "publicSurface": {
            "introducedDeclarations": sorted(after_public - before_public),
            "removedDeclarations": sorted(before_public - after_public),
        },
    }


def _added_diff_source(root: pathlib.Path, before_revision: str) -> str:
    diff = _git(
        root,
        "diff",
        "--unified=3",
        before_revision,
        "--",
        "lib",
        strip=False,
    )
    added = "\n".join(
        line[1:]
        for line in diff.splitlines()
        if line.startswith("+") and not line.startswith("+++")
    )
    untracked = _git(
        root,
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
        "lib",
        strip=False,
    )
    untracked_sources = [
        (root / relative_path).read_text()
        for relative_path in untracked.splitlines()
        if relative_path and not _is_generated_lib_path(relative_path)
    ]
    return "\n".join([added, *untracked_sources])


def _chat_notifier_callback_captures(
    root: pathlib.Path, before_revision: str
) -> list[str]:
    added = _added_diff_source(root, before_revision)
    capture_pattern = re.compile(
        r"(?:\([^)]*\)|\b\w+)\s*=>[^;\n]*"
        r"(?:\bnotifier\b|\bref\b|\bstate\b|sendHiddenPrompt)",
        re.IGNORECASE,
    )
    return sorted({match.group(0).strip() for match in capture_pattern.finditer(added)})


def _run_after_audit(root: pathlib.Path) -> dict[str, Any]:
    local_dart = root / ".fvm/flutter_sdk/bin/dart"
    executable = str(local_dart) if local_dart.is_file() else "dart"
    result = subprocess.run(
        [
            executable,
            "run",
            "tool/audit_chat_notifier_turn_scope.dart",
            "--manifest",
            "tool/chat_notifier_decomposition_manifest.json",
        ],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip()
        raise SelectionError(f"Turn-scope worktree audit failed: {message}")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SelectionError(
            f"Turn-scope worktree audit did not return JSON: {error}"
        ) from error
    if not isinstance(value, dict):
        raise SelectionError("Turn-scope worktree audit must return an object")
    return value


def _ambient_read_comparison(
    *,
    root: pathlib.Path,
    before_revision: str,
    after_audit: dict[str, Any] | None,
) -> dict[str, Any]:
    baseline_source = _git_source(
        root,
        before_revision,
        "tool/chat_notifier_turn_scope_baseline.json",
    )
    try:
        before_audit = json.loads(baseline_source)
    except json.JSONDecodeError as error:
        raise SelectionError(f"Before turn-scope baseline is invalid: {error}") from error
    current_audit = after_audit or _run_after_audit(root)
    before_summary = _require_object(
        before_audit.get("summary"), "beforeAudit.summary"
    )
    after_summary = _require_object(
        current_audit.get("summary"), "afterAudit.summary"
    )
    before_count = before_summary.get("turnReachableReads")
    after_count = after_summary.get("turnReachableReads")
    if not isinstance(before_count, int) or not isinstance(after_count, int):
        raise SelectionError("Turn-scope summaries require turnReachableReads")
    before_ids = {
        _require_string(read.get("id"), "beforeAudit.reads[].id")
        for read in _require_list(before_audit.get("reads"), "beforeAudit.reads")
        if _require_object(read, "beforeAudit.reads[]").get("turnReachable") is True
    }
    after_ids = {
        _require_string(read.get("id"), "afterAudit.reads[].id")
        for read in _require_list(current_audit.get("reads"), "afterAudit.reads")
        if _require_object(read, "afterAudit.reads[]").get("turnReachable") is True
    }
    return {
        "beforeCount": before_count,
        "afterCount": after_count,
        "delta": after_count - before_count,
        "introducedIds": sorted(after_ids - before_ids),
        "removedIds": sorted(before_ids - after_ids),
    }


def compare_prototype(
    *,
    root: pathlib.Path,
    selection_path: pathlib.Path,
    before_revision: str,
    after_worktree: pathlib.Path,
    after_audit: dict[str, Any] | None = None,
) -> dict[str, Any]:
    root = root.resolve()
    if after_worktree.resolve() != root:
        raise SelectionError("after-worktree must resolve to the repository root")
    selection = _load_json(selection_path.resolve(), "Validated selection")
    _require_schema(
        selection,
        label="Validated selection",
        schema_name=VALIDATED_SELECTION_SCHEMA_NAME,
        schema_version=VALIDATED_SELECTION_SCHEMA_VERSION,
    )
    selection_revision = _require_string(
        selection.get("sourceRevision"), "selection.sourceRevision"
    )
    if COMMIT_PATTERN.fullmatch(selection_revision) is None:
        raise SelectionError("selection.sourceRevision must be a full Git SHA")
    resolved_before = _resolve_commit(root, before_revision, "before-revision")
    resolved_after = _resolve_commit(root, "HEAD", "after revision")
    _require_ancestor(
        root,
        resolved_before,
        resolved_after,
        "before-revision must be an ancestor of the checked-out HEAD",
    )
    selected = _require_object(selection.get("selected"), "selection.selected")
    selected_source_path = _require_string(
        selected.get("sourcePath"), "selection.selected.sourcePath"
    )
    if _is_ancestor(root, selection_revision, resolved_before):
        selection_base_relation = "ancestor"
    else:
        selected_at_selection = _git_source(
            root, selection_revision, selected_source_path
        )
        selected_at_before = _git_source(
            root, resolved_before, selected_source_path
        )
        if selected_at_selection != selected_at_before:
            raise SelectionError(
                "Non-ancestral selection revision must have the same selected "
                "source at before-revision"
            )
        selection_base_relation = "equivalent-selected-source"
    verification = _require_object(
        selection.get("verification"), "selection.verification"
    )
    selected_part = _require_object(
        verification.get("selectedPart"), "selection.verification.selectedPart"
    )
    migrated_symbols = _require_unique_strings(
        selected_part.get("migratedPathSymbols"),
        "selection.verification.selectedPart.migratedPathSymbols",
    )

    production = _production_comparison(root, resolved_before)
    identity = _identity_comparison(
        root=root,
        before_revision=resolved_before,
        selected_source_path=selected_source_path,
        migrated_symbols=migrated_symbols,
    )
    surfaces = _surface_comparison(root, resolved_before, production)
    captures = _chat_notifier_callback_captures(root, resolved_before)
    surfaces["callbacks"]["chatNotifierCaptureCandidates"] = captures
    ambient_reads = _ambient_read_comparison(
        root=root,
        before_revision=resolved_before,
        after_audit=after_audit,
    )
    return {
        "schemaName": COMPARISON_SCHEMA_NAME,
        "schemaVersion": COMPARISON_SCHEMA_VERSION,
        "selectionRevision": selection_revision,
        "selectionBaseRelation": selection_base_relation,
        "beforeRevision": resolved_before,
        "afterRevision": resolved_after,
        "afterWorktree": ".",
        "selectedPart": selected.get("partPath"),
        "migratedPathSymbols": migrated_symbols,
        "production": production,
        "identityParameters": identity,
        "ports": surfaces["ports"],
        "callbacks": surfaces["callbacks"],
        "publicSurface": surfaces["publicSurface"],
        "turnReachableAmbientReads": ambient_reads,
        "structuralGates": {
            "identityParameterRemoved": identity["removedCount"] >= 1,
            "turnReachableAmbientReadsDoNotIncrease": ambient_reads["delta"] <= 0,
            "noNewCallbackCapturesChatNotifier": not captures,
        },
    }


def write_json_atomic(path: pathlib.Path, value: dict[str, Any]) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as output:
            temporary_path = pathlib.Path(output.name)
            json.dump(value, output, indent=2, sort_keys=True)
            output.write("\n")
        temporary_path.replace(path)
    except OSError as error:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise SelectionError(
            f"Could not write selection output {path}: {error}"
        ) from error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    subparsers = parser.add_subparsers(dest="command", required=True)
    select = subparsers.add_parser(
        "select", help="Select the highest-coupling current ChatNotifier part"
    )
    select.add_argument("--audit", required=True, type=pathlib.Path)
    select.add_argument("--manifest", required=True, type=pathlib.Path)
    select.add_argument("--source-revision", default="HEAD")
    select.add_argument("--require-clean", action="store_true")
    select.add_argument("--output", required=True, type=pathlib.Path)
    validate = subparsers.add_parser(
        "validate-gates", help="Validate focused and live gates for a selection"
    )
    validate.add_argument("--selection", required=True, type=pathlib.Path)
    validate.add_argument(
        "--verification-manifest", required=True, type=pathlib.Path
    )
    validate.add_argument("--output", required=True, type=pathlib.Path)
    compare = subparsers.add_parser(
        "compare", help="Compare the completed prototype with its clean base"
    )
    compare.add_argument("--selection", required=True, type=pathlib.Path)
    compare.add_argument("--before-revision", required=True)
    compare.add_argument("--after-worktree", required=True, type=pathlib.Path)
    compare.add_argument("--output", required=True, type=pathlib.Path)
    return parser


def main(arguments: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(arguments)
    try:
        if args.command == "select":
            selection = build_selection(
                root=repository_root(),
                audit_path=args.audit,
                manifest_path=args.manifest,
                source_revision=args.source_revision,
                require_clean=args.require_clean,
            )
            write_json_atomic(args.output, selection)
            selected = selection["selected"]
            print(
                "TurnRuntime prototype candidate selected: "
                f"{selected['partPath']} "
                f"(identity entrypoints="
                f"{selected['turnReachableIdentityEntrypoints']['count']}, "
                f"ambient reads={selected['turnReachableAmbientReads']['count']}, "
                f"production lines={selected['productionLines']}); "
                f"source {selection['sourceRevision']}"
            )
        elif args.command == "validate-gates":
            validated = validate_gates(
                root=repository_root(),
                selection_path=args.selection,
                verification_manifest_path=args.verification_manifest,
            )
            write_json_atomic(args.output, validated)
            print(
                "TurnRuntime prototype gates valid: "
                f"{validated['selected']['partPath']}; "
                f"source {validated['sourceRevision']}; live canary not executed"
            )
        elif args.command == "compare":
            comparison = compare_prototype(
                root=repository_root(),
                selection_path=args.selection,
                before_revision=args.before_revision,
                after_worktree=args.after_worktree,
            )
            write_json_atomic(args.output, comparison)
            gates = comparison["structuralGates"]
            print(
                "TurnRuntime prototype compared: "
                f"production delta={comparison['production']['delta']:+d}; "
                f"identity removed="
                f"{comparison['identityParameters']['removedCount']}; "
                f"ambient delta="
                f"{comparison['turnReachableAmbientReads']['delta']:+d}; "
                f"structural gates="
                f"{'pass' if all(gates.values()) else 'fail'}"
            )
        else:
            raise SelectionError(f"Unsupported command: {args.command}")
        return 0
    except SelectionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

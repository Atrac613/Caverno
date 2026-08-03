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
        else:
            raise SelectionError(f"Unsupported command: {args.command}")
        return 0
    except SelectionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

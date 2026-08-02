#!/usr/bin/env python3
"""Select and measure a bounded ChatNotifier TurnRuntime prototype."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
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
PROVIDER_ROOT = pathlib.PurePosixPath(
    "lib/features/chat/presentation/providers"
)


class SelectionError(Exception):
    """Raised when prototype selection inputs are invalid or inconsistent."""


def repository_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


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
        raise SelectionError(f"git {' '.join(arguments)} failed: {message}")
    return result.stdout.strip()


def resolve_source_revision(root: pathlib.Path, revision: str) -> str:
    resolved = _git(root, "rev-parse", "--verify", f"{revision}^{{commit}}")
    head = _git(root, "rev-parse", "--verify", "HEAD^{commit}")
    if resolved != head:
        raise SelectionError(
            "Source revision must resolve to the checked-out HEAD commit"
        )
    return resolved


def require_clean_worktree(root: pathlib.Path) -> None:
    changed = _git(root, "status", "--porcelain", "--untracked-files=all")
    if changed:
        paths = [line[3:] if len(line) > 3 else line for line in changed.splitlines()]
        raise SelectionError(
            "Prototype selection requires a clean worktree: "
            + ", ".join(paths)
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
            if method["turnReachable"] and parameters:
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
    return parser


def main(arguments: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(arguments)
    try:
        if args.command != "select":
            raise SelectionError(f"Unsupported command: {args.command}")
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
        return 0
    except SelectionError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

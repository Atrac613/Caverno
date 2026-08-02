#!/usr/bin/env python3
"""Validate and eventually measure the ChatNotifier renewal inventories.

Phase 0A intentionally implements only the finite static guard inventory. The
corpus and tool-catalogue analysis arguments are accepted so the final command
surface is stable, but dynamic measurement remains blocked until its own
tested slice is complete.
"""

from __future__ import annotations

import argparse
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


def _require_fields(
    item: dict[str, Any], required: set[str], label: str
) -> None:
    missing = sorted(required - item.keys())
    if missing:
        raise InventoryError(f"{label} is missing fields: {', '.join(missing)}")


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
        expected_edges = [f"{root_name} -> {raw['symbol']}" for root_name in expected_roots]
        if raw["staticEdges"] != expected_edges:
            raise InventoryError(
                f"entries[{index}].staticEdges are stale for {raw['symbol']}"
            )

    return {
        "discovered": len(discovered),
        "entries": len(entries),
        "exclusions": len(exclusions),
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
    parser.add_argument("--print-guard-candidates", action="store_true")
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
            )
            if path is not None
        ]
        if args.require_clean_source:
            require_clean_source(root, revision, manifests)

        if args.print_guard_candidates:
            print(json.dumps(discover_guard_candidates(root), indent=2))
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
            raise InventoryError(
                "Tool-manifest validation is not implemented in Phase 0A"
            )
        if args.corpus_manifest is not None or args.output is not None:
            raise InventoryError(
                "Dynamic corpus analysis is not implemented in Phase 0A"
            )
        if guard_path is None:
            parser.error("select a manifest check or --print-guard-candidates")
        return 0
    except InventoryError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

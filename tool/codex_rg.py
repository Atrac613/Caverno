#!/usr/bin/env python3
"""Run a bounded, artifact-preserving ripgrep discovery search."""

from __future__ import annotations

import base64
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


USAGE = """Usage:
  tool/codex_rg.sh [wrapper options] -- <rg arguments>
  tool/codex_rg.sh [wrapper options] PATTERN [PATH ...]

Wrapper options:
  --max-hits N        Show at most N matching lines. Default: 40.
  --max-line-chars N  Show at most N characters per matching line. Default: 300.
  --output PATH       Save the complete ripgrep JSON stream at PATH.
  --raw               Run ordinary rg with unbounded terminal output.
  -h, --help          Show this help.

Place wrapper options before the first rg argument. Use -- when rg arguments
could be confused with wrapper options.
Summary mode accepts match-producing searches only. Use --raw for file lists,
counts, quiet checks, help, version output, or other non-match modes.
"""


class UsageError(ValueError):
    """Report an invalid wrapper invocation."""


def _positive_int(value: str, option: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise UsageError(f"{option} requires a positive integer.") from error
    if parsed < 1:
        raise UsageError(f"{option} requires a positive integer.")
    return parsed


def _parse_args(argv: list[str]) -> tuple[int, int, Path | None, bool, list[str]]:
    max_hits = 40
    max_line_chars = 300
    output: Path | None = None
    raw = False
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument == "--":
            index += 1
            break
        if argument in ("-h", "--help"):
            print(USAGE, end="")
            raise SystemExit(0)
        if argument == "--raw":
            raw = True
            index += 1
            continue
        if argument in ("--max-hits", "--max-line-chars", "--output"):
            if index + 1 >= len(argv):
                raise UsageError(f"{argument} requires a value.")
            value = argv[index + 1]
            if argument == "--max-hits":
                max_hits = _positive_int(value, argument)
            elif argument == "--max-line-chars":
                max_line_chars = _positive_int(value, argument)
            else:
                output = Path(value)
            index += 2
            continue
        break

    rg_args = argv[index:]
    if not rg_args:
        raise UsageError("Provide a ripgrep pattern and optional paths.")
    return max_hits, max_line_chars, output, raw, rg_args


def _default_output_path() -> Path:
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    return Path("build/codex_reports") / f"rg-{timestamp}-{os.getpid()}.jsonl"


def _decode_json_text(value: Any) -> str:
    if not isinstance(value, dict):
        return ""
    text = value.get("text")
    if isinstance(text, str):
        return text
    encoded = value.get("bytes")
    if isinstance(encoded, str):
        try:
            return base64.b64decode(encoded).decode("utf-8", errors="replace")
        except (ValueError, base64.binascii.Error):
            return "<invalid encoded text>"
    return ""


def _single_line(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\r", "\\r").replace("\n", "\\n")


def _clip(value: str, limit: int) -> str:
    if len(value) <= limit:
        return value
    return f"{value[:limit]}... <{len(value) - limit} chars omitted>"


def _summarize(
    path: Path,
    max_hits: int,
    max_line_chars: int,
) -> tuple[list[str], int, int]:
    matching_lines = 0
    match_count = 0
    invalid_lines = 0
    files: set[str] = set()
    hits: list[str] = []

    with path.open(encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            try:
                event = json.loads(raw_line)
            except json.JSONDecodeError:
                if raw_line.strip():
                    invalid_lines += 1
                continue
            if event.get("type") != "match":
                continue
            data = event.get("data")
            if not isinstance(data, dict):
                continue
            file_path = _decode_json_text(data.get("path")) or "<unknown>"
            line_text = _decode_json_text(data.get("lines")).rstrip("\r\n")
            line_number = data.get("line_number")
            submatches = data.get("submatches")
            occurrence_count = len(submatches) if isinstance(submatches, list) else 1

            files.add(file_path)
            matching_lines += 1
            match_count += occurrence_count
            if len(hits) < max_hits:
                location = f"{_single_line(file_path)}:{line_number or '?'}"
                hits.append(f"  {location}: {_clip(_single_line(line_text), max_line_chars)}")

    lines = [
        f"MATCHES: {match_count} across {matching_lines} lines in {len(files)} files",
    ]
    if hits:
        lines.append(f"First {len(hits)} matching lines (path-sorted):")
        lines.extend(hits)
    if matching_lines > len(hits):
        lines.append(f"  ... {matching_lines - len(hits)} more matching lines omitted")
    return lines, matching_lines, invalid_lines


def _write_diagnostics(stderr_path: Path, stderr: bytes) -> None:
    stderr_path.write_bytes(stderr)
    stderr_path.chmod(0o600)
    if not stderr:
        return
    diagnostic_lines = stderr.decode("utf-8", errors="replace").splitlines()
    print("ripgrep diagnostics:")
    for line in diagnostic_lines[:40]:
        print(f"  {line}")
    if len(diagnostic_lines) > 40:
        print(f"  ... {len(diagnostic_lines) - 40} more diagnostic lines omitted")
    print(f"Full stderr: {stderr_path}")


def main(argv: list[str]) -> int:
    os.umask(0o077)
    try:
        max_hits, max_line_chars, output, raw, rg_args = _parse_args(argv)
    except UsageError as error:
        print(f"Error: {error}", file=sys.stderr)
        print(USAGE, file=sys.stderr, end="")
        return 64

    if raw:
        return subprocess.call(["rg", *rg_args])

    output_path = output or _default_output_path()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.touch(mode=0o600, exist_ok=True)
    output_path.chmod(0o600)
    stderr_path = output_path.with_name(f"{output_path.name}.stderr")
    with output_path.open("wb") as stdout_handle:
        result = subprocess.run(
            ["rg", "--json", "--sort=path", *rg_args],
            stdout=stdout_handle,
            stderr=subprocess.PIPE,
            check=False,
        )

    wrapper_status = result.returncode
    if result.returncode == 0:
        summary, _, invalid_lines = _summarize(
            output_path,
            max_hits,
            max_line_chars,
        )
        if invalid_lines:
            print(
                "ERROR: rg produced non-JSON output that cannot be summarized; "
                "rerun this mode with --raw.",
                file=sys.stderr,
            )
            wrapper_status = 65
        elif output_path.stat().st_size == 0:
            print(
                "ERROR: rg exited successfully without JSON events; rerun this "
                "mode with --raw.",
                file=sys.stderr,
            )
            wrapper_status = 65
        else:
            print("\n".join(summary))
    elif result.returncode == 1:
        print("NO MATCHES: 0 across 0 lines in 0 files")
    else:
        print(f"ERROR: rg exited with status {result.returncode}.", file=sys.stderr)

    _write_diagnostics(stderr_path, result.stderr)
    print(f"Full JSON result: {output_path} ({output_path.stat().st_size} bytes)")
    return wrapper_status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

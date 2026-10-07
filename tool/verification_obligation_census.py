#!/usr/bin/env python3
"""Which failed commands became completion obligations, and did they test anything?

Why this exists
---------------
A failed command blocks a coding turn unless an allowlist proves it a probe
(`VerificationMetadataQueryPolicy`, `LiteralEnvironmentInspectionPolicy`).
Four Watcher farm sessions in a row (1afd70a6, d27e7528, 016d4d5e, 64bbc516)
had a done subtask rejected because a new probe shape -- `pip list | grep`,
`command -v`, `ls .venv venv` -- missed the allowlist, and the repair
recovery then demanded the probe pass.

The proposal under evaluation inverts the default for completion evidence: a
failed command is an obligation only when it exercised the project (a test
runner, a build or analyzer, a project file, an inline program importing a
project module, or a request to a local server). This census measures both
sides before any harness change:

* demands   -- commands the repair recoveries told the model to make pass;
* rejections -- project subtasks "rejected by the harness", with the last
  demanded command in that turn;
* risk      -- every distinct failed command, so the ones the proposal would
  stop counting can be read for real checks hiding among them.

Counting follows tool/analyze_tool_results.py: tool results are deduplicated
by id within a session and payloads are parsed, never matched as substrings.
Only grounded logs (at least one LLM completion) are counted.

The project test is a prototype of the proposed rule, evaluated against the
current filesystem, so a file deleted since the session reads as absent.

Usage
-----
    python3 tool/verification_obligation_census.py
    python3 tool/verification_obligation_census.py --dir build/integration_test_reports
    python3 tool/verification_obligation_census.py --json build/verification_obligation_census.json

Honors CAVERNO_SESSION_LOG_DIR / CAVERNO_HOME like triage_session_logs.py.
Pure stdlib; no Flutter or Dart needed.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import pathlib
import re
import shlex
import sys

COMPLETION_OPERATIONS = {
    "streamChatCompletionWithTools",
    "streamChatCompletionWithToolResults",
    "streamChatCompletion",
    "createChatCompletion",
}
COMMAND_TOOLS = {
    "local_execute_command",
    "process_start",
    "process_status",
    "process_wait",
    "run_tests",
}

TEST_RUNNERS = [
    r"(?:^|/)pytest\b",
    r"\bpython[\d.]*\s+-m\s+(?:pytest|unittest|nose2?|doctest)\b",
    r"\btox\b",
    r"\b(?:dart|flutter)\s+test\b",
    r"\bflutter\s+drive\b",
    r"\b(?:npm|yarn|pnpm|bun)\s+(?:run\s+)?test\b",
    r"\bnpx\s+(?:jest|vitest|mocha|playwright)\b",
    r"\b(?:jest|vitest|mocha)\b",
    r"\b(?:go|cargo|swift)\s+test\b",
    r"\bxcodebuild\b.*\btest\b",
    r"\bmake\s+(?:test|check)\b",
    r"\b(?:rspec|phpunit|ctest)\b",
    r"\b(?:\./)?gradlew?\s+(?:test|check)\b",
    r"\bmvn\s+(?:test|verify)\b",
]
BUILDS_AND_ANALYZERS = [
    r"\b(?:dart|flutter)\s+analyze\b",
    r"\bflutter\s+build\b",
    r"\bdart\s+compile\b",
    r"\b(?:tsc|eslint|flake8|pyflakes|mypy|pylint|shellcheck)\b",
    r"\bruff\s+check\b",
    r"\bpython[\d.]*\s+-m\s+(?:py_compile|compileall|pyflakes|mypy|ruff)\b",
    r"\bnode\s+--check\b",
    r"\bcargo\s+(?:build|check|clippy)\b",
    r"\bgo\s+(?:build|vet)\b",
    r"\bswift\s+build\b",
    r"\bxcodebuild\b",
    r"\b(?:npm|yarn|pnpm)\s+run\s+(?:build|lint|typecheck)\b",
    r"\b(?:\./)?gradlew?\s+(?:build|assemble)\b",
    r"\bmvn\s+(?:package|compile)\b",
]
PROJECT_RUNNERS = [
    r"\b(?:dart|flutter|cargo|go|swift|deno|bun)\s+run\b",
    r"\bnpm\s+(?:start|run)\b",
]
INTERPRETERS = re.compile(
    r"^(?:.*/)?(?:python[\d.]*|node|ruby|perl|bash|sh|zsh|deno|bun|php|lua)$"
)
LOCAL_SERVER = re.compile(r"\b(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?\b")
IMPORT = re.compile(r"(?:^|[;\n]\s*|\s)(?:from\s+([A-Za-z_]\w*)|import\s+([A-Za-z_]\w*))")


def log_dir(override: str | None) -> pathlib.Path:
    if override:
        return pathlib.Path(override).expanduser()
    if os.environ.get("CAVERNO_SESSION_LOG_DIR"):
        return pathlib.Path(os.environ["CAVERNO_SESSION_LOG_DIR"]).expanduser()
    home = os.environ.get("CAVERNO_HOME") or "~/.caverno"
    return pathlib.Path(home).expanduser() / "session_logs" / "coding"


def iter_records(path: pathlib.Path):
    with path.open(errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue


def payload_of(result) -> dict:
    value = result.get("result")
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except ValueError:
            return {}
        return decoded if isinstance(decoded, dict) else {}
    return {}


def exit_code(result) -> int | None:
    outcome = result.get("outcome") or {}
    if isinstance(outcome.get("exit_code"), int):
        return outcome["exit_code"]
    value = payload_of(result).get("exit_code")
    return value if isinstance(value, int) else None


def split_segments(command: str) -> list[str]:
    """Top-level `;`, `&&`, `||`, `|` and newline parts, quotes respected."""
    segments, start, quote, index = [], 0, None, 0
    while index < len(command):
        char = command[index]
        if quote:
            if char == quote:
                quote = None
        elif char in "'\"":
            quote = char
        elif char in ";\n|&":
            if char == "&" and not command.startswith("&&", index):
                index += 1
                continue
            segments.append(command[start:index])
            index += 2 if command.startswith(("&&", "||"), index) else 1
            start = index
            continue
        index += 1
    segments.append(command[start:])
    return [segment.strip() for segment in segments if segment.strip()]


METADATA_ARGS = {"--version", "-V", "--help", "-h"}
REDIRECT = re.compile(r"^\d*(?:>>?|<|&>)(?:&\d+|/dev/\w+)?$|^\d*>&\d+$|^&>/dev/null$|^\d*>/dev/null$")
QUOTED = re.compile(r"""['"]([^'"\n]+)['"]""")


def is_metadata_query(words: list[str]) -> bool:
    """A runner asked only for its version or help ran no project code."""
    tail = [word for word in words[1:] if word not in ("-m", "pytest", "pip")]
    return bool(tail) and all(word in METADATA_ARGS for word in tail)


def inline_program(words: list[str], segment: str, command: str) -> str | None:
    for index, word in enumerate(words[1:], start=1):
        if word in ("-c", "-e") and index + 1 < len(words):
            return words[index + 1]
    if "<<" in segment:
        return command.split("<<", 1)[1]
    return None


def exercises_project(command: str, directory: str) -> str | None:
    """The proposed rule: why [command] tested the project, or None."""
    if LOCAL_SERVER.search(command):
        return "local server request"
    for segment in split_segments(command):
        if segment.startswith("cd "):
            target = segment[3:].strip().strip("'\"")
            directory = target if target.startswith("/") else os.path.join(directory, target)
            continue
        try:
            words = shlex.split(segment)
        except ValueError:
            words = segment.split()
        # Descriptor redirects only route output; they are not arguments.
        words = [word for word in words if not REDIRECT.match(word)]
        if not words or is_metadata_query(words):
            continue
        for label, patterns in (
            ("test runner", TEST_RUNNERS),
            ("build or analyzer", BUILDS_AND_ANALYZERS),
            ("project runner", PROJECT_RUNNERS),
        ):
            if any(re.search(pattern, segment) for pattern in patterns):
                return label
        head = words[0]
        if re.search(r"(?:^|/)(?:\.?venv|env|node_modules/\.bin)/", head) and not INTERPRETERS.match(head):
            # pip, ruff or a console script from an environment is tooling;
            # test runners and analyzers among them were matched above.
            continue
        if head.startswith("./") or (
            "/" in head and not head.startswith("/") and not INTERPRETERS.match(head)
        ):
            return "project executable"
        if not INTERPRETERS.match(head):
            continue
        program = inline_program(words, segment, command)
        if program is not None:
            for match in IMPORT.finditer(program):
                name = match.group(1) or match.group(2)
                if os.path.isfile(os.path.join(directory, f"{name}.py")) or os.path.isdir(
                    os.path.join(directory, name)
                ):
                    return "inline program importing a project module"
            for match in QUOTED.finditer(program):
                if os.path.isfile(os.path.join(directory, match.group(1))):
                    return "inline program reading a project file"
            continue
        if "-m" in words:
            # A module run (`-m pip`, `-m venv`) is the interpreter's tooling;
            # test and analyzer modules were matched above.
            continue
        script = next((word for word in words[1:] if not word.startswith("-")), None)
        if script and not script.startswith("/") or (
            script and os.path.realpath(script).startswith(os.path.realpath(directory) + "/")
        ):
            return "project file"
    return None


def classify(command: str, directory: str) -> tuple[str, str]:
    reason = exercises_project(command, directory or ".")
    return ("project", reason) if reason else ("observation", "no project code ran")


def census(root: pathlib.Path) -> dict:
    demands = {}
    rejections = []
    failures = {}
    sessions = grounded = 0
    for path in sorted(set(root.glob("**/*.jsonl"))):
        records = list(iter_records(path))
        sessions += 1
        if not any(
            record.get("operation") in COMPLETION_OPERATIONS and record.get("response")
            for record in records
        ):
            continue
        grounded += 1
        session = path.stem[:8]
        seen = set()
        # The stop decision follows the turn's exit marker, so the demand it
        # reports is the one the finished turn left behind.
        last_demand = finished_turn_demand = None
        for record in records:
            decision = record.get("projectTaskDecision") or {}
            if decision.get("decision") == "stopped" and "rejected by the harness" in str(
                decision.get("reason", "")
            ):
                rejections.append(
                    {
                        "session": session,
                        "reason": decision.get("reason"),
                        "gapCodes": decision.get("gapCodes"),
                        "lastDemand": finished_turn_demand,
                    }
                )
            if record.get("operation") == "turn_exit":
                finished_turn_demand, last_demand = last_demand, None
            for result in (record.get("request") or {}).get("toolResults") or []:
                result_id = result.get("id")
                if not result_id or result_id in seen:
                    continue
                seen.add(result_id)
                payload = payload_of(result)
                evidence = payload.get("capturedEvidence") or {}
                unresolved = evidence.get("unresolvedVerification")
                if result.get("name") == "coding_continuation_recovery" and isinstance(
                    unresolved, dict
                ):
                    command = str(unresolved.get("command") or "")
                    directory = str(unresolved.get("workingDirectory") or "")
                    key = (session, unresolved.get("toolCallId") or command)
                    kind, why = classify(command, directory)
                    entry = demands.setdefault(
                        key,
                        {
                            "session": session,
                            "command": command,
                            "workingDirectory": directory,
                            "exitCode": unresolved.get("exitCode"),
                            "kind": kind,
                            "why": why,
                            "recoveries": [],
                        },
                    )
                    entry["recoveries"].append(payload.get("code"))
                    last_demand = {"command": command, "kind": kind}
                if result.get("name") not in COMMAND_TOOLS:
                    continue
                if payload.get("result_origin") in ("refusal", "harness"):
                    continue
                code = exit_code(result)
                if code is None or code == 0:
                    continue
                command = str(payload.get("command") or (result.get("arguments") or {}).get("command") or "")
                directory = str(
                    payload.get("working_directory")
                    or (result.get("arguments") or {}).get("working_directory")
                    or ""
                )
                kind, why = classify(command, directory)
                failures[(session, result_id)] = {
                    "session": session,
                    "id": result_id,
                    "name": result.get("name"),
                    "arguments": result.get("arguments") or {},
                    "result": result.get("result") if isinstance(result.get("result"), str) else json.dumps(result.get("result"), ensure_ascii=False),
                    "outcome": result.get("outcome"),
                    "command": command,
                    "exitCode": code,
                    "kind": kind,
                    "why": why,
                }
    return {
        "sessions": sessions,
        "grounded": grounded,
        "demands": list(demands.values()),
        "rejections": rejections,
        "failures": list(failures.values()),
    }


def short(command: str, width: int = 110) -> str:
    flat = " ".join(command.split())
    return flat if len(flat) <= width else flat[: width - 3] + "..."


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", help="log directory (default: the coding corpus)")
    parser.add_argument("--json", help="write the full census to this path")
    args = parser.parse_args()
    root = log_dir(args.dir)
    if not root.exists():
        print(f"no log directory: {root}", file=sys.stderr)
        return 1
    data = census(root)
    print(f"logs: {data['sessions']} ({data['grounded']} grounded) under {root}")

    demands = data["demands"]
    by_kind = collections.Counter(item["kind"] for item in demands)
    print(f"\nrepair demands: {len(demands)} distinct commands -> {dict(by_kind)}")
    for item in sorted(demands, key=lambda item: (item["kind"], item["session"])):
        print(f"  [{item['kind']:11}] {item['session']} exit={item['exitCode']} "
              f"x{len(item['recoveries'])} ({item['why']}): {short(item['command'])}")

    rejections = data["rejections"]
    print(f"\nharness rejections: {len(rejections)}")
    for item in rejections:
        demand = item["lastDemand"] or {}
        print(f"  {item['session']} gaps={item['gapCodes']} last demand="
              f"[{demand.get('kind', '-')}] {short(demand.get('command', '-'), 80)}")

    failures = data["failures"]
    by_kind = collections.Counter(item["kind"] for item in failures)
    why = collections.Counter(item["why"] for item in failures if item["kind"] == "project")
    print(f"\nfailed commands: {len(failures)} distinct -> {dict(by_kind)}")
    print(f"  project reasons: {dict(why)}")
    print("  would stop counting (read these for real checks):")
    for item in sorted(failures, key=lambda item: item["session"]):
        if item["kind"] == "observation":
            print(f"    {item['session']} exit={item['exitCode']}: {short(item['command'])}")

    if args.json:
        pathlib.Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(args.json).write_text(json.dumps(data, ensure_ascii=False, indent=1))
        print(f"\nfull census: {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Run `caverno farm` over small fixture projects and summarize the outcomes.

CLI5d. Each fixture under tool/fixtures/farm_matrix/<name>/ is copied to a
fresh temporary git repository and run with its own --data-dir.

A CLI run always asks a person for approvals: it pins the approval mode to
defaultPermissions whatever the copied settings say (CLI2). By default the
matrix runs non-interactively, so each fixture stops at its first approval
with exit 77, and which capability stopped which fixture is recorded as data.
With --interactive each fixture runs in this terminal instead, and its
approvals are answered here or, when Remote Coding is on, from a paired phone
(CLI5c), so a fixture can run through to its commit.

Each data directory starts from --preferences when given, otherwise from a
copy of the app's preferences. The run is refused unless every LLM route in
those settings is a loopback or private-network address, because fixture
contents are sent to the model (--allow-external lifts this).

Results go to build/farm_matrix/<UTC timestamp>/: summary.md, summary.json,
and per fixture the farm's JSON events, stderr, data directory, and the
triage_session_logs.py / check_fix_firings.py reports.
"""

from __future__ import annotations

import argparse
import codecs
import datetime as dt
import ipaddress
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "tool" / "fixtures" / "farm_matrix"
DEFAULT_APP = (
    REPO / "build/macos/Build/Products/Debug/Caverno.app/Contents/MacOS/Caverno"
)
SETTINGS_KEY = "flutter.app_settings"
FARM_TURN_ID = "farm"


def is_private_url(url: str) -> bool:
    """Whether [url] names a loopback, link-local or private-network host."""
    host = (urlparse(url).hostname or "").strip().lower()
    if not host:
        return False
    if host == "localhost" or host.endswith(".localhost"):
        return True
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        return False
    return address.is_loopback or address.is_private or address.is_link_local


def llm_routes(settings: dict, base_url_override: str | None) -> dict[str, str]:
    """Every base URL a run with [settings] may send a request to, by role."""
    endpoints = {
        endpoint.get("id"): endpoint.get("baseUrl", "")
        for endpoint in settings.get("llmEndpoints") or []
    }
    routes = {"primary": base_url_override or settings.get("baseUrl", "")}
    for key, value in settings.items():
        if key.endswith("EndpointId") and key != "activeLlmEndpointId" and value:
            routes[key[: -len("EndpointId")]] = endpoints.get(value, "")
    return {role: url for role, url in routes.items() if url}


def preference_problems(
    preferences: dict,
    *,
    base_url_override: str | None,
    allow_external: bool,
) -> list[str]:
    """Why [preferences] must not be used for a matrix run, if any reason."""
    try:
        settings = json.loads(preferences.get(SETTINGS_KEY, ""))
    except json.JSONDecodeError:
        return [f"{SETTINGS_KEY} is missing or not JSON"]
    problems = []
    if not allow_external:
        external = {
            role: url
            for role, url in llm_routes(settings, base_url_override).items()
            if not is_private_url(url)
        }
        if external:
            problems.append(f"external LLM routes: {external}")
    return problems


def summarize_events(lines: list[str]) -> dict:
    """The farm run's outcome from its `--json` stdout.

    A Debug build prints the Dart VM service banner to stdout first, so a
    line that is not a JSON object is skipped rather than failing the parse.
    """
    decisions: list[str] = []
    last_approval = None
    terminal = None
    tools: dict[str, int] = {}
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get("type")
        payload = event.get("payload") or {}
        if kind == "project_task_decision":
            decisions.append(f"{payload.get('phase')}:{payload.get('decision')}")
        elif kind == "approval_required":
            last_approval = {
                key: payload.get(key)
                for key in ("capability", "summary", "command", "target")
                if payload.get(key) is not None
            }
        elif kind == "tool_lifecycle" and payload.get("state") == "completed":
            name = payload.get("toolName", "?")
            tools[name] = tools.get(name, 0) + 1
        elif kind in ("run_completed", "run_failed") and event.get("turnId") == FARM_TURN_ID:
            terminal = {"type": kind, **payload}
    return {
        "terminal": terminal,
        "decisions": decisions,
        "lastApproval": last_approval,
        "completedTools": tools,
    }


def summarize_session_logs(root: Path) -> dict:
    """Workflow decisions and turn count from a run's session logs.

    An interactive run has no `--json` stream, so its outcome is read back
    from what the run logged.
    """
    decisions: list[str] = []
    turns = 0
    for path in sorted(root.glob("**/*.jsonl")):
        for line in path.read_text(errors="replace").splitlines():
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            decision = entry.get("projectTaskDecision")
            if isinstance(decision, dict):
                decisions.append(f"{decision.get('phase')}:{decision.get('decision')}")
            if entry.get("operation") == "turn_exit":
                turns += 1
    return {"decisions": decisions, "turns": turns}


# What a person answering approvals needs to see. A Debug build streams its
# whole diagnostic log, and an approval prompt sat buried under it until the
# fixture's time limit ran out.
_SHOWN_LINE = re.compile(
    r"^(\[approval\]|Command:|Target:|This action can be remembered|"
    r"Answered on another device|Ignored input|\[question\]|\s+\d+\) |"
    r"\[farm\]|\[remote\]|\[workflow\]|Caverno (failed|completed))"
)
# Prompts end without a newline while they wait, and log lines can follow on
# the same line once the run moves on.
_PROMPTS = ("Approve once? [y/N] ", "Answer: ")


class ConsoleFilter:
    """Passes only the lines and prompts in [_SHOWN_LINE] and [_PROMPTS]."""

    def __init__(self, write):
        self._write = write
        self._line = ""
        self._in_command = False

    def feed(self, text: str) -> None:
        for char in text:
            if char == "\n":
                self._emit_line(self._line)
                self._line = ""
                continue
            self._line += char
            if self._line in _PROMPTS:
                self._write(self._line)
                self._line = ""

    def _emit_line(self, line: str) -> None:
        if line.startswith("Command:"):
            self._in_command = True
        elif line.startswith("Target:") or _SHOWN_LINE.match(line):
            self._in_command = False
        if self._in_command or _SHOWN_LINE.match(line):
            self._write(line + "\n")


def run_interactive(command: list[str], console_log: Path, timeout) -> int | str:
    """Runs [command] on this terminal, showing only what needs an answer.

    stdin stays the terminal, so approvals are answered here; the full output
    is kept in [console_log].
    """
    process = subprocess.Popen(command, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")

    def show(text: str) -> None:
        sys.stderr.write(text)
        sys.stderr.flush()

    console = ConsoleFilter(show)
    deadline = None if timeout is None else time.monotonic() + timeout
    with console_log.open("w") as log:
        while True:
            chunk = process.stdout.read1(4096)
            if not chunk:
                break
            text = decoder.decode(chunk)
            log.write(text)
            console.feed(text)
            if deadline is not None and time.monotonic() > deadline:
                process.kill()
                process.wait()
                return "timeout"
    return process.wait()


def _text(value) -> str:
    if isinstance(value, bytes):
        return value.decode(errors="replace")
    return value or ""


def prepare_project(fixture: Path) -> Path:
    project = Path(tempfile.mkdtemp(prefix=f"farm_matrix_{fixture.name}_"))
    shutil.copytree(fixture / "project", project, dirs_exist_ok=True)
    spec = json.loads((fixture / "fixture.json").read_text())
    for step in spec.get("setup", []):
        result = subprocess.run(step, cwd=project, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"setup {step} failed: {result.stderr.strip()}")
    for step in (
        ["git", "init", "-q"],
        ["git", "config", "user.name", "Farm Matrix"],
        ["git", "config", "user.email", "farm-matrix@example.invalid"],
        ["git", "add", "-A"],
        ["git", "commit", "-q", "-m", "Fixture baseline"],
    ):
        subprocess.run(step, cwd=project, check=True, capture_output=True)
    return project


def seed_data_dir(args, data_dir: Path) -> dict:
    """Starts [data_dir] from --preferences, or from the app's preferences."""
    data_dir.mkdir(parents=True)
    target = data_dir / "preferences.json"
    if args.preferences:
        shutil.copyfile(args.preferences, target)
        target.chmod(0o600)
    else:
        subprocess.run([str(args.app), "doctor", "--data-dir", str(data_dir),
                        "--json"], stdin=subprocess.DEVNULL,
                       capture_output=True, timeout=120)
    return json.loads(target.read_text())


def run_fixture(args, fixture: Path, out: Path) -> dict:
    data_dir = out / "data"
    problems = preference_problems(
        seed_data_dir(args, data_dir),
        base_url_override=args.base_url,
        allow_external=args.allow_external,
    )
    if problems:
        return {"fixture": fixture.name, "exitCode": "refused",
                "elapsedSeconds": 0, "refused": problems}
    project = prepare_project(fixture)
    command = [str(args.app), "farm", "--project", str(project),
               "--data-dir", str(data_dir)]
    if not args.interactive:
        command.append("--json")
    for flag, value in (("--base-url", args.base_url), ("--model", args.model),
                        ("--api-key", args.api_key)):
        if value:
            command += [flag, value]
    started = dt.datetime.now(dt.timezone.utc)
    stdout = stderr = ""
    try:
        if args.interactive:
            print(f"\n=== {fixture.name}: {project} ===", file=sys.stderr, flush=True)
            exit_code = run_interactive(command, out / "console.log", args.timeout)
        else:
            result = subprocess.run(command, stdin=subprocess.DEVNULL,
                                    capture_output=True, text=True,
                                    timeout=args.timeout)
            exit_code, stdout, stderr = result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired as error:
        exit_code, stdout, stderr = "timeout", _text(error.stdout), _text(error.stderr)
    elapsed = (dt.datetime.now(dt.timezone.utc) - started).total_seconds()
    (out / "events.jsonl").write_text(stdout)
    (out / "stderr.log").write_text(stderr)
    logs = data_dir / "session_logs"
    for name, report in (
        ("triage.txt", [sys.executable, str(REPO / "tool/triage_session_logs.py"),
                        "--dir", str(logs), "--top", "5"]),
        ("firings.txt", [sys.executable, str(REPO / "tool/check_fix_firings.py"),
                         "--dir", str(logs), "--repo", str(REPO)]),
    ):
        produced = subprocess.run(report, capture_output=True, text=True, cwd=REPO)
        (out / name).write_text(produced.stdout + produced.stderr)
    commits = subprocess.run(["git", "log", "--oneline", "-3"], cwd=project,
                             capture_output=True, text=True).stdout
    summary = summarize_events(stdout.splitlines())
    if args.interactive:
        summary.update(summarize_session_logs(logs))
    return {
        "fixture": fixture.name,
        "exitCode": exit_code,
        "elapsedSeconds": round(elapsed),
        "project": str(project),
        "commits": commits.strip().splitlines(),
        **summary,
    }


def render_markdown(results: list[dict]) -> str:
    rows = ["| Fixture | Exit | Outcome | Stopped at | Seconds |",
            "|---|---|---|---|---|"]
    for result in results:
        if "refused" in result:
            rows.append(f"| {result['fixture']} | - | refused: "
                        f"{'; '.join(result['refused'])} | | |")
            continue
        terminal = result.get("terminal") or {}
        approval = result.get("lastApproval") or {}
        stopped = (
            f"{approval.get('capability')}: {str(approval.get('summary', ''))[:60]}"
            if result["exitCode"] == 77 else ""
        )
        outcome = (terminal.get("code") or terminal.get("type")
                   or (result.get("decisions") or ["no terminal event"])[-1])
        rows.append(
            f"| {result['fixture']} | {result['exitCode']} | {outcome} | "
            f"{stopped} | {result['elapsedSeconds']} |"
        )
    return "# Farm matrix\n\n" + "\n".join(rows) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preferences", type=Path,
                        help="a CLI preferences.json to start each data dir from")
    parser.add_argument("--interactive", action="store_true",
                        help="run each fixture in this terminal to answer approvals")
    parser.add_argument("--fixture", action="append", help="run only these fixtures")
    parser.add_argument("--timeout", type=int, default=None,
                        help="seconds per fixture (default 1800; none with --interactive)")
    parser.add_argument("--app", type=Path, default=DEFAULT_APP)
    parser.add_argument("--base-url")
    parser.add_argument("--model")
    parser.add_argument("--api-key")
    parser.add_argument("--allow-external", action="store_true")
    args = parser.parse_args()
    if not args.app.exists():
        print(f"app not found: {args.app} (build it with tool/safe-flutter)",
              file=sys.stderr)
        return 64
    if args.timeout is None and not args.interactive:
        args.timeout = 1800
    if args.interactive and not sys.stdin.isatty():
        print("--interactive needs a terminal", file=sys.stderr)
        return 64
    fixtures = sorted(p for p in FIXTURES.iterdir() if (p / "fixture.json").exists())
    if args.fixture:
        fixtures = [p for p in fixtures if p.name in set(args.fixture)]
    if not fixtures:
        print("no fixtures selected", file=sys.stderr)
        return 64
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    root = REPO / "build" / "farm_matrix" / stamp
    results = []
    for fixture in fixtures:
        print(f"[matrix] {fixture.name} ...", file=sys.stderr, flush=True)
        result = run_fixture(args, fixture, root / fixture.name)
        print(f"[matrix] {fixture.name}: exit {result['exitCode']}",
              file=sys.stderr, flush=True)
        results.append(result)
    (root / "summary.json").write_text(json.dumps(results, indent=2))
    (root / "summary.md").write_text(render_markdown(results))
    print(render_markdown(results))
    print(f"Full results: {root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

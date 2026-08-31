#!/usr/bin/env python3
"""Report whether a shipped harness change has actually fired in a session log.

A harness change that only passes its unit tests is unproven: the path it
touches may simply never be reached in real turns. This walks the session-log
corpus for the textual signature each change leaves behind, and reports, per
change, whether it has been observed and how many logs even ran on a build
capable of producing it.

Every hit is qualified by git ancestry, so a signature found in a log from a
build that predates the change is reported as a coincidence rather than as a
confirmation.

Extend SIGNATURES when a change ships. A row is worth adding when the change
leaves a distinctive string in the log; changes whose only evidence is absence
(a notice that stops appearing) do not fit this instrument.

Usage:
    python3 tool/check_fix_firings.py [--dir LOG_DIR] [--repo REPO]

Honors CAVERNO_SESSION_LOG_DIR; defaults to ~/.caverno/session_logs.
"""

import argparse
import glob
import json
import os
import subprocess
import sys

# name -> commit that introduced it, what it does, and the log evidence that
# proves it ran. `match` receives the whole log serialized as one JSON string.
SIGNATURES = {
    "failed_read_digest": {
        "commit": "5e7f8ebb",
        "what": "failed read reported as FAILED, not as gathered context",
        "match": lambda s: "— FAILED (" in s,
    },
    "command_exit_status": {
        "commit": "982a1671",
        "what": "command digest line carries its exit status",
        "match": lambda s: "` (exit " in s or "` (last exit " in s,
    },
    "trailing_unchanged_run": {
        "commit": "982a1671",
        "what": "unchanged flagged from the trailing run of inspections",
        "match": lambda s: "(unchanged — the last " in s,
    },
    "abort_notice_shell_work": {
        "commit": "11badd76",
        "what": "abort notice reports commands that ran cleanly",
        "match": lambda s: "Already ran successfully in this turn:" in s,
    },
    "release_approval_token": {
        "commit": "ef6af66d",
        "what": "release approval decided by an issued token, not by wording",
        # The blocked-release payload names the token it issued, and that
        # payload rides into the next request, so the token is the durable
        # trace. The shadow-divergence line is app log only.
        "match": lambda s: "approval token rel-" in s,
    },
    "honest_inspection_digest": {
        "commit": "0265fe04",
        "what": "digest stops claiming inspection output is still readable",
        "match": lambda s: "Inspections already made this turn" in s,
    },
    "mutation_digest_section": {
        "commit": "99c05391",
        "what": "digest names the files the turn changed",
        "match": lambda s: "Files this turn changed" in s,
    },
    "unchecked_mutation_notice": {
        "commit": "99c05391",
        "what": "digest says an edit has had no command or check since",
        "match": lambda s: "no command or check has run since" in s,
    },
    "noop_write_notice": {
        "commit": "99c05391",
        "what": "digest flags a write that changed nothing",
        "match": lambda s: "no-op: the file was already exactly this" in s,
    },
    "blocked_mutation_notice": {
        "commit": "ab994dec",
        "what": "turn that changed no files says so",
        "match": lambda s: "blocked_mutation_notice" in s
        or "File change check: this turn changed no files" in s,
    },
}

_ANCESTRY_CACHE = {}


def build_contains(commit, fix_commit, repo):
    """Whether the build at `commit` contains `fix_commit`, per git ancestry.

    Asking git rather than inferring an order from the logs: a change that
    never shipped as a build of its own never appears as a build commit, and
    any ordering guessed from log appearance sorts it last -- which reads as
    "no log could contain it" for changes that are in fact running.

    Returns None when either commit is unknown to the repo, which must be
    reported as unknown rather than folded into either verdict.
    """
    key = (commit, fix_commit)
    if key in _ANCESTRY_CACHE:
        return _ANCESTRY_CACHE[key]
    verdict = None
    try:
        for ref in (commit, fix_commit):
            if subprocess.run(
                ["git", "-C", repo, "cat-file", "-e", f"{ref}^{{commit}}"],
                capture_output=True,
            ).returncode != 0:
                _ANCESTRY_CACHE[key] = None
                return None
        verdict = (
            subprocess.run(
                [
                    "git",
                    "-C",
                    repo,
                    "merge-base",
                    "--is-ancestor",
                    fix_commit,
                    commit,
                ],
                capture_output=True,
            ).returncode
            == 0
        )
    except OSError:
        verdict = None
    _ANCESTRY_CACHE[key] = verdict
    return verdict


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        default=os.path.expanduser(
            os.environ.get("CAVERNO_SESSION_LOG_DIR", "~/.caverno/session_logs")
        ),
    )
    parser.add_argument("--repo", default=os.getcwd())
    args = parser.parse_args()

    logs = sorted(
        glob.glob(os.path.join(args.dir, "**", "*.jsonl"), recursive=True),
        key=os.path.getmtime,
    )
    if not logs:
        print(f"no session logs under {args.dir}", file=sys.stderr)
        return 1

    hits = {name: [] for name in SIGNATURES}
    eligible = {name: 0 for name in SIGNATURES}

    for path in logs:
        try:
            entries = [json.loads(line) for line in open(path) if line.strip()]
        except (OSError, ValueError):
            continue
        if not entries:
            continue
        # Grounded only: a log carrying no real LLM exchange proves nothing.
        if not any("request" in e and "response" in e for e in entries):
            continue
        commit = entries[0].get("build", {}).get("commit", "?")
        blob = json.dumps(entries, ensure_ascii=False)
        for name, signature in SIGNATURES.items():
            could = build_contains(commit, signature["commit"], args.repo)
            if could:
                eligible[name] += 1
            if signature["match"](blob):
                hits[name].append((os.path.basename(path)[:8], commit, could))

    print(f"scanned {len(logs)} logs under {args.dir}\n")
    unproven = 0
    for name, signature in SIGNATURES.items():
        rows = hits[name]
        confirmed = [row for row in rows if row[2] is True]
        stale = [row for row in rows if row[2] is False]
        unknown = [row for row in rows if row[2] is None]
        if not confirmed:
            unproven += 1
        print(
            f"[{'FIRED' if confirmed else 'not yet observed'}] {name}  "
            f"({signature['commit']})"
        )
        print(f"    {signature['what']}")
        print(f"    logs on a build that could produce it: {eligible[name]}")
        for log, commit, _ in confirmed:
            print(f"    confirmed: {log} (build {commit})")
        for log, commit, _ in stale:
            print(
                f"    IGNORED: {log} (build {commit} predates it — the "
                f"signature is a coincidence, not a confirmation)"
            )
        for log, commit, _ in unknown:
            print(f"    UNKNOWN BUILD: {log} (build {commit} not in this repo)")
        print()

    print(f"{len(SIGNATURES) - unproven}/{len(SIGNATURES)} observed in the wild")
    return 0


if __name__ == "__main__":
    sys.exit(main())

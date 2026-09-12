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

Two corpora are scanned, and kept apart. Real sessions answer "has this fired
in use"; the live canaries under build/integration_test_reports answer the
weaker but distinct question "is this path reachable at all". Merging them would
let a fixture pass for usage; omitting the canaries -- which is what this tool
did until 2026-09-12 -- reports a path as unobserved after a canary has just
proved it, which is how ANA2's closed evidence gap kept reading as open.

Usage:
    python3 tool/check_fix_firings.py [--dir LOG_DIR] [--repo REPO]
                                      [--canary-dir DIR] [--no-canaries]

Honors CAVERNO_SESSION_LOG_DIR; defaults to ~/.caverno/session_logs for real
sessions and <repo>/build/integration_test_reports for canary runs. Passing
--dir scans only that directory, as a real-session corpus.
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
    "anabasis_parent_boundary": {
        "commit": "0e60696e",
        "what": "the Anabasis parent is refused a mutation and delegates instead",
        # Observed 2026-09-04, session 459bd75f: the parent called write_file,
        # read the refusal, and switched to spawn_subagent inside the same
        # request -- no repeat, so the refusal wording needs no work. The child
        # then edited successfully, which is delegation being the parent's only
        # route to effect rather than a restriction on the work.
        "match": lambda s: "anabasis_parent_authority_refused" in s,
    },
    "anabasis_delegation_refused": {
        "commit": "8102fab4",
        "what": "planned delegation names a task the plan does not offer",
        # The refusal half of the admission gate: it proves the queue reached
        # the parent, was consulted, and was answered with something the plan
        # does not currently offer. It does not prove planned work was ever
        # delegated -- anabasis_delegation_admitted below carries that.
        "match": lambda s: "anabasis_delegation_not_ready" in s,
    },
    "anabasis_delegation_admitted": {
        "commit": "8102fab4",
        "what": "a ready saved task is selected and its contract reaches the child",
        # The accepted half, and the one ANA2's standing evidence gap is
        # actually about: a planned parent selecting planned work and handing
        # a child its saved scope. It leaves a trace because the admitted
        # prompt does not stay in the parent -- AnabasisDelegationAdmission
        # appends the contract to the child's prompt, and child requests are
        # logged under usageRole "subagent" like any other request.
        "match": lambda s: "Saved task contract (authoritative scope)" in s,
    },
    "saved_validation_final_text": {
        "commit": "8102fab4",
        "what": "a printed tool call after saved validation is replaced, not run",
        # A final-only response carries no execution authority, so a printed
        # call in it is an action promise nobody kept. Seeing this line means
        # a real turn ended that way and the promise was withdrawn instead of
        # being read as work done.
        "match": lambda s: "The saved validation command succeeded. "
        "No additional tool call was executed." in s,
    },
    "anabasis_acceptance_refused": {
        "commit": "161e784d4",
        "what": "the parent is refused an acceptance and told what is outstanding",
        # The readable half of the acceptance gate, and the one that proves the
        # parent tried. Five codes share this prefix on purpose; matching the
        # shared key rather than one of them means any of the five counts.
        "match": lambda s: '"code":"acceptance_' in s
        or '"code": "acceptance_' in s,
    },
    "anabasis_acceptance_recorded": {
        "commit": "161e784d4",
        "what": "the parent records a semantic acceptance of a delegated task",
        # ANA3 PR 2b's whole point: the judgement stops being something the
        # next turn has to redo from the same files. The success payload names
        # the task, so this is the durable trace.
        "match": lambda s: '"accepted_task_id"' in s,
    },
    "policy_refusal_not_approval": {
        "commit": "f6bc075eb",
        "what": "an aborting policy refusal is named as one, not as an approval",
        # The branch that was wrong is the one worth watching. A refusal used to
        # abort with "was blocked by approval ... Approve it manually" and
        # "Reason: null", which sent the reader after a dialog that does not
        # exist and printed null over the refusal's own required_action. Match
        # the new wording rather than the absence of the old: an absence fires
        # on every log that never aborted at all.
        "match": lambda s: "was refused by policy (" in s,
    },
    "parent_records_its_own_judgement": {
        "commit": "81aea8858",
        "what": "the parent runs a bookkeeping tool the authority guard used to refuse",
        # Distinct from anabasis_acceptance_recorded on purpose: that one fires
        # only when an acceptance is written, and this fires when the parent gets
        # as far as the handler at all. The two guards between them left
        # accept_task with no caller, so "attempted" and "recorded" were
        # indistinguishable in the corpus -- both simply absent.
        "match": lambda s: '"name":"accept_task"' in s
        or '\\"name\\":\\"accept_task\\"' in s,
    },
    "material_assumption_confirmation": {
        "commit": "0e60696e",
        "what": "a material contract assumption stops a mutation and is asked about",
        # The refusal is what the guard emits, and it is the half that reaches
        # the log: the answer arrives through an approval, not through a model
        # request. Seeing this code at all means the marks a plan wrote
        # travelled all the way to a refused tool call, which no unit test can
        # establish -- ANA0 measured the model marking assumptions, never a
        # real turn being held by one.
        "match": lambda s: "material_contract_assumption_unconfirmed" in s,
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
    parser.add_argument(
        "--canary-dir",
        default=None,
        help="Live canary report root (default: <repo>/build/integration_test_reports).",
    )
    parser.add_argument(
        "--no-canaries",
        action="store_true",
        help="Scan real sessions only.",
    )
    args = parser.parse_args()

    # An explicit --dir means "scan exactly this", which is what the canary
    # runners pass to judge one run in isolation.
    explicit_dir = any(arg.startswith("--dir") for arg in sys.argv[1:])
    roots = [(args.dir, "wild")]
    if not args.no_canaries and not explicit_dir:
        canary_dir = args.canary_dir or os.path.join(
            args.repo, "build", "integration_test_reports"
        )
        if os.path.isdir(canary_dir):
            roots.append((canary_dir, "canary"))

    logs = []
    for root, origin in roots:
        for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            logs.append((path, origin))
    logs.sort(key=lambda row: os.path.getmtime(row[0]))
    if not logs:
        print(f"no session logs under {args.dir}", file=sys.stderr)
        return 1

    hits = {name: [] for name in SIGNATURES}
    eligible = {name: 0 for name in SIGNATURES}

    for path, origin in logs:
        try:
            with open(path, encoding="utf-8") as handle:
                entries = [json.loads(line) for line in handle if line.strip()]
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
                hits[name].append(
                    (os.path.basename(path)[:8], commit, could, origin)
                )

    scanned = ", ".join(
        f"{sum(1 for _, o in logs if o == origin)} {origin}"
        for _, origin in roots
    )
    print(f"scanned {len(logs)} logs ({scanned})\n")
    unproven = 0
    for name, signature in SIGNATURES.items():
        rows = hits[name]
        confirmed = [row for row in rows if row[2] is True]
        wild = [row for row in confirmed if row[3] == "wild"]
        canary = [row for row in confirmed if row[3] == "canary"]
        stale = [row for row in rows if row[2] is False]
        unknown = [row for row in rows if row[2] is None]
        if not wild:
            unproven += 1
        # Three verdicts, because "reachable" and "used" are different claims
        # and only the first is what a canary can establish.
        if wild:
            verdict = "FIRED"
        elif canary:
            verdict = "FIRED (canary only)"
        else:
            verdict = "not yet observed"
        print(f"[{verdict}] {name}  ({signature['commit']})")
        print(f"    {signature['what']}")
        print(f"    logs on a build that could produce it: {eligible[name]}")
        for log, commit, _, origin in confirmed:
            print(f"    confirmed: {log} (build {commit}, {origin})")
        for log, commit, _, _origin in stale:
            print(
                f"    IGNORED: {log} (build {commit} predates it — the "
                f"signature is a coincidence, not a confirmation)"
            )
        for log, commit, _, _origin in unknown:
            print(f"    UNKNOWN BUILD: {log} (build {commit} not in this repo)")
        print()

    canary_only = sum(
        1
        for name in SIGNATURES
        if not [r for r in hits[name] if r[2] is True and r[3] == "wild"]
        and [r for r in hits[name] if r[2] is True and r[3] == "canary"]
    )
    print(f"{len(SIGNATURES) - unproven}/{len(SIGNATURES)} observed in the wild")
    if canary_only:
        print(f"{canary_only} more proved reachable by a canary only")
    return 0


if __name__ == "__main__":
    sys.exit(main())

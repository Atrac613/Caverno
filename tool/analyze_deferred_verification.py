#!/usr/bin/env python3
"""Count turns that end on an announced-but-unexecuted next step.

Motivated by `docs/session_2659093b_deferred_verification_2026-07-22.md`, where
a turn ended with "next I will actually run the commands to verify" and then
stopped, with no guard firing and auto-continue skipping. That was n=1; this
counts how often the shape occurs.

What this measures, precisely
-----------------------------
For each turn (delimited by `turn_exit` records), it takes the turn's final
user-visible answer and asks whether that answer **commits to a further action**
("次に〜します", "I will now …"). It reports those as *candidates*.

It does NOT prove the action was skipped. A forward-looking sentence is a
lexical trigger, not a verdict — the same rule the rest of this work follows.
Some candidates are legitimate (the model offering the user a next step, or
auto-continue picking the work up). Read the counts as an upper bound and use
`--sample` to estimate precision by eye.

Method limitations, stated because they bound the numbers
---------------------------------------------------------
* **Order-based correlation.** `turn_exit` carries an `assistantMessageId`, but
  responses in the log carry no id, so a turn's final answer is taken as the
  last plausible assistant response *preceding* that `turn_exit` in file order.
* **Memory-extraction calls are excluded** by dropping JSON-object responses;
  a genuine answer that happens to start with `{` would be missed.
* Responses are per-record and not replayed, so unlike request messages they
  need no de-duplication (see `caverno-tool-traffic-concentration`).

Usage
-----
    python3 tool/analyze_deferred_verification.py
    python3 tool/analyze_deferred_verification.py --sample 8
    python3 tool/analyze_deferred_verification.py --since-days 30

Honors CAVERNO_SESSION_LOG_DIR / CAVERNO_HOME. Pure stdlib.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import pathlib
import re
import sys

# Forward commitments: the model saying it will do something next. Japanese
# drops the subject, so these cannot distinguish "I will run it" from "you
# should run it" — which is exactly why the output is labelled candidates.
COMMITMENT_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("ja_next_step", re.compile(r"次の(?:ステップ|手順)")),
    ("ja_next_will", re.compile(r"次に[^。\n]{0,40}?(?:します|行います|実行|確認|検証|テスト)")),
    ("ja_continue", re.compile(r"(?:続いて|これから|引き続き)[^。\n]{0,40}?(?:します|行います|実行)")),
    ("ja_will_verify", re.compile(r"(?:動作確認|検証|テスト)を(?:行います|実施します|します)")),
    ("en_i_will_now", re.compile(r"\b(?:I(?:'ll| will) now|let me now)\b", re.I)),
    ("en_next_i_will", re.compile(r"\bnext,?\s+I(?:'ll| will)\b", re.I)),
    ("en_next_step", re.compile(r"\bnext step\b", re.I)),
]

# A candidate that hands the decision back to the user is a legitimate turn
# ending, not an unkept promise. Judged on the tail, where the handoff lands.
ASKS_USER = re.compile(
    r"(?:ますか[?？]|ですか[?？]|でしょうか[?？]|いかがですか|ご希望|どちら"
    r"|\?\s*$|\bwhich would you\b|\bdo you want\b|\bshall I\b)",
    re.I,
)


def log_dir() -> pathlib.Path:
    if os.environ.get("CAVERNO_SESSION_LOG_DIR"):
        return pathlib.Path(os.environ["CAVERNO_SESSION_LOG_DIR"]).expanduser()
    home = os.environ.get("CAVERNO_HOME") or "~/.caverno"
    return pathlib.Path(home).expanduser() / "session_logs"


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


def plausible_answer(record: dict) -> str | None:
    """The user-visible answer text of a response, or None.

    Drops memory-extraction and other structured calls by rejecting JSON
    objects, and drops empty content.
    """
    response = record.get("response")
    if not isinstance(response, dict):
        return None
    content = response.get("content")
    if not isinstance(content, str):
        return None
    stripped = content.strip()
    if not stripped or stripped.startswith("{"):
        return None
    return stripped


def collect(paths, since_days: int | None):
    cutoff = None
    if since_days is not None:
        cutoff = dt.datetime.now() - dt.timedelta(days=since_days)

    turns = 0
    turns_with_answer = 0
    candidates = []
    pattern_hits = collections.Counter()
    reason_of_candidates = collections.Counter()
    reason_of_all = collections.Counter()

    for path in paths:
        if cutoff is not None:
            try:
                if dt.datetime.fromtimestamp(path.stat().st_mtime) < cutoff:
                    continue
            except OSError:
                continue

        pending_answer: str | None = None
        for record in iter_records(path):
            answer = plausible_answer(record)
            if answer is not None:
                pending_answer = answer

            if record.get("operation") != "turn_exit":
                continue

            turns += 1
            exit_info = record.get("turnExit") or {}
            reason = exit_info.get("reason", "(none)")
            reason_of_all[reason] += 1

            if pending_answer is None:
                pending_answer = None
                continue
            turns_with_answer += 1

            matched = [
                name
                for name, pattern in COMMITMENT_PATTERNS
                if pattern.search(pending_answer)
            ]
            if matched:
                asks_user = bool(ASKS_USER.search(pending_answer[-200:]))
                for name in matched:
                    pattern_hits[name] += 1
                reason_of_candidates[reason] += 1
                candidates.append(
                    {
                        "asks_user": asks_user,
                        "session": path.name[:8],
                        "turn": exit_info.get("turnId"),
                        "reason": reason,
                        "transforms": exit_info.get("transforms") or [],
                        "patterns": matched,
                        "answer": pending_answer,
                    }
                )
            pending_answer = None

    return {
        "turns": turns,
        "turns_with_answer": turns_with_answer,
        "candidates": candidates,
        "pattern_hits": pattern_hits,
        "reason_of_candidates": reason_of_candidates,
        "reason_of_all": reason_of_all,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--since-days", type=int, default=None)
    parser.add_argument(
        "--sample",
        type=int,
        default=0,
        help="print N candidate answers so precision can be judged by eye",
    )
    args = parser.parse_args()

    root = log_dir()
    if not root.is_dir():
        print(f"No session log directory at {root}", file=sys.stderr)
        return 1
    paths = sorted(root.glob("*/*.jsonl")) + sorted(root.glob("*.jsonl"))
    if not paths:
        print(f"No session logs under {root}", file=sys.stderr)
        return 1

    result = collect(paths, args.since_days)
    turns = result["turns"]
    with_answer = result["turns_with_answer"]
    candidates = result["candidates"]

    print(f"== Turns ending on an announced next step ({root}) ==")
    print(f"{len(paths)} session logs, {turns} turns, {with_answer} with a final answer")
    if with_answer:
        share = 100 * len(candidates) / with_answer
        print(f"candidates: {len(candidates)} ({share:.1f}% of turns with an answer)")
    print("\nNOTE: candidates are lexical matches, not confirmed skips. Use")
    print("--sample to judge precision before quoting any of this.")

    if result["pattern_hits"]:
        print("\n== Which pattern matched ==")
        for name, count in result["pattern_hits"].most_common():
            print(f"{count:5}  {name}")

    if result["reason_of_candidates"]:
        print("\n== Turn-exit reason, candidates vs all turns ==")
        print(f"{'reason':28}{'candidates':>11}{'all turns':>11}")
        for reason, count in result["reason_of_all"].most_common():
            print(f"{reason:28}{result['reason_of_candidates'][reason]:11}{count:11}")

    asks = [c for c in candidates if c["asks_user"]]
    commits = [c for c in candidates if not c["asks_user"]]
    print("\n== Handoff vs commitment ==")
    print(f"{len(asks):5}  hand the decision back to the user (legitimate ending)")
    print(f"{len(commits):5}  commit to a further action")

    transform_bearing = [c for c in candidates if c["transforms"]]
    print(
        f"\ncandidates whose turn recorded any guard transform: "
        f"{len(transform_bearing)} of {len(candidates)}"
    )

    if args.sample and candidates:
        step = max(1, len(candidates) // args.sample)
        print(f"\n== Sample ({args.sample}) for precision judgement ==")
        for candidate in candidates[::step][: args.sample]:
            tail = candidate["answer"][-320:].replace("\n", " ")
            print(f"\n--- {candidate['session']} {candidate['turn']} "
                  f"[{candidate['reason']}] {candidate['patterns']}")
            print(f"    …{tail}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

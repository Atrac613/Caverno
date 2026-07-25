#!/usr/bin/env python3
"""Summarize one planner A/B canary run from its session logs.

Reads the session logs a run produced and reports the numbers the two arms are
compared on, plus the check that matters most: which model actually served plan
drafting. A harness that quietly ran both phases on the same model would
otherwise yield a confident, wrong measurement.

Plan-drafting requests are identified structurally — a non-streaming completion
whose user message opens with the proposal instruction the planning prompt
service emits — not by guessing from model names.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

PROPOSAL_PREFIXES = (
    "Create a workflow proposal",
    "Create a task proposal",
)


def load_entries(session_log_root: pathlib.Path) -> list[dict]:
    entries: list[dict] = []
    for path in sorted(session_log_root.rglob("*.jsonl")):
        for line in path.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def is_plan_drafting(entry: dict) -> bool:
    request = entry.get("request") or {}
    for message in request.get("messages") or []:
        if message.get("role") != "user":
            continue
        content = (message.get("content") or "").lstrip()
        if content.startswith(PROPOSAL_PREFIXES):
            return True
    return False


def summarize(entries: list[dict]) -> dict:
    planning_models: dict[str, int] = {}
    execution_models: dict[str, int] = {}
    planning_seconds = 0.0
    execution_seconds = 0.0
    truncations = 0

    for entry in entries:
        request = entry.get("request") or {}
        model = request.get("model")
        if model is None:
            continue
        duration = (entry.get("durationMs") or 0) / 1000
        if (entry.get("response") or {}).get("finishReason") == "length":
            truncations += 1
        bucket = planning_models if is_plan_drafting(entry) else execution_models
        bucket[model] = bucket.get(model, 0) + 1
        if bucket is planning_models:
            planning_seconds += duration
        else:
            execution_seconds += duration

    return {
        "planningCallsByModel": planning_models,
        "executionCallsByModel": execution_models,
        "planningCallCount": sum(planning_models.values()),
        "executionCallCount": sum(execution_models.values()),
        "planningSeconds": round(planning_seconds, 1),
        "executionSeconds": round(execution_seconds, 1),
        "lengthTruncations": truncations,
    }


def read_suite_report(path: pathlib.Path) -> dict:
    if not path.is_file():
        return {"available": False}
    report = json.loads(path.read_text())
    quality = report.get("reportQualitySummary") or {}
    scenarios = report.get("scenarios") or []
    return {
        "available": True,
        "ready": quality.get("ready"),
        "blockerCount": quality.get("blockerCount"),
        "scenarioResults": [
            {
                "name": scenario.get("name"),
                "status": scenario.get("status") or scenario.get("result"),
            }
            for scenario in scenarios
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--session-logs", required=True)
    parser.add_argument("--suite-report", required=True)
    parser.add_argument("--arm", required=True)
    parser.add_argument("--expected-planning-model", required=True)
    parser.add_argument("--expected-execution-model", required=True)
    parser.add_argument("--wall-clock-seconds", type=int, required=True)
    parser.add_argument("--run-status", type=int, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    entries = load_entries(pathlib.Path(args.session_logs))
    summary = summarize(entries)
    summary.update(
        arm=args.arm,
        wallClockSeconds=args.wall_clock_seconds,
        runStatus=args.run_status,
        suiteReport=read_suite_report(pathlib.Path(args.suite_report)),
    )

    planning_models = set(summary["planningCallsByModel"])
    execution_models = set(summary["executionCallsByModel"])
    problems = []
    if not planning_models:
        problems.append("no plan-drafting request was recorded")
    elif planning_models != {args.expected_planning_model}:
        problems.append(
            "plan drafting ran on "
            f"{sorted(planning_models)}, expected {args.expected_planning_model}"
        )
    if execution_models and execution_models != {args.expected_execution_model}:
        problems.append(
            "execution ran on "
            f"{sorted(execution_models)}, expected {args.expected_execution_model}"
        )
    summary["armVerified"] = not problems
    summary["armProblems"] = problems

    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2, ensure_ascii=False))

    print(f"  Arm: {args.arm} (verified: {summary['armVerified']})")
    print(f"  Plan drafting: {summary['planningCallsByModel']} "
          f"({summary['planningSeconds']}s)")
    print(f"  Execution:     {summary['executionCallsByModel']} "
          f"({summary['executionSeconds']}s)")
    print(f"  Length truncations: {summary['lengthTruncations']}")
    print(f"  Wall clock: {summary['wallClockSeconds']}s")
    for problem in problems:
        print(f"  ARM PROBLEM: {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())

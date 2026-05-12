#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M23_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m23_cycle_outcome_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/cycle_outcome_handoff.json"
SUMMARY_MD="${RUN_DIR}/cycle_outcome_handoff.md"
M22_REVIEW=""
OUTCOME_ACCEPTED="no"
NEXT_OBSERVE_NEEDED="unknown"
NEXT_OBSERVE_NOTE=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh [options]

Options:
  --root PATH                    Report root directory.
  --m22-review PATH              M22 post-action review JSON.
  --outcome-accepted VALUE       yes or no.
  --next-observe-needed VALUE    yes, no, or unknown.
  --next-observe-note TEXT       Optional user-provided next observe note.
  --help                         Show this help.

This M23 handoff is report-only. It reads ready M22 post-action review evidence
and records whether the completed action cycle should be closed or restarted
with a new observe-only pass. It does not call an LLM, grant TCC, open apps,
operate System Settings, move the pointer, click, type, submit, post, purchase,
or perform desktop actions.
USAGE
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --m22-review)
      require_value "$@"
      M22_REVIEW="$2"
      shift 2
      ;;
    --outcome-accepted)
      require_value "$@"
      OUTCOME_ACCEPTED="$2"
      shift 2
      ;;
    --next-observe-needed)
      require_value "$@"
      NEXT_OBSERVE_NEEDED="$2"
      shift 2
      ;;
    --next-observe-note)
      require_value "$@"
      NEXT_OBSERVE_NOTE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m23_cycle_outcome_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/cycle_outcome_handoff.json"
SUMMARY_MD="${RUN_DIR}/cycle_outcome_handoff.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M22_REVIEW}" ]]; then
  M22_REVIEW="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m22_post_action_review_*/post_action_review.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M22_REVIEW}" ]]; then
  echo "M22 post-action review not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M22_REVIEW}" ]]; then
  echo "M22 post-action review not found: ${M22_REVIEW}" >&2
  exit 66
fi

echo "Running macOS Computer Use M23 cycle outcome handoff"
echo "  Purpose: close or restart the action cycle from ready M22 review evidence"
echo "  M22 review: ${M22_REVIEW}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M22_REVIEW="${M22_REVIEW}" \
OUTCOME_ACCEPTED="${OUTCOME_ACCEPTED}" \
NEXT_OBSERVE_NEEDED="${NEXT_OBSERVE_NEEDED}" \
NEXT_OBSERVE_NOTE="${NEXT_OBSERVE_NOTE}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m22_review_path = Path(os.environ["M22_REVIEW"])

m22 = json.loads(m22_review_path.read_text())
gate = m22.get("m22PostActionReviewGate")
gate = gate if isinstance(gate, dict) else {}
review_inputs = m22.get("reviewInputs")
review_inputs = review_inputs if isinstance(review_inputs, dict) else {}
source_manual_inputs = m22.get("sourceManualInputs")
source_manual_inputs = (
    source_manual_inputs if isinstance(source_manual_inputs, dict) else {}
)
approved_values = m22.get("approvedValues")
approved_values = approved_values if isinstance(approved_values, dict) else {}

handoff_inputs = {
    "outcomeAccepted": os.environ["OUTCOME_ACCEPTED"].strip().lower(),
    "nextObserveNeeded": os.environ["NEXT_OBSERVE_NEEDED"].strip().lower(),
    "nextObserveNote": os.environ["NEXT_OBSERVE_NOTE"],
}

recommendation = str(m22.get("nextCycleRecommendation") or "unknown")


def value_allowed(value, allowed):
    return value in allowed


checks = [
    {
        "id": "m22_review_schema_valid",
        "ok": m22.get("schemaName") == "macos_computer_use_m22_post_action_review"
        and m22.get("milestone") == "M22",
        "nextAction": "Select a valid M22 post_action_review.json before preparing the cycle outcome handoff.",
    },
    {
        "id": "m22_review_ready",
        "ok": bool(m22.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M22 post-action review until m22PostActionReviewGate.status is ready.",
    },
    {
        "id": "desktop_boundary_report_only",
        "ok": m22.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M23 must only read review evidence; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m22.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M23.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m22.get("llmBoundary") == "no_llm_call",
        "nextAction": "M23 cycle outcome handoff must not call an LLM.",
    },
    {
        "id": "outcome_accepted",
        "ok": handoff_inputs["outcomeAccepted"] == "yes",
        "nextAction": "Ask the user to accept the reviewed M22 outcome before closing or restarting the cycle.",
    },
    {
        "id": "next_observe_needed_valid",
        "ok": value_allowed(handoff_inputs["nextObserveNeeded"], {"yes", "no", "unknown"}),
        "nextAction": "Use a valid next-observe-needed value: yes, no, or unknown.",
    },
    {
        "id": "next_observe_needed_known",
        "ok": handoff_inputs["nextObserveNeeded"] in {"yes", "no"},
        "nextAction": "Ask the user whether the next cycle needs a new observe-only pass.",
    },
    {
        "id": "next_observe_matches_m22_recommendation",
        "ok": (
            recommendation == "start_new_observe_action_cycle"
            and handoff_inputs["nextObserveNeeded"] == "yes"
        )
        or (
            recommendation == "no_follow_up"
            and handoff_inputs["nextObserveNeeded"] == "no"
        ),
        "nextAction": "Keep M23 next-observe-needed aligned with the M22 nextCycleRecommendation.",
    },
    {
        "id": "next_observe_note_recorded_when_needed",
        "ok": handoff_inputs["nextObserveNeeded"] != "yes"
        or bool(handoff_inputs["nextObserveNote"].strip())
        or bool(str(review_inputs.get("followUpNote") or "").strip()),
        "nextAction": "Record a next-observe note when M23 restarts the observe/action cycle.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
next_observe_needed = handoff_inputs["nextObserveNeeded"] == "yes"
cycle_outcome = (
    "restart_observe_action_cycle"
    if next_observe_needed
    else ("closed" if ready else "unknown")
)
next_observe_note = (
    handoff_inputs["nextObserveNote"].strip()
    or str(review_inputs.get("followUpNote") or "").strip()
)

gate_next_action = (
    "Start a new M14 observe-only evidence pass with the recorded follow-up note."
    if ready and next_observe_needed
    else (
        "Archive the completed action cycle evidence."
        if ready
        else "Resolve M23 cycle outcome blockers before closing or restarting the action cycle."
    )
)

summary = {
    "schemaName": "macos_computer_use_m23_cycle_outcome_handoff",
    "schemaVersion": 1,
    "purpose": "computer_use_m23_cycle_outcome_handoff",
    "milestone": "M23",
    "previousMilestone": "M22",
    "ready": ready,
    "sourceM22PostActionReview": str(m22_review_path),
    "executionBoundary": "cycle_outcome_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceNextCycleRecommendation": recommendation,
    "cycleOutcome": cycle_outcome,
    "approvedValues": {
        "exactText": approved_values.get("exactText"),
        "targetLabel": approved_values.get("targetLabel"),
        "publicActionLabel": approved_values.get("publicActionLabel"),
    },
    "sourceReviewInputs": review_inputs,
    "sourceManualInputs": source_manual_inputs,
    "handoffInputs": handoff_inputs,
    "nextObserveSeed": {
        "required": next_observe_needed,
        "source": "m23_cycle_outcome_handoff",
        "note": next_observe_note,
        "returnMilestone": "M14" if next_observe_needed else None,
        "boundary": "observe_only_no_desktop_action",
    },
    "m23CycleOutcomeHandoffGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This handoff does not execute desktop actions.",
        "It reads ready M22 review evidence.",
        "TCC, System Settings, LLM calls, clicks, typing, submits, posts, and purchases remain outside this script.",
        "Any new action must restart at observe-only evidence before approval or execution.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M23 Cycle Outcome Handoff",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M22 post-action review: `{m22_review_path}`",
    "- Boundary: report-only cycle outcome handoff, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Source next cycle recommendation: {recommendation}",
    f"- Cycle outcome: {cycle_outcome}",
    "",
    "## Gate",
    "",
]
for check in checks:
    status = "ready" if check["ok"] else "blocked"
    md_lines.append(
        f"- `{check['id']}`: {status}"
        + ("" if check["ok"] else f" - {check['nextAction']}")
    )

md_lines.extend(
    [
        "",
        "## Handoff Inputs",
        "",
        "| Input | Value |",
        "| --- | --- |",
    ]
)
for key, value in handoff_inputs.items():
    md_lines.append(f"| {cell(key)} | {cell(value)} |")

md_lines.extend(
    [
        "",
        "## Next Observe Seed",
        "",
        f"- Required: {str(next_observe_needed).lower()}",
        f"- Return milestone: {'M14' if next_observe_needed else '-'}",
        f"- Note: {next_observe_note or '-'}",
        "",
        "## Source Review",
        "",
        f"- Result reviewed: {review_inputs.get('resultReviewed', '-')}",
        f"- Post-action state: {review_inputs.get('postActionState', '-')}",
        f"- Follow-up required: {review_inputs.get('followUpRequired', '-')}",
        f"- Runtime action: {source_manual_inputs.get('runtimeAction', '-')}",
        f"- Post-action observation: {source_manual_inputs.get('postActionObservation', '-')}",
        "",
        "## Manual Boundary",
        "",
        "This cycle outcome handoff only records whether a completed",
        "user-operated runtime cycle is closed or needs a new observe-only",
        "pass. Any follow-up action must start a new approval-bound cycle.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M23 cycle outcome handoff written to {summary_json}")
print(f"M23 cycle outcome handoff Markdown written to {summary_md}")
print(f"Gate status: {summary['m23CycleOutcomeHandoffGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Cycle outcome: {cycle_outcome}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

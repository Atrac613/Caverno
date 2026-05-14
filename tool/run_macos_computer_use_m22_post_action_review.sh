#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M22_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m22_post_action_review_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/post_action_review.json"
SUMMARY_MD="${RUN_DIR}/post_action_review.md"
M20_INTAKE=""
RESULT_REVIEWED="no"
POST_ACTION_STATE="unknown"
FOLLOW_UP_REQUIRED="no"
FOLLOW_UP_NOTE=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m22_post_action_review.sh [options]

Options:
  --root PATH                    Report root directory.
  --m20-intake PATH              M20 execution result intake JSON.
  --result-reviewed VALUE        yes or no.
  --post-action-state VALUE      stable, needs-follow-up, or unknown.
  --follow-up-required VALUE     yes or no.
  --follow-up-note TEXT          Optional user-provided follow-up note.
  --help                         Show this help.

This M22 review is report-only. It reads ready M20 user-reported runtime
result evidence and records whether the result was reviewed and whether a new
observe/action approval cycle is required. It does not call an LLM, grant TCC,
open apps, operate System Settings, move the pointer, click, type, submit,
post, purchase, or perform desktop actions.
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
    --m20-intake)
      require_value "$@"
      M20_INTAKE="$2"
      shift 2
      ;;
    --result-reviewed)
      require_value "$@"
      RESULT_REVIEWED="$2"
      shift 2
      ;;
    --post-action-state)
      require_value "$@"
      POST_ACTION_STATE="$2"
      shift 2
      ;;
    --follow-up-required)
      require_value "$@"
      FOLLOW_UP_REQUIRED="$2"
      shift 2
      ;;
    --follow-up-note)
      require_value "$@"
      FOLLOW_UP_NOTE="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m22_post_action_review_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/post_action_review.json"
SUMMARY_MD="${RUN_DIR}/post_action_review.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M20_INTAKE}" ]]; then
  M20_INTAKE="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m20_execution_result_intake_*/execution_result_intake.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M20_INTAKE}" ]]; then
  echo "M20 execution result intake not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M20_INTAKE}" ]]; then
  echo "M20 execution result intake not found: ${M20_INTAKE}" >&2
  exit 66
fi

echo "Running macOS Computer Use M22 post-action review"
echo "  Purpose: review user-operated runtime result evidence from ready M20 intake"
echo "  M20 intake: ${M20_INTAKE}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M20_INTAKE="${M20_INTAKE}" \
RESULT_REVIEWED="${RESULT_REVIEWED}" \
POST_ACTION_STATE="${POST_ACTION_STATE}" \
FOLLOW_UP_REQUIRED="${FOLLOW_UP_REQUIRED}" \
FOLLOW_UP_NOTE="${FOLLOW_UP_NOTE}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m20_intake_path = Path(os.environ["M20_INTAKE"])

m20 = json.loads(m20_intake_path.read_text())
gate = m20.get("m20ExecutionResultIntakeGate")
gate = gate if isinstance(gate, dict) else {}
manual_inputs = m20.get("manualInputs")
manual_inputs = manual_inputs if isinstance(manual_inputs, dict) else {}
approved_values = m20.get("approvedValues")
approved_values = approved_values if isinstance(approved_values, dict) else {}

review_inputs = {
    "resultReviewed": os.environ["RESULT_REVIEWED"].strip().lower(),
    "postActionState": os.environ["POST_ACTION_STATE"].strip().lower(),
    "followUpRequired": os.environ["FOLLOW_UP_REQUIRED"].strip().lower(),
    "followUpNote": os.environ["FOLLOW_UP_NOTE"],
}


def value_allowed(value, allowed):
    return value in allowed


checks = [
    {
        "id": "m20_intake_schema_valid",
        "ok": m20.get("schemaName")
        == "macos_computer_use_m20_execution_result_intake"
        and m20.get("milestone") == "M20",
        "nextAction": "Select a valid M20 execution_result_intake.json before reviewing the result.",
    },
    {
        "id": "m20_intake_ready",
        "ok": bool(m20.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M20 execution result intake until m20ExecutionResultIntakeGate.status is ready.",
    },
    {
        "id": "desktop_boundary_user_evidence_only",
        "ok": m20.get("desktopActionBoundary") == "user_operated_evidence_only",
        "nextAction": "M22 must only review user-operated evidence; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m20.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M22.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m20.get("llmBoundary") == "no_llm_call",
        "nextAction": "M22 post-action review must not call an LLM.",
    },
    {
        "id": "runtime_action_succeeded",
        "ok": manual_inputs.get("runtimeAction") == "succeeded",
        "nextAction": "Review only a succeeded user-operated runtime action before closing the action cycle.",
    },
    {
        "id": "post_action_observation_done",
        "ok": manual_inputs.get("postActionObservation") == "done",
        "nextAction": "Record the post-action observation in M20 before reviewing the result.",
    },
    {
        "id": "result_reviewed",
        "ok": review_inputs["resultReviewed"] == "yes",
        "nextAction": "Ask the user to review the M20 runtime result before marking M22 ready.",
    },
    {
        "id": "post_action_state_valid",
        "ok": value_allowed(
            review_inputs["postActionState"],
            {"stable", "needs-follow-up", "unknown"},
        ),
        "nextAction": "Use a valid post-action state: stable, needs-follow-up, or unknown.",
    },
    {
        "id": "post_action_state_known",
        "ok": review_inputs["postActionState"] in {"stable", "needs-follow-up"},
        "nextAction": "Ask the user whether the post-action state is stable or needs follow-up.",
    },
    {
        "id": "follow_up_required_valid",
        "ok": value_allowed(review_inputs["followUpRequired"], {"yes", "no"}),
        "nextAction": "Use yes or no for follow-up-required.",
    },
    {
        "id": "follow_up_note_recorded_when_required",
        "ok": review_inputs["followUpRequired"] != "yes"
        or bool(review_inputs["followUpNote"].strip()),
        "nextAction": "Record a follow-up note when the result needs another action cycle.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
follow_up_required = review_inputs["followUpRequired"] == "yes"
next_cycle_recommendation = (
    "start_new_observe_action_cycle" if follow_up_required else "no_follow_up"
)
gate_next_action = (
    "Return to M14 observe-only evidence before proposing any follow-up action."
    if ready and follow_up_required
    else (
        "Archive the reviewed M20 result as the completed action cycle evidence."
        if ready
        else "Resolve M22 post-action review blockers before closing the action cycle."
    )
)

summary = {
    "schemaName": "macos_computer_use_m22_post_action_review",
    "schemaVersion": 1,
    "purpose": "computer_use_m22_post_action_review",
    "milestone": "M22",
    "previousMilestone": "M20",
    "ready": ready,
    "sourceM20ExecutionResultIntake": str(m20_intake_path),
    "executionBoundary": "post_action_review_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "approvedValues": {
        "exactText": approved_values.get("exactText"),
        "targetLabel": approved_values.get("targetLabel"),
        "publicActionLabel": approved_values.get("publicActionLabel"),
    },
    "sourceManualInputs": manual_inputs,
    "reviewInputs": review_inputs,
    "nextCycleRecommendation": next_cycle_recommendation,
    "m22PostActionReviewGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This review does not execute desktop actions.",
        "It reads ready M20 user-reported result evidence.",
        "TCC, System Settings, LLM calls, clicks, typing, submits, posts, and purchases remain outside this script.",
        "Any follow-up action must start a new observe and approval cycle.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M22 Post-Action Review",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M20 execution result intake: `{m20_intake_path}`",
    "- Boundary: report-only post-action review, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Next cycle recommendation: {next_cycle_recommendation}",
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
        "## Review Inputs",
        "",
        "| Input | Value |",
        "| --- | --- |",
    ]
)
for key, value in review_inputs.items():
    md_lines.append(f"| {cell(key)} | {cell(value)} |")

md_lines.extend(
    [
        "",
        "## Source Result",
        "",
        f"- Runtime action: {manual_inputs.get('runtimeAction', '-')}",
        f"- Post-action observation: {manual_inputs.get('postActionObservation', '-')}",
        f"- Target: {approved_values.get('targetLabel', '-')}",
        f"- Exact text: {approved_values.get('exactText', '-')}",
        f"- Public action: {approved_values.get('publicActionLabel', '-')}",
        "",
        "## Manual Boundary",
        "",
        "This post-action review only records review evidence for a completed",
        "user-operated runtime step. Any follow-up desktop action must start a",
        "new observe-only evidence and approval-bound cycle.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M22 post-action review written to {summary_json}")
print(f"M22 post-action review Markdown written to {summary_md}")
print(f"Gate status: {summary['m22PostActionReviewGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Next cycle recommendation: {next_cycle_recommendation}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M20_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m20_execution_result_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_result_intake.json"
SUMMARY_MD="${RUN_DIR}/execution_result_intake.md"
M18_HANDOFF=""
FRESH_OBSERVATION="missing"
TARGET_CONFIRMED="no"
EXACT_TEXT_CONFIRMED="no"
PUBLIC_ACTION_CONFIRMED="not-applicable"
RUNTIME_ACTION="not-run"
POST_ACTION_OBSERVATION="missing"
OPERATOR_NOTE=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m20_execution_result_intake.sh [options]

Options:
  --root PATH                    Report root directory.
  --m18-handoff PATH             M18 execution handoff JSON.
  --fresh-observation VALUE      done or missing.
  --target-confirmed VALUE       yes, no, or not-required.
  --exact-text-confirmed VALUE   yes, no, or not-required.
  --public-action-confirmed VALUE yes, no, or not-applicable.
  --runtime-action VALUE         succeeded, failed, aborted, or not-run.
  --post-action-observation VALUE done or missing.
  --operator-note TEXT           Optional user-provided result note.
  --help                         Show this help.

This M20 intake is report-only. It records user-operated runtime result
evidence after an M18 handoff. It does not call an LLM, grant TCC, open apps,
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
    --m18-handoff)
      require_value "$@"
      M18_HANDOFF="$2"
      shift 2
      ;;
    --fresh-observation)
      require_value "$@"
      FRESH_OBSERVATION="$2"
      shift 2
      ;;
    --target-confirmed)
      require_value "$@"
      TARGET_CONFIRMED="$2"
      shift 2
      ;;
    --exact-text-confirmed)
      require_value "$@"
      EXACT_TEXT_CONFIRMED="$2"
      shift 2
      ;;
    --public-action-confirmed)
      require_value "$@"
      PUBLIC_ACTION_CONFIRMED="$2"
      shift 2
      ;;
    --runtime-action)
      require_value "$@"
      RUNTIME_ACTION="$2"
      shift 2
      ;;
    --post-action-observation)
      require_value "$@"
      POST_ACTION_OBSERVATION="$2"
      shift 2
      ;;
    --operator-note)
      require_value "$@"
      OPERATOR_NOTE="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m20_execution_result_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_result_intake.json"
SUMMARY_MD="${RUN_DIR}/execution_result_intake.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M18_HANDOFF}" ]]; then
  M18_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m18_execution_handoff_*/execution_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M18_HANDOFF}" ]]; then
  echo "M18 execution handoff not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M18_HANDOFF}" ]]; then
  echo "M18 execution handoff not found: ${M18_HANDOFF}" >&2
  exit 66
fi

echo "Running macOS Computer Use M20 execution result intake"
echo "  Purpose: record user-operated runtime result evidence from ready M18 handoff"
echo "  M18 handoff: ${M18_HANDOFF}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M18_HANDOFF="${M18_HANDOFF}" \
FRESH_OBSERVATION="${FRESH_OBSERVATION}" \
TARGET_CONFIRMED="${TARGET_CONFIRMED}" \
EXACT_TEXT_CONFIRMED="${EXACT_TEXT_CONFIRMED}" \
PUBLIC_ACTION_CONFIRMED="${PUBLIC_ACTION_CONFIRMED}" \
RUNTIME_ACTION="${RUNTIME_ACTION}" \
POST_ACTION_OBSERVATION="${POST_ACTION_OBSERVATION}" \
OPERATOR_NOTE="${OPERATOR_NOTE}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m18_handoff_path = Path(os.environ["M18_HANDOFF"])

m18 = json.loads(m18_handoff_path.read_text())
gate = m18.get("m18ExecutionHandoffGate")
gate = gate if isinstance(gate, dict) else {}
approved_values = m18.get("approvedValues")
approved_values = approved_values if isinstance(approved_values, dict) else {}
confirmations = m18.get("actionTimeConfirmations")
confirmations = confirmations if isinstance(confirmations, list) else []
checklist = m18.get("executionChecklist")
checklist = checklist if isinstance(checklist, list) else []

manual_inputs = {
    "freshObservation": os.environ["FRESH_OBSERVATION"].strip().lower(),
    "targetConfirmed": os.environ["TARGET_CONFIRMED"].strip().lower(),
    "exactTextConfirmed": os.environ["EXACT_TEXT_CONFIRMED"].strip().lower(),
    "publicActionConfirmed": os.environ["PUBLIC_ACTION_CONFIRMED"].strip().lower(),
    "runtimeAction": os.environ["RUNTIME_ACTION"].strip().lower(),
    "postActionObservation": os.environ["POST_ACTION_OBSERVATION"].strip().lower(),
    "operatorNote": os.environ["OPERATOR_NOTE"],
}


def confirmation_required(confirmation_id):
    for item in confirmations:
        if isinstance(item, dict) and item.get("id") == confirmation_id:
            return bool(item.get("required"))
    return False


def value_allowed(value, allowed):
    return value in allowed


target_required = confirmation_required("target_label")
exact_text_required = confirmation_required("exact_text")
public_action_required = bool(m18.get("publicActionRequiresSeparateApproval"))

checks = [
    {
        "id": "m18_handoff_schema_valid",
        "ok": m18.get("schemaName") == "macos_computer_use_m18_execution_handoff"
        and m18.get("milestone") == "M18",
        "nextAction": "Select a valid M18 execution_handoff.json before recording result evidence.",
    },
    {
        "id": "m18_handoff_ready",
        "ok": bool(m18.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M18 execution handoff until m18ExecutionHandoffGate.status is ready.",
    },
    {
        "id": "desktop_boundary_user_operated",
        "ok": m18.get("desktopActionBoundary") == "user_operated_only",
        "nextAction": "M20 must only record user-operated desktop action evidence.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m18.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain user-operated and outside this intake.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m18.get("llmBoundary") == "no_llm_call",
        "nextAction": "M20 result intake must not call an LLM.",
    },
    {
        "id": "fresh_observation_recorded",
        "ok": manual_inputs["freshObservation"] == "done",
        "nextAction": "Ask the user to record that a fresh observation was completed before the runtime action.",
    },
    {
        "id": "target_confirmation_recorded",
        "ok": (not target_required and manual_inputs["targetConfirmed"] == "not-required")
        or (target_required and manual_inputs["targetConfirmed"] == "yes"),
        "nextAction": "Ask the user to confirm the target matched the approved target label at action time.",
    },
    {
        "id": "exact_text_confirmation_recorded",
        "ok": (not exact_text_required and manual_inputs["exactTextConfirmed"] == "not-required")
        or (exact_text_required and manual_inputs["exactTextConfirmed"] == "yes"),
        "nextAction": "Ask the user to confirm the typed text exactly matched the approved text at action time.",
    },
    {
        "id": "public_action_confirmation_recorded",
        "ok": (not public_action_required and manual_inputs["publicActionConfirmed"] == "not-applicable")
        or (public_action_required and manual_inputs["publicActionConfirmed"] == "yes"),
        "nextAction": "Ask the user to confirm any public action separately at action time.",
    },
    {
        "id": "runtime_action_status_valid",
        "ok": value_allowed(
            manual_inputs["runtimeAction"],
            {"succeeded", "failed", "aborted", "not-run"},
        ),
        "nextAction": "Use a valid runtime action status: succeeded, failed, aborted, or not-run.",
    },
    {
        "id": "runtime_action_succeeded",
        "ok": manual_inputs["runtimeAction"] == "succeeded",
        "nextAction": "Record a succeeded user-operated runtime action before marking M20 ready.",
    },
    {
        "id": "post_action_observation_recorded",
        "ok": manual_inputs["postActionObservation"] == "done",
        "nextAction": "Ask the user to record that post-action observation was completed.",
    },
]

for input_id, allowed in [
    ("freshObservation", {"done", "missing"}),
    ("targetConfirmed", {"yes", "no", "not-required"}),
    ("exactTextConfirmed", {"yes", "no", "not-required"}),
    ("publicActionConfirmed", {"yes", "no", "not-applicable"}),
    ("postActionObservation", {"done", "missing"}),
]:
    checks.append(
        {
            "id": f"{input_id}_value_valid",
            "ok": manual_inputs[input_id] in allowed,
            "nextAction": f"Use a valid value for {input_id}: {', '.join(sorted(allowed))}.",
        }
    )

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers

result_sequence = [
    {
        "id": "fresh_observation",
        "source": "user_reported",
        "status": manual_inputs["freshObservation"],
        "required": True,
    },
    {
        "id": "target_confirmation",
        "source": "user_reported",
        "status": manual_inputs["targetConfirmed"],
        "required": target_required,
        "approvedValue": approved_values.get("targetLabel"),
    },
    {
        "id": "exact_text_confirmation",
        "source": "user_reported",
        "status": manual_inputs["exactTextConfirmed"],
        "required": exact_text_required,
        "approvedValue": approved_values.get("exactText"),
    },
    {
        "id": "public_action_confirmation",
        "source": "user_reported",
        "status": manual_inputs["publicActionConfirmed"],
        "required": public_action_required,
        "approvedValue": approved_values.get("publicActionLabel"),
    },
    {
        "id": "runtime_action",
        "source": "user_reported",
        "status": manual_inputs["runtimeAction"],
        "required": True,
    },
    {
        "id": "post_action_observation",
        "source": "user_reported",
        "status": manual_inputs["postActionObservation"],
        "required": True,
    },
]

gate_next_action = (
    "Review the user-operated runtime result evidence before any follow-up action."
    if ready
    else "Resolve M20 result intake blockers before accepting runtime evidence."
)

summary = {
    "schemaName": "macos_computer_use_m20_execution_result_intake",
    "schemaVersion": 1,
    "purpose": "computer_use_m20_execution_result_intake",
    "milestone": "M20",
    "previousMilestone": "M18",
    "ready": ready,
    "sourceM18ExecutionHandoff": str(m18_handoff_path),
    "executionBoundary": "manual_result_intake_report_only",
    "desktopActionBoundary": "user_operated_evidence_only",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "approvedValues": {
        "exactText": approved_values.get("exactText"),
        "targetLabel": approved_values.get("targetLabel"),
        "publicActionLabel": approved_values.get("publicActionLabel"),
    },
    "manualInputs": manual_inputs,
    "requiredConfirmations": {
        "targetLabel": target_required,
        "exactText": exact_text_required,
        "publicActionLabel": public_action_required,
    },
    "resultSequence": result_sequence,
    "sourceExecutionChecklistCount": len(checklist),
    "m20ExecutionResultIntakeGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This intake does not execute desktop actions.",
        "It records only user-reported runtime result evidence.",
        "TCC, System Settings, LLM calls, clicks, typing, submits, posts, and purchases remain outside this script.",
        "Follow-up actions require a new approval-bound cycle.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M20 Execution Result Intake",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M18 execution handoff: `{m18_handoff_path}`",
    "- Boundary: report-only result intake, no LLM call, no TCC, no System Settings, no desktop actions",
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
        "## User-Reported Result Sequence",
        "",
        "| Step | Required | Status | Approved Value |",
        "| --- | --- | --- | --- |",
    ]
)
for step in result_sequence:
    md_lines.append(
        "| {id} | {required} | {status} | {value} |".format(
            id=cell(step["id"]),
            required=str(step["required"]).lower(),
            status=cell(step["status"]),
            value=cell(step.get("approvedValue")),
        )
    )

if manual_inputs["operatorNote"]:
    md_lines.extend(["", "## Operator Note", "", manual_inputs["operatorNote"]])

md_lines.extend(
    [
        "",
        "## Manual Boundary",
        "",
        "This result intake only records user-reported evidence from a separately",
        "user-operated runtime step. Any follow-up desktop action must start a new",
        "approval-bound observe and confirmation cycle.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M20 execution result intake written to {summary_json}")
print(f"M20 execution result intake Markdown written to {summary_md}")
print(f"Gate status: {summary['m20ExecutionResultIntakeGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

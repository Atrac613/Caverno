#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M18_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m18_execution_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_handoff.json"
SUMMARY_MD="${RUN_DIR}/execution_handoff.md"
M17_REHEARSAL=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m18_execution_handoff.sh [options]

Options:
  --root PATH          Report root directory.
  --m17-rehearsal PATH M17 execution rehearsal JSON.
  --help               Show this help.

This M18 handoff is report-only. It reads a ready M17 execution rehearsal and
prepares the user-operated runtime handoff. It does not call an LLM, grant TCC,
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
    --m17-rehearsal)
      require_value "$@"
      M17_REHEARSAL="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m18_execution_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_handoff.json"
SUMMARY_MD="${RUN_DIR}/execution_handoff.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M17_REHEARSAL}" ]]; then
  M17_REHEARSAL="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m17_execution_rehearsal_*/execution_rehearsal.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M17_REHEARSAL}" ]]; then
  echo "M17 execution rehearsal not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M17_REHEARSAL}" ]]; then
  echo "M17 execution rehearsal not found: ${M17_REHEARSAL}" >&2
  exit 66
fi

echo "Running macOS Computer Use M18 execution handoff"
echo "  Purpose: prepare user-operated runtime handoff from ready M17 rehearsal"
echo "  M17 rehearsal: ${M17_REHEARSAL}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M17_REHEARSAL="${M17_REHEARSAL}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m17_rehearsal_path = Path(os.environ["M17_REHEARSAL"])

m17 = json.loads(m17_rehearsal_path.read_text())
gate = m17.get("m17ExecutionRehearsalGate")
gate = gate if isinstance(gate, dict) else {}
approved_values = m17.get("approvedValues")
approved_values = approved_values if isinstance(approved_values, dict) else {}
execution_phases = m17.get("executionPhases")
execution_phases = execution_phases if isinstance(execution_phases, list) else []


def phase_by_id(phase_id):
    for phase in execution_phases:
        if isinstance(phase, dict) and phase.get("id") == phase_id:
            return phase
    return {}


approved_exact_text = approved_values.get("exactText")
approved_target_label = approved_values.get("targetLabel")
approved_public_action_label = approved_values.get("publicActionLabel")
focus_phase = phase_by_id("focus_target")
type_phase = phase_by_id("type_exact_text")
public_phase = phase_by_id("confirm_public_action")
requires_public_action = bool(public_phase)

checks = [
    {
        "id": "m17_rehearsal_schema_valid",
        "ok": m17.get("schemaName")
        == "macos_computer_use_m17_execution_rehearsal"
        and m17.get("milestone") == "M17",
        "nextAction": "Select a valid M17 execution_rehearsal.json before preparing the M18 handoff.",
    },
    {
        "id": "m17_rehearsal_ready",
        "ok": bool(m17.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M17 execution rehearsal until m17ExecutionRehearsalGate.status is ready.",
    },
    {
        "id": "desktop_boundary_reviewed",
        "ok": m17.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M18 must start from report-only rehearsal evidence before any user-operated desktop action.",
    },
    {
        "id": "tcc_boundary_reviewed",
        "ok": m17.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain user-operated and outside this handoff.",
    },
    {
        "id": "llm_boundary_reviewed",
        "ok": m17.get("llmBoundary") == "no_llm_call",
        "nextAction": "M18 handoff generation must not call an LLM.",
    },
    {
        "id": "target_confirmation_ready",
        "ok": not focus_phase or bool(approved_target_label),
        "nextAction": "Return to M16/M17 and approve the target label before runtime handoff.",
    },
    {
        "id": "exact_text_confirmation_ready",
        "ok": not type_phase or bool(approved_exact_text),
        "nextAction": "Return to M16/M17 and approve the exact text before runtime handoff.",
    },
    {
        "id": "public_action_confirmation_ready",
        "ok": not requires_public_action or bool(approved_public_action_label),
        "nextAction": "Return to M16/M17 and approve the public action label before runtime handoff.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers

action_time_confirmations = [
    {
        "id": "fresh_observation",
        "required": True,
        "approvedBeforeRun": False,
        "description": "Capture a fresh read-only observation immediately before any user-operated action.",
    },
    {
        "id": "target_label",
        "required": bool(focus_phase),
        "approvedBeforeRun": bool(approved_target_label),
        "approvedValue": approved_target_label,
        "description": "Confirm the target still matches the approved label at action time.",
    },
    {
        "id": "exact_text",
        "required": bool(type_phase),
        "approvedBeforeRun": bool(approved_exact_text),
        "approvedValue": approved_exact_text,
        "description": "Confirm the text to type is exactly the approved text at action time.",
    },
]
if requires_public_action:
    action_time_confirmations.append(
        {
            "id": "public_action_label",
            "required": True,
            "approvedBeforeRun": bool(approved_public_action_label),
            "approvedValue": approved_public_action_label,
            "description": "Ask for separate action-time approval before submit, post, send, publish, purchase, or order.",
        }
    )

execution_checklist = [
    {
        "id": "pre_execution_observe",
        "operator": "user",
        "mode": "read_only",
        "description": "User runs or requests a fresh observation before any action.",
    },
]
if focus_phase:
    execution_checklist.extend(
        [
            {
                "id": "confirm_target_at_action_time",
                "operator": "user",
                "mode": "confirmation_required",
                "approvedValue": approved_target_label,
                "description": "User confirms the current visible target still matches the approved target label.",
            },
            {
                "id": "focus_target",
                "operator": "user_operated_computer_use",
                "mode": "future_runtime_action",
                "approvedValue": approved_target_label,
                "description": "Future runtime may focus only the confirmed target.",
            },
        ]
    )
if type_phase:
    execution_checklist.extend(
        [
            {
                "id": "confirm_exact_text_at_action_time",
                "operator": "user",
                "mode": "confirmation_required",
                "approvedValue": approved_exact_text,
                "description": "User confirms the exact text immediately before typing.",
            },
            {
                "id": "type_exact_text",
                "operator": "user_operated_computer_use",
                "mode": "future_runtime_action",
                "approvedValue": approved_exact_text,
                "description": "Future runtime may type only the approved exact text.",
            },
        ]
    )
if requires_public_action:
    execution_checklist.extend(
        [
            {
                "id": "confirm_public_action_at_action_time",
                "operator": "user",
                "mode": "separate_confirmation_required",
                "approvedValue": approved_public_action_label,
                "description": "User gives separate action-time approval for the public action.",
            },
            {
                "id": "public_action",
                "operator": "user_operated_computer_use",
                "mode": "future_runtime_public_action",
                "approvedValue": approved_public_action_label,
                "description": "Future runtime may perform only the separately confirmed public action.",
            },
        ]
    )
execution_checklist.append(
    {
        "id": "post_action_observation",
        "operator": "user",
        "mode": "read_only_after_action",
        "description": "User runs or requests a read-only observation after any future action.",
    }
)

gate_next_action = (
    "Ask the user to perform the runtime step manually with fresh observation and action-time confirmations."
    if ready
    else "Resolve M18 handoff blockers before preparing any runtime execution step."
)

summary = {
    "schemaName": "macos_computer_use_m18_execution_handoff",
    "schemaVersion": 1,
    "purpose": "computer_use_m18_execution_handoff",
    "milestone": "M18",
    "previousMilestone": "M17",
    "ready": ready,
    "sourceM17ExecutionRehearsal": str(m17_rehearsal_path),
    "executionBoundary": "user_operated_runtime_handoff",
    "desktopActionBoundary": "user_operated_only",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "publicActionRequiresSeparateApproval": requires_public_action,
    "approvedValues": {
        "exactText": approved_exact_text,
        "targetLabel": approved_target_label,
        "publicActionLabel": approved_public_action_label,
    },
    "actionTimeConfirmations": action_time_confirmations,
    "executionChecklist": execution_checklist,
    "m18ExecutionHandoffGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This handoff does not execute desktop actions.",
        "The user must prepare the app state and keep TCC runtime verification user-operated.",
        "The user must confirm the target and exact text again at action time.",
        "Public actions require separate action-time approval.",
        "A fresh observation must happen before and after any future action.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")

md_lines = [
    "# macOS Computer Use M18 Execution Handoff",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M17 execution rehearsal: `{m17_rehearsal_path}`",
    "- Boundary: report-only handoff, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Public action requires separate approval: {str(requires_public_action).lower()}",
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
        "## Action-Time Confirmations",
        "",
        "| Confirmation | Required | Approved Before Run | Value |",
        "| --- | --- | --- | --- |",
    ]
)
for item in action_time_confirmations:
    md_lines.append(
        "| {id} | {required} | {approved} | {value} |".format(
            id=str(item["id"]).replace("|", "\\|"),
            required=str(item.get("required", False)).lower(),
            approved=str(item.get("approvedBeforeRun", False)).lower(),
            value=str(item.get("approvedValue") or "-").replace("|", "\\|"),
        )
    )

md_lines.extend(
    [
        "",
        "## User-Operated Checklist",
        "",
        "| Step | Operator | Mode | Value |",
        "| --- | --- | --- | --- |",
    ]
)
for step in execution_checklist:
    md_lines.append(
        "| {id} | {operator} | {mode} | {value} |".format(
            id=str(step["id"]).replace("|", "\\|"),
            operator=str(step["operator"]).replace("|", "\\|"),
            mode=str(step["mode"]).replace("|", "\\|"),
            value=str(step.get("approvedValue") or "-").replace("|", "\\|"),
        )
    )

md_lines.extend(
    [
        "",
        "## Manual Boundary",
        "",
        "This handoff is not an execution engine. It is a user-operated runtime",
        "checklist for a future step that must keep observation, approval, action,",
        "and post-action observation separate.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M18 execution handoff written to {summary_json}")
print(f"M18 execution handoff Markdown written to {summary_md}")
print(f"Gate status: {summary['m18ExecutionHandoffGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

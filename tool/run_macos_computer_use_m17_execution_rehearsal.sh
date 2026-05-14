#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M17_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m17_execution_rehearsal_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_rehearsal.json"
SUMMARY_MD="${RUN_DIR}/execution_rehearsal.md"
M16_PACKET=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m17_execution_rehearsal.sh [options]

Options:
  --root PATH       Report root directory.
  --m16-packet PATH M16 approval packet JSON.
  --help            Show this help.

This M17 rehearsal is report-only. It reads an approved M16 approval packet and
prepares the future execution checklist. It does not call an LLM, grant TCC,
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
    --m16-packet)
      require_value "$@"
      M16_PACKET="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m17_execution_rehearsal_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/execution_rehearsal.json"
SUMMARY_MD="${RUN_DIR}/execution_rehearsal.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M16_PACKET}" ]]; then
  M16_PACKET="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m16_approval_packet_*/approval_packet.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M16_PACKET}" ]]; then
  echo "M16 approval packet not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M16_PACKET}" ]]; then
  echo "M16 approval packet not found: ${M16_PACKET}" >&2
  exit 66
fi

echo "Running macOS Computer Use M17 execution rehearsal"
echo "  Purpose: prepare future execution checklist from approved M16 packet"
echo "  M16 packet: ${M16_PACKET}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M16_PACKET="${M16_PACKET}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m16_packet_path = Path(os.environ["M16_PACKET"])

m16 = json.loads(m16_packet_path.read_text())
gate = m16.get("m16ApprovalPacketGate")
gate = gate if isinstance(gate, dict) else {}
approved_values = m16.get("approvedValues")
approved_values = approved_values if isinstance(approved_values, dict) else {}
required_approvals = m16.get("requiredApprovals")
required_approvals = required_approvals if isinstance(required_approvals, list) else []
exact_text_candidates = m16.get("exactTextCandidates")
exact_text_candidates = (
    exact_text_candidates if isinstance(exact_text_candidates, list) else []
)
text_entry_targets = m16.get("textEntryTargets")
text_entry_targets = text_entry_targets if isinstance(text_entry_targets, list) else []
public_action_targets = m16.get("publicActionTargets")
public_action_targets = (
    public_action_targets if isinstance(public_action_targets, list) else []
)


def approval_by_id(approval_id):
    for approval in required_approvals:
        if isinstance(approval, dict) and approval.get("id") == approval_id:
            return approval
    return {}


def approved_value(approval_id, key):
    approval = approval_by_id(approval_id)
    value = approval.get("approvedValue") if isinstance(approval, dict) else None
    return value or approved_values.get(key)


approved_exact_text = approved_value("exact_text", "exactText")
approved_target_label = approved_value("target_label", "targetLabel")
approved_public_action_label = approved_value(
    "public_action_label", "publicActionLabel"
)
requires_public_action = bool(public_action_targets)

checks = [
    {
        "id": "m16_packet_schema_valid",
        "ok": m16.get("schemaName") == "macos_computer_use_m16_approval_packet"
        and m16.get("milestone") == "M16",
        "nextAction": "Select a valid M16 approval_packet.json before preparing the M17 rehearsal.",
    },
    {
        "id": "m16_packet_ready",
        "ok": bool(m16.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M16 approval packet until m16ApprovalPacketGate.status is ready.",
    },
    {
        "id": "approval_status_approved",
        "ok": m16.get("approvalStatus") == "approved",
        "nextAction": "Ask the user to approve every required M16 approval before any execution rehearsal advances.",
    },
    {
        "id": "exact_text_approved",
        "ok": not exact_text_candidates or bool(approved_exact_text),
        "nextAction": "Ask the user to approve the exact text before typing can be rehearsed.",
    },
    {
        "id": "target_label_approved",
        "ok": not (text_entry_targets or m16.get("candidateTargets"))
        or bool(approved_target_label),
        "nextAction": "Ask the user to approve the target label before click or type steps can be rehearsed.",
    },
    {
        "id": "public_action_label_approved",
        "ok": not requires_public_action or bool(approved_public_action_label),
        "nextAction": "Ask the user to separately approve the public action label before any submit or post step can be rehearsed.",
    },
    {
        "id": "desktop_boundary_preserved",
        "ok": m16.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M17 rehearsal must stay report-only and must not run desktop actions.",
    },
    {
        "id": "tcc_boundary_preserved",
        "ok": m16.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "M17 rehearsal must not grant TCC or operate System Settings.",
    },
    {
        "id": "llm_boundary_preserved",
        "ok": m16.get("llmBoundary") == "no_llm_call",
        "nextAction": "M17 rehearsal must not call an LLM.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers

execution_phases = [
    {
        "id": "observe_again",
        "mode": "read_only",
        "approved": True,
        "description": "Capture a fresh observation before any future action.",
    },
    {
        "id": "focus_target",
        "mode": "future_user_approved_desktop_action",
        "approved": bool(approved_target_label),
        "approvedValue": approved_target_label,
        "description": "Focus the user-approved target in a future execution milestone.",
    },
    {
        "id": "type_exact_text",
        "mode": "future_user_approved_input",
        "approved": bool(approved_exact_text),
        "approvedValue": approved_exact_text,
        "description": "Type only the user-approved exact text in a future execution milestone.",
    },
]
if requires_public_action:
    execution_phases.append(
        {
            "id": "confirm_public_action",
            "mode": "future_separate_user_approved_public_action",
            "approved": bool(approved_public_action_label),
            "approvedValue": approved_public_action_label,
            "description": "Use a separate approval before any submit, post, send, publish, purchase, or order action.",
        }
    )
execution_phases.append(
    {
        "id": "post_action_observation",
        "mode": "read_only_after_future_action",
        "approved": True,
        "description": "Capture a read-only observation after any future action.",
    }
)

gate_next_action = (
    "Use this rehearsal as the report-only checklist for a future user-operated execution milestone."
    if ready
    else "Resolve M17 rehearsal blockers before any future execution milestone."
)

summary = {
    "schemaName": "macos_computer_use_m17_execution_rehearsal",
    "schemaVersion": 1,
    "purpose": "computer_use_m17_execution_rehearsal",
    "milestone": "M17",
    "previousMilestone": "M16",
    "ready": ready,
    "sourceM16ApprovalPacket": str(m16_packet_path),
    "executionBoundary": "no_desktop_action_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "approvalStatus": m16.get("approvalStatus"),
    "approvedValues": {
        "exactText": approved_exact_text,
        "targetLabel": approved_target_label,
        "publicActionLabel": approved_public_action_label,
    },
    "executionPhases": execution_phases,
    "m17ExecutionRehearsalGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This rehearsal does not execute desktop actions.",
        "Future execution must begin with a fresh read-only observation.",
        "Future typing must use only the approved exact text.",
        "Future public actions require separate user approval at the moment of action.",
        "TCC and System Settings remain user-operated and outside this rehearsal.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")

md_lines = [
    "# macOS Computer Use M17 Execution Rehearsal",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M16 approval packet: `{m16_packet_path}`",
    f"- Approval status: {m16.get('approvalStatus')}",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions",
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
        "## Approved Values",
        "",
        "| Approval | Value |",
        "| --- | --- |",
        f"| exact_text | {approved_exact_text or '-'} |",
        f"| target_label | {approved_target_label or '-'} |",
        f"| public_action_label | {approved_public_action_label or '-'} |",
        "",
        "## Execution Phases",
        "",
        "| Phase | Mode | Approved | Value |",
        "| --- | --- | --- | --- |",
    ]
)
for phase in execution_phases:
    md_lines.append(
        "| {id} | {mode} | {approved} | {value} |".format(
            id=str(phase["id"]).replace("|", "\\|"),
            mode=str(phase["mode"]).replace("|", "\\|"),
            approved=str(phase.get("approved", False)).lower(),
            value=str(phase.get("approvedValue") or "-").replace("|", "\\|"),
        )
    )

md_lines.extend(
    [
        "",
        "## Report-Only Boundary",
        "",
        "This rehearsal does not execute desktop actions. It is only a checklist",
        "for a future milestone that must remain user-approved at each action",
        "boundary.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M17 execution rehearsal written to {summary_json}")
print(f"M17 execution rehearsal Markdown written to {summary_md}")
print(f"Gate status: {summary['m17ExecutionRehearsalGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M16_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m16_approval_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/approval_packet.json"
SUMMARY_MD="${RUN_DIR}/approval_packet.md"
M15_HANDOFF=""
M15_LLM_REVIEW=""
APPROVED_EXACT_TEXT="${CAVERNO_MACOS_COMPUTER_USE_M16_APPROVED_EXACT_TEXT:-}"
APPROVED_TARGET_LABEL="${CAVERNO_MACOS_COMPUTER_USE_M16_APPROVED_TARGET_LABEL:-}"
APPROVED_PUBLIC_ACTION_LABEL="${CAVERNO_MACOS_COMPUTER_USE_M16_APPROVED_PUBLIC_ACTION_LABEL:-}"

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m16_approval_packet.sh [options]

Options:
  --root PATH                         Report root directory.
  --m15-handoff PATH                  M15 action proposal handoff JSON.
  --m15-llm-review PATH               Optional M15 LLM review summary JSON.
  --approved-exact-text TEXT          Optional user-approved exact text.
  --approved-target-label TEXT        Optional user-approved target label.
  --approved-public-action-label TEXT Optional user-approved public action label.
  --help                              Show this help.

This M16 packet is report-only. It reads ready M15 action proposal evidence and
prepares the explicit approval packet for a future execution milestone. It does
not call an LLM, grant TCC, open apps, operate System Settings, move the
pointer, click, type, submit, post, purchase, or perform desktop actions.
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
    --m15-handoff)
      require_value "$@"
      M15_HANDOFF="$2"
      shift 2
      ;;
    --m15-llm-review)
      require_value "$@"
      M15_LLM_REVIEW="$2"
      shift 2
      ;;
    --approved-exact-text)
      require_value "$@"
      APPROVED_EXACT_TEXT="$2"
      shift 2
      ;;
    --approved-target-label)
      require_value "$@"
      APPROVED_TARGET_LABEL="$2"
      shift 2
      ;;
    --approved-public-action-label)
      require_value "$@"
      APPROVED_PUBLIC_ACTION_LABEL="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m16_approval_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/approval_packet.json"
SUMMARY_MD="${RUN_DIR}/approval_packet.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M15_HANDOFF}" ]]; then
  M15_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m15_action_proposal_handoff_*/action_proposal_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M15_LLM_REVIEW}" ]]; then
  M15_LLM_REVIEW="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m15_llm_review_canary_*/canary_summary.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M15_HANDOFF}" ]]; then
  echo "M15 action proposal handoff not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M15_HANDOFF}" ]]; then
  echo "M15 action proposal handoff not found: ${M15_HANDOFF}" >&2
  exit 66
fi
if [[ -n "${M15_LLM_REVIEW}" && ! -f "${M15_LLM_REVIEW}" ]]; then
  echo "M15 LLM review summary not found: ${M15_LLM_REVIEW}" >&2
  exit 66
fi

echo "Running macOS Computer Use M16 approval packet"
echo "  Purpose: prepare explicit user approvals from ready M15 evidence"
echo "  M15 handoff: ${M15_HANDOFF}"
echo "  M15 LLM review: ${M15_LLM_REVIEW:-not provided}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M15_HANDOFF="${M15_HANDOFF}" \
M15_LLM_REVIEW="${M15_LLM_REVIEW}" \
APPROVED_EXACT_TEXT="${APPROVED_EXACT_TEXT}" \
APPROVED_TARGET_LABEL="${APPROVED_TARGET_LABEL}" \
APPROVED_PUBLIC_ACTION_LABEL="${APPROVED_PUBLIC_ACTION_LABEL}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m15_handoff_path = Path(os.environ["M15_HANDOFF"])
m15_llm_review_value = os.environ.get("M15_LLM_REVIEW", "").strip()
m15_llm_review_path = Path(m15_llm_review_value) if m15_llm_review_value else None
approved_exact_text = os.environ.get("APPROVED_EXACT_TEXT", "").strip()
approved_target_label = os.environ.get("APPROVED_TARGET_LABEL", "").strip()
approved_public_action_label = os.environ.get(
    "APPROVED_PUBLIC_ACTION_LABEL", ""
).strip()

m15 = json.loads(m15_handoff_path.read_text())
m15_review = (
    json.loads(m15_llm_review_path.read_text()) if m15_llm_review_path else None
)

m15_gate = m15.get("m15ActionProposalGate")
m15_gate = m15_gate if isinstance(m15_gate, dict) else {}
review_consistency = m15.get("reviewGateConsistency")
review_consistency = review_consistency if isinstance(review_consistency, dict) else {}
review_summary = m15.get("prReviewSummary")
review_summary = review_summary if isinstance(review_summary, dict) else {}
review_counts = m15.get("reviewTargetCounts")
review_counts = review_counts if isinstance(review_counts, dict) else {}

exact_text_candidates = m15.get("exactTextCandidates")
exact_text_candidates = (
    exact_text_candidates if isinstance(exact_text_candidates, list) else []
)
text_entry_targets = m15.get("textEntryTargets")
text_entry_targets = text_entry_targets if isinstance(text_entry_targets, list) else []
public_action_targets = m15.get("publicActionTargets")
public_action_targets = (
    public_action_targets if isinstance(public_action_targets, list) else []
)
confirmation_requirements = m15.get("confirmationRequirements")
confirmation_requirements = (
    confirmation_requirements
    if isinstance(confirmation_requirements, list)
    else []
)

llm_review_gate = {}
if isinstance(m15_review, dict):
    gate = m15_review.get("m15LlmReviewGate")
    llm_review_gate = gate if isinstance(gate, dict) else {}

base_checks = [
    {
        "id": "m15_handoff_ready",
        "ok": bool(m15.get("ready")) and m15_gate.get("status") == "ready",
        "nextAction": "Run the M15 action proposal handoff until m15ActionProposalGate.status is ready.",
    },
    {
        "id": "m15_review_gate_consistent",
        "ok": review_consistency.get("status") == "consistent"
        or review_consistency.get("ok") is True,
        "nextAction": "Resolve inconsistent M15 review and gate evidence before preparing approval packets.",
    },
    {
        "id": "desktop_boundary_preserved",
        "ok": m15.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M16 approval packets must be generated before any desktop action is armed.",
    },
    {
        "id": "tcc_boundary_preserved",
        "ok": m15.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "Keep TCC and System Settings operations user-operated and outside M16.",
    },
    {
        "id": "llm_boundary_preserved",
        "ok": m15.get("llmBoundary") == "no_llm_call",
        "nextAction": "M16 approval packet generation must not call an LLM.",
    },
    {
        "id": "m15_llm_review_ready_when_present",
        "ok": m15_llm_review_path is None
        or llm_review_gate.get("status") == "ready",
        "nextAction": "Resolve blocked M15 LLM review evidence before preparing the M16 packet.",
    },
]

base_blockers = [check["id"] for check in base_checks if not check["ok"]]
packet_ready = not base_blockers

required_approvals = [
    {
        "id": "observe_again",
        "required": True,
        "status": "read_only_allowed",
        "reason": "A fresh observation is read-only and must precede future execution.",
    },
    {
        "id": "exact_text",
        "required": bool(exact_text_candidates),
        "status": "approved" if approved_exact_text else "pending_user_approval",
        "approvedValue": approved_exact_text or None,
        "reason": "The user must approve the exact text before future typing.",
    },
    {
        "id": "target_label",
        "required": bool(text_entry_targets or m15.get("candidateTargets")),
        "status": "approved" if approved_target_label else "pending_user_approval",
        "approvedValue": approved_target_label or None,
        "reason": "The user must approve the target before future clicking or typing.",
    },
    {
        "id": "public_action_label",
        "required": bool(public_action_targets),
        "status": (
            "approved"
            if approved_public_action_label
            else "pending_separate_user_approval"
        ),
        "approvedValue": approved_public_action_label or None,
        "reason": "Public submit, post, send, publish, or purchase actions require separate approval.",
    },
    {
        "id": "post_action_observation",
        "required": True,
        "status": "required_after_future_action",
        "reason": "Any future action must be followed by a read-only observation.",
    },
]
approval_blockers = [
    approval["id"]
    for approval in required_approvals
    if approval.get("required")
    and str(approval.get("status", "")).startswith("pending")
]
approval_status = "approved" if not approval_blockers else "pending_user_approval"

gate_next_action = (
    "Ask the user to approve exact text, target, and any public action before the future execution milestone."
    if packet_ready and approval_blockers
    else "Use this packet as input to the future execution milestone; this script still did not execute actions."
    if packet_ready
    else "Resolve blocked M15 evidence before preparing the M16 approval packet."
)

summary = {
    "schemaName": "macos_computer_use_m16_approval_packet",
    "schemaVersion": 1,
    "purpose": "computer_use_m16_approval_packet",
    "milestone": "M16",
    "previousMilestone": "M15",
    "ready": packet_ready,
    "approvalStatus": approval_status,
    "executionBoundary": "no_desktop_action_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceM15Handoff": str(m15_handoff_path),
    "sourceM15LlmReview": str(m15_llm_review_path) if m15_llm_review_path else None,
    "targetIntent": m15.get("targetIntent"),
    "exactTextCandidates": exact_text_candidates,
    "textEntryTargets": text_entry_targets,
    "publicActionTargets": public_action_targets,
    "confirmationRequirements": confirmation_requirements,
    "approvedValues": {
        "exactText": approved_exact_text or None,
        "targetLabel": approved_target_label or None,
        "publicActionLabel": approved_public_action_label or None,
    },
    "requiredApprovals": required_approvals,
    "approvalBlockers": approval_blockers,
    "m16ApprovalPacketGate": {
        "status": "ready" if packet_ready else "blocked",
        "ready": packet_ready,
        "checks": base_checks,
        "blockers": base_blockers,
        "approvalStatus": approval_status,
        "approvalBlockers": approval_blockers,
        "nextAction": gate_next_action,
    },
    "m15ReviewEvidence": {
        "handoffReady": bool(m15.get("ready")),
        "handoffGateStatus": m15_gate.get("status"),
        "reviewStatus": review_summary.get("status"),
        "reviewGateConsistencyStatus": review_consistency.get("status"),
        "reviewTargetCounts": review_counts,
        "llmReviewStatus": llm_review_gate.get("status") if llm_review_gate else None,
    },
    "manualBoundary": [
        "Do not execute desktop actions from this packet.",
        "Do not type text until the exact text is approved.",
        "Do not click a target until the target label is approved.",
        "Do not submit, post, send, publish, purchase, or order until the public action is separately approved.",
        "Do not grant TCC or operate System Settings from this packet.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")

md_lines = [
    "# macOS Computer Use M16 Approval Packet",
    "",
    f"- Ready: {str(packet_ready).lower()}",
    f"- Approval status: {approval_status}",
    f"- Source M15 handoff: `{m15_handoff_path}`",
    f"- Source M15 LLM review: `{m15_llm_review_path}`"
    if m15_llm_review_path
    else "- Source M15 LLM review: not provided",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions",
    "",
    "## Gate",
    "",
]
for check in base_checks:
    status = "ready" if check["ok"] else "blocked"
    md_lines.append(
        f"- `{check['id']}`: {status}"
        + ("" if check["ok"] else f" - {check['nextAction']}")
    )

md_lines.extend(["", "## Required Approvals", "", "| Approval | Required | Status | Value |", "| --- | --- | --- | --- |"])
for approval in required_approvals:
    md_lines.append(
        "| {id} | {required} | {status} | {value} |".format(
            id=str(approval["id"]).replace("|", "\\|"),
            required=str(approval.get("required", False)).lower(),
            status=str(approval["status"]).replace("|", "\\|"),
            value=str(approval.get("approvedValue") or "-").replace("|", "\\|"),
        )
    )

md_lines.extend(["", "## M15 Review Evidence", ""])
for key, value in summary["m15ReviewEvidence"].items():
    md_lines.append(f"- `{key}`: {value}")

md_lines.extend(
    [
        "",
        "## Manual Boundary",
        "",
        "This packet does not execute desktop actions. Future click, typing,",
        "navigation, submit, post, purchase, or other externally visible actions",
        "must remain separated into explicit user approval steps.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines))

print(f"M16 approval packet written to {summary_json}")
print(f"M16 approval packet Markdown written to {summary_md}")
print(f"Gate status: {summary['m16ApprovalPacketGate']['status']}")
print(f"Approval status: {approval_status}")
if base_blockers:
    print("Blockers: " + ", ".join(base_blockers))
if approval_blockers:
    print("Approval blockers: " + ", ".join(approval_blockers))

raise SystemExit(0 if packet_ready else 1)
PY

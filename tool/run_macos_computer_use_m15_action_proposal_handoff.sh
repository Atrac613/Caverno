#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M15_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m15_action_proposal_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/action_proposal_handoff.json"
SUMMARY_MD="${RUN_DIR}/action_proposal_handoff.md"
M14_SUMMARY=""
TARGET_INTENT="${CAVERNO_MACOS_COMPUTER_USE_M15_TARGET_INTENT:-}"

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh [options]

Options:
  --root PATH              Report root directory.
  --m14-summary PATH       M14 real-app observe canary summary JSON.
  --target-intent TEXT     Optional future user intent for the handoff.
  --help                   Show this help.

This handoff is report-only. It reads M14 observe-only evidence and prepares
an approval-bound action proposal checklist. It does not call an LLM, grant
TCC, open apps, operate System Settings, move the pointer, click, type,
switch Spaces, submit, post, or purchase.
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
    --m14-summary)
      require_value "$@"
      M14_SUMMARY="$2"
      shift 2
      ;;
    --target-intent)
      require_value "$@"
      TARGET_INTENT="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m15_action_proposal_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/action_proposal_handoff.json"
SUMMARY_MD="${RUN_DIR}/action_proposal_handoff.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M14_SUMMARY}" ]]; then
  M14_SUMMARY="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_real_app_observe_canary_*/canary_summary.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M14_SUMMARY}" ]]; then
  echo "M14 summary not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M14_SUMMARY}" ]]; then
  echo "M14 summary not found: ${M14_SUMMARY}" >&2
  exit 66
fi

echo "Running macOS Computer Use M15 action proposal handoff"
echo "  Purpose: convert M14 observe-only evidence into approval-bound next steps"
echo "  M14 summary: ${M14_SUMMARY}"
echo "  Target intent: ${TARGET_INTENT:-from M14 summary}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M14_SUMMARY="${M14_SUMMARY}" \
TARGET_INTENT="${TARGET_INTENT}" \
python3 - <<'PY'
import json
import os
import re
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m14_summary_path = Path(os.environ["M14_SUMMARY"])
target_intent_override = os.environ.get("TARGET_INTENT", "").strip()

m14 = json.loads(m14_summary_path.read_text())
target_intent = target_intent_override or str(m14.get("targetIntent") or "")
candidate_targets = m14.get("candidateTargets")
candidate_targets = candidate_targets if isinstance(candidate_targets, list) else []
confirmation_requirements = m14.get("confirmationRequirements")
confirmation_requirements = (
    confirmation_requirements if isinstance(confirmation_requirements, list) else []
)
action_plan = m14.get("actionPlan")
action_plan = action_plan if isinstance(action_plan, list) else []
m14_gate = m14.get("m14EvidenceGate")
m14_gate = m14_gate if isinstance(m14_gate, dict) else {}

mutation_tools = {
    "computer_click",
    "computer_type_text",
    "computer_switch_space",
    "computer_press_key",
    "computer_scroll",
    "computer_drag",
    "computer_move_mouse",
    "computer_focus_window",
}
planned_tools = [
    str(step.get("tool", "")).strip()
    for step in action_plan
    if isinstance(step, dict)
]
text_targets = [
    target
    for target in candidate_targets
    if isinstance(target, dict)
    and any(
        token in json.dumps(target).lower()
        for token in ["text", "compose", "search", "address", "input", "field"]
    )
]
public_targets = [
    target
    for target in candidate_targets
    if isinstance(target, dict)
    and str(target.get("risk", "")).lower() == "public_action"
]
exact_text_sources = []
for key in ["exactText", "requestedText", "textToType", "proposedText"]:
    value = m14.get(key)
    if isinstance(value, str) and value.strip():
        exact_text_sources.append({"source": key, "text": value.strip()})

quoted_text_pattern = re.compile(r'"([^"]+)"|\'([^\']+)\'')
for match in quoted_text_pattern.finditer(target_intent):
    text = next((group for group in match.groups() if group), "").strip()
    if text:
        exact_text_sources.append({"source": "targetIntent", "text": text})

deduped_exact_text = []
seen_exact_text = set()
for item in exact_text_sources:
    key = item["text"]
    if key in seen_exact_text:
        continue
    seen_exact_text.add(key)
    deduped_exact_text.append(
        {
            "source": item["source"],
            "text": item["text"],
            "status": "requires_user_approval",
        }
    )

review_target_counts = {
    "candidateTargets": len(candidate_targets),
    "textEntryTargets": len(text_targets),
    "publicActionTargets": len(public_targets),
    "exactTextCandidates": len(deduped_exact_text),
    "confirmationRequirements": len(confirmation_requirements),
}

checks = [
    {
        "id": "m14_evidence_ready",
        "ok": bool(m14.get("ready")) and m14_gate.get("status") == "ready",
        "nextAction": "Run the M14 real-app observe canary until m14EvidenceGate.status is ready.",
    },
    {
        "id": "desktop_boundary_preserved",
        "ok": m14.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "Use only observe-only evidence before preparing action proposals.",
    },
    {
        "id": "tcc_boundary_preserved",
        "ok": m14.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "Keep TCC and System Settings verification user-operated.",
    },
    {
        "id": "targets_available",
        "ok": bool(candidate_targets),
        "nextAction": "Capture a fresh screenshot and rerun M14 so visible targets are classified.",
    },
    {
        "id": "text_entry_targets_available",
        "ok": bool(text_targets),
        "nextAction": "M15 needs at least one visible or intent-relevant text-entry target before proposing typing.",
    },
    {
        "id": "public_action_targets_classified",
        "ok": bool(public_targets),
        "nextAction": "Classify public submit, post, send, or publish controls as public_action.",
    },
    {
        "id": "confirmation_requirements_available",
        "ok": bool(confirmation_requirements),
        "nextAction": "Document the exact confirmations required before future input or public action.",
    },
    {
        "id": "no_mutating_tool_planned",
        "ok": not any(tool in mutation_tools for tool in planned_tools),
        "nextAction": "M15 handoff must not inherit executable click, typing, or navigation tools from M14 evidence.",
    },
]
blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
review_status = "ready_for_review" if ready else "blocked_pending_review_evidence"
gate_status = "ready" if ready else "blocked"
gate_next_action = (
    "M15 action proposal handoff is ready for user review."
    if ready
    else "Resolve blocked M15 handoff checks before proposing any action."
)
review_summary = {
    "status": review_status,
    "ready": ready,
    "sourceEvidence": "m14_real_app_observe_canary",
    "blockedReviewEvidence": blockers,
    "requiredConfirmations": [
        "observe_again",
        "confirm_exact_text",
        "confirm_target",
        "confirm_public_action",
    ],
    "reviewTargetCounts": review_target_counts,
    "operationBoundary": {
        "llmCalls": "not_allowed",
        "tccGrants": "not_allowed",
        "desktopActions": "not_allowed",
        "futureActions": "approval_required",
        "publicActions": "separate_approval_required",
    },
}
review_gate_consistency_ok = (
    review_summary["ready"] == ready
    and (review_summary["status"] == "ready_for_review") == (gate_status == "ready")
    and review_summary["blockedReviewEvidence"] == blockers
)
review_gate_consistency = {
    "ok": review_gate_consistency_ok,
    "status": "consistent" if review_gate_consistency_ok else "inconsistent",
    "nextAction": (
        "No action required."
        if review_gate_consistency_ok
        else "Resolve inconsistent M15 review and gate evidence before proposing any action."
    ),
}

approval_bound_steps = [
    {
        "phase": "observe_again",
        "status": "allowed_without_extra_approval",
        "tool": "computer_vision_observe",
        "reason": "Refreshing visual context is read-only.",
    },
    {
        "phase": "confirm_exact_text",
        "status": "requires_user_approval",
        "reason": "The user must approve the exact text before any future typing.",
    },
    {
        "phase": "confirm_target",
        "status": "requires_user_approval",
        "reason": "The user must approve the target field or control before any future click.",
    },
    {
        "phase": "confirm_public_action",
        "status": "requires_separate_user_approval",
        "reason": "Any submit, post, send, publish, or purchase action is externally visible.",
    },
]

summary = {
    "schemaName": "macos_computer_use_m15_action_proposal_handoff",
    "schemaVersion": 1,
    "purpose": "computer_use_m15_action_proposal_handoff",
    "milestone": "M15",
    "previousMilestone": "M14",
    "ready": ready,
    "executionBoundary": "approval_bound_action_proposal_report_only",
    "tccBoundary": "no_tcc_operation",
    "desktopActionBoundary": "no_desktop_action",
    "llmBoundary": "no_llm_call",
    "sourceM14Summary": str(m14_summary_path),
    "targetApp": m14.get("targetApp"),
    "observedApp": m14.get("observedApp"),
    "targetIntent": target_intent,
    "candidateTargets": candidate_targets,
    "textEntryTargets": text_targets,
    "publicActionTargets": public_targets,
    "exactTextCandidates": deduped_exact_text,
    "reviewTargetCounts": review_target_counts,
    "confirmationRequirements": confirmation_requirements,
    "approvalBoundActionProposal": approval_bound_steps,
    "prReviewSummary": review_summary,
    "reviewGateConsistency": review_gate_consistency,
    "m15ActionProposalGate": {
        "status": gate_status,
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "Do not click, type, switch Spaces, submit, post, purchase, or navigate from this handoff.",
        "Ask the user to approve exact text before future typing.",
        "Ask the user to approve the target control before future clicking.",
        "Ask for separate confirmation before any public action.",
    ],
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

def status_line(check):
    return "ready" if check["ok"] else "blocked"

md_lines = [
    "# macOS Computer Use M15 Action Proposal Handoff",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M14 summary: `{m14_summary_path}`",
    f"- Target app: {summary.get('targetApp') or 'unknown'}",
    f"- Observed app: {summary.get('observedApp') or 'unknown'}",
    f"- Target intent: {target_intent or 'unknown'}",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions",
    "",
    "## PR Review Summary",
    "",
    f"- Status: {review_summary['status']}",
    f"- Ready: {str(ready).lower()}",
    f"- Source evidence: {review_summary['sourceEvidence']}",
    "- Blocked review evidence: " + (", ".join(blockers) if blockers else "none"),
    "- Required confirmations: "
    + ", ".join(review_summary["requiredConfirmations"]),
    "- Review target counts: "
    + ", ".join(
        f"{key}={value}" for key, value in review_target_counts.items()
    ),
    f"- Review/gate consistency: {review_gate_consistency['status']}",
    "- Boundary: no LLM call, no TCC, no System Settings, no desktop actions; future input and public actions require explicit approval.",
    "",
    "## Gate",
    "",
]
for check in checks:
    md_lines.append(
        f"- `{check['id']}`: {status_line(check)}"
        + ("" if check["ok"] else f" - {check['nextAction']}")
    )
md_lines.extend(
    [
        "",
        "## Approval-Bound Proposal",
        "",
    ]
)
for step in approval_bound_steps:
    md_lines.append(
        f"- `{step['phase']}`: {step['status']} - {step['reason']}"
    )
if text_targets or public_targets or deduped_exact_text:
    md_lines.extend(
        [
            "",
            "## Review Targets",
            "",
        ]
    )
    if text_targets:
        md_lines.extend(
            [
                "| Text Entry Target | Role | Risk |",
                "| --- | --- | --- |",
            ]
        )
        for target in text_targets:
            md_lines.append(
                "| {label} | {role} | {risk} |".format(
                    label=str(target.get("label") or "unknown").replace("|", "\\|"),
                    role=str(target.get("role") or "unknown").replace("|", "\\|"),
                    risk=str(target.get("risk") or "unknown").replace("|", "\\|"),
                )
            )
        md_lines.append("")
    if public_targets:
        md_lines.extend(
            [
                "| Public Action Target | Role | Risk |",
                "| --- | --- | --- |",
            ]
        )
        for target in public_targets:
            md_lines.append(
                "| {label} | {role} | {risk} |".format(
                    label=str(target.get("label") or "unknown").replace("|", "\\|"),
                    role=str(target.get("role") or "unknown").replace("|", "\\|"),
                    risk=str(target.get("risk") or "unknown").replace("|", "\\|"),
                )
            )
        md_lines.append("")
    if deduped_exact_text:
        md_lines.extend(
            [
                "| Exact Text Candidate | Source | Status |",
                "| --- | --- | --- |",
            ]
        )
        for item in deduped_exact_text:
            md_lines.append(
                "| {text} | {source} | {status} |".format(
                    text=item["text"].replace("|", "\\|"),
                    source=item["source"].replace("|", "\\|"),
                    status=item["status"].replace("|", "\\|"),
                )
            )
        md_lines.append("")
md_lines.extend(
    [
        "",
        "## Manual Boundary",
        "",
        "This handoff does not execute desktop actions. Future click, typing,",
        "navigation, submit, post, purchase, or other externally visible actions",
        "must be separated into explicit user approval steps.",
        "",
    ]
)
summary_md.write_text("\n".join(md_lines))

print(f"M15 action proposal handoff written to {summary_json}")
print(f"M15 action proposal Markdown written to {summary_md}")
print(f"Ready: {str(ready).lower()}")
print(f"Candidate targets: {len(candidate_targets)}")
print(f"Text-entry targets: {len(text_targets)}")
print(f"Public-action targets: {len(public_targets)}")
print(f"Exact text candidates: {len(deduped_exact_text)}")
if blockers:
    print("Blockers: " + ", ".join(blockers))
PY

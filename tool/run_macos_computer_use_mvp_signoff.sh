#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RELEASE_READINESS_WRAPPER="${CAVERNO_MACOS_COMPUTER_USE_READINESS_WRAPPER:-tool/run_macos_computer_use_release_readiness.sh}"
MANUAL_TCC_REPORT="${CAVERNO_MACOS_COMPUTER_USE_MANUAL_TCC_REPORT:-}"
DESKTOP_ACTION_CANARY_SUMMARY="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_SUMMARY:-}"
LLM_CANARY_SUMMARY="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_SUMMARY:-}"
REFRESH_SAFE_INPUTS=0
REFRESH_LLM_CANARY=0
DRY_RUN=0
FINAL_SIGNOFF=0
OUTPUT_JSON=""
OUTPUT_MD=""
HANDOFF_MD=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_signoff.sh [options]

Options:
  --root PATH                         Report root directory.
  --manual-tcc-report PATH            User-produced manual TCC report or summary.
  --desktop-action-canary-summary PATH User-produced desktop action canary summary.
  --llm-canary-summary PATH           Computer Use LLM canary summary.
  --refresh-safe-inputs               Refresh non-TCC M7/history inputs.
  --refresh-llm-canary                Refresh aggregate fixture LLM canary when CAVERNO_LLM_* is set.
  --final-signoff                     Refresh safe inputs and LLM evidence, then aggregate.
  --dry-run                           Write handoff and print aggregation command only.
  --output-json PATH                  Override MVP readiness JSON output.
  --output-md PATH                    Override MVP readiness Markdown output.
  --handoff-md PATH                   Override user handoff Markdown output.
  --help                              Show this help.

This wrapper never grants TCC, edits TCC, operates System Settings, or runs the
desktop action canary. It prints the user-operated commands and aggregates
reports that the user provides.
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
    --manual-tcc-report)
      require_value "$@"
      MANUAL_TCC_REPORT="$2"
      shift 2
      ;;
    --desktop-action-canary-summary)
      require_value "$@"
      DESKTOP_ACTION_CANARY_SUMMARY="$2"
      shift 2
      ;;
    --llm-canary-summary)
      require_value "$@"
      LLM_CANARY_SUMMARY="$2"
      shift 2
      ;;
    --refresh-safe-inputs)
      REFRESH_SAFE_INPUTS=1
      shift
      ;;
    --refresh-llm-canary)
      REFRESH_LLM_CANARY=1
      shift
      ;;
    --final-signoff)
      FINAL_SIGNOFF=1
      REFRESH_SAFE_INPUTS=1
      REFRESH_LLM_CANARY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --output-json)
      require_value "$@"
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-md)
      require_value "$@"
      OUTPUT_MD="$2"
      shift 2
      ;;
    --handoff-md)
      require_value "$@"
      HANDOFF_MD="$2"
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

if [[ -z "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${REPORT_ROOT}/macos_computer_use_mvp_readiness.json"
fi
if [[ -z "${OUTPUT_MD}" ]]; then
  OUTPUT_MD="${REPORT_ROOT}/macos_computer_use_mvp_readiness.md"
fi
if [[ -z "${HANDOFF_MD}" ]]; then
  HANDOFF_MD="${REPORT_ROOT}/macos_computer_use_mvp_handoff.md"
fi
ARTIFACT_INDEX_MD="${REPORT_ROOT}/macos_computer_use_readiness_artifact_index.md"
ARTIFACT_INDEX_COMMAND="dart run tool/macos_computer_use_readiness_artifact_index.dart --root ${REPORT_ROOT}"
MVP_READINESS_PREFLIGHT_COMMAND="bash tool/run_macos_computer_use_mvp_readiness_preflight.sh --root ${REPORT_ROOT}"

mkdir -p "${REPORT_ROOT}"

discovered_artifacts="$(
  REPORT_ROOT="${REPORT_ROOT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


report_root = Path(os.environ["REPORT_ROOT"])


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def json_files():
    if not report_root.exists():
        return []
    return [path for path in report_root.rglob("*.json") if path.is_file()]


def latest_matching(matches):
    candidates = []
    for path in json_files():
        decoded = read_json(path)
        if decoded is None or not matches(path, decoded):
            continue
        candidates.append((path.stat().st_mtime, str(path), path))
    candidates.sort()
    return candidates[-1][2] if candidates else None


manual = latest_matching(
    lambda _path, decoded: decoded.get("schemaName")
    == "macos_computer_use_manual_tcc_report_summary"
    or "releaseRuntimeSignoffGate" in decoded
)
desktop = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_desktop_action_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_desktop_action_canary_summary"
)
vision = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith(
        "macos_computer_use_mvp_fixture_vision_llm_canary_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_mvp_fixture_vision_llm_canary_summary"
)
aggregate = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_mvp_fixture_llm_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_mvp_fixture_llm_canary_summary"
)
real_app_observe = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_real_app_observe_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_real_app_observe_canary_summary"
)
m15_action_proposal = latest_matching(
    lambda path, decoded: path.name == "action_proposal_handoff.json"
    and path.parent.name.startswith("macos_computer_use_m15_action_proposal_handoff_")
    and decoded.get("schemaName")
    == "macos_computer_use_m15_action_proposal_handoff"
)
m15_llm_review = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_m15_llm_review_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_m15_llm_review_canary_summary"
)
m16_approval_packet = latest_matching(
    lambda path, decoded: path.name == "approval_packet.json"
    and path.parent.name.startswith("macos_computer_use_m16_approval_packet_")
    and decoded.get("schemaName")
    == "macos_computer_use_m16_approval_packet"
)
m17_execution_rehearsal = latest_matching(
    lambda path, decoded: path.name == "execution_rehearsal.json"
    and path.parent.name.startswith("macos_computer_use_m17_execution_rehearsal_")
    and decoded.get("schemaName")
    == "macos_computer_use_m17_execution_rehearsal"
)
m18_execution_handoff = latest_matching(
    lambda path, decoded: path.name == "execution_handoff.json"
    and path.parent.name.startswith("macos_computer_use_m18_execution_handoff_")
    and decoded.get("schemaName")
    == "macos_computer_use_m18_execution_handoff"
)
m20_execution_result_intake = latest_matching(
    lambda path, decoded: path.name == "execution_result_intake.json"
    and path.parent.name.startswith("macos_computer_use_m20_execution_result_intake_")
    and decoded.get("schemaName")
    == "macos_computer_use_m20_execution_result_intake"
)
m22_post_action_review = latest_matching(
    lambda path, decoded: path.name == "post_action_review.json"
    and path.parent.name.startswith("macos_computer_use_m22_post_action_review_")
    and decoded.get("schemaName")
    == "macos_computer_use_m22_post_action_review"
)
m23_cycle_outcome_handoff = latest_matching(
    lambda path, decoded: path.name == "cycle_outcome_handoff.json"
    and path.parent.name.startswith(
        "macos_computer_use_m23_cycle_outcome_handoff_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m23_cycle_outcome_handoff"
)
m25_next_cycle_seed_handoff = latest_matching(
    lambda path, decoded: path.name == "next_cycle_seed_handoff.json"
    and path.parent.name.startswith(
        "macos_computer_use_m25_next_cycle_seed_handoff_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m25_next_cycle_seed_handoff"
)
m26_observe_restart_packet = latest_matching(
    lambda path, decoded: path.name == "observe_restart_packet.json"
    and path.parent.name.startswith(
        "macos_computer_use_m26_observe_restart_packet_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m26_observe_restart_packet"
)
m27_screenshot_request_handoff = latest_matching(
    lambda path, decoded: path.name == "screenshot_request_handoff.json"
    and path.parent.name.startswith(
        "macos_computer_use_m27_screenshot_request_handoff_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m27_screenshot_request_handoff"
)
m28_screenshot_evidence_intake = latest_matching(
    lambda path, decoded: path.name == "screenshot_evidence_intake.json"
    and path.parent.name.startswith(
        "macos_computer_use_m28_screenshot_evidence_intake_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m28_screenshot_evidence_intake"
)
m29_observe_canary_run_packet = latest_matching(
    lambda path, decoded: path.name == "observe_canary_run_packet.json"
    and path.parent.name.startswith(
        "macos_computer_use_m29_observe_canary_run_packet_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m29_observe_canary_run_packet"
)
m30_observe_result_intake = latest_matching(
    lambda path, decoded: path.name == "observe_result_intake.json"
    and path.parent.name.startswith(
        "macos_computer_use_m30_observe_result_intake_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_m30_observe_result_intake"
)
decision = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_llm_decision_canary_")
    and str(decoded.get("scenario", "")).startswith("mvp-fixture")
)
llm = real_app_observe or vision or aggregate or decision

for name, path in [
    ("DISCOVERED_MANUAL_TCC_REPORT", manual),
    ("DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY", desktop),
    ("DISCOVERED_LLM_CANARY_SUMMARY", llm),
    ("DISCOVERED_M15_ACTION_PROPOSAL_HANDOFF", m15_action_proposal),
    ("DISCOVERED_M15_LLM_REVIEW_CANARY_SUMMARY", m15_llm_review),
    ("DISCOVERED_M16_APPROVAL_PACKET", m16_approval_packet),
    ("DISCOVERED_M17_EXECUTION_REHEARSAL", m17_execution_rehearsal),
    ("DISCOVERED_M18_EXECUTION_HANDOFF", m18_execution_handoff),
    ("DISCOVERED_M20_EXECUTION_RESULT_INTAKE", m20_execution_result_intake),
    ("DISCOVERED_M22_POST_ACTION_REVIEW", m22_post_action_review),
    ("DISCOVERED_M23_CYCLE_OUTCOME_HANDOFF", m23_cycle_outcome_handoff),
    ("DISCOVERED_M25_NEXT_CYCLE_SEED_HANDOFF", m25_next_cycle_seed_handoff),
    ("DISCOVERED_M26_OBSERVE_RESTART_PACKET", m26_observe_restart_packet),
    ("DISCOVERED_M27_SCREENSHOT_REQUEST_HANDOFF", m27_screenshot_request_handoff),
    ("DISCOVERED_M28_SCREENSHOT_EVIDENCE_INTAKE", m28_screenshot_evidence_intake),
    ("DISCOVERED_M29_OBSERVE_CANARY_RUN_PACKET", m29_observe_canary_run_packet),
    ("DISCOVERED_M30_OBSERVE_RESULT_INTAKE", m30_observe_result_intake),
]:
    print(f"{name}={shlex.quote(str(path) if path else '')}")
PY
)"
eval "${discovered_artifacts}"

M15_ACTION_PROPOSAL_HANDOFF="${DISCOVERED_M15_ACTION_PROPOSAL_HANDOFF:-}"
M15_ACTION_PROPOSAL_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m15_action_proposal_handoff_fragment.md"
M15_ACTION_PROPOSAL_STATUS="missing"
M15_ACTION_PROPOSAL_NEXT_ACTION="Run the M15 action proposal handoff after M14 observe-only evidence is ready."
M15_ACTION_PROPOSAL_BOUNDARY="report-only, no LLM call, no TCC, no System Settings, no desktop actions"
M15_LLM_REVIEW_CANARY_SUMMARY="${DISCOVERED_M15_LLM_REVIEW_CANARY_SUMMARY:-}"
M15_LLM_REVIEW_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m15_llm_review_fragment.md"
M15_LLM_REVIEW_STATUS="missing"
M15_LLM_REVIEW_NEXT_ACTION="Run the M15 LLM review canary after the M15 action proposal handoff is ready."
M15_LLM_REVIEW_BOUNDARY="review-only, no tool execution, no TCC, no System Settings, no desktop actions"
M16_APPROVAL_PACKET="${DISCOVERED_M16_APPROVAL_PACKET:-}"
M16_APPROVAL_PACKET_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m16_approval_packet_fragment.md"
M16_APPROVAL_PACKET_STATUS="missing"
M16_APPROVAL_PACKET_APPROVAL_STATUS="missing"
M16_APPROVAL_PACKET_NEXT_ACTION="Run the M16 approval packet after the M15 action proposal handoff and M15 LLM review are ready."
M16_APPROVAL_PACKET_BOUNDARY="report-only, no LLM call, no TCC, no System Settings, no desktop actions"
M17_EXECUTION_REHEARSAL="${DISCOVERED_M17_EXECUTION_REHEARSAL:-}"
M17_EXECUTION_REHEARSAL_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m17_execution_rehearsal_fragment.md"
M17_EXECUTION_REHEARSAL_STATUS="missing"
M17_EXECUTION_REHEARSAL_APPROVAL_STATUS="missing"
M17_EXECUTION_REHEARSAL_NEXT_ACTION="Run the M17 execution rehearsal after the M16 approval packet is approved."
M17_EXECUTION_REHEARSAL_BOUNDARY="report-only, no LLM call, no TCC, no System Settings, no desktop actions"
M18_EXECUTION_HANDOFF="${DISCOVERED_M18_EXECUTION_HANDOFF:-}"
M18_EXECUTION_HANDOFF_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m18_execution_handoff_fragment.md"
M18_EXECUTION_HANDOFF_STATUS="missing"
M18_EXECUTION_HANDOFF_NEXT_ACTION="Run the M18 execution handoff after the M17 execution rehearsal is ready."
M18_EXECUTION_HANDOFF_BOUNDARY="report-only handoff, no LLM call, no TCC, no System Settings, no desktop actions"
M20_EXECUTION_RESULT_INTAKE="${DISCOVERED_M20_EXECUTION_RESULT_INTAKE:-}"
M20_EXECUTION_RESULT_INTAKE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m20_execution_result_intake_fragment.md"
M20_EXECUTION_RESULT_INTAKE_STATUS="missing"
M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION="Run the M20 execution result intake after the user completes the M18-guided runtime step."
M20_EXECUTION_RESULT_INTAKE_BOUNDARY="report-only result intake, no LLM call, no TCC, no System Settings, no desktop actions"
M22_POST_ACTION_REVIEW="${DISCOVERED_M22_POST_ACTION_REVIEW:-}"
M22_POST_ACTION_REVIEW_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m22_post_action_review_fragment.md"
M22_POST_ACTION_REVIEW_STATUS="missing"
M22_POST_ACTION_REVIEW_NEXT_ACTION="Run the M22 post-action review after M20 result intake is ready."
M22_POST_ACTION_REVIEW_BOUNDARY="report-only post-action review, no LLM call, no TCC, no System Settings, no desktop actions"
M23_CYCLE_OUTCOME_HANDOFF="${DISCOVERED_M23_CYCLE_OUTCOME_HANDOFF:-}"
M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m23_cycle_outcome_handoff_fragment.md"
M23_CYCLE_OUTCOME_HANDOFF_STATUS="missing"
M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION="Run the M23 cycle outcome handoff after M22 post-action review is ready."
M23_CYCLE_OUTCOME_HANDOFF_BOUNDARY="report-only cycle outcome handoff, no LLM call, no TCC, no System Settings, no desktop actions"
M25_NEXT_CYCLE_SEED_HANDOFF="${DISCOVERED_M25_NEXT_CYCLE_SEED_HANDOFF:-}"
M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m25_next_cycle_seed_handoff_fragment.md"
M25_NEXT_CYCLE_SEED_HANDOFF_STATUS="missing"
M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION="Run the M25 next-cycle seed handoff after an M23 restart outcome is ready."
M25_NEXT_CYCLE_SEED_HANDOFF_BOUNDARY="report-only next-cycle seed handoff, no LLM call, no TCC, no System Settings, no desktop actions"
M26_OBSERVE_RESTART_PACKET="${DISCOVERED_M26_OBSERVE_RESTART_PACKET:-}"
M26_OBSERVE_RESTART_PACKET_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m26_observe_restart_packet_fragment.md"
M26_OBSERVE_RESTART_PACKET_STATUS="missing"
M26_OBSERVE_RESTART_PACKET_NEXT_ACTION="Run the M26 observe restart packet after an M25 next-cycle seed is ready."
M26_OBSERVE_RESTART_PACKET_BOUNDARY="report-only M14 observe restart packet, no LLM call, no TCC, no System Settings, no desktop actions"
M27_SCREENSHOT_REQUEST_HANDOFF="${DISCOVERED_M27_SCREENSHOT_REQUEST_HANDOFF:-}"
M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m27_screenshot_request_handoff_fragment.md"
M27_SCREENSHOT_REQUEST_HANDOFF_STATUS="missing"
M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION="Run the M27 screenshot request handoff after an M26 observe restart packet is ready."
M27_SCREENSHOT_REQUEST_HANDOFF_BOUNDARY="report-only manual screenshot request, no LLM call, no TCC, no System Settings, no desktop actions"
M28_SCREENSHOT_EVIDENCE_INTAKE="${DISCOVERED_M28_SCREENSHOT_EVIDENCE_INTAKE:-}"
M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m28_screenshot_evidence_intake_fragment.md"
M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS="missing"
M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION="Run the M28 screenshot evidence intake after an M27 screenshot request handoff is ready and the user provides a screenshot."
M28_SCREENSHOT_EVIDENCE_INTAKE_BOUNDARY="report-only screenshot evidence intake, no LLM call, no TCC, no System Settings, no desktop actions"
M29_OBSERVE_CANARY_RUN_PACKET="${DISCOVERED_M29_OBSERVE_CANARY_RUN_PACKET:-}"
M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m29_observe_canary_run_packet_fragment.md"
M29_OBSERVE_CANARY_RUN_PACKET_STATUS="missing"
M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION="Run the M29 observe canary run packet after M28 screenshot evidence intake is ready."
M29_OBSERVE_CANARY_RUN_PACKET_BOUNDARY="report-only M14 observe canary run packet, no LLM call, no TCC, no System Settings, no desktop actions"
M30_OBSERVE_RESULT_INTAKE="${DISCOVERED_M30_OBSERVE_RESULT_INTAKE:-}"
M30_OBSERVE_RESULT_INTAKE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_m30_observe_result_intake_fragment.md"
M30_OBSERVE_RESULT_INTAKE_STATUS="missing"
M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION="Run the M30 observe result intake after the user-produced M14 observe summary is ready."
M30_OBSERVE_RESULT_INTAKE_BOUNDARY="report-only M14 observe result intake, no LLM call, no TCC, no System Settings, no desktop actions"
if [[ -n "${M15_ACTION_PROPOSAL_HANDOFF}" && -f "${M15_ACTION_PROPOSAL_HANDOFF}" ]]; then
  m15_action_proposal_values="$(
    M15_ACTION_PROPOSAL_HANDOFF="${M15_ACTION_PROPOSAL_HANDOFF}" M15_ACTION_PROPOSAL_FRAGMENT="${M15_ACTION_PROPOSAL_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M15_ACTION_PROPOSAL_HANDOFF"])
fragment_path = Path(os.environ["M15_ACTION_PROPOSAL_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m15ActionProposalGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
review = summary.get("prReviewSummary") if isinstance(summary, dict) else None
review = review if isinstance(review, dict) else {}
consistency = summary.get("reviewGateConsistency") if isinstance(summary, dict) else None
consistency = consistency if isinstance(consistency, dict) else {}
next_action = str(gate.get("nextAction") or "Review the M15 action proposal handoff.")
checks = as_list(gate.get("checks"))
blockers = as_list(gate.get("blockers"))
review_status = str(review.get("status") or "-")
review_blocked_evidence = as_list(review.get("blockedReviewEvidence"))
review_blocked = bool(review_blocked_evidence) or (
    bool(review) and review_status != "ready_for_review"
)
consistency_status = str(consistency.get("status") or "-")
consistency_ok = consistency.get("ok")
consistency_blocked = consistency_ok is False or (
    bool(consistency) and consistency_status != "consistent"
)
status = str(gate.get("status") or ("ready" if summary and summary.get("ready") is True else "blocked"))
if status == "ready" and review_blocked:
    status = "blocked"
    next_action = "Resolve blocked M15 review evidence before proposing any action."
if consistency_blocked:
    status = "blocked"
    next_action = "Resolve inconsistent M15 review and gate evidence before proposing any action."
approval_steps = as_list(summary.get("approvalBoundActionProposal") if isinstance(summary, dict) else [])
text_entry_targets = as_list(summary.get("textEntryTargets") if isinstance(summary, dict) else [])
public_action_targets = as_list(summary.get("publicActionTargets") if isinstance(summary, dict) else [])
exact_text_candidates = as_list(summary.get("exactTextCandidates") if isinstance(summary, dict) else [])
review_target_counts = summary.get("reviewTargetCounts") if isinstance(summary, dict) else None
review_target_counts = review_target_counts if isinstance(review_target_counts, dict) else {}
if not review_target_counts:
    review_target_counts = {
        "textEntryTargets": len(text_entry_targets),
        "publicActionTargets": len(public_action_targets),
        "exactTextCandidates": len(exact_text_candidates),
    }
boundary = "report-only"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}"
    )

lines = [
    "",
    "## M15 Action Proposal Evidence",
    "",
    f"- M15 action proposal handoff: `{summary_path}`",
    f"- M15 action proposal status: {status}",
    f"- M15 action proposal boundary: {boundary}",
    f"- M15 action proposal next action: {next_action}",
]
if blockers:
    lines.append("- M15 action proposal blockers: " + ", ".join(str(item) for item in blockers))
else:
    lines.append("- M15 action proposal blockers: none")
if review:
    lines.extend([
        "- M15 action proposal PR review status: " + review_status,
        "- M15 action proposal blocked review evidence: "
        + (", ".join(str(item) for item in review_blocked_evidence) if review_blocked_evidence else "none"),
    ])
if consistency:
    lines.append("- M15 action proposal review/gate consistency: " + consistency_status)
if review_target_counts:
    lines.append(
        "- M15 action proposal review target counts: "
        + ", ".join(f"{key}={value}" for key, value in review_target_counts.items())
    )
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )
if approval_steps:
    lines.extend([
        "",
        "| Approval Phase | Status | Reason |",
        "| --- | --- | --- |",
    ])
    for step in approval_steps:
        if not isinstance(step, dict):
            continue
        lines.append(
            "| {phase} | {status} | {reason} |".format(
                phase=cell(step.get("phase")),
                status=cell(step.get("status")),
                reason=cell(step.get("reason")),
            )
        )
if text_entry_targets or public_action_targets or exact_text_candidates:
    lines.extend([
        "",
        "### M15 Review Targets",
        "",
    ])
    if text_entry_targets:
        lines.extend([
            "| Text Entry Target | Role | Risk |",
            "| --- | --- | --- |",
        ])
        for target in text_entry_targets:
            if not isinstance(target, dict):
                continue
            lines.append(
                "| {label} | {role} | {risk} |".format(
                    label=cell(target.get("label")),
                    role=cell(target.get("role")),
                    risk=cell(target.get("risk")),
                )
            )
    if public_action_targets:
        lines.extend([
            "",
            "| Public Action Target | Role | Risk |",
            "| --- | --- | --- |",
        ])
        for target in public_action_targets:
            if not isinstance(target, dict):
                continue
            lines.append(
                "| {label} | {role} | {risk} |".format(
                    label=cell(target.get("label")),
                    role=cell(target.get("role")),
                    risk=cell(target.get("risk")),
                )
            )
    if exact_text_candidates:
        lines.extend([
            "",
            "| Exact Text Candidate | Source | Status |",
            "| --- | --- | --- |",
        ])
        for item in exact_text_candidates:
            if not isinstance(item, dict):
                continue
            lines.append(
                "| {text} | {source} | {status} |".format(
                    text=cell(item.get("text")),
                    source=cell(item.get("source")),
                    status=cell(item.get("status")),
                )
            )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M15_ACTION_PROPOSAL_STATUS={shlex.quote(status)}")
print(f"M15_ACTION_PROPOSAL_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M15_ACTION_PROPOSAL_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m15_action_proposal_values}"
else
  cat >"${M15_ACTION_PROPOSAL_FRAGMENT}" <<EOF

## M15 Action Proposal Evidence

- M15 action proposal handoff: \`not discovered\`
- M15 action proposal status: missing
- M15 action proposal boundary: ${M15_ACTION_PROPOSAL_BOUNDARY}
- M15 action proposal next action: ${M15_ACTION_PROPOSAL_NEXT_ACTION}
- M15 action proposal blockers: missing_m15_action_proposal_handoff
EOF
fi

if [[ -n "${M15_LLM_REVIEW_CANARY_SUMMARY}" && -f "${M15_LLM_REVIEW_CANARY_SUMMARY}" ]]; then
  m15_llm_review_values="$(
    M15_LLM_REVIEW_CANARY_SUMMARY="${M15_LLM_REVIEW_CANARY_SUMMARY}" M15_LLM_REVIEW_FRAGMENT="${M15_LLM_REVIEW_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M15_LLM_REVIEW_CANARY_SUMMARY"])
fragment_path = Path(os.environ["M15_LLM_REVIEW_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m15LlmReviewGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
failed_count = summary.get("failedCount") if isinstance(summary, dict) else None
passed_count = summary.get("passedCount") if isinstance(summary, dict) else None
run_count = summary.get("runCount") if isinstance(summary, dict) else None
status = str(gate.get("status") or "")
if not status:
    if isinstance(failed_count, (int, float)):
        status = "ready" if failed_count == 0 else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "M15 LLM review canary is ready for user review."
        if status == "ready"
        else "Resolve M15 LLM review boundary failures before any action proposal execution."
    )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m15_llm_review_summary_unreadable"]
boundary = "review-only"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}"
    )
runs = as_list(summary.get("runs") if isinstance(summary, dict) else [])

lines = [
    "",
    "## M15 LLM Review Evidence",
    "",
    f"- M15 LLM review canary: `{summary_path}`",
    f"- M15 LLM review status: {status}",
    f"- M15 LLM review boundary: {boundary}",
    f"- M15 LLM review next action: {next_action}",
    f"- M15 LLM review blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M15 LLM review runs: {run_count if run_count is not None else 'not available'}",
    f"- M15 LLM review passed: {passed_count if passed_count is not None else 'not available'}",
    f"- M15 LLM review failed: {failed_count if failed_count is not None else 'not available'}",
]
if isinstance(summary, dict) and summary.get("boundaryDecision"):
    lines.append(f"- M15 LLM review boundary decision: {summary.get('boundaryDecision')}")
if runs:
    lines.extend([
        "",
        "| Run | Status | Failure Class | Boundary Decision |",
        "| --- | --- | --- | --- |",
    ])
    for run in runs:
        if not isinstance(run, dict):
            continue
        lines.append(
            "| {name} | {status} | {failure} | {decision} |".format(
                name=cell(run.get("name")),
                status=cell(run.get("status")),
                failure=cell(run.get("failureClass")),
                decision=cell(run.get("boundaryDecision")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M15_LLM_REVIEW_STATUS={shlex.quote(status)}")
print(f"M15_LLM_REVIEW_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M15_LLM_REVIEW_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m15_llm_review_values}"
else
  cat >"${M15_LLM_REVIEW_FRAGMENT}" <<EOF

## M15 LLM Review Evidence

- M15 LLM review canary: \`not discovered\`
- M15 LLM review status: missing
- M15 LLM review boundary: ${M15_LLM_REVIEW_BOUNDARY}
- M15 LLM review next action: ${M15_LLM_REVIEW_NEXT_ACTION}
- M15 LLM review blockers: missing_m15_llm_review_canary
EOF
fi

if [[ -n "${M16_APPROVAL_PACKET}" && -f "${M16_APPROVAL_PACKET}" ]]; then
  m16_approval_packet_values="$(
    M16_APPROVAL_PACKET="${M16_APPROVAL_PACKET}" M16_APPROVAL_PACKET_FRAGMENT="${M16_APPROVAL_PACKET_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M16_APPROVAL_PACKET"])
fragment_path = Path(os.environ["M16_APPROVAL_PACKET_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def first_map_string(values, key):
    for value in values:
        if not isinstance(value, dict):
            continue
        text = str(value.get(key) or "").strip()
        if text:
            return text
    return None


def preferred_target_label(targets):
    fallback = None
    intent_like_fallback = None
    for target in targets:
        if not isinstance(target, dict):
            continue
        label = str(target.get("label") or "").strip()
        if not label:
            continue
        role = str(target.get("role") or "").lower()
        lower_label = label.lower()
        fallback = fallback or label
        if (
            "happening" in lower_label
            or "compose" in lower_label
            or "post" in lower_label
        ):
            intent_like_fallback = intent_like_fallback or label
        if "compose" in role or "text_field" in role:
            return label
    return intent_like_fallback or fallback


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m16ApprovalPacketGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
approval_status = str(
    (summary.get("approvalStatus") if isinstance(summary, dict) else None)
    or gate.get("approvalStatus")
    or "unknown"
)
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "M16 approval packet is ready for user approval review."
        if status == "ready"
        else "Resolve blocked M15 evidence before preparing the M16 approval packet."
    )
blockers = as_list(gate.get("blockers"))
approval_blockers = as_list(
    (summary.get("approvalBlockers") if isinstance(summary, dict) else None)
    or gate.get("approvalBlockers")
)
if approval_blockers and approval_status != "approved":
    next_action = (
        f"{next_action} Re-run M16 with the approved values only after the user "
        f"confirms: {', '.join(str(item) for item in approval_blockers)}."
    )
if status != "ready" and not blockers and summary is None:
    blockers = ["m16_approval_packet_unreadable"]
boundary = "report-only"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
required_approvals = as_list(
    summary.get("requiredApprovals") if isinstance(summary, dict) else []
)
exact_text_candidates = as_list(
    summary.get("exactTextCandidates") if isinstance(summary, dict) else []
)
text_entry_targets = as_list(
    summary.get("textEntryTargets") if isinstance(summary, dict) else []
)
public_action_targets = as_list(
    summary.get("publicActionTargets") if isinstance(summary, dict) else []
)
checks = as_list(gate.get("checks"))
suggested_exact_text = first_map_string(exact_text_candidates, "text")
suggested_target_label = preferred_target_label(text_entry_targets)
suggested_public_action_label = first_map_string(public_action_targets, "label")
approval_command = None
if (
    isinstance(summary, dict)
    and status == "ready"
    and approval_status != "approved"
    and summary.get("sourceM15Handoff")
):
    approval_command_parts = [
        "bash",
        "tool/run_macos_computer_use_m16_approval_packet.sh",
        "--root",
        str(summary_path.parent.parent),
        "--m15-handoff",
        str(summary.get("sourceM15Handoff")),
    ]
    source_review = str(summary.get("sourceM15LlmReview") or "").strip()
    if source_review:
        approval_command_parts.extend(["--m15-llm-review", source_review])
    if suggested_exact_text:
        approval_command_parts.extend([
            "--approved-exact-text",
            suggested_exact_text,
        ])
    if suggested_target_label:
        approval_command_parts.extend([
            "--approved-target-label",
            suggested_target_label,
        ])
    if suggested_public_action_label:
        approval_command_parts.extend([
            "--approved-public-action-label",
            suggested_public_action_label,
        ])
    approval_command = shlex.join(approval_command_parts)

lines = [
    "",
    "## M16 Approval Packet Evidence",
    "",
    f"- M16 approval packet: `{summary_path}`",
    f"- M16 approval packet status: {status}",
    f"- M16 approval packet approval status: {approval_status}",
    f"- M16 approval packet boundary: {boundary}",
    f"- M16 approval packet next action: {next_action}",
    f"- M16 approval packet blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M16 approval packet approval blockers: {', '.join(str(item) for item in approval_blockers) if approval_blockers else 'none'}",
    f"- M16 exact text candidates: {len(exact_text_candidates)}",
    f"- M16 text-entry targets: {len(text_entry_targets)}",
    f"- M16 public-action targets: {len(public_action_targets)}",
    f"- M16 suggested exact text approval: {suggested_exact_text or '-'}",
    f"- M16 suggested target approval: {suggested_target_label or '-'}",
    f"- M16 suggested public action approval: {suggested_public_action_label or '-'}",
]
if approval_command:
    lines.append(
        f"- M16 approval command after user confirmation: `{approval_command}`"
    )
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )
if required_approvals:
    lines.extend([
        "",
        "| Approval | Required | Status | Value |",
        "| --- | --- | --- | --- |",
    ])
    for approval in required_approvals:
        if not isinstance(approval, dict):
            continue
        lines.append(
            "| {id} | {required} | {status} | {value} |".format(
                id=cell(approval.get("id")),
                required=cell(str(approval.get("required", False)).lower()),
                status=cell(approval.get("status")),
                value=cell(approval.get("approvedValue")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M16_APPROVAL_PACKET_STATUS={shlex.quote(status)}")
print(f"M16_APPROVAL_PACKET_APPROVAL_STATUS={shlex.quote(approval_status)}")
print(f"M16_APPROVAL_PACKET_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M16_APPROVAL_PACKET_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m16_approval_packet_values}"
else
  cat >"${M16_APPROVAL_PACKET_FRAGMENT}" <<EOF

## M16 Approval Packet Evidence

- M16 approval packet: \`not discovered\`
- M16 approval packet status: missing
- M16 approval packet approval status: ${M16_APPROVAL_PACKET_APPROVAL_STATUS}
- M16 approval packet boundary: ${M16_APPROVAL_PACKET_BOUNDARY}
- M16 approval packet next action: ${M16_APPROVAL_PACKET_NEXT_ACTION}
- M16 approval packet blockers: missing_m16_approval_packet
EOF
fi

if [[ -n "${M17_EXECUTION_REHEARSAL}" && -f "${M17_EXECUTION_REHEARSAL}" ]]; then
  m17_execution_rehearsal_values="$(
    M17_EXECUTION_REHEARSAL="${M17_EXECUTION_REHEARSAL}" M17_EXECUTION_REHEARSAL_FRAGMENT="${M17_EXECUTION_REHEARSAL_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M17_EXECUTION_REHEARSAL"])
fragment_path = Path(os.environ["M17_EXECUTION_REHEARSAL_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m17ExecutionRehearsalGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
approval_status = str(
    (summary.get("approvalStatus") if isinstance(summary, dict) else None)
    or "unknown"
)
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "M17 execution rehearsal is ready for future user-operated execution review."
        if status == "ready"
        else "Resolve blocked M17 rehearsal checks before future execution."
    )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m17_execution_rehearsal_unreadable"]
boundary = "report-only"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
execution_phases = as_list(
    summary.get("executionPhases") if isinstance(summary, dict) else []
)
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M17 Execution Rehearsal Evidence",
    "",
    f"- M17 execution rehearsal: `{summary_path}`",
    f"- M17 execution rehearsal status: {status}",
    f"- M17 execution rehearsal approval status: {approval_status}",
    f"- M17 execution rehearsal boundary: {boundary}",
    f"- M17 execution rehearsal next action: {next_action}",
    f"- M17 execution rehearsal blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M17 execution rehearsal phases: {len(execution_phases)}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )
if execution_phases:
    lines.extend([
        "",
        "| Phase | Mode | Approved | Value |",
        "| --- | --- | --- | --- |",
    ])
    for phase in execution_phases:
        if not isinstance(phase, dict):
            continue
        lines.append(
            "| {phase} | {mode} | {approved} | {value} |".format(
                phase=cell(phase.get("id")),
                mode=cell(phase.get("mode")),
                approved=cell(str(phase.get("approved", False)).lower()),
                value=cell(phase.get("approvedValue")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M17_EXECUTION_REHEARSAL_STATUS={shlex.quote(status)}")
print(f"M17_EXECUTION_REHEARSAL_APPROVAL_STATUS={shlex.quote(approval_status)}")
print(f"M17_EXECUTION_REHEARSAL_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M17_EXECUTION_REHEARSAL_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m17_execution_rehearsal_values}"
else
  cat >"${M17_EXECUTION_REHEARSAL_FRAGMENT}" <<EOF

## M17 Execution Rehearsal Evidence

- M17 execution rehearsal: \`not discovered\`
- M17 execution rehearsal status: missing
- M17 execution rehearsal approval status: ${M17_EXECUTION_REHEARSAL_APPROVAL_STATUS}
- M17 execution rehearsal boundary: ${M17_EXECUTION_REHEARSAL_BOUNDARY}
- M17 execution rehearsal next action: ${M17_EXECUTION_REHEARSAL_NEXT_ACTION}
- M17 execution rehearsal blockers: missing_m17_execution_rehearsal
EOF
fi

if [[ -n "${M18_EXECUTION_HANDOFF}" && -f "${M18_EXECUTION_HANDOFF}" ]]; then
  m18_execution_handoff_values="$(
    M18_EXECUTION_HANDOFF="${M18_EXECUTION_HANDOFF}" M18_EXECUTION_HANDOFF_FRAGMENT="${M18_EXECUTION_HANDOFF_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M18_EXECUTION_HANDOFF"])
fragment_path = Path(os.environ["M18_EXECUTION_HANDOFF_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m18ExecutionHandoffGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "Ask the user to perform the runtime step manually with fresh observation and action-time confirmations."
        if status == "ready"
        else "Resolve M18 handoff blockers before preparing any runtime execution step."
    )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m18_execution_handoff_unreadable"]
boundary = "report-only handoff"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))
confirmations = as_list(
    summary.get("actionTimeConfirmations") if isinstance(summary, dict) else []
)
checklist = as_list(
    summary.get("executionChecklist") if isinstance(summary, dict) else []
)

lines = [
    "",
    "## M18 Execution Handoff Evidence",
    "",
    f"- M18 execution handoff: `{summary_path}`",
    f"- M18 execution handoff status: {status}",
    f"- M18 execution handoff boundary: {boundary}",
    f"- M18 execution handoff next action: {next_action}",
    f"- M18 execution handoff blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M18 action-time confirmations: {len(confirmations)}",
    f"- M18 execution checklist steps: {len(checklist)}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )
if confirmations:
    lines.extend([
        "",
        "| Confirmation | Required | Approved Before Run | Value |",
        "| --- | --- | --- | --- |",
    ])
    for confirmation in confirmations:
        if not isinstance(confirmation, dict):
            continue
        lines.append(
            "| {id} | {required} | {approved} | {value} |".format(
                id=cell(confirmation.get("id")),
                required=cell(str(confirmation.get("required", False)).lower()),
                approved=cell(str(confirmation.get("approvedBeforeRun", False)).lower()),
                value=cell(confirmation.get("approvedValue")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M18_EXECUTION_HANDOFF_STATUS={shlex.quote(status)}")
print(f"M18_EXECUTION_HANDOFF_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M18_EXECUTION_HANDOFF_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m18_execution_handoff_values}"
else
  cat >"${M18_EXECUTION_HANDOFF_FRAGMENT}" <<EOF

## M18 Execution Handoff Evidence

- M18 execution handoff: \`not discovered\`
- M18 execution handoff status: missing
- M18 execution handoff boundary: ${M18_EXECUTION_HANDOFF_BOUNDARY}
- M18 execution handoff next action: ${M18_EXECUTION_HANDOFF_NEXT_ACTION}
- M18 execution handoff blockers: missing_m18_execution_handoff
EOF
fi

if [[ -n "${M20_EXECUTION_RESULT_INTAKE}" && -f "${M20_EXECUTION_RESULT_INTAKE}" ]]; then
  m20_execution_result_intake_values="$(
    M20_EXECUTION_RESULT_INTAKE="${M20_EXECUTION_RESULT_INTAKE}" M20_EXECUTION_RESULT_INTAKE_FRAGMENT="${M20_EXECUTION_RESULT_INTAKE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M20_EXECUTION_RESULT_INTAKE"])
fragment_path = Path(os.environ["M20_EXECUTION_RESULT_INTAKE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m20ExecutionResultIntakeGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
manual_inputs = summary.get("manualInputs") if isinstance(summary, dict) else None
manual_inputs = manual_inputs if isinstance(manual_inputs, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "Review the user-operated runtime result evidence before any follow-up action."
        if status == "ready"
        else "Resolve M20 result intake blockers before accepting runtime evidence."
    )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m20_execution_result_intake_unreadable"]
boundary = "report-only result intake"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))
result_sequence = as_list(summary.get("resultSequence") if isinstance(summary, dict) else [])
runtime_action = str(manual_inputs.get("runtimeAction") or "unknown")
post_action_observation = str(manual_inputs.get("postActionObservation") or "unknown")

lines = [
    "",
    "## M20 Execution Result Intake Evidence",
    "",
    f"- M20 execution result intake: `{summary_path}`",
    f"- M20 execution result intake status: {status}",
    f"- M20 execution result intake boundary: {boundary}",
    f"- M20 execution result intake next action: {next_action}",
    f"- M20 execution result intake blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M20 runtime action: {runtime_action}",
    f"- M20 post-action observation: {post_action_observation}",
    f"- M20 result sequence steps: {len(result_sequence)}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )
if result_sequence:
    lines.extend([
        "",
        "| Result Step | Required | Status |",
        "| --- | --- | --- |",
    ])
    for step in result_sequence:
        if not isinstance(step, dict):
            continue
        lines.append(
            "| {id} | {required} | {status} |".format(
                id=cell(step.get("id")),
                required=cell(str(step.get("required", False)).lower()),
                status=cell(step.get("status")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M20_EXECUTION_RESULT_INTAKE_STATUS={shlex.quote(status)}")
print(f"M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M20_EXECUTION_RESULT_INTAKE_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m20_execution_result_intake_values}"
else
  cat >"${M20_EXECUTION_RESULT_INTAKE_FRAGMENT}" <<EOF

## M20 Execution Result Intake Evidence

- M20 execution result intake: \`not discovered\`
- M20 execution result intake status: missing
- M20 execution result intake boundary: ${M20_EXECUTION_RESULT_INTAKE_BOUNDARY}
- M20 execution result intake next action: ${M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION}
- M20 execution result intake blockers: none
EOF
fi

if [[ -n "${M22_POST_ACTION_REVIEW}" && -f "${M22_POST_ACTION_REVIEW}" ]]; then
  m22_post_action_review_values="$(
    M22_POST_ACTION_REVIEW="${M22_POST_ACTION_REVIEW}" M22_POST_ACTION_REVIEW_FRAGMENT="${M22_POST_ACTION_REVIEW_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M22_POST_ACTION_REVIEW"])
fragment_path = Path(os.environ["M22_POST_ACTION_REVIEW_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m22PostActionReviewGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
review_inputs = summary.get("reviewInputs") if isinstance(summary, dict) else None
review_inputs = review_inputs if isinstance(review_inputs, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    recommendation = (
        summary.get("nextCycleRecommendation") if isinstance(summary, dict) else None
    )
    if status == "ready" and recommendation == "start_new_observe_action_cycle":
        next_action = (
            "Return to M14 observe-only evidence before proposing any follow-up action."
        )
    elif status == "ready":
        next_action = (
            "Archive the reviewed M20 result as the completed action cycle evidence."
        )
    else:
        next_action = (
            "Resolve M22 post-action review blockers before closing the action cycle."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m22_post_action_review_unreadable"]
boundary = "report-only post-action review"
recommendation = "unknown"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
    recommendation = str(summary.get("nextCycleRecommendation") or "unknown")
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M22 Post-Action Review Evidence",
    "",
    f"- M22 post-action review: `{summary_path}`",
    f"- M22 post-action review status: {status}",
    f"- M22 post-action review boundary: {boundary}",
    f"- M22 post-action review next action: {next_action}",
    f"- M22 post-action review blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M22 result reviewed: {review_inputs.get('resultReviewed', 'unknown')}",
    f"- M22 post-action state: {review_inputs.get('postActionState', 'unknown')}",
    f"- M22 follow-up required: {review_inputs.get('followUpRequired', 'unknown')}",
    f"- M22 next cycle recommendation: {recommendation}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M22_POST_ACTION_REVIEW_STATUS={shlex.quote(status)}")
print(f"M22_POST_ACTION_REVIEW_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M22_POST_ACTION_REVIEW_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m22_post_action_review_values}"
else
  cat >"${M22_POST_ACTION_REVIEW_FRAGMENT}" <<EOF

## M22 Post-Action Review Evidence

- M22 post-action review: \`not discovered\`
- M22 post-action review status: missing
- M22 post-action review boundary: ${M22_POST_ACTION_REVIEW_BOUNDARY}
- M22 post-action review next action: ${M22_POST_ACTION_REVIEW_NEXT_ACTION}
- M22 post-action review blockers: none
EOF
fi

if [[ -n "${M23_CYCLE_OUTCOME_HANDOFF}" && -f "${M23_CYCLE_OUTCOME_HANDOFF}" ]]; then
  m23_cycle_outcome_handoff_values="$(
    M23_CYCLE_OUTCOME_HANDOFF="${M23_CYCLE_OUTCOME_HANDOFF}" M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT="${M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M23_CYCLE_OUTCOME_HANDOFF"])
fragment_path = Path(os.environ["M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m23CycleOutcomeHandoffGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
handoff_inputs = summary.get("handoffInputs") if isinstance(summary, dict) else None
handoff_inputs = handoff_inputs if isinstance(handoff_inputs, dict) else {}
next_observe_seed = summary.get("nextObserveSeed") if isinstance(summary, dict) else None
next_observe_seed = next_observe_seed if isinstance(next_observe_seed, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
cycle_outcome = "unknown"
recommendation = "unknown"
if isinstance(summary, dict):
    cycle_outcome = str(summary.get("cycleOutcome") or "unknown")
    recommendation = str(summary.get("sourceNextCycleRecommendation") or "unknown")
if not next_action:
    if status == "ready" and cycle_outcome == "restart_observe_action_cycle":
        next_action = (
            "Start a new M14 observe-only evidence pass with the recorded follow-up note."
        )
    elif status == "ready":
        next_action = "Archive the completed action cycle evidence."
    else:
        next_action = (
            "Resolve M23 cycle outcome blockers before closing or restarting the action cycle."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m23_cycle_outcome_handoff_unreadable"]
boundary = "report-only cycle outcome handoff"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M23 Cycle Outcome Handoff Evidence",
    "",
    f"- M23 cycle outcome handoff: `{summary_path}`",
    f"- M23 cycle outcome handoff status: {status}",
    f"- M23 cycle outcome handoff boundary: {boundary}",
    f"- M23 cycle outcome handoff next action: {next_action}",
    f"- M23 cycle outcome handoff blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M23 source next cycle recommendation: {recommendation}",
    f"- M23 cycle outcome: {cycle_outcome}",
    f"- M23 next observe needed: {handoff_inputs.get('nextObserveNeeded', 'unknown')}",
    f"- M23 next observe required: {next_observe_seed.get('required', 'unknown')}",
    f"- M23 next observe return milestone: {next_observe_seed.get('returnMilestone', '-')}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M23_CYCLE_OUTCOME_HANDOFF_STATUS={shlex.quote(status)}")
print(f"M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M23_CYCLE_OUTCOME_HANDOFF_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m23_cycle_outcome_handoff_values}"
else
  cat >"${M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT}" <<EOF

## M23 Cycle Outcome Handoff Evidence

- M23 cycle outcome handoff: \`not discovered\`
- M23 cycle outcome handoff status: missing
- M23 cycle outcome handoff boundary: ${M23_CYCLE_OUTCOME_HANDOFF_BOUNDARY}
- M23 cycle outcome handoff next action: ${M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION}
- M23 cycle outcome handoff blockers: none
EOF
fi

if [[ -n "${M25_NEXT_CYCLE_SEED_HANDOFF}" && -f "${M25_NEXT_CYCLE_SEED_HANDOFF}" ]]; then
  m25_next_cycle_seed_handoff_values="$(
    M25_NEXT_CYCLE_SEED_HANDOFF="${M25_NEXT_CYCLE_SEED_HANDOFF}" M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT="${M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M25_NEXT_CYCLE_SEED_HANDOFF"])
fragment_path = Path(os.environ["M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m25NextCycleSeedHandoffGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
seed_inputs = summary.get("seedInputs") if isinstance(summary, dict) else None
seed_inputs = seed_inputs if isinstance(seed_inputs, dict) else {}
next_cycle_seed = summary.get("nextCycleSeed") if isinstance(summary, dict) else None
next_cycle_seed = next_cycle_seed if isinstance(next_cycle_seed, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    if status == "ready":
        next_action = (
            "Start a new M14 observe-only evidence pass using the recorded next-cycle seed."
        )
    else:
        next_action = (
            "Resolve M25 next-cycle seed blockers before starting the next observe-only pass."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m25_next_cycle_seed_handoff_unreadable"]
boundary = "report-only next-cycle seed handoff"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M25 Next-Cycle Seed Handoff Evidence",
    "",
    f"- M25 next-cycle seed handoff: `{summary_path}`",
    f"- M25 next-cycle seed handoff status: {status}",
    f"- M25 next-cycle seed handoff boundary: {boundary}",
    f"- M25 next-cycle seed handoff next action: {next_action}",
    f"- M25 next-cycle seed handoff blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M25 seed accepted: {seed_inputs.get('seedAccepted', 'unknown')}",
    f"- M25 return milestone: {next_cycle_seed.get('returnMilestone', 'unknown')}",
    f"- M25 seed boundary: {next_cycle_seed.get('boundary', 'unknown')}",
    f"- M25 seed note: {next_cycle_seed.get('note', '-')}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M25_NEXT_CYCLE_SEED_HANDOFF_STATUS={shlex.quote(status)}")
print(f"M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M25_NEXT_CYCLE_SEED_HANDOFF_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m25_next_cycle_seed_handoff_values}"
else
  cat >"${M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT}" <<EOF

## M25 Next-Cycle Seed Handoff Evidence

- M25 next-cycle seed handoff: \`not discovered\`
- M25 next-cycle seed handoff status: missing
- M25 next-cycle seed handoff boundary: ${M25_NEXT_CYCLE_SEED_HANDOFF_BOUNDARY}
- M25 next-cycle seed handoff next action: ${M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION}
- M25 next-cycle seed handoff blockers: none
EOF
fi

if [[ -n "${M26_OBSERVE_RESTART_PACKET}" && -f "${M26_OBSERVE_RESTART_PACKET}" ]]; then
  m26_observe_restart_packet_values="$(
    M26_OBSERVE_RESTART_PACKET="${M26_OBSERVE_RESTART_PACKET}" M26_OBSERVE_RESTART_PACKET_FRAGMENT="${M26_OBSERVE_RESTART_PACKET_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M26_OBSERVE_RESTART_PACKET"])
fragment_path = Path(os.environ["M26_OBSERVE_RESTART_PACKET_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m26ObserveRestartPacketGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
next_observe = summary.get("nextObservePreparation") if isinstance(summary, dict) else None
next_observe = next_observe if isinstance(next_observe, dict) else {}
commands = summary.get("commands") if isinstance(summary, dict) else None
commands = commands if isinstance(commands, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    if status == "ready":
        next_action = (
            "Ask the user to manually prepare the target app, capture a screenshot, and run the M14 observe-only canary command."
        )
    else:
        next_action = (
            "Resolve M26 observe restart packet blockers before asking for a new M14 screenshot."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m26_observe_restart_packet_unreadable"]
boundary = "report-only M14 observe restart packet"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M26 Observe Restart Packet Evidence",
    "",
    f"- M26 observe restart packet: `{summary_path}`",
    f"- M26 observe restart packet status: {status}",
    f"- M26 observe restart packet boundary: {boundary}",
    f"- M26 observe restart packet next action: {next_action}",
    f"- M26 observe restart packet blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M26 target app: {summary.get('targetApp', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M26 target intent: {summary.get('targetIntent', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M26 return milestone: {next_observe.get('returnMilestone', 'unknown')}",
    f"- M26 observe boundary: {next_observe.get('boundary', 'unknown')}",
    f"- M26 M14 observe command: `{commands.get('m14ObserveCanary', '-')}`",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M26_OBSERVE_RESTART_PACKET_STATUS={shlex.quote(status)}")
print(f"M26_OBSERVE_RESTART_PACKET_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M26_OBSERVE_RESTART_PACKET_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m26_observe_restart_packet_values}"
else
  cat >"${M26_OBSERVE_RESTART_PACKET_FRAGMENT}" <<EOF

## M26 Observe Restart Packet Evidence

- M26 observe restart packet: \`not discovered\`
- M26 observe restart packet status: missing
- M26 observe restart packet boundary: ${M26_OBSERVE_RESTART_PACKET_BOUNDARY}
- M26 observe restart packet next action: ${M26_OBSERVE_RESTART_PACKET_NEXT_ACTION}
- M26 observe restart packet blockers: none
EOF
fi

if [[ -n "${M27_SCREENSHOT_REQUEST_HANDOFF}" && -f "${M27_SCREENSHOT_REQUEST_HANDOFF}" ]]; then
  m27_screenshot_request_handoff_values="$(
    M27_SCREENSHOT_REQUEST_HANDOFF="${M27_SCREENSHOT_REQUEST_HANDOFF}" M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT="${M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M27_SCREENSHOT_REQUEST_HANDOFF"])
fragment_path = Path(os.environ["M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m27ScreenshotRequestHandoffGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
request = summary.get("userScreenshotRequest") if isinstance(summary, dict) else None
request = request if isinstance(request, dict) else {}
commands = summary.get("commands") if isinstance(summary, dict) else None
commands = commands if isinstance(commands, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    if status == "ready":
        next_action = (
            "Ask the user to manually prepare the target app, capture the requested screenshot, and run the M14 observe-only canary command."
        )
    else:
        next_action = (
            "Resolve M27 screenshot request handoff blockers before asking for the manual screenshot."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m27_screenshot_request_handoff_unreadable"]
boundary = "report-only manual screenshot request"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M27 Screenshot Request Handoff Evidence",
    "",
    f"- M27 screenshot request handoff: `{summary_path}`",
    f"- M27 screenshot request handoff status: {status}",
    f"- M27 screenshot request handoff boundary: {boundary}",
    f"- M27 screenshot request handoff next action: {next_action}",
    f"- M27 screenshot request handoff blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M27 target app: {summary.get('targetApp', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M27 target intent: {summary.get('targetIntent', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M27 screenshot provided: {request.get('provided', 'unknown')}",
    f"- M27 M14 observe command: `{commands.get('m14ObserveCanary', '-')}`",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M27_SCREENSHOT_REQUEST_HANDOFF_STATUS={shlex.quote(status)}")
print(f"M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M27_SCREENSHOT_REQUEST_HANDOFF_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m27_screenshot_request_handoff_values}"
else
  cat >"${M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT}" <<EOF

## M27 Screenshot Request Handoff Evidence

- M27 screenshot request handoff: \`not discovered\`
- M27 screenshot request handoff status: missing
- M27 screenshot request handoff boundary: ${M27_SCREENSHOT_REQUEST_HANDOFF_BOUNDARY}
- M27 screenshot request handoff next action: ${M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION}
- M27 screenshot request handoff blockers: none
EOF
fi

if [[ -n "${M28_SCREENSHOT_EVIDENCE_INTAKE}" && -f "${M28_SCREENSHOT_EVIDENCE_INTAKE}" ]]; then
  m28_screenshot_evidence_intake_values="$(
    M28_SCREENSHOT_EVIDENCE_INTAKE="${M28_SCREENSHOT_EVIDENCE_INTAKE}" M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT="${M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M28_SCREENSHOT_EVIDENCE_INTAKE"])
fragment_path = Path(os.environ["M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m28ScreenshotEvidenceIntakeGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
evidence = summary.get("screenshotEvidence") if isinstance(summary, dict) else None
evidence = evidence if isinstance(evidence, dict) else {}
commands = summary.get("commands") if isinstance(summary, dict) else None
commands = commands if isinstance(commands, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    if status == "ready":
        next_action = (
            "Run the M14 observe-only canary with the user-provided screenshot, then continue the approval-bound observe/action cycle."
        )
    else:
        next_action = (
            "Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m28_screenshot_evidence_intake_unreadable"]
boundary = "report-only screenshot evidence intake"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M28 Screenshot Evidence Intake",
    "",
    f"- M28 screenshot evidence intake: `{summary_path}`",
    f"- M28 screenshot evidence intake status: {status}",
    f"- M28 screenshot evidence intake boundary: {boundary}",
    f"- M28 screenshot evidence intake next action: {next_action}",
    f"- M28 screenshot evidence intake blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M28 target app: {summary.get('targetApp', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M28 target intent: {summary.get('targetIntent', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M28 screenshot path: {evidence.get('path', 'unknown')}",
    f"- M28 screenshot bytes: {evidence.get('sizeBytes', 'unknown')}",
    f"- M28 M14 observe command: `{commands.get('m14ObserveCanary', '-')}`",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS={shlex.quote(status)}")
print(f"M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M28_SCREENSHOT_EVIDENCE_INTAKE_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m28_screenshot_evidence_intake_values}"
else
  cat >"${M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT}" <<EOF

## M28 Screenshot Evidence Intake

- M28 screenshot evidence intake: \`not discovered\`
- M28 screenshot evidence intake status: missing
- M28 screenshot evidence intake boundary: ${M28_SCREENSHOT_EVIDENCE_INTAKE_BOUNDARY}
- M28 screenshot evidence intake next action: ${M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION}
- M28 screenshot evidence intake blockers: none
EOF
fi

if [[ -n "${M29_OBSERVE_CANARY_RUN_PACKET}" && -f "${M29_OBSERVE_CANARY_RUN_PACKET}" ]]; then
  m29_observe_canary_run_packet_values="$(
    M29_OBSERVE_CANARY_RUN_PACKET="${M29_OBSERVE_CANARY_RUN_PACKET}" M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT="${M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M29_OBSERVE_CANARY_RUN_PACKET"])
fragment_path = Path(os.environ["M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m29ObserveCanaryRunPacketGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
evidence = summary.get("screenshotEvidence") if isinstance(summary, dict) else None
evidence = evidence if isinstance(evidence, dict) else {}
commands = summary.get("commands") if isinstance(summary, dict) else None
commands = commands if isinstance(commands, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    if status == "ready":
        next_action = (
            "Ask the user to run the M14 observe-only canary command with the recorded screenshot, then review the new M14 evidence."
        )
    else:
        next_action = (
            "Resolve M29 observe canary run packet blockers before asking the user to run M14."
        )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m29_observe_canary_run_packet_unreadable"]
boundary = "report-only M14 observe canary run packet"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M29 Observe Canary Run Packet",
    "",
    f"- M29 observe canary run packet: `{summary_path}`",
    f"- M29 observe canary run packet status: {status}",
    f"- M29 observe canary run packet boundary: {boundary}",
    f"- M29 observe canary run packet next action: {next_action}",
    f"- M29 observe canary run packet blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M29 target app: {summary.get('targetApp', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M29 target intent: {summary.get('targetIntent', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M29 screenshot path: {evidence.get('path', 'unknown')}",
    f"- M29 screenshot bytes: {evidence.get('sizeBytes', 'unknown')}",
    f"- M29 M14 observe command: `{commands.get('m14ObserveCanary', '-')}`",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M29_OBSERVE_CANARY_RUN_PACKET_STATUS={shlex.quote(status)}")
print(f"M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M29_OBSERVE_CANARY_RUN_PACKET_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m29_observe_canary_run_packet_values}"
else
  cat >"${M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT}" <<EOF

## M29 Observe Canary Run Packet

- M29 observe canary run packet: \`not discovered\`
- M29 observe canary run packet status: missing
- M29 observe canary run packet boundary: ${M29_OBSERVE_CANARY_RUN_PACKET_BOUNDARY}
- M29 observe canary run packet next action: ${M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION}
- M29 observe canary run packet blockers: none
EOF
fi

if [[ -n "${M30_OBSERVE_RESULT_INTAKE}" && -f "${M30_OBSERVE_RESULT_INTAKE}" ]]; then
  m30_observe_result_intake_values="$(
    M30_OBSERVE_RESULT_INTAKE="${M30_OBSERVE_RESULT_INTAKE}" M30_OBSERVE_RESULT_INTAKE_FRAGMENT="${M30_OBSERVE_RESULT_INTAKE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["M30_OBSERVE_RESULT_INTAKE"])
fragment_path = Path(os.environ["M30_OBSERVE_RESULT_INTAKE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
gate = summary.get("m30ObserveResultIntakeGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else {}
m14_evidence = summary.get("m14ObserveEvidence") if isinstance(summary, dict) else None
m14_evidence = m14_evidence if isinstance(m14_evidence, dict) else {}
commands = summary.get("commands") if isinstance(summary, dict) else None
commands = commands if isinstance(commands, dict) else {}
status = str(gate.get("status") or "")
if not status:
    if isinstance(summary, dict) and isinstance(summary.get("ready"), bool):
        status = "ready" if summary.get("ready") is True else "blocked"
    elif summary is None:
        status = "blocked"
    else:
        status = "unknown"
next_action = str(gate.get("nextAction") or "")
if not next_action:
    next_action = (
        "Return to M15 action proposal handoff using the ready M14 observe evidence from this intake."
        if status == "ready"
        else "Resolve M30 observe result intake blockers before returning to M15."
    )
blockers = as_list(gate.get("blockers"))
if status != "ready" and not blockers and summary is None:
    blockers = ["m30_observe_result_intake_unreadable"]
boundary = "report-only M14 observe result intake"
if isinstance(summary, dict):
    boundary = (
        f"{summary.get('llmBoundary', 'unknown_llm_boundary')}, "
        f"{summary.get('tccBoundary', 'unknown_tcc_boundary')}, "
        f"{summary.get('desktopActionBoundary', 'unknown_desktop_boundary')}, "
        f"{summary.get('executionBoundary', 'unknown_execution_boundary')}"
    )
checks = as_list(gate.get("checks"))

lines = [
    "",
    "## M30 Observe Result Intake",
    "",
    f"- M30 observe result intake: `{summary_path}`",
    f"- M30 observe result intake status: {status}",
    f"- M30 observe result intake boundary: {boundary}",
    f"- M30 observe result intake next action: {next_action}",
    f"- M30 observe result intake blockers: {', '.join(str(item) for item in blockers) if blockers else 'none'}",
    f"- M30 target app: {summary.get('targetApp', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M30 target intent: {summary.get('targetIntent', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M30 screenshot path: {summary.get('screenshotPath', 'unknown') if isinstance(summary, dict) else 'unknown'}",
    f"- M30 M14 evidence gate: {m14_evidence.get('gateStatus', 'unknown')}",
    f"- M30 candidate targets: {m14_evidence.get('candidateTargetCount', 'unknown')}",
    f"- M30 M15 action proposal command: `{commands.get('m15ActionProposalHandoff', '-')}`",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        lines.append(
            "| {id} | {status} | {next_action} |".format(
                id=cell(check.get("id")),
                status="passed" if check.get("ok") is True else "blocked",
                next_action=cell(check.get("nextAction")),
            )
        )

fragment_path.write_text("\n".join(lines) + "\n")
print(f"M30_OBSERVE_RESULT_INTAKE_STATUS={shlex.quote(status)}")
print(f"M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION={shlex.quote(next_action)}")
print(f"M30_OBSERVE_RESULT_INTAKE_BOUNDARY={shlex.quote(boundary)}")
PY
  )"
  eval "${m30_observe_result_intake_values}"
else
  cat >"${M30_OBSERVE_RESULT_INTAKE_FRAGMENT}" <<EOF

## M30 Observe Result Intake

- M30 observe result intake: \`not discovered\`
- M30 observe result intake status: missing
- M30 observe result intake boundary: ${M30_OBSERVE_RESULT_INTAKE_BOUNDARY}
- M30 observe result intake next action: ${M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION}
- M30 observe result intake blockers: none
EOF
fi

manual_tcc_status="not provided"
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  if [[ -f "${MANUAL_TCC_REPORT}" ]]; then
    manual_tcc_status="provided"
  else
    manual_tcc_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_MANUAL_TCC_REPORT:-}" ]]; then
  MANUAL_TCC_REPORT="${DISCOVERED_MANUAL_TCC_REPORT}"
  manual_tcc_status="discovered"
fi

desktop_action_status="not provided"
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  if [[ -f "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
    desktop_action_status="provided"
  else
    desktop_action_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY:-}" ]]; then
  DESKTOP_ACTION_CANARY_SUMMARY="${DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY}"
  desktop_action_status="discovered"
fi

llm_canary_status="discovery only"
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  if [[ -f "${LLM_CANARY_SUMMARY}" ]]; then
    llm_canary_status="provided"
  else
    llm_canary_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_LLM_CANARY_SUMMARY:-}" ]]; then
  LLM_CANARY_SUMMARY="${DISCOVERED_LLM_CANARY_SUMMARY}"
  llm_canary_status="discovered"
fi

shell_join() {
  local output=""
  local part
  for part in "$@"; do
    if [[ -n "${output}" ]]; then
      output+=" "
    fi
    printf -v part "%q" "${part}"
    output+="${part}"
  done
  printf '%s' "${output}"
}

final_mvp_args=(
  bash
  tool/run_macos_computer_use_mvp_signoff.sh
  --final-signoff
  --root "${REPORT_ROOT}"
)
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  final_mvp_args+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  final_mvp_args+=(--desktop-action-canary-summary "${DESKTOP_ACTION_CANARY_SUMMARY}")
fi
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  final_mvp_args+=(--llm-canary-summary "${LLM_CANARY_SUMMARY}")
fi
FINAL_MVP_AGGREGATION_COMMAND="$(shell_join "${final_mvp_args[@]}")"
required_input_evidence_ready=0
if [[ ("${manual_tcc_status}" == "provided" || "${manual_tcc_status}" == "discovered") && ("${desktop_action_status}" == "provided" || "${desktop_action_status}" == "discovered") && ("${llm_canary_status}" == "provided" || "${llm_canary_status}" == "discovered") ]]; then
  required_input_evidence_ready=1
fi
review_status="blocked_pending_evidence"
ready_input_evidence=()
missing_input_evidence=()
pending_user_operated_evidence=()
pending_automation_safe_evidence=()
blocked_review_evidence=()
if [[ "${manual_tcc_status}" == "provided" || "${manual_tcc_status}" == "discovered" ]]; then
  ready_input_evidence+=(manual_tcc)
else
  missing_input_evidence+=(manual_tcc)
  pending_user_operated_evidence+=(manual_tcc)
fi
if [[ "${desktop_action_status}" == "provided" || "${desktop_action_status}" == "discovered" ]]; then
  ready_input_evidence+=(desktop_action_canary)
else
  missing_input_evidence+=(desktop_action_canary)
  pending_user_operated_evidence+=(desktop_action_canary)
fi
if [[ "${llm_canary_status}" == "provided" || "${llm_canary_status}" == "discovered" ]]; then
  ready_input_evidence+=(llm_canary)
else
  missing_input_evidence+=(llm_canary)
  pending_automation_safe_evidence+=(llm_canary)
fi
if [[ -n "${M15_ACTION_PROPOSAL_HANDOFF}" && "${M15_ACTION_PROPOSAL_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m15_action_proposal_handoff)
fi
if [[ -n "${M15_LLM_REVIEW_CANARY_SUMMARY}" && "${M15_LLM_REVIEW_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m15_llm_review_canary)
fi
if [[ -n "${M16_APPROVAL_PACKET}" && "${M16_APPROVAL_PACKET_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m16_approval_packet)
fi
if [[ -n "${M17_EXECUTION_REHEARSAL}" && "${M17_EXECUTION_REHEARSAL_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m17_execution_rehearsal)
fi
if [[ -n "${M18_EXECUTION_HANDOFF}" && "${M18_EXECUTION_HANDOFF_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m18_execution_handoff)
fi
if [[ -n "${M20_EXECUTION_RESULT_INTAKE}" && "${M20_EXECUTION_RESULT_INTAKE_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m20_execution_result_intake)
fi
if [[ -n "${M22_POST_ACTION_REVIEW}" && "${M22_POST_ACTION_REVIEW_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m22_post_action_review)
fi
if [[ -n "${M23_CYCLE_OUTCOME_HANDOFF}" && "${M23_CYCLE_OUTCOME_HANDOFF_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m23_cycle_outcome_handoff)
fi
if [[ -n "${M25_NEXT_CYCLE_SEED_HANDOFF}" && "${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m25_next_cycle_seed_handoff)
fi
if [[ -n "${M26_OBSERVE_RESTART_PACKET}" && "${M26_OBSERVE_RESTART_PACKET_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m26_observe_restart_packet)
fi
if [[ -n "${M27_SCREENSHOT_REQUEST_HANDOFF}" && "${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m27_screenshot_request_handoff)
fi
if [[ -n "${M28_SCREENSHOT_EVIDENCE_INTAKE}" && "${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m28_screenshot_evidence_intake)
fi
if [[ -n "${M29_OBSERVE_CANARY_RUN_PACKET}" && "${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m29_observe_canary_run_packet)
fi
if [[ -n "${M30_OBSERVE_RESULT_INTAKE}" && "${M30_OBSERVE_RESULT_INTAKE_STATUS}" != "ready" ]]; then
  blocked_review_evidence+=(m30_observe_result_intake)
fi

if [[ "${required_input_evidence_ready}" != "1" ]]; then
  review_status="blocked_pending_evidence"
elif [[ "${#blocked_review_evidence[@]}" -gt 0 ]]; then
  review_status="blocked_pending_review_evidence"
else
  review_status="ready_for_final_aggregation"
fi

csv_or_none() {
  if [[ "$#" -eq 0 ]]; then
    printf 'none'
    return
  fi
  local output=""
  local part
  for part in "$@"; do
    if [[ -n "${output}" ]]; then
      output+=", "
    fi
    output+="${part}"
  done
  printf '%s' "${output}"
}

if [[ "${#ready_input_evidence[@]}" -eq 0 ]]; then
  ready_input_evidence_summary="none"
else
  ready_input_evidence_summary="$(csv_or_none "${ready_input_evidence[@]}")"
fi
if [[ "${#missing_input_evidence[@]}" -eq 0 ]]; then
  missing_input_evidence_summary="none"
else
  missing_input_evidence_summary="$(csv_or_none "${missing_input_evidence[@]}")"
fi
if [[ "${#pending_user_operated_evidence[@]}" -eq 0 ]]; then
  pending_user_operated_evidence_summary="none"
else
  pending_user_operated_evidence_summary="$(csv_or_none "${pending_user_operated_evidence[@]}")"
fi
if [[ "${#pending_automation_safe_evidence[@]}" -eq 0 ]]; then
  pending_automation_safe_evidence_summary="none"
else
  pending_automation_safe_evidence_summary="$(csv_or_none "${pending_automation_safe_evidence[@]}")"
fi
if [[ "${#blocked_review_evidence[@]}" -eq 0 ]]; then
  blocked_review_evidence_summary="none"
else
  blocked_review_evidence_summary="$(csv_or_none "${blocked_review_evidence[@]}")"
fi

LLM_EVIDENCE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_mvp_llm_evidence_handoff.md"
llm_evidence_values="$(
  LLM_CANARY_SUMMARY="${LLM_CANARY_SUMMARY}" LLM_EVIDENCE_FRAGMENT="${LLM_EVIDENCE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["LLM_CANARY_SUMMARY"]) if os.environ["LLM_CANARY_SUMMARY"] else None
fragment_path = Path(os.environ["LLM_EVIDENCE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    if path is None or not path.exists():
        return None
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


summary = read_json(summary_path)
gate_name = "MVP"
gate = None
if isinstance(summary, dict):
    m14_gate = summary.get("m14EvidenceGate")
    if isinstance(m14_gate, dict):
        gate = m14_gate
        gate_name = "M14"
    else:
        gate = summary.get("mvpEvidenceGate")
gate = gate if isinstance(gate, dict) else None
checks = gate.get("checks") if isinstance(gate, dict) else []
checks = checks if isinstance(checks, list) else []
blockers = gate.get("blockers") if isinstance(gate, dict) else []
blockers = blockers if isinstance(blockers, list) else []
phases = (
    summary.get("expectedUserOperatedRuntimePhases")
    if isinstance(summary, dict)
    else []
)
phases = phases if isinstance(phases, list) else []
status = str(gate.get("status")) if gate and gate.get("status") else "not available"
blocker_text = ", ".join(str(blocker) for blocker in blockers) if blockers else "none"
phase_text = ", ".join(str(phase) for phase in phases) if phases else "not available"

lines = [
    "",
    "## LLM Evidence Gate",
    "",
    f"- LLM evidence summary: `{summary_path if summary_path else 'not provided'}`",
    f"- {gate_name} evidence gate: {status}",
    f"- {gate_name} evidence blockers: {blocker_text}",
    f"- Expected user-operated runtime phases: {phase_text}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        check_id = check.get("id", "unknown")
        check_status = "passed" if check.get("ok") is True else "blocked"
        next_action = check.get("nextAction") or "-"
        lines.append(f"| {check_id} | {check_status} | {next_action} |")
elif summary_path:
    lines.extend([
        "",
        "- No MVP evidence gate was present in the selected LLM summary.",
    ])
else:
    lines.extend([
        "",
        "- No LLM summary is selected yet.",
    ])

fragment_path.write_text("\n".join(lines) + "\n")
print(f"LLM_EVIDENCE_STATUS={shlex.quote(status)}")
print(f"LLM_EVIDENCE_BLOCKERS={shlex.quote(blocker_text)}")
print(f"LLM_EVIDENCE_PHASES={shlex.quote(phase_text)}")
PY
)"
eval "${llm_evidence_values}"

DESKTOP_ACTION_EVIDENCE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_mvp_desktop_action_evidence_handoff.md"
desktop_action_evidence_values="$(
  DESKTOP_ACTION_CANARY_SUMMARY="${DESKTOP_ACTION_CANARY_SUMMARY}" DESKTOP_ACTION_EVIDENCE_FRAGMENT="${DESKTOP_ACTION_EVIDENCE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["DESKTOP_ACTION_CANARY_SUMMARY"]) if os.environ["DESKTOP_ACTION_CANARY_SUMMARY"] else None
fragment_path = Path(os.environ["DESKTOP_ACTION_EVIDENCE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    if path is None or not path.exists():
        return None
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
runs = as_list(summary.get("runs") if isinstance(summary, dict) else [])
phases = as_list(summary.get("expectedPhases") if isinstance(summary, dict) else [])
guidance = as_list(summary.get("safeTargetGuidance") if isinstance(summary, dict) else [])
stable = summary.get("stable") if isinstance(summary, dict) else None
failed = summary.get("failed") if isinstance(summary, dict) else None
run_count = summary.get("runCount") if isinstance(summary, dict) else None
status = "not provided"
if summary_path and summary is None:
    status = "unreadable"
elif isinstance(summary, dict):
    status = "passed" if run_count and failed == 0 and stable is True else "blocked"

lines = [
    "",
    "## Desktop Action Evidence",
    "",
    f"- Desktop action summary: `{summary_path if summary_path else 'not provided'}`",
    f"- Desktop action status: {status}",
    f"- Desktop action runs: {run_count if run_count is not None else 'not available'}",
    f"- Desktop action failures: {failed if failed is not None else 'not available'}",
]
if phases:
    lines.append(
        "- Expected phases: " + ", ".join(f"`{str(phase)}`" for phase in phases)
    )
else:
    lines.append("- Expected phases: not available")
if guidance:
    lines.append(
        "- Safe target guidance: " + "; ".join(str(item) for item in guidance)
    )
if runs:
    lines.extend([
        "",
        "| Run | Status | Failure Class | Pre Observe | Click | Post Observe | Changed Evidence |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ])
    for run in runs:
        if not isinstance(run, dict):
            continue
        phase_status = run.get("phaseStatus")
        phase_status = phase_status if isinstance(phase_status, dict) else {}
        lines.append(
            "| {name} | {status} | {failure} | {pre} | {click} | {post} | {changed} |".format(
                name=cell(run.get("name")),
                status=cell(run.get("status")),
                failure=cell(run.get("failureClass")),
                pre=cell(phase_status.get("preObserve")),
                click=cell(phase_status.get("click")),
                post=cell(phase_status.get("postObserve")),
                changed=cell(phase_status.get("changedEvidence")),
            )
        )
elif summary_path:
    lines.extend([
        "",
        "- No run-level desktop action evidence was present in the selected summary.",
    ])
else:
    lines.extend([
        "",
        "- No desktop action summary is selected yet.",
    ])

fragment_path.write_text("\n".join(lines) + "\n")
print(f"DESKTOP_ACTION_EVIDENCE_STATUS={shlex.quote(status)}")
print(f"DESKTOP_ACTION_EVIDENCE_RUNS={shlex.quote(str(run_count) if run_count is not None else 'not available')}")
print(f"DESKTOP_ACTION_EVIDENCE_FAILURES={shlex.quote(str(failed) if failed is not None else 'not available')}")
PY
)"
eval "${desktop_action_evidence_values}"

cat >"${HANDOFF_MD}" <<EOF
# macOS Computer Use MVP Handoff

- Automation boundary: user-operated TCC and desktop action only
- Report-only handoff and aggregation checks do not require TCC or live desktop action.
- MVP checklist: \`docs/macos_computer_use_mvp_checklist.md\`
- Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}
- Manual TCC status: ${manual_tcc_status}
- Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}
- Desktop action canary status: ${desktop_action_status}
- LLM canary summary: ${LLM_CANARY_SUMMARY:-discovery only}
- LLM canary status: ${llm_canary_status}
- M15 action proposal handoff: ${M15_ACTION_PROPOSAL_HANDOFF:-not discovered}
- M15 action proposal status: ${M15_ACTION_PROPOSAL_STATUS}
- M15 LLM review canary: ${M15_LLM_REVIEW_CANARY_SUMMARY:-not discovered}
- M15 LLM review status: ${M15_LLM_REVIEW_STATUS}
- M16 approval packet: ${M16_APPROVAL_PACKET:-not discovered}
- M16 approval packet status: ${M16_APPROVAL_PACKET_STATUS}
- M16 approval packet approval status: ${M16_APPROVAL_PACKET_APPROVAL_STATUS}
- M17 execution rehearsal: ${M17_EXECUTION_REHEARSAL:-not discovered}
- M17 execution rehearsal status: ${M17_EXECUTION_REHEARSAL_STATUS}
- M17 execution rehearsal approval status: ${M17_EXECUTION_REHEARSAL_APPROVAL_STATUS}
- M18 execution handoff: ${M18_EXECUTION_HANDOFF:-not discovered}
- M18 execution handoff status: ${M18_EXECUTION_HANDOFF_STATUS}
- M20 execution result intake: ${M20_EXECUTION_RESULT_INTAKE:-not discovered}
- M20 execution result intake status: ${M20_EXECUTION_RESULT_INTAKE_STATUS}
- M22 post-action review: ${M22_POST_ACTION_REVIEW:-not discovered}
- M22 post-action review status: ${M22_POST_ACTION_REVIEW_STATUS}
- M23 cycle outcome handoff: ${M23_CYCLE_OUTCOME_HANDOFF:-not discovered}
- M23 cycle outcome handoff status: ${M23_CYCLE_OUTCOME_HANDOFF_STATUS}
- M25 next-cycle seed handoff: ${M25_NEXT_CYCLE_SEED_HANDOFF:-not discovered}
- M25 next-cycle seed handoff status: ${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}
- M26 observe restart packet: ${M26_OBSERVE_RESTART_PACKET:-not discovered}
- M26 observe restart packet status: ${M26_OBSERVE_RESTART_PACKET_STATUS}
- M27 screenshot request handoff: ${M27_SCREENSHOT_REQUEST_HANDOFF:-not discovered}
- M27 screenshot request handoff status: ${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}
- M28 screenshot evidence intake: ${M28_SCREENSHOT_EVIDENCE_INTAKE:-not discovered}
- M28 screenshot evidence intake status: ${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}
- M29 observe canary run packet: ${M29_OBSERVE_CANARY_RUN_PACKET:-not discovered}
- M29 observe canary run packet status: ${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}
- M30 observe result intake: ${M30_OBSERVE_RESULT_INTAKE:-not discovered}
- M30 observe result intake status: ${M30_OBSERVE_RESULT_INTAKE_STATUS}

## Current Required Input Evidence Status

- \`manual_tcc\`: ${manual_tcc_status}
- \`desktop_action_canary\`: ${desktop_action_status}
- \`llm_canary\`: ${llm_canary_status}

## Optional Review Evidence

- \`m15_action_proposal_handoff\`: ${M15_ACTION_PROPOSAL_STATUS}
- M15 action proposal boundary: ${M15_ACTION_PROPOSAL_BOUNDARY}
- M15 action proposal next action: ${M15_ACTION_PROPOSAL_NEXT_ACTION}
- \`m15_llm_review_canary\`: ${M15_LLM_REVIEW_STATUS}
- M15 LLM review boundary: ${M15_LLM_REVIEW_BOUNDARY}
- M15 LLM review next action: ${M15_LLM_REVIEW_NEXT_ACTION}
- \`m16_approval_packet\`: ${M16_APPROVAL_PACKET_STATUS}
- M16 approval packet approval status: ${M16_APPROVAL_PACKET_APPROVAL_STATUS}
- M16 approval packet boundary: ${M16_APPROVAL_PACKET_BOUNDARY}
- M16 approval packet next action: ${M16_APPROVAL_PACKET_NEXT_ACTION}
- \`m17_execution_rehearsal\`: ${M17_EXECUTION_REHEARSAL_STATUS}
- M17 execution rehearsal approval status: ${M17_EXECUTION_REHEARSAL_APPROVAL_STATUS}
- M17 execution rehearsal boundary: ${M17_EXECUTION_REHEARSAL_BOUNDARY}
- M17 execution rehearsal next action: ${M17_EXECUTION_REHEARSAL_NEXT_ACTION}
- \`m18_execution_handoff\`: ${M18_EXECUTION_HANDOFF_STATUS}
- M18 execution handoff boundary: ${M18_EXECUTION_HANDOFF_BOUNDARY}
- M18 execution handoff next action: ${M18_EXECUTION_HANDOFF_NEXT_ACTION}
- \`m20_execution_result_intake\`: ${M20_EXECUTION_RESULT_INTAKE_STATUS}
- M20 execution result intake boundary: ${M20_EXECUTION_RESULT_INTAKE_BOUNDARY}
- M20 execution result intake next action: ${M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION}
- \`m22_post_action_review\`: ${M22_POST_ACTION_REVIEW_STATUS}
- M22 post-action review boundary: ${M22_POST_ACTION_REVIEW_BOUNDARY}
- M22 post-action review next action: ${M22_POST_ACTION_REVIEW_NEXT_ACTION}
- \`m23_cycle_outcome_handoff\`: ${M23_CYCLE_OUTCOME_HANDOFF_STATUS}
- M23 cycle outcome handoff boundary: ${M23_CYCLE_OUTCOME_HANDOFF_BOUNDARY}
- M23 cycle outcome handoff next action: ${M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION}
- \`m25_next_cycle_seed_handoff\`: ${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}
- M25 next-cycle seed handoff boundary: ${M25_NEXT_CYCLE_SEED_HANDOFF_BOUNDARY}
- M25 next-cycle seed handoff next action: ${M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION}
- \`m26_observe_restart_packet\`: ${M26_OBSERVE_RESTART_PACKET_STATUS}
- M26 observe restart packet boundary: ${M26_OBSERVE_RESTART_PACKET_BOUNDARY}
- M26 observe restart packet next action: ${M26_OBSERVE_RESTART_PACKET_NEXT_ACTION}
- \`m27_screenshot_request_handoff\`: ${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}
- M27 screenshot request handoff boundary: ${M27_SCREENSHOT_REQUEST_HANDOFF_BOUNDARY}
- M27 screenshot request handoff next action: ${M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION}
- \`m28_screenshot_evidence_intake\`: ${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}
- M28 screenshot evidence intake boundary: ${M28_SCREENSHOT_EVIDENCE_INTAKE_BOUNDARY}
- M28 screenshot evidence intake next action: ${M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION}
- \`m29_observe_canary_run_packet\`: ${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}
- M29 observe canary run packet boundary: ${M29_OBSERVE_CANARY_RUN_PACKET_BOUNDARY}
- M29 observe canary run packet next action: ${M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION}
- \`m30_observe_result_intake\`: ${M30_OBSERVE_RESULT_INTAKE_STATUS}
- M30 observe result intake boundary: ${M30_OBSERVE_RESULT_INTAKE_BOUNDARY}
- M30 observe result intake next action: ${M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION}

## Expected Final Input Paths

- Manual TCC: \`macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json\`
- Desktop action: \`macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json\`
- MVP fixture LLM: \`macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json\`

## MVP Sign-Off Outputs

- JSON: ${OUTPUT_JSON}
- Markdown: ${OUTPUT_MD}
- Handoff Markdown: ${HANDOFF_MD}
- Release readiness PR Review Summary (final sign-off output): ${OUTPUT_MD}
- Artifact index Markdown: ${ARTIFACT_INDEX_MD}
- Artifact index command: \`${ARTIFACT_INDEX_COMMAND}\`
- MVP readiness preflight command: \`${MVP_READINESS_PREFLIGHT_COMMAND}\`
- Dry-run note: final readiness JSON and Markdown are not written until final sign-off runs.

## PR Review Summary

- Status: ${review_status}
- Ready input evidence: ${ready_input_evidence_summary}
- Missing input evidence: ${missing_input_evidence_summary}
- Pending user-operated evidence: ${pending_user_operated_evidence_summary}
- Pending automation-safe evidence: ${pending_automation_safe_evidence_summary}
- Blocked review evidence: ${blocked_review_evidence_summary}
- Boundary: TCC grants and desktop actions remain user-operated; report-only checks may be automated.

## Operation Boundary

- \`tccGrants\`: user_operated
- \`desktopActions\`: user_operated
- \`inputSmokeRequiresArming\`: true
- \`systemAudioSmokeRequiresArming\`: true

## User-Operated Commands

1. Manual TCC handoff preview:

   \`\`\`bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only
   \`\`\`

2. Manual TCC sign-off after granting the helper in macOS privacy settings:

   \`\`\`bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh
   \`\`\`

3. Desktop action handoff preview before preparing a safe click target:

   \`\`\`bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only
   \`\`\`

4. Desktop action canary after preparing a safe click target:

   \`\`\`bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target
   \`\`\`

5. Final MVP aggregation:

   \`\`\`bash
   bash tool/run_macos_computer_use_mvp_signoff.sh \\
     --manual-tcc-report <manual-tcc-report-or-summary.json> \\
     --desktop-action-canary-summary <desktop-action-canary-summary.json> \\
     --llm-canary-summary <llm-canary-summary.json>
   \`\`\`

## Final MVP Aggregation Command

\`\`\`bash
${FINAL_MVP_AGGREGATION_COMMAND}
\`\`\`

## Automation-Safe Commands

\`\`\`bash
bash tool/run_macos_computer_use_release_readiness.sh --ci
bash tool/run_macos_computer_use_live_canary.sh --overlay
bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh
bash tool/run_macos_computer_use_mvp_llm_readiness.sh
\`\`\`
EOF

cat "${LLM_EVIDENCE_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${DESKTOP_ACTION_EVIDENCE_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M15_ACTION_PROPOSAL_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M15_LLM_REVIEW_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M16_APPROVAL_PACKET_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M17_EXECUTION_REHEARSAL_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M18_EXECUTION_HANDOFF_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M20_EXECUTION_RESULT_INTAKE_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M22_POST_ACTION_REVIEW_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M23_CYCLE_OUTCOME_HANDOFF_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M25_NEXT_CYCLE_SEED_HANDOFF_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M26_OBSERVE_RESTART_PACKET_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M27_SCREENSHOT_REQUEST_HANDOFF_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M28_SCREENSHOT_EVIDENCE_INTAKE_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M29_OBSERVE_CANARY_RUN_PACKET_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${M30_OBSERVE_RESULT_INTAKE_FRAGMENT}" >>"${HANDOFF_MD}"

{
  echo
  echo "## Missing Input Next Actions"
  echo
  if [[ "${manual_tcc_status}" != "provided" && "${manual_tcc_status}" != "discovered" ]]; then
    echo "- Run \`bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only\` first to print the helper grant target without running M8. Ask the user to run \`bash tool/run_macos_computer_use_manual_tcc_signoff.sh\` and provide \`manual_tcc_report_summary.json\`."
  fi
  if [[ "${desktop_action_status}" != "provided" && "${desktop_action_status}" != "discovered" ]]; then
    echo "- Run \`bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only\` first to print the safe target checklist without running the desktop action. Ask the user to run \`bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target\` after preparing the safe target and provide \`canary_summary.json\`."
  fi
  if [[ "${llm_canary_status}" != "provided" && "${llm_canary_status}" != "discovered" ]]; then
    echo "- Run \`bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh\`, run \`bash tool/run_macos_computer_use_real_app_observe_canary.sh\` with a user-provided screenshot, or provide a Computer Use LLM canary \`canary_summary.json\` before final sign-off aggregation."
  fi
  if [[ "${#blocked_review_evidence[@]}" -gt 0 ]]; then
    if [[ -n "${M15_ACTION_PROPOSAL_HANDOFF}" && "${M15_ACTION_PROPOSAL_STATUS}" != "ready" ]]; then
      echo "- ${M15_ACTION_PROPOSAL_NEXT_ACTION}"
    fi
    if [[ -n "${M15_LLM_REVIEW_CANARY_SUMMARY}" && "${M15_LLM_REVIEW_STATUS}" != "ready" ]]; then
      echo "- ${M15_LLM_REVIEW_NEXT_ACTION}"
    fi
    if [[ -n "${M16_APPROVAL_PACKET}" && "${M16_APPROVAL_PACKET_STATUS}" != "ready" ]]; then
      echo "- ${M16_APPROVAL_PACKET_NEXT_ACTION}"
    fi
    if [[ -n "${M17_EXECUTION_REHEARSAL}" && "${M17_EXECUTION_REHEARSAL_STATUS}" != "ready" ]]; then
      echo "- ${M17_EXECUTION_REHEARSAL_NEXT_ACTION}"
    fi
    if [[ -n "${M18_EXECUTION_HANDOFF}" && "${M18_EXECUTION_HANDOFF_STATUS}" != "ready" ]]; then
      echo "- ${M18_EXECUTION_HANDOFF_NEXT_ACTION}"
    fi
    if [[ -n "${M20_EXECUTION_RESULT_INTAKE}" && "${M20_EXECUTION_RESULT_INTAKE_STATUS}" != "ready" ]]; then
      echo "- ${M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION}"
    fi
    if [[ -n "${M22_POST_ACTION_REVIEW}" && "${M22_POST_ACTION_REVIEW_STATUS}" != "ready" ]]; then
      echo "- ${M22_POST_ACTION_REVIEW_NEXT_ACTION}"
    fi
    if [[ -n "${M23_CYCLE_OUTCOME_HANDOFF}" && "${M23_CYCLE_OUTCOME_HANDOFF_STATUS}" != "ready" ]]; then
      echo "- ${M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION}"
    fi
    if [[ -n "${M25_NEXT_CYCLE_SEED_HANDOFF}" && "${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}" != "ready" ]]; then
      echo "- ${M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION}"
    fi
    if [[ -n "${M26_OBSERVE_RESTART_PACKET}" && "${M26_OBSERVE_RESTART_PACKET_STATUS}" != "ready" ]]; then
      echo "- ${M26_OBSERVE_RESTART_PACKET_NEXT_ACTION}"
    fi
    if [[ -n "${M27_SCREENSHOT_REQUEST_HANDOFF}" && "${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}" != "ready" ]]; then
      echo "- ${M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION}"
    fi
    if [[ -n "${M28_SCREENSHOT_EVIDENCE_INTAKE}" && "${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}" != "ready" ]]; then
      echo "- ${M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION}"
    fi
    if [[ -n "${M29_OBSERVE_CANARY_RUN_PACKET}" && "${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}" != "ready" ]]; then
      echo "- ${M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION}"
    fi
    if [[ -n "${M30_OBSERVE_RESULT_INTAKE}" && "${M30_OBSERVE_RESULT_INTAKE_STATUS}" != "ready" ]]; then
      echo "- ${M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION}"
    fi
  fi
  if [[ "${required_input_evidence_ready}" == "1" && "${#blocked_review_evidence[@]}" -eq 0 ]]; then
    echo "- No required input evidence is missing from this wrapper invocation. If readiness still fails, inspect the blocked gate details in the Markdown report."
  elif [[ "${required_input_evidence_ready}" == "1" ]]; then
    echo "- Required input evidence is present, but blocked review evidence must be resolved before final aggregation."
  fi
} >>"${HANDOFF_MD}"

echo "Running macOS Computer Use MVP sign-off aggregator"
echo "  Report root: ${REPORT_ROOT}"
echo "  Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}"
echo "  Manual TCC status: ${manual_tcc_status}"
echo "  Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}"
echo "  Desktop action canary status: ${desktop_action_status}"
echo "  LLM canary summary: ${LLM_CANARY_SUMMARY:-discovery only}"
echo "  LLM canary status: ${llm_canary_status}"
echo "Expected final input paths:"
echo "  Manual TCC: macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json"
echo "  Desktop action: macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json"
echo "  MVP fixture LLM: macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json"
echo "  LLM evidence gate: ${LLM_EVIDENCE_STATUS}"
echo "  LLM evidence blockers: ${LLM_EVIDENCE_BLOCKERS}"
echo "  LLM evidence phases: ${LLM_EVIDENCE_PHASES}"
echo "  Desktop action evidence status: ${DESKTOP_ACTION_EVIDENCE_STATUS}"
echo "  Desktop action evidence runs: ${DESKTOP_ACTION_EVIDENCE_RUNS}"
echo "  Desktop action evidence failures: ${DESKTOP_ACTION_EVIDENCE_FAILURES}"
echo "  M15 action proposal handoff: ${M15_ACTION_PROPOSAL_HANDOFF:-not discovered}"
echo "  M15 action proposal status: ${M15_ACTION_PROPOSAL_STATUS}"
echo "  M15 action proposal boundary: ${M15_ACTION_PROPOSAL_BOUNDARY}"
echo "  M15 action proposal next action: ${M15_ACTION_PROPOSAL_NEXT_ACTION}"
echo "  M15 LLM review canary: ${M15_LLM_REVIEW_CANARY_SUMMARY:-not discovered}"
echo "  M15 LLM review status: ${M15_LLM_REVIEW_STATUS}"
echo "  M15 LLM review boundary: ${M15_LLM_REVIEW_BOUNDARY}"
echo "  M15 LLM review next action: ${M15_LLM_REVIEW_NEXT_ACTION}"
echo "  M16 approval packet: ${M16_APPROVAL_PACKET:-not discovered}"
echo "  M16 approval packet status: ${M16_APPROVAL_PACKET_STATUS}"
echo "  M16 approval packet approval status: ${M16_APPROVAL_PACKET_APPROVAL_STATUS}"
echo "  M16 approval packet boundary: ${M16_APPROVAL_PACKET_BOUNDARY}"
echo "  M16 approval packet next action: ${M16_APPROVAL_PACKET_NEXT_ACTION}"
echo "  M17 execution rehearsal: ${M17_EXECUTION_REHEARSAL:-not discovered}"
echo "  M17 execution rehearsal status: ${M17_EXECUTION_REHEARSAL_STATUS}"
echo "  M17 execution rehearsal approval status: ${M17_EXECUTION_REHEARSAL_APPROVAL_STATUS}"
echo "  M17 execution rehearsal boundary: ${M17_EXECUTION_REHEARSAL_BOUNDARY}"
echo "  M17 execution rehearsal next action: ${M17_EXECUTION_REHEARSAL_NEXT_ACTION}"
echo "  M18 execution handoff: ${M18_EXECUTION_HANDOFF:-not discovered}"
echo "  M18 execution handoff status: ${M18_EXECUTION_HANDOFF_STATUS}"
echo "  M18 execution handoff boundary: ${M18_EXECUTION_HANDOFF_BOUNDARY}"
echo "  M18 execution handoff next action: ${M18_EXECUTION_HANDOFF_NEXT_ACTION}"
echo "  M20 execution result intake: ${M20_EXECUTION_RESULT_INTAKE:-not discovered}"
echo "  M20 execution result intake status: ${M20_EXECUTION_RESULT_INTAKE_STATUS}"
echo "  M20 execution result intake boundary: ${M20_EXECUTION_RESULT_INTAKE_BOUNDARY}"
echo "  M20 execution result intake next action: ${M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION}"
echo "  M22 post-action review: ${M22_POST_ACTION_REVIEW:-not discovered}"
echo "  M22 post-action review status: ${M22_POST_ACTION_REVIEW_STATUS}"
echo "  M22 post-action review boundary: ${M22_POST_ACTION_REVIEW_BOUNDARY}"
echo "  M22 post-action review next action: ${M22_POST_ACTION_REVIEW_NEXT_ACTION}"
echo "  M23 cycle outcome handoff: ${M23_CYCLE_OUTCOME_HANDOFF:-not discovered}"
echo "  M23 cycle outcome handoff status: ${M23_CYCLE_OUTCOME_HANDOFF_STATUS}"
echo "  M23 cycle outcome handoff boundary: ${M23_CYCLE_OUTCOME_HANDOFF_BOUNDARY}"
echo "  M23 cycle outcome handoff next action: ${M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION}"
echo "  M25 next-cycle seed handoff: ${M25_NEXT_CYCLE_SEED_HANDOFF:-not discovered}"
echo "  M25 next-cycle seed handoff status: ${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}"
echo "  M25 next-cycle seed handoff boundary: ${M25_NEXT_CYCLE_SEED_HANDOFF_BOUNDARY}"
echo "  M25 next-cycle seed handoff next action: ${M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION}"
echo "  M26 observe restart packet: ${M26_OBSERVE_RESTART_PACKET:-not discovered}"
echo "  M26 observe restart packet status: ${M26_OBSERVE_RESTART_PACKET_STATUS}"
echo "  M26 observe restart packet boundary: ${M26_OBSERVE_RESTART_PACKET_BOUNDARY}"
echo "  M26 observe restart packet next action: ${M26_OBSERVE_RESTART_PACKET_NEXT_ACTION}"
echo "  M27 screenshot request handoff: ${M27_SCREENSHOT_REQUEST_HANDOFF:-not discovered}"
echo "  M27 screenshot request handoff status: ${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}"
echo "  M27 screenshot request handoff boundary: ${M27_SCREENSHOT_REQUEST_HANDOFF_BOUNDARY}"
echo "  M27 screenshot request handoff next action: ${M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION}"
echo "  M28 screenshot evidence intake: ${M28_SCREENSHOT_EVIDENCE_INTAKE:-not discovered}"
echo "  M28 screenshot evidence intake status: ${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}"
echo "  M28 screenshot evidence intake boundary: ${M28_SCREENSHOT_EVIDENCE_INTAKE_BOUNDARY}"
echo "  M28 screenshot evidence intake next action: ${M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION}"
echo "  M29 observe canary run packet: ${M29_OBSERVE_CANARY_RUN_PACKET:-not discovered}"
echo "  M29 observe canary run packet status: ${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}"
echo "  M29 observe canary run packet boundary: ${M29_OBSERVE_CANARY_RUN_PACKET_BOUNDARY}"
echo "  M29 observe canary run packet next action: ${M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION}"
echo "  M30 observe result intake: ${M30_OBSERVE_RESULT_INTAKE:-not discovered}"
echo "  M30 observe result intake status: ${M30_OBSERVE_RESULT_INTAKE_STATUS}"
echo "  M30 observe result intake boundary: ${M30_OBSERVE_RESULT_INTAKE_BOUNDARY}"
echo "  M30 observe result intake next action: ${M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION}"
echo "  Refresh safe inputs: ${REFRESH_SAFE_INPUTS}"
echo "  Refresh LLM canary: ${REFRESH_LLM_CANARY}"
echo "  Final sign-off mode: ${FINAL_SIGNOFF}"
echo "  Dry run: ${DRY_RUN}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Handoff Markdown: ${HANDOFF_MD}"
echo "MVP sign-off outputs:"
echo "  JSON: ${OUTPUT_JSON}"
echo "  Markdown: ${OUTPUT_MD}"
echo "  Handoff Markdown: ${HANDOFF_MD}"
echo "PR review summary:"
echo "  Handoff PR Review Summary: ${HANDOFF_MD}"
echo "  Release readiness PR Review Summary (final sign-off output): ${OUTPUT_MD}"
echo "  Artifact index PR Review Summary: ${ARTIFACT_INDEX_MD}"
echo "  Artifact index command: ${ARTIFACT_INDEX_COMMAND}"
echo "  MVP readiness preflight command: ${MVP_READINESS_PREFLIGHT_COMMAND}"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "  Dry-run note: final readiness JSON and Markdown are not written until final sign-off runs."
fi
echo "  Status: ${review_status}"
echo "  Ready input evidence: ${ready_input_evidence_summary}"
echo "  Missing input evidence: ${missing_input_evidence_summary}"
echo "  Pending user-operated evidence: ${pending_user_operated_evidence_summary}"
echo "  Pending automation-safe evidence: ${pending_automation_safe_evidence_summary}"
echo "  Blocked review evidence: ${blocked_review_evidence_summary}"
echo "  Release readiness wrapper: ${RELEASE_READINESS_WRAPPER}"
echo "  TCC boundary: user-operated manual verification only"
echo "  Desktop action boundary: user-operated safe click target only"
echo "  Final MVP aggregation command: ${FINAL_MVP_AGGREGATION_COMMAND}"

echo
echo "User-operated commands:"
echo "  bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only"
echo "  bash tool/run_macos_computer_use_manual_tcc_signoff.sh"
echo "  bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only"
echo "  bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target"
echo
echo "MVP handoff next actions:"
if [[ "${manual_tcc_status}" != "provided" && "${manual_tcc_status}" != "discovered" ]]; then
  echo "  - Run \`bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only\` first to print the helper grant target without running M8. Ask the user to run \`bash tool/run_macos_computer_use_manual_tcc_signoff.sh\` and provide \`manual_tcc_report_summary.json\`."
fi
if [[ "${desktop_action_status}" != "provided" && "${desktop_action_status}" != "discovered" ]]; then
  echo "  - Run \`bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only\` first to print the safe target checklist without running the desktop action. Ask the user to run \`bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target\` after preparing the safe target and provide \`canary_summary.json\`."
fi
if [[ "${llm_canary_status}" != "provided" && "${llm_canary_status}" != "discovered" ]]; then
  echo "  - Run \`bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh\`, run \`bash tool/run_macos_computer_use_real_app_observe_canary.sh\` with a user-provided screenshot, or provide a Computer Use LLM canary \`canary_summary.json\` before final sign-off aggregation."
fi
if [[ -n "${M15_ACTION_PROPOSAL_HANDOFF}" && "${M15_ACTION_PROPOSAL_STATUS}" != "ready" ]]; then
  echo "  - ${M15_ACTION_PROPOSAL_NEXT_ACTION}"
fi
if [[ -n "${M15_LLM_REVIEW_CANARY_SUMMARY}" && "${M15_LLM_REVIEW_STATUS}" != "ready" ]]; then
  echo "  - ${M15_LLM_REVIEW_NEXT_ACTION}"
fi
if [[ -n "${M16_APPROVAL_PACKET}" && "${M16_APPROVAL_PACKET_STATUS}" != "ready" ]]; then
  echo "  - ${M16_APPROVAL_PACKET_NEXT_ACTION}"
fi
if [[ -n "${M17_EXECUTION_REHEARSAL}" && "${M17_EXECUTION_REHEARSAL_STATUS}" != "ready" ]]; then
  echo "  - ${M17_EXECUTION_REHEARSAL_NEXT_ACTION}"
fi
if [[ -n "${M18_EXECUTION_HANDOFF}" && "${M18_EXECUTION_HANDOFF_STATUS}" != "ready" ]]; then
  echo "  - ${M18_EXECUTION_HANDOFF_NEXT_ACTION}"
fi
if [[ -n "${M20_EXECUTION_RESULT_INTAKE}" && "${M20_EXECUTION_RESULT_INTAKE_STATUS}" != "ready" ]]; then
  echo "  - ${M20_EXECUTION_RESULT_INTAKE_NEXT_ACTION}"
fi
if [[ -n "${M22_POST_ACTION_REVIEW}" && "${M22_POST_ACTION_REVIEW_STATUS}" != "ready" ]]; then
  echo "  - ${M22_POST_ACTION_REVIEW_NEXT_ACTION}"
fi
if [[ -n "${M23_CYCLE_OUTCOME_HANDOFF}" && "${M23_CYCLE_OUTCOME_HANDOFF_STATUS}" != "ready" ]]; then
  echo "  - ${M23_CYCLE_OUTCOME_HANDOFF_NEXT_ACTION}"
fi
if [[ -n "${M25_NEXT_CYCLE_SEED_HANDOFF}" && "${M25_NEXT_CYCLE_SEED_HANDOFF_STATUS}" != "ready" ]]; then
  echo "  - ${M25_NEXT_CYCLE_SEED_HANDOFF_NEXT_ACTION}"
fi
if [[ -n "${M26_OBSERVE_RESTART_PACKET}" && "${M26_OBSERVE_RESTART_PACKET_STATUS}" != "ready" ]]; then
  echo "  - ${M26_OBSERVE_RESTART_PACKET_NEXT_ACTION}"
fi
if [[ -n "${M27_SCREENSHOT_REQUEST_HANDOFF}" && "${M27_SCREENSHOT_REQUEST_HANDOFF_STATUS}" != "ready" ]]; then
  echo "  - ${M27_SCREENSHOT_REQUEST_HANDOFF_NEXT_ACTION}"
fi
if [[ -n "${M28_SCREENSHOT_EVIDENCE_INTAKE}" && "${M28_SCREENSHOT_EVIDENCE_INTAKE_STATUS}" != "ready" ]]; then
  echo "  - ${M28_SCREENSHOT_EVIDENCE_INTAKE_NEXT_ACTION}"
fi
if [[ -n "${M29_OBSERVE_CANARY_RUN_PACKET}" && "${M29_OBSERVE_CANARY_RUN_PACKET_STATUS}" != "ready" ]]; then
  echo "  - ${M29_OBSERVE_CANARY_RUN_PACKET_NEXT_ACTION}"
fi
if [[ -n "${M30_OBSERVE_RESULT_INTAKE}" && "${M30_OBSERVE_RESULT_INTAKE_STATUS}" != "ready" ]]; then
  echo "  - ${M30_OBSERVE_RESULT_INTAKE_NEXT_ACTION}"
fi
if [[ "${required_input_evidence_ready}" == "1" ]]; then
  echo "  all required input evidence was provided or discovered by this wrapper"
fi

cd "${ROOT_DIR}"

readiness_args=(
  --signoff
  --root "${REPORT_ROOT}"
  --output-json "${OUTPUT_JSON}"
  --output-md "${OUTPUT_MD}"
)

if [[ "${REFRESH_SAFE_INPUTS}" == "0" ]]; then
  readiness_args+=(--no-refresh)
fi
if [[ "${REFRESH_LLM_CANARY}" == "1" ]]; then
  readiness_args+=(--refresh-llm-canary)
fi
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  readiness_args+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  readiness_args+=(--desktop-action-canary-summary "${DESKTOP_ACTION_CANARY_SUMMARY}")
fi
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  readiness_args+=(--llm-canary-summary "${LLM_CANARY_SUMMARY}")
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  printf 'Dry run: would execute: bash %q' "${RELEASE_READINESS_WRAPPER}"
  printf ' %q' "${readiness_args[@]}"
  printf '\n'
  exit 0
fi

set +e
bash "${RELEASE_READINESS_WRAPPER}" "${readiness_args[@]}"
readiness_exit=$?
set -e

if [[ -f "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${OUTPUT_JSON}" HANDOFF_MD="${HANDOFF_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


output_json = Path(os.environ["OUTPUT_JSON"])
handoff_md = Path(os.environ["HANDOFF_MD"])
summary = json.loads(output_json.read_text())
gates = summary.get("gates")
gates = gates if isinstance(gates, list) else []
blocked = [gate for gate in gates if isinstance(gate, dict) and not gate.get("ready")]
ready = [gate for gate in gates if isinstance(gate, dict) and gate.get("ready")]

lines = [
    "",
    "## Final Readiness Next Actions",
    "",
    f"- Readiness status: {summary.get('status', 'unknown')}",
    f"- Ready gates: {', '.join(str(gate.get('id')) for gate in ready) if ready else 'none'}",
    f"- Blocked gates: {', '.join(str(gate.get('id')) for gate in blocked) if blocked else 'none'}",
    "",
]
if blocked:
    for gate in blocked:
        gate_id = gate.get("id", "unknown")
        status = gate.get("status", "unknown")
        next_action = gate.get("nextAction", "Inspect the readiness report.")
        artifact = gate.get("artifactPath") or "not available"
        lines.append(f"- `{gate_id}` ({status}): {next_action} Artifact: `{artifact}`")
else:
    lines.append("- No blocked gates remain. MVP sign-off evidence is ready.")

with handoff_md.open("a") as handle:
    handle.write("\n".join(lines) + "\n")

print("\n".join(lines))
PY
else
  {
    echo
    echo "## Final Readiness Next Actions"
    echo
    echo "- Readiness report was not written. Inspect the release readiness command output."
  } >>"${HANDOFF_MD}"
fi

exit "${readiness_exit}"

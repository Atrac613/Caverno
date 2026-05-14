#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M30_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m30_observe_result_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_result_intake.json"
SUMMARY_MD="${RUN_DIR}/observe_result_intake.md"
M29_PACKET=""
M14_SUMMARY=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m30_observe_result_intake.sh [options]

Options:
  --root PATH                    Report root directory.
  --m29-packet PATH              M29 observe canary run packet JSON.
  --m14-summary PATH             User-produced M14 real-app observe summary JSON.
  --help                         Show this help.

This M30 intake is report-only. It reads a ready M29 run packet and the
user-produced M14 observe-only canary summary, validates that both artifacts
refer to the same observe cycle, and prepares the next M15 handoff command. It
does not call an LLM, grant TCC, open apps, capture screens, move the pointer,
click, type, submit, post, purchase, or perform desktop actions.
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
    --m29-packet)
      require_value "$@"
      M29_PACKET="$2"
      shift 2
      ;;
    --m14-summary)
      require_value "$@"
      M14_SUMMARY="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m30_observe_result_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_result_intake.json"
SUMMARY_MD="${RUN_DIR}/observe_result_intake.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M29_PACKET}" ]]; then
  M29_PACKET="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m29_observe_canary_run_packet_*/observe_canary_run_packet.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi
if [[ -z "${M14_SUMMARY}" ]]; then
  M14_SUMMARY="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_real_app_observe_canary_*/canary_summary.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M29_PACKET}" ]]; then
  echo "M29 observe canary run packet not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ -z "${M14_SUMMARY}" ]]; then
  echo "M14 real-app observe summary not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M29_PACKET}" ]]; then
  echo "M29 observe canary run packet not found: ${M29_PACKET}" >&2
  exit 66
fi
if [[ ! -f "${M14_SUMMARY}" ]]; then
  echo "M14 real-app observe summary not found: ${M14_SUMMARY}" >&2
  exit 66
fi

echo "Running macOS Computer Use M30 observe result intake"
echo "  Purpose: validate user-produced M14 observe evidence against the M29 run packet"
echo "  M29 packet: ${M29_PACKET}"
echo "  M14 summary: ${M14_SUMMARY}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
REPORT_ROOT="${REPORT_ROOT}" \
M29_PACKET="${M29_PACKET}" \
M14_SUMMARY="${M14_SUMMARY}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
report_root = os.environ["REPORT_ROOT"]
m29_packet_path = Path(os.environ["M29_PACKET"])
m14_summary_path = Path(os.environ["M14_SUMMARY"])


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def as_dict(value):
    return value if isinstance(value, dict) else {}


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


def text(value):
    return str(value or "").strip()


def cell(value):
    return ("-" if value is None else str(value)).replace("|", "\\|").replace("\n", "<br>")


m29 = read_json(m29_packet_path)
m14 = read_json(m14_summary_path)
m29_gate = as_dict(m29.get("m29ObserveCanaryRunPacketGate") if m29 else None)
m14_gate = as_dict(m14.get("m14EvidenceGate") if m14 else None)
m29_evidence = as_dict(m29.get("screenshotEvidence") if m29 else None)
m29_run_packet = as_dict(m29.get("m14ObserveRunPacket") if m29 else None)

m29_target_app = text((m29 or {}).get("targetApp") or m29_run_packet.get("targetApp"))
m14_target_app = text((m14 or {}).get("targetApp"))
m29_target_intent = text((m29 or {}).get("targetIntent") or m29_run_packet.get("targetIntent"))
m14_target_intent = text((m14 or {}).get("targetIntent"))
m29_screenshot = text(m29_evidence.get("path") or m29_run_packet.get("screenshotPath"))
m14_screenshot = text((m14 or {}).get("screenshotPath"))
candidate_targets = as_list((m14 or {}).get("candidateTargets"))
confirmation_requirements = as_list((m14 or {}).get("confirmationRequirements"))
public_targets = [
    target
    for target in candidate_targets
    if isinstance(target, dict)
    and str(target.get("risk", "")).lower() == "public_action"
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

m15_command = shell_join(
    [
        "bash",
        "tool/run_macos_computer_use_m15_action_proposal_handoff.sh",
        "--root",
        report_root,
        "--m14-summary",
        str(m14_summary_path),
    ]
)
artifact_index_command = shell_join(
    [
        "dart",
        "run",
        "tool/macos_computer_use_readiness_artifact_index.dart",
        "--root",
        report_root,
    ]
)
signoff_dry_run_command = shell_join(
    [
        "bash",
        "tool/run_macos_computer_use_mvp_signoff.sh",
        "--dry-run",
        "--root",
        report_root,
    ]
)

target_app_matches = bool(m29_target_app and m14_target_app and m29_target_app == m14_target_app)
target_intent_matches = bool(
    m29_target_intent and m14_target_intent and m29_target_intent == m14_target_intent
)
screenshot_matches = bool(m29_screenshot and m14_screenshot and m29_screenshot == m14_screenshot)

checks = [
    {
        "id": "m29_packet_schema_valid",
        "ok": bool(m29)
        and m29.get("schemaName") == "macos_computer_use_m29_observe_canary_run_packet"
        and m29.get("milestone") == "M29",
        "nextAction": "Select a valid M29 observe_canary_run_packet.json.",
    },
    {
        "id": "m29_packet_ready",
        "ok": bool(m29) and m29.get("ready") is True and m29_gate.get("status") == "ready",
        "nextAction": "Run M29 until m29ObserveCanaryRunPacketGate.status is ready.",
    },
    {
        "id": "m29_returns_to_m14",
        "ok": m29_run_packet.get("returnMilestone") == "M14",
        "nextAction": "Use an M29 packet whose M14 run packet returns to M14 evidence.",
    },
    {
        "id": "m29_observe_boundary",
        "ok": m29_run_packet.get("boundary") == "observe_only_no_desktop_action",
        "nextAction": "Keep the source run packet scoped to observe-only evidence.",
    },
    {
        "id": "m14_summary_schema_valid",
        "ok": bool(m14)
        and m14.get("schemaName") == "macos_computer_use_real_app_observe_canary_summary"
        and m14.get("milestone") == "M14",
        "nextAction": "Select a valid M14 real-app observe canary canary_summary.json.",
    },
    {
        "id": "m14_evidence_ready",
        "ok": bool(m14) and m14.get("ready") is True and m14_gate.get("status") == "ready",
        "nextAction": "Ask the user to rerun M14 until m14EvidenceGate.status is ready.",
    },
    {
        "id": "m14_observe_only",
        "ok": bool(m14)
        and m14.get("observationOnly") is True
        and m14.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "Use M14 observe-only evidence with no desktop actions.",
    },
    {
        "id": "m14_tcc_boundary",
        "ok": bool(m14) and m14.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "Keep TCC and System Settings outside M14 and M30.",
    },
    {
        "id": "target_app_matches",
        "ok": target_app_matches,
        "nextAction": "Use an M14 summary generated for the same target app as the M29 packet.",
    },
    {
        "id": "target_intent_matches",
        "ok": target_intent_matches,
        "nextAction": "Use an M14 summary generated for the same target intent as the M29 packet.",
    },
    {
        "id": "screenshot_path_matches",
        "ok": screenshot_matches,
        "nextAction": "Use the M14 summary generated from the screenshot recorded by M29.",
    },
    {
        "id": "candidate_targets_present",
        "ok": bool(candidate_targets),
        "nextAction": "M14 must classify visible candidate targets before M15 can propose actions.",
    },
    {
        "id": "text_targets_present",
        "ok": bool(text_targets),
        "nextAction": "M14 must identify at least one visible or intent-relevant text-entry target.",
    },
    {
        "id": "public_targets_classified",
        "ok": bool(public_targets),
        "nextAction": "M14 must classify public submit, post, send, or publish controls as public_action.",
    },
    {
        "id": "confirmation_requirements_present",
        "ok": bool(confirmation_requirements),
        "nextAction": "M14 must list confirmations required before future input or public actions.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": bool(m29)
        and m29.get("desktopActionBoundary") == "no_desktop_action"
        and bool(m14)
        and m14.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M30 can only intake reports; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": bool(m29)
        and m29.get("tccBoundary") == "no_tcc_operation"
        and bool(m14)
        and m14.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain user-operated and outside M30.",
    },
    {
        "id": "m30_llm_boundary_no_llm",
        "ok": True,
        "nextAction": "No action required.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Return to M15 action proposal handoff using the ready M14 observe evidence from this intake."
    if ready
    else "Resolve M30 observe result intake blockers before returning to M15."
)

summary = {
    "schemaName": "macos_computer_use_m30_observe_result_intake",
    "schemaVersion": 1,
    "purpose": "computer_use_m30_observe_result_intake",
    "milestone": "M30",
    "previousMilestone": "M29",
    "returnToMilestone": "M15",
    "ready": ready,
    "sourceM29ObserveCanaryRunPacket": str(m29_packet_path),
    "sourceM14ObserveCanarySummary": str(m14_summary_path),
    "executionBoundary": "m14_observe_result_intake_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "targetApp": m14_target_app or m29_target_app,
    "targetIntent": m14_target_intent or m29_target_intent,
    "screenshotPath": m14_screenshot or m29_screenshot,
    "sourceAlignment": {
        "targetAppMatches": target_app_matches,
        "targetIntentMatches": target_intent_matches,
        "screenshotPathMatches": screenshot_matches,
    },
    "m14ObserveEvidence": {
        "ready": bool(m14 and m14.get("ready") is True),
        "gateStatus": m14_gate.get("status"),
        "visionDecision": (m14 or {}).get("visionDecision") if m14 else None,
        "observedApp": (m14 or {}).get("observedApp") if m14 else None,
        "candidateTargetCount": len(candidate_targets),
        "textEntryTargetCount": len(text_targets),
        "publicActionTargetCount": len(public_targets),
        "confirmationRequirementCount": len(confirmation_requirements),
        "observationOnly": (m14 or {}).get("observationOnly") if m14 else None,
        "requiresUserApprovalBeforeAction": (m14 or {}).get("requiresUserApprovalBeforeAction")
        if m14
        else None,
    },
    "nextHandoff": {
        "returnMilestone": "M15",
        "command": m15_command,
        "requiresUserReview": True,
        "boundary": "approval_bound_action_proposal_report_only",
    },
    "commands": {
        "m15ActionProposalHandoff": m15_command,
        "artifactIndex": artifact_index_command,
        "mvpSignoffDryRun": signoff_dry_run_command,
    },
    "m30ObserveResultIntakeGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use M30 Observe Result Intake",
    "",
    "- Purpose: validate user-produced M14 observe evidence against the M29 run packet",
    "- Milestone: M30",
    "- Previous milestone: M29",
    "- Return milestone: M15",
    f"- M29 packet: `{m29_packet_path}`",
    f"- M14 summary: `{m14_summary_path}`",
    f"- Ready: {str(ready).lower()}",
    "- Execution boundary: m14_observe_result_intake_report_only",
    "- TCC boundary: no TCC operation",
    "- LLM boundary: no LLM call",
    "- Desktop action boundary: no desktop action",
    f"- Target app: {summary['targetApp'] or '-'}",
    f"- Target intent: {summary['targetIntent'] or '-'}",
    f"- Screenshot path: {summary['screenshotPath'] or '-'}",
    f"- M14 evidence gate: {m14_gate.get('status', 'unknown')}",
    f"- Candidate targets: {len(candidate_targets)}",
    f"- Text-entry targets: {len(text_targets)}",
    f"- Public-action targets: {len(public_targets)}",
    f"- Confirmation requirements: {len(confirmation_requirements)}",
    "",
    "## Gate",
    "",
    f"- Gate status: {summary['m30ObserveResultIntakeGate']['status']}",
    f"- Gate blockers: {', '.join(blockers) if blockers else 'none'}",
    f"- Gate next action: {gate_next_action}",
    "",
    "## Source Alignment",
    "",
    f"- Target app matches: {str(target_app_matches).lower()}",
    f"- Target intent matches: {str(target_intent_matches).lower()}",
    f"- Screenshot path matches: {str(screenshot_matches).lower()}",
    "",
    "## Checks",
    "",
    "| Check | Status | Next Action |",
    "| --- | --- | --- |",
]
for check in checks:
    lines.append(
        "| {id} | {status} | {nextAction} |".format(
            id=cell(check["id"]),
            status="passed" if check["ok"] else "blocked",
            nextAction=cell(check["nextAction"]),
        )
    )

lines.extend(
    [
        "",
        "## Next Handoff",
        "",
        f"```bash\n{m15_command}\n```",
    ]
)
summary_md.write_text("\n".join(lines) + "\n")

print(f"Gate status: {summary['m30ObserveResultIntakeGate']['status']}")
print(f"Gate blockers: {', '.join(blockers) if blockers else 'none'}")
print("Execution boundary: m14_observe_result_intake_report_only")
print("Desktop action boundary: no_desktop_action")
print("TCC boundary: no_tcc_operation")
print("LLM boundary: no_llm_call")
print(f"M14 evidence gate: {m14_gate.get('status', 'unknown')}")
print(f"Candidate targets: {len(candidate_targets)}")
print(f"Text-entry targets: {len(text_targets)}")
print(f"Public-action targets: {len(public_targets)}")
print(f"Confirmation requirements: {len(confirmation_requirements)}")
print(f"M15 action proposal command: {m15_command}")
print(f"Summary JSON: {summary_json}")
print(f"Summary Markdown: {summary_md}")

if not ready:
    raise SystemExit(1)
PY

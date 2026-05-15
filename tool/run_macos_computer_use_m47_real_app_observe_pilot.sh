#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M47_REAL_APP_OBSERVE_PILOT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m47_real_app_observe_pilot_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/real_app_observe_pilot.json"
SUMMARY_MD="${RUN_DIR}/real_app_observe_pilot.md"
M14_SUMMARY=""
TARGET_INTENT="${CAVERNO_MACOS_COMPUTER_USE_M47_TARGET_INTENT:-}"
APPROVED_EXACT_TEXT="${CAVERNO_MACOS_COMPUTER_USE_M47_APPROVED_EXACT_TEXT:-}"
APPROVED_TARGET_LABEL="${CAVERNO_MACOS_COMPUTER_USE_M47_APPROVED_TARGET_LABEL:-}"
APPROVED_PUBLIC_ACTION_LABEL="${CAVERNO_MACOS_COMPUTER_USE_M47_APPROVED_PUBLIC_ACTION_LABEL:-}"
GENERATED_ARTIFACTS_FILE=""

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m47_real_app_observe_pilot.sh [options]

Options:
  --root PATH                         Report root directory.
  --m14-summary PATH                  Ready M14 real-app observe canary summary JSON.
  --target-intent TEXT                Optional M15 target intent override.
  --approved-exact-text TEXT          Optional exact text approval for generated M16.
  --approved-target-label TEXT        Optional target label approval for generated M16.
  --approved-public-action-label TEXT Optional public action approval for generated M16.
  --help                              Show this help.

This M47 pilot is report-only. It reads ready M14 real-app observe evidence,
generates M15-M18 handoffs, and validates that element-aware target, text-entry,
public-action, and confirmation metadata stay stable. It does not call an LLM,
grant TCC, open apps, operate System Settings, move the pointer, click, type,
submit, post, purchase, or perform desktop actions.
USAGE
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m47_real_app_observe_pilot_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/real_app_observe_pilot.json"
SUMMARY_MD="${RUN_DIR}/real_app_observe_pilot.md"
mkdir -p "${RUN_DIR}"
GENERATED_ARTIFACTS_FILE="${RUN_DIR}/generated_artifacts.env"

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

echo "Running macOS Computer Use M47 real-app observe pilot"
echo "  Purpose: validate M14-M18 element-aware real-app observe handoffs"
echo "  M14 summary: ${M14_SUMMARY}"
echo "  Target intent: ${TARGET_INTENT:-from M14 summary}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

REPORT_ROOT="${REPORT_ROOT}" \
RUN_DIR="${RUN_DIR}" \
M14_SUMMARY="${M14_SUMMARY}" \
TARGET_INTENT="${TARGET_INTENT}" \
APPROVED_EXACT_TEXT="${APPROVED_EXACT_TEXT}" \
APPROVED_TARGET_LABEL="${APPROVED_TARGET_LABEL}" \
APPROVED_PUBLIC_ACTION_LABEL="${APPROVED_PUBLIC_ACTION_LABEL}" \
GENERATED_ARTIFACTS_FILE="${GENERATED_ARTIFACTS_FILE}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


report_root = Path(os.environ["REPORT_ROOT"])
run_dir = Path(os.environ["RUN_DIR"])
m14_summary_path = Path(os.environ["M14_SUMMARY"])
target_intent = os.environ.get("TARGET_INTENT", "").strip()
approved_exact_text = os.environ.get("APPROVED_EXACT_TEXT", "").strip()
approved_target_label = os.environ.get("APPROVED_TARGET_LABEL", "").strip()
approved_public_action_label = os.environ.get("APPROVED_PUBLIC_ACTION_LABEL", "").strip()
generated_artifacts_file = Path(os.environ["GENERATED_ARTIFACTS_FILE"])

m14 = json.loads(m14_summary_path.read_text())
candidate_targets = m14.get("candidateTargets")
candidate_targets = candidate_targets if isinstance(candidate_targets, list) else []
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
    if isinstance(target, dict) and str(target.get("risk", "")).lower() == "public_action"
]

def label_of(targets):
    for target in targets:
        label = str(target.get("label") or "").strip()
        if label:
            return label
    return ""

def quoted(value):
    return shlex.quote(str(value))

intent = target_intent or str(m14.get("targetIntent") or "")
exact_text = approved_exact_text or str(m14.get("exactText") or "").strip()
if not exact_text:
    exact_text = "Good morning from Caverno"
target_label = approved_target_label or label_of(text_targets)
public_action_label = approved_public_action_label or label_of(public_targets)

lines = [
    f"M14_SUMMARY={quoted(m14_summary_path)}",
    f"TARGET_INTENT={quoted(intent)}",
    f"APPROVED_EXACT_TEXT={quoted(exact_text)}",
    f"APPROVED_TARGET_LABEL={quoted(target_label)}",
    f"APPROVED_PUBLIC_ACTION_LABEL={quoted(public_action_label)}",
]
generated_artifacts_file.write_text("\n".join(lines) + "\n")
PY

# shellcheck source=/dev/null
source "${GENERATED_ARTIFACTS_FILE}"

bash "${ROOT_DIR}/tool/run_macos_computer_use_m15_action_proposal_handoff.sh" \
  --root "${REPORT_ROOT}" \
  --m14-summary "${M14_SUMMARY}" \
  --target-intent "${TARGET_INTENT}"
M15_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m15_action_proposal_handoff_*/action_proposal_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"

m16_args=(
  --root "${REPORT_ROOT}"
  --m15-handoff "${M15_HANDOFF}"
  --approved-exact-text "${APPROVED_EXACT_TEXT}"
  --approved-target-label "${APPROVED_TARGET_LABEL}"
)
if [[ -n "${APPROVED_PUBLIC_ACTION_LABEL}" ]]; then
  m16_args+=(--approved-public-action-label "${APPROVED_PUBLIC_ACTION_LABEL}")
fi
bash "${ROOT_DIR}/tool/run_macos_computer_use_m16_approval_packet.sh" "${m16_args[@]}"
M16_PACKET="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m16_approval_packet_*/approval_packet.json' -type f 2>/dev/null | sort | tail -n 1 || true)"

bash "${ROOT_DIR}/tool/run_macos_computer_use_m17_execution_rehearsal.sh" \
  --root "${REPORT_ROOT}" \
  --m16-packet "${M16_PACKET}"
M17_REHEARSAL="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m17_execution_rehearsal_*/execution_rehearsal.json' -type f 2>/dev/null | sort | tail -n 1 || true)"

bash "${ROOT_DIR}/tool/run_macos_computer_use_m18_execution_handoff.sh" \
  --root "${REPORT_ROOT}" \
  --m17-rehearsal "${M17_REHEARSAL}"
M18_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m18_execution_handoff_*/execution_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M14_SUMMARY="${M14_SUMMARY}" \
M15_HANDOFF="${M15_HANDOFF}" \
M16_PACKET="${M16_PACKET}" \
M17_REHEARSAL="${M17_REHEARSAL}" \
M18_HANDOFF="${M18_HANDOFF}" \
APPROVED_EXACT_TEXT="${APPROVED_EXACT_TEXT}" \
APPROVED_TARGET_LABEL="${APPROVED_TARGET_LABEL}" \
APPROVED_PUBLIC_ACTION_LABEL="${APPROVED_PUBLIC_ACTION_LABEL}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m14_summary_path = Path(os.environ["M14_SUMMARY"])
m15_handoff_path = Path(os.environ["M15_HANDOFF"])
m16_packet_path = Path(os.environ["M16_PACKET"])
m17_rehearsal_path = Path(os.environ["M17_REHEARSAL"])
m18_handoff_path = Path(os.environ["M18_HANDOFF"])
approved_exact_text = os.environ.get("APPROVED_EXACT_TEXT", "").strip()
approved_target_label = os.environ.get("APPROVED_TARGET_LABEL", "").strip()
approved_public_action_label = os.environ.get("APPROVED_PUBLIC_ACTION_LABEL", "").strip()

m14 = json.loads(m14_summary_path.read_text())
m15 = json.loads(m15_handoff_path.read_text())
m16 = json.loads(m16_packet_path.read_text())
m17 = json.loads(m17_rehearsal_path.read_text())
m18 = json.loads(m18_handoff_path.read_text())

def as_list(value):
    return value if isinstance(value, list) else []

def gate_status(document, key):
    gate = document.get(key)
    gate = gate if isinstance(gate, dict) else {}
    return gate.get("status"), gate.get("ready") is True, as_list(gate.get("blockers"))

def target_labels(targets):
    labels = []
    for target in as_list(targets):
        if not isinstance(target, dict):
            continue
        label = str(target.get("label") or "").strip()
        if label:
            labels.append(label)
    return labels

def stable_label(label, targets):
    if not label:
        return False
    return label in target_labels(targets)

m14_gate_status, m14_gate_ready, m14_blockers = gate_status(m14, "m14EvidenceGate")
m15_gate_status, m15_gate_ready, m15_blockers = gate_status(m15, "m15ActionProposalGate")
m16_gate_status, m16_gate_ready, m16_blockers = gate_status(m16, "m16ApprovalPacketGate")
m17_gate_status, m17_gate_ready, m17_blockers = gate_status(m17, "m17ExecutionRehearsalGate")
m18_gate_status, m18_gate_ready, m18_blockers = gate_status(m18, "m18ExecutionHandoffGate")

m14_candidate_targets = as_list(m14.get("candidateTargets"))
m15_text_targets = as_list(m15.get("textEntryTargets"))
m15_public_targets = as_list(m15.get("publicActionTargets"))
m16_text_targets = as_list(m16.get("textEntryTargets"))
m16_public_targets = as_list(m16.get("publicActionTargets"))
m17_values = m17.get("approvedValues") if isinstance(m17.get("approvedValues"), dict) else {}
m18_values = m18.get("approvedValues") if isinstance(m18.get("approvedValues"), dict) else {}
m18_confirmations = as_list(m18.get("actionTimeConfirmations"))

public_action_required = bool(m15_public_targets)
checks = [
    {
        "id": "m14_ready",
        "ok": bool(m14.get("ready")) and m14_gate_status == "ready",
        "nextAction": "Run M14 real-app observe canary until m14EvidenceGate.status is ready.",
    },
    {
        "id": "m15_ready",
        "ok": bool(m15.get("ready")) and m15_gate_status == "ready",
        "nextAction": "Regenerate M15 from ready M14 evidence.",
    },
    {
        "id": "m16_ready",
        "ok": bool(m16.get("ready")) and m16_gate_status == "ready",
        "nextAction": "Regenerate M16 from ready M15 evidence.",
    },
    {
        "id": "m17_ready",
        "ok": bool(m17.get("ready")) and m17_gate_status == "ready",
        "nextAction": "Regenerate M17 from approved M16 evidence.",
    },
    {
        "id": "m18_ready",
        "ok": bool(m18.get("ready")) and m18_gate_status == "ready",
        "nextAction": "Regenerate M18 from ready M17 evidence.",
    },
    {
        "id": "text_entry_target_stable",
        "ok": stable_label(approved_target_label, m14_candidate_targets)
        and stable_label(approved_target_label, m15_text_targets)
        and stable_label(approved_target_label, m16_text_targets)
        and m17_values.get("targetLabel") == approved_target_label
        and m18_values.get("targetLabel") == approved_target_label,
        "nextAction": "Keep the approved text-entry target label stable from M14 through M18.",
    },
    {
        "id": "exact_text_stable",
        "ok": bool(approved_exact_text)
        and m17_values.get("exactText") == approved_exact_text
        and m18_values.get("exactText") == approved_exact_text,
        "nextAction": "Preserve the approved exact text from M16 through M18.",
    },
    {
        "id": "public_action_boundary_stable",
        "ok": (not public_action_required)
        or (
            stable_label(approved_public_action_label, m14_candidate_targets)
            and stable_label(approved_public_action_label, m15_public_targets)
            and stable_label(approved_public_action_label, m16_public_targets)
            and m17_values.get("publicActionLabel") == approved_public_action_label
            and m18_values.get("publicActionLabel") == approved_public_action_label
            and m18.get("publicActionRequiresSeparateApproval") is True
        ),
        "nextAction": "Keep public-action labels and separate approval metadata stable through M18.",
    },
    {
        "id": "action_time_confirmations_present",
        "ok": all(
            confirmation_id in json.dumps(m18_confirmations)
            for confirmation_id in ["fresh_observation", "target_label", "exact_text"]
        )
        and (not public_action_required or "public_action_label" in json.dumps(m18_confirmations)),
        "nextAction": "M18 must list fresh observation, target, exact text, and public-action confirmations.",
    },
    {
        "id": "report_only_boundaries_preserved",
        "ok": m15.get("desktopActionBoundary") == "no_desktop_action"
        and m16.get("desktopActionBoundary") == "no_desktop_action"
        and m17.get("desktopActionBoundary") == "no_desktop_action"
        and m18.get("desktopActionBoundary") == "user_operated_only"
        and m18.get("llmBoundary") == "no_llm_call",
        "nextAction": "Keep M47 pilot generation report-only and user-operated at runtime boundaries.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
summary = {
    "schemaName": "macos_computer_use_m47_real_app_observe_pilot",
    "schemaVersion": 1,
    "purpose": "computer_use_m47_real_app_observe_pilot",
    "milestone": "M47",
    "previousMilestone": "M46",
    "ready": ready,
    "status": "ready" if ready else "blocked",
    "executionBoundary": "report_only_real_app_observe_pilot",
    "desktopActionBoundary": "no_desktop_action_until_m18_user_operated_handoff",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceArtifacts": {
        "m14Summary": str(m14_summary_path),
        "m15Handoff": str(m15_handoff_path),
        "m16Packet": str(m16_packet_path),
        "m17Rehearsal": str(m17_rehearsal_path),
        "m18Handoff": str(m18_handoff_path),
    },
    "approvedValues": {
        "exactText": approved_exact_text,
        "targetLabel": approved_target_label,
        "publicActionLabel": approved_public_action_label or None,
    },
    "stableMetadata": {
        "m14CandidateTargetLabels": target_labels(m14_candidate_targets),
        "m15TextEntryTargetLabels": target_labels(m15_text_targets),
        "m15PublicActionTargetLabels": target_labels(m15_public_targets),
        "m16TextEntryTargetLabels": target_labels(m16_text_targets),
        "m16PublicActionTargetLabels": target_labels(m16_public_targets),
        "m18ActionTimeConfirmationIds": [
            item.get("id") for item in m18_confirmations if isinstance(item, dict)
        ],
    },
    "milestoneStatuses": {
        "M14": {"status": m14_gate_status, "ready": m14_gate_ready, "blockers": m14_blockers},
        "M15": {"status": m15_gate_status, "ready": m15_gate_ready, "blockers": m15_blockers},
        "M16": {"status": m16_gate_status, "ready": m16_gate_ready, "blockers": m16_blockers},
        "M17": {"status": m17_gate_status, "ready": m17_gate_ready, "blockers": m17_blockers},
        "M18": {"status": m18_gate_status, "ready": m18_gate_ready, "blockers": m18_blockers},
    },
    "m47RealAppObservePilotGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": "M47 real-app observe pilot evidence is ready for M48 user-operated action pilot."
        if ready
        else "Resolve blocked M47 pilot checks before starting M48.",
    },
    "manualBoundary": [
        "M47 does not open apps, capture screens, grant TCC, or execute desktop actions.",
        "The user-provided screenshot must come from a manually prepared real app state.",
        "M18 remains a user-operated runtime handoff and does not execute actions.",
    ],
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use M47 Real-App Observe Pilot",
    "",
    f"- Ready: {str(ready).lower()}",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- M14 summary: `{m14_summary_path}`",
    f"- M15 handoff: `{m15_handoff_path}`",
    f"- M16 packet: `{m16_packet_path}`",
    f"- M17 rehearsal: `{m17_rehearsal_path}`",
    f"- M18 handoff: `{m18_handoff_path}`",
    "",
    "## Gate",
    "",
    "| Check | Status | Next Action |",
    "| --- | --- | --- |",
]
for check in checks:
    lines.append(
        "| {id} | {status} | {nextAction} |".format(
            id=check["id"],
            status="passed" if check["ok"] else "blocked",
            nextAction=check["nextAction"],
        )
    )
lines.extend(
    [
        "",
        "## Stable Metadata",
        "",
        f"- Approved exact text: {approved_exact_text or '-'}",
        f"- Approved target label: {approved_target_label or '-'}",
        f"- Approved public action label: {approved_public_action_label or '-'}",
        "- M18 action-time confirmations: "
        + ", ".join(summary["stableMetadata"]["m18ActionTimeConfirmationIds"]),
        "",
        "## Source Artifacts",
        "",
    ]
)
for key, value in summary["sourceArtifacts"].items():
    lines.append(f"- `{key}`: `{value}`")
summary_md.write_text("\n".join(lines) + "\n")

print(f"Ready: {str(ready).lower()}")
print(f"Blockers: {', '.join(blockers) if blockers else 'none'}")
print(f"Summary JSON: {summary_json}")
print(f"Summary Markdown: {summary_md}")
raise SystemExit(0 if ready else 1)
PY

echo "M47 real-app observe pilot summary written to ${SUMMARY_JSON}"

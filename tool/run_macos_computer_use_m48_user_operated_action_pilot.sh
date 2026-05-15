#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M48_USER_OPERATED_ACTION_PILOT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m48_user_operated_action_pilot_${RUN_ID}"
GENERATED_ROOT="${RUN_DIR}/generated"
SUMMARY_JSON="${RUN_DIR}/user_operated_action_pilot.json"
SUMMARY_MD="${RUN_DIR}/user_operated_action_pilot.md"
M47_PILOT=""
M18_HANDOFF=""
FRESH_OBSERVATION="${CAVERNO_MACOS_COMPUTER_USE_M48_FRESH_OBSERVATION:-missing}"
TARGET_CONFIRMED="${CAVERNO_MACOS_COMPUTER_USE_M48_TARGET_CONFIRMED:-no}"
EXACT_TEXT_CONFIRMED="${CAVERNO_MACOS_COMPUTER_USE_M48_EXACT_TEXT_CONFIRMED:-no}"
PUBLIC_ACTION_CONFIRMED="${CAVERNO_MACOS_COMPUTER_USE_M48_PUBLIC_ACTION_CONFIRMED:-not-applicable}"
RUNTIME_ACTION="${CAVERNO_MACOS_COMPUTER_USE_M48_RUNTIME_ACTION:-not-run}"
POST_ACTION_OBSERVATION="${CAVERNO_MACOS_COMPUTER_USE_M48_POST_ACTION_OBSERVATION:-missing}"
OPERATOR_NOTE="${CAVERNO_MACOS_COMPUTER_USE_M48_OPERATOR_NOTE:-}"
RESULT_REVIEWED="${CAVERNO_MACOS_COMPUTER_USE_M48_RESULT_REVIEWED:-no}"
POST_ACTION_STATE="${CAVERNO_MACOS_COMPUTER_USE_M48_POST_ACTION_STATE:-unknown}"
FOLLOW_UP_REQUIRED="${CAVERNO_MACOS_COMPUTER_USE_M48_FOLLOW_UP_REQUIRED:-no}"
FOLLOW_UP_NOTE="${CAVERNO_MACOS_COMPUTER_USE_M48_FOLLOW_UP_NOTE:-}"
OUTCOME_ACCEPTED="${CAVERNO_MACOS_COMPUTER_USE_M48_OUTCOME_ACCEPTED:-no}"
NEXT_OBSERVE_NEEDED="${CAVERNO_MACOS_COMPUTER_USE_M48_NEXT_OBSERVE_NEEDED:-unknown}"
NEXT_OBSERVE_NOTE="${CAVERNO_MACOS_COMPUTER_USE_M48_NEXT_OBSERVE_NOTE:-}"
SAFE_TARGET_CONFIRMED="${CAVERNO_MACOS_COMPUTER_USE_M48_SAFE_TARGET_CONFIRMED:-no}"
RESOLVED_INPUTS_FILE=""

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m48_user_operated_action_pilot.sh [options]

Options:
  --root PATH                       Report root directory.
  --m47-pilot PATH                  Ready M47 real-app observe pilot JSON.
  --m18-handoff PATH                Optional M18 execution handoff override.
  --fresh-observation VALUE         done or missing.
  --target-confirmed VALUE          yes, no, or not-required.
  --exact-text-confirmed VALUE      yes, no, or not-required.
  --public-action-confirmed VALUE   yes, no, or not-applicable.
  --runtime-action VALUE            succeeded, failed, aborted, or not-run.
  --post-action-observation VALUE   done or missing.
  --operator-note TEXT              Optional user-provided result note.
  --result-reviewed VALUE           yes or no.
  --post-action-state VALUE         stable, needs-follow-up, or unknown.
  --follow-up-required VALUE        yes or no.
  --follow-up-note TEXT             Optional user-provided follow-up note.
  --outcome-accepted VALUE          yes or no.
  --next-observe-needed VALUE       yes, no, or unknown.
  --next-observe-note TEXT          Optional next observe note.
  --safe-target-confirmed VALUE     yes or no.
  --help                            Show this help.

This M48 pilot is report-only. It reads ready M47 pilot evidence, records a
user-operated action result through M20, M22, and M23, and validates that one
safe real-app action cycle has observe, approval, action, post-action observe,
result intake, review, and cycle outcome evidence. It does not call an LLM,
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
    --m47-pilot)
      require_value "$@"
      M47_PILOT="$2"
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
    --safe-target-confirmed)
      require_value "$@"
      SAFE_TARGET_CONFIRMED="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m48_user_operated_action_pilot_${RUN_ID}"
GENERATED_ROOT="${RUN_DIR}/generated"
SUMMARY_JSON="${RUN_DIR}/user_operated_action_pilot.json"
SUMMARY_MD="${RUN_DIR}/user_operated_action_pilot.md"
mkdir -p "${RUN_DIR}" "${GENERATED_ROOT}"
RESOLVED_INPUTS_FILE="${RUN_DIR}/resolved_inputs.env"

if [[ -z "${M47_PILOT}" ]]; then
  M47_PILOT="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m47_real_app_observe_pilot_*/real_app_observe_pilot.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M47_PILOT}" ]]; then
  echo "M47 real-app observe pilot not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M47_PILOT}" ]]; then
  echo "M47 real-app observe pilot not found: ${M47_PILOT}" >&2
  exit 66
fi

REPORT_ROOT="${REPORT_ROOT}" \
M47_PILOT="${M47_PILOT}" \
M18_HANDOFF="${M18_HANDOFF}" \
RESOLVED_INPUTS_FILE="${RESOLVED_INPUTS_FILE}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


m47_pilot_path = Path(os.environ["M47_PILOT"])
m18_handoff = os.environ.get("M18_HANDOFF", "").strip()
resolved_inputs_file = Path(os.environ["RESOLVED_INPUTS_FILE"])

m47 = json.loads(m47_pilot_path.read_text())
source_artifacts = m47.get("sourceArtifacts")
source_artifacts = source_artifacts if isinstance(source_artifacts, dict) else {}
resolved_m18 = m18_handoff or str(source_artifacts.get("m18Handoff") or "").strip()

if not resolved_m18:
    raise SystemExit("M47 pilot does not include sourceArtifacts.m18Handoff.")
if not Path(resolved_m18).is_file():
    raise SystemExit(f"M18 handoff not found: {resolved_m18}")

resolved_inputs_file.write_text(
    "M18_HANDOFF={}\n".format(shlex.quote(resolved_m18))
)
PY

source "${RESOLVED_INPUTS_FILE}"

echo "Running macOS Computer Use M48 user-operated action pilot"
echo "  Purpose: validate one safe real-app user-operated action cycle"
echo "  M47 pilot: ${M47_PILOT}"
echo "  M18 handoff: ${M18_HANDOFF}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

M20_ARGS=(
  --root "${GENERATED_ROOT}"
  --m18-handoff "${M18_HANDOFF}"
  --fresh-observation "${FRESH_OBSERVATION}"
  --target-confirmed "${TARGET_CONFIRMED}"
  --exact-text-confirmed "${EXACT_TEXT_CONFIRMED}"
  --public-action-confirmed "${PUBLIC_ACTION_CONFIRMED}"
  --runtime-action "${RUNTIME_ACTION}"
  --post-action-observation "${POST_ACTION_OBSERVATION}"
)
if [[ -n "${OPERATOR_NOTE}" ]]; then
  M20_ARGS+=(--operator-note "${OPERATOR_NOTE}")
fi
bash "${ROOT_DIR}/tool/run_macos_computer_use_m20_execution_result_intake.sh" "${M20_ARGS[@]}"

M20_INTAKE="$(find "${GENERATED_ROOT}" -path '*/macos_computer_use_m20_execution_result_intake_*/execution_result_intake.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
if [[ -z "${M20_INTAKE}" || ! -f "${M20_INTAKE}" ]]; then
  echo "Generated M20 execution result intake not found under ${GENERATED_ROOT}." >&2
  exit 66
fi

M22_ARGS=(
  --root "${GENERATED_ROOT}"
  --m20-intake "${M20_INTAKE}"
  --result-reviewed "${RESULT_REVIEWED}"
  --post-action-state "${POST_ACTION_STATE}"
  --follow-up-required "${FOLLOW_UP_REQUIRED}"
)
if [[ -n "${FOLLOW_UP_NOTE}" ]]; then
  M22_ARGS+=(--follow-up-note "${FOLLOW_UP_NOTE}")
fi
bash "${ROOT_DIR}/tool/run_macos_computer_use_m22_post_action_review.sh" "${M22_ARGS[@]}"

M22_REVIEW="$(find "${GENERATED_ROOT}" -path '*/macos_computer_use_m22_post_action_review_*/post_action_review.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
if [[ -z "${M22_REVIEW}" || ! -f "${M22_REVIEW}" ]]; then
  echo "Generated M22 post-action review not found under ${GENERATED_ROOT}." >&2
  exit 66
fi

M23_ARGS=(
  --root "${GENERATED_ROOT}"
  --m22-review "${M22_REVIEW}"
  --outcome-accepted "${OUTCOME_ACCEPTED}"
  --next-observe-needed "${NEXT_OBSERVE_NEEDED}"
)
if [[ -n "${NEXT_OBSERVE_NOTE}" ]]; then
  M23_ARGS+=(--next-observe-note "${NEXT_OBSERVE_NOTE}")
fi
bash "${ROOT_DIR}/tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh" "${M23_ARGS[@]}"

M23_HANDOFF="$(find "${GENERATED_ROOT}" -path '*/macos_computer_use_m23_cycle_outcome_handoff_*/cycle_outcome_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
if [[ -z "${M23_HANDOFF}" || ! -f "${M23_HANDOFF}" ]]; then
  echo "Generated M23 cycle outcome handoff not found under ${GENERATED_ROOT}." >&2
  exit 66
fi

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M47_PILOT="${M47_PILOT}" \
M18_HANDOFF="${M18_HANDOFF}" \
M20_INTAKE="${M20_INTAKE}" \
M22_REVIEW="${M22_REVIEW}" \
M23_HANDOFF="${M23_HANDOFF}" \
SAFE_TARGET_CONFIRMED="${SAFE_TARGET_CONFIRMED}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m47_pilot_path = Path(os.environ["M47_PILOT"])
m18_handoff_path = Path(os.environ["M18_HANDOFF"])
m20_intake_path = Path(os.environ["M20_INTAKE"])
m22_review_path = Path(os.environ["M22_REVIEW"])
m23_handoff_path = Path(os.environ["M23_HANDOFF"])
safe_target_confirmed = os.environ["SAFE_TARGET_CONFIRMED"].strip().lower()

m47 = json.loads(m47_pilot_path.read_text())
m18 = json.loads(m18_handoff_path.read_text())
m20 = json.loads(m20_intake_path.read_text())
m22 = json.loads(m22_review_path.read_text())
m23 = json.loads(m23_handoff_path.read_text())

source_artifacts = m47.get("sourceArtifacts")
source_artifacts = source_artifacts if isinstance(source_artifacts, dict) else {}
m47_gate = m47.get("m47RealAppObservePilotGate")
m47_gate = m47_gate if isinstance(m47_gate, dict) else {}
m20_gate = m20.get("m20ExecutionResultIntakeGate")
m20_gate = m20_gate if isinstance(m20_gate, dict) else {}
m22_gate = m22.get("m22PostActionReviewGate")
m22_gate = m22_gate if isinstance(m22_gate, dict) else {}
m23_gate = m23.get("m23CycleOutcomeHandoffGate")
m23_gate = m23_gate if isinstance(m23_gate, dict) else {}

m47_values = m47.get("approvedValues")
m47_values = m47_values if isinstance(m47_values, dict) else {}
m20_values = m20.get("approvedValues")
m20_values = m20_values if isinstance(m20_values, dict) else {}
m22_values = m22.get("approvedValues")
m22_values = m22_values if isinstance(m22_values, dict) else {}
m23_values = m23.get("approvedValues")
m23_values = m23_values if isinstance(m23_values, dict) else {}
m20_manual_inputs = m20.get("manualInputs")
m20_manual_inputs = m20_manual_inputs if isinstance(m20_manual_inputs, dict) else {}
m22_review_inputs = m22.get("reviewInputs")
m22_review_inputs = m22_review_inputs if isinstance(m22_review_inputs, dict) else {}
m23_handoff_inputs = m23.get("handoffInputs")
m23_handoff_inputs = m23_handoff_inputs if isinstance(m23_handoff_inputs, dict) else {}

source_m14_path = str(source_artifacts.get("m14Summary") or "")
m14 = {}
if source_m14_path and Path(source_m14_path).is_file():
    m14 = json.loads(Path(source_m14_path).read_text())
candidate_targets = m14.get("candidateTargets")
candidate_targets = candidate_targets if isinstance(candidate_targets, list) else []
high_risk_values = {"secure_field", "credential", "payment", "destructive"}
high_risk_targets = [
    target
    for target in candidate_targets
    if isinstance(target, dict)
    and str(target.get("risk") or "").strip().lower() in high_risk_values
]

public_action_label = m47_values.get("publicActionLabel")
public_action_required = bool(public_action_label)

def same_value(key):
    expected = m47_values.get(key)
    return (
        m20_values.get(key) == expected
        and m22_values.get(key) == expected
        and m23_values.get(key) == expected
    )

checks = [
    {
        "id": "m47_pilot_schema_valid",
        "ok": m47.get("schemaName") == "macos_computer_use_m47_real_app_observe_pilot"
        and m47.get("milestone") == "M47",
        "nextAction": "Select a valid M47 real_app_observe_pilot.json before running M48.",
    },
    {
        "id": "m47_pilot_ready",
        "ok": bool(m47.get("ready")) and m47_gate.get("status") == "ready",
        "nextAction": "Run the M47 real-app observe pilot until m47RealAppObservePilotGate.status is ready.",
    },
    {
        "id": "m18_handoff_matches_m47",
        "ok": str(source_artifacts.get("m18Handoff") or "") == str(m18_handoff_path),
        "nextAction": "Use the M18 handoff produced by the selected M47 pilot.",
    },
    {
        "id": "m18_user_operated_handoff_ready",
        "ok": m18.get("schemaName") == "macos_computer_use_m18_execution_handoff"
        and bool(m18.get("ready"))
        and m18.get("desktopActionBoundary") == "user_operated_only",
        "nextAction": "Start from a ready M18 user-operated execution handoff.",
    },
    {
        "id": "m20_result_intake_ready",
        "ok": m20.get("schemaName") == "macos_computer_use_m20_execution_result_intake"
        and bool(m20.get("ready"))
        and m20_gate.get("status") == "ready",
        "nextAction": "Record ready M20 execution result intake evidence.",
    },
    {
        "id": "m22_post_action_review_ready",
        "ok": m22.get("schemaName") == "macos_computer_use_m22_post_action_review"
        and bool(m22.get("ready"))
        and m22_gate.get("status") == "ready",
        "nextAction": "Review the M20 result with ready M22 post-action review evidence.",
    },
    {
        "id": "m23_cycle_outcome_ready",
        "ok": m23.get("schemaName") == "macos_computer_use_m23_cycle_outcome_handoff"
        and bool(m23.get("ready"))
        and m23_gate.get("status") == "ready",
        "nextAction": "Accept the M22 review and write ready M23 cycle outcome evidence.",
    },
    {
        "id": "safe_target_confirmed",
        "ok": safe_target_confirmed == "yes" and not high_risk_targets,
        "nextAction": "Use a safe target with no secure, credential, payment, or destructive risk and confirm it explicitly.",
    },
    {
        "id": "approval_metadata_preserved",
        "ok": same_value("targetLabel")
        and same_value("exactText")
        and same_value("publicActionLabel"),
        "nextAction": "Keep approved target, exact text, and public-action labels stable through M20-M23.",
    },
    {
        "id": "public_action_separate_approval_preserved",
        "ok": (not public_action_required)
        or (
            m18.get("publicActionRequiresSeparateApproval") is True
            and m20_manual_inputs.get("publicActionConfirmed") == "yes"
        ),
        "nextAction": "Preserve separate public-action approval through the user-operated result intake.",
    },
    {
        "id": "user_operated_action_evidence_recorded",
        "ok": m20_manual_inputs.get("freshObservation") == "done"
        and m20_manual_inputs.get("runtimeAction") == "succeeded"
        and m20_manual_inputs.get("postActionObservation") == "done",
        "nextAction": "Record fresh observation, succeeded user action, and post-action observation in M20.",
    },
    {
        "id": "post_action_review_closed",
        "ok": m22_review_inputs.get("resultReviewed") == "yes"
        and m22_review_inputs.get("postActionState") == "stable"
        and m22_review_inputs.get("followUpRequired") == "no",
        "nextAction": "Close only a reviewed, stable post-action state for the M48 pilot.",
    },
    {
        "id": "cycle_outcome_closed",
        "ok": m23.get("cycleOutcome") == "closed"
        and m23_handoff_inputs.get("outcomeAccepted") == "yes"
        and m23_handoff_inputs.get("nextObserveNeeded") == "no",
        "nextAction": "Accept the reviewed outcome and close the action cycle without a new observe pass.",
    },
    {
        "id": "report_only_boundaries_preserved",
        "ok": m47.get("llmBoundary") == "no_llm_call"
        and m20.get("llmBoundary") == "no_llm_call"
        and m22.get("llmBoundary") == "no_llm_call"
        and m23.get("llmBoundary") == "no_llm_call"
        and m47.get("tccBoundary") == "no_tcc_operation"
        and m20.get("tccBoundary") == "no_tcc_operation"
        and m22.get("tccBoundary") == "no_tcc_operation"
        and m23.get("tccBoundary") == "no_tcc_operation"
        and m20.get("desktopActionBoundary") == "user_operated_evidence_only"
        and m22.get("desktopActionBoundary") == "no_desktop_action"
        and m23.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "Keep M48 generation report-only and record only user-operated runtime evidence.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
summary = {
    "schemaName": "macos_computer_use_m48_user_operated_action_pilot",
    "schemaVersion": 1,
    "purpose": "computer_use_m48_user_operated_action_pilot",
    "milestone": "M48",
    "previousMilestone": "M47",
    "ready": ready,
    "status": "ready" if ready else "blocked",
    "executionBoundary": "report_only_user_operated_action_pilot",
    "desktopActionBoundary": "user_operated_evidence_only",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceArtifacts": {
        "m14Summary": source_artifacts.get("m14Summary"),
        "m15Handoff": source_artifacts.get("m15Handoff"),
        "m16Packet": source_artifacts.get("m16Packet"),
        "m17Rehearsal": source_artifacts.get("m17Rehearsal"),
        "m18Handoff": str(m18_handoff_path),
        "m20Intake": str(m20_intake_path),
        "m22Review": str(m22_review_path),
        "m23CycleOutcome": str(m23_handoff_path),
        "m47Pilot": str(m47_pilot_path),
    },
    "approvedValues": {
        "exactText": m47_values.get("exactText"),
        "targetLabel": m47_values.get("targetLabel"),
        "publicActionLabel": public_action_label,
    },
    "userOperatedEvidence": {
        "freshObservation": m20_manual_inputs.get("freshObservation"),
        "targetConfirmed": m20_manual_inputs.get("targetConfirmed"),
        "exactTextConfirmed": m20_manual_inputs.get("exactTextConfirmed"),
        "publicActionConfirmed": m20_manual_inputs.get("publicActionConfirmed"),
        "runtimeAction": m20_manual_inputs.get("runtimeAction"),
        "postActionObservation": m20_manual_inputs.get("postActionObservation"),
        "resultReviewed": m22_review_inputs.get("resultReviewed"),
        "postActionState": m22_review_inputs.get("postActionState"),
        "followUpRequired": m22_review_inputs.get("followUpRequired"),
        "outcomeAccepted": m23_handoff_inputs.get("outcomeAccepted"),
        "nextObserveNeeded": m23_handoff_inputs.get("nextObserveNeeded"),
        "cycleOutcome": m23.get("cycleOutcome"),
        "safeTargetConfirmed": safe_target_confirmed,
    },
    "safetySummary": {
        "highRiskTargetCount": len(high_risk_targets),
        "highRiskTargetRisks": sorted(
            {
                str(target.get("risk") or "").strip().lower()
                for target in high_risk_targets
            }
        ),
        "publicActionRequiresSeparateApproval": public_action_required,
        "publicActionLabel": public_action_label,
    },
    "milestoneStatuses": {
        "M47": {"status": m47_gate.get("status"), "ready": bool(m47.get("ready"))},
        "M18": {"ready": bool(m18.get("ready"))},
        "M20": {"status": m20_gate.get("status"), "ready": bool(m20.get("ready"))},
        "M22": {"status": m22_gate.get("status"), "ready": bool(m22.get("ready"))},
        "M23": {"status": m23_gate.get("status"), "ready": bool(m23.get("ready"))},
    },
    "m48UserOperatedActionPilotGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": "M48 user-operated action pilot evidence is ready for M49 privacy and audit release pack."
        if ready
        else "Resolve blocked M48 pilot checks before starting M49.",
    },
    "manualBoundary": [
        "M48 only records evidence from a separately user-operated runtime action.",
        "M48 does not open apps, capture screens, grant TCC, or execute desktop actions.",
        "Any follow-up desktop action must start a new observe and approval cycle.",
    ],
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

def cell(value):
    return str(value).replace("|", "\\|") if value is not None else "-"

lines = [
    "# macOS Computer Use M48 User-Operated Action Pilot",
    "",
    f"- Ready: {str(ready).lower()}",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- M47 pilot: `{m47_pilot_path}`",
    f"- M18 handoff: `{m18_handoff_path}`",
    f"- M20 intake: `{m20_intake_path}`",
    f"- M22 review: `{m22_review_path}`",
    f"- M23 cycle outcome: `{m23_handoff_path}`",
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
            nextAction=cell(check["nextAction"]),
        )
    )

lines.extend(
    [
        "",
        "## User-Operated Evidence",
        "",
        "| Field | Value |",
        "| --- | --- |",
    ]
)
for key, value in summary["userOperatedEvidence"].items():
    lines.append(f"| {cell(key)} | {cell(value)} |")

lines.extend(
    [
        "",
        "## Approved Values",
        "",
        f"- Target label: {cell(m47_values.get('targetLabel'))}",
        f"- Exact text: {cell(m47_values.get('exactText'))}",
        f"- Public action label: {cell(public_action_label)}",
        "",
        "## Manual Boundary",
        "",
        "This pilot records the result of a separately user-operated action.",
        "It does not execute or automate the desktop action itself.",
        "",
    ]
)

summary_md.write_text("\n".join(lines) + "\n")

print(f"M48 user-operated action pilot written to {summary_json}")
print(f"M48 user-operated action pilot Markdown written to {summary_md}")
print(f"Gate status: {summary['m48UserOperatedActionPilotGate']['status']}")
print(f"Ready: {str(ready).lower()}")
print("Blockers: " + (", ".join(blockers) if blockers else "none"))

raise SystemExit(0 if ready else 1)
PY

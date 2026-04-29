#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_REPEAT_COUNT:-1}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_desktop_action_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value."
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repeat)
      require_value "$@"
      REPEAT_COUNT="$2"
      shift 2
      ;;
    --report-root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --device)
      require_value "$@"
      DEVICE="$2"
      shift 2
      ;;
    --reporter)
      require_value "$@"
      REPORTER="$2"
      shift 2
      ;;
    --help)
      cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_desktop_action_canary.sh [options]

Options:
  --repeat COUNT       Run the canary multiple times.
  --report-root PATH   Report root directory.
  --device DEVICE      Flutter device id.
  --reporter REPORTER  Flutter test reporter.

This canary is user-operated. It requires the user to grant TCC permissions and
to prepare a safe click target before running.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_desktop_action_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use desktop action canary"
echo "  Purpose: observe the screen, click once, and observe again"
echo "  TCC boundary: user-operated manual verification only"
echo "  Safety: prepare a safe click target before running"
echo "  Safe target: use a visible, harmless target such as an empty text field or test window"
echo "  Avoid: destructive buttons, purchase flows, send buttons, system controls, and private data"
echo "  Success phases: pre_observe_image, click_sent, post_observe_image"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report dir: ${RUN_DIR}"

status=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_name="$(printf "run_%02d" "${index}")"
  run_report="${RUN_DIR}/${run_name}.json"
  run_log="${RUN_DIR}/${run_name}.log"
  echo "Running ${run_name}/${REPEAT_COUNT}"
  set +e
  CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${run_report}" \
    bash "${ROOT_DIR}/tool/run_macos_computer_use_smoke_test.sh" \
      --desktop-action-canary \
      --device "${DEVICE}" \
      --reporter "${REPORTER}" \
      >"${run_log}" 2>&1
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    status=1
  fi
done

RUN_DIR="${RUN_DIR}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
runs = []


def classify_failure(gate, blockers):
    if not gate:
        return "desktop_action_gate_missing"

    blocker_classes = {
        "initial_vision_observe_failed": "target_not_visible",
        "initial_vision_image_missing": "target_not_visible",
        "armed_click_failed_or_skipped": "click_not_sent",
        "post_click_vision_observe_failed": "post_observe_unavailable",
        "post_click_vision_image_missing": "post_observe_unavailable",
        "post_click_observation_unchanged": "post_observe_unchanged",
    }
    for blocker in blocker_classes:
        if blocker in blockers:
            return blocker_classes[blocker]
    if gate.get("postClickChanged") is False:
        return "post_observe_unchanged"
    return "desktop_action_canary_blocked"


def phase_status(gate):
    if not gate:
        return {
            "preObserve": "missing",
            "click": "missing",
            "postObserve": "missing",
            "changedEvidence": "not_measured",
        }
    blockers = gate.get("blockers")
    blockers = blockers if isinstance(blockers, list) else []
    pre_observe_ready = (
        gate.get("initialObservationImageAttached") is True
        and "initial_vision_observe_failed" not in blockers
    )
    click_sent = gate.get("clickPassed") is True
    post_observe_ready = (
        gate.get("postClickObservationImageAttached") is True
        and "post_click_vision_observe_failed" not in blockers
    )
    changed = gate.get("postClickChanged")
    return {
        "preObserve": "ready" if pre_observe_ready else "blocked",
        "click": "sent" if click_sent else "blocked",
        "postObserve": "ready" if post_observe_ready else "blocked",
        "changedEvidence": (
            "changed"
            if changed is True
            else "unchanged"
            if changed is False
            else "not_measured"
        ),
    }


for report_path in sorted(run_dir.glob("run_*.json")):
    name = report_path.stem
    log_path = report_path.with_suffix(".log")
    try:
        report = json.loads(report_path.read_text())
    except Exception as error:
        runs.append({
            "name": name,
            "status": "failed",
            "failureClass": "report_unreadable",
            "error": str(error),
            "report": str(report_path),
            "log": str(log_path),
        })
        continue

    raw_gate = report.get("desktopActionCanaryGate")
    gate = raw_gate if isinstance(raw_gate, dict) else {}
    blockers = gate.get("blockers")
    blockers = blockers if isinstance(blockers, list) else []
    passed = report.get("ok") is True and gate.get("status") == "ready"
    failure_class = "passed" if passed else classify_failure(gate, blockers)
    runs.append({
        "name": name,
        "status": "passed" if passed else "failed",
        "failureClass": failure_class,
        "gateStatus": gate.get("status", "missing"),
        "phaseStatus": phase_status(gate),
        "blockers": blockers,
        "report": str(report_path),
        "log": str(log_path),
    })

passed_count = sum(1 for run in runs if run["status"] == "passed")
failed_count = len(runs) - passed_count
failure_classes = {}
for run in runs:
    failure_class = run["failureClass"]
    failure_classes[failure_class] = failure_classes.get(failure_class, 0) + 1
summary = {
    "schemaName": "macos_computer_use_desktop_action_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_desktop_action_canary",
    "tccBoundary": "manual_user_operated",
    "safeTargetGuidance": [
        "Use a visible, harmless target such as an empty text field or test window.",
        "Avoid destructive buttons, purchase flows, send buttons, system controls, and private data.",
        "Keep the pointer target stable until the post-click observation completes.",
    ],
    "expectedPhases": [
        "pre_observe_image",
        "click_sent",
        "post_observe_image",
    ],
    "failureClassGuidance": {
        "target_not_visible": "Initial observation failed or did not include an image.",
        "click_not_sent": "The armed click did not run.",
        "post_observe_unavailable": "Post-click observation failed or did not include an image.",
        "post_observe_unchanged": "Post-click observation was available but did not show a measured change.",
    },
    "stable": failed_count == 0,
    "runCount": len(runs),
    "passed": passed_count,
    "failed": failed_count,
    "passRate": 0 if not runs else passed_count / len(runs),
    "failureClasses": failure_classes,
    "runs": runs,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use Desktop Action Canary Summary",
    "",
    "- Purpose: observe the screen, click once, and observe again",
    "- TCC boundary: user-operated manual verification only",
    "- Safety: user prepares a safe click target before running",
    "- Safe target: visible harmless target, such as an empty text field or test window",
    "- Avoid: destructive buttons, purchase flows, send buttons, system controls, and private data",
    "- Success phases: pre_observe_image, click_sent, post_observe_image",
    f"- Stable: {str(summary['stable']).lower()}",
    f"- Run count: {len(runs)}",
    f"- Passed: {passed_count}",
    f"- Failed: {failed_count}",
    f"- Pass rate: {summary['passRate'] * 100:.1f}%",
    "",
    "| Run | Status | Failure Class | Phases | Gate | Blockers | Artifacts |",
    "| --- | --- | --- | --- | --- | --- | --- |",
]
for run in runs:
    blockers = ", ".join(str(item) for item in run.get("blockers") or []) or "-"
    phases = run.get("phaseStatus") or {}
    phase_text = "<br>".join(f"{key}: `{value}`" for key, value in phases.items()) or "-"
    artifacts = f"report: `{run['report']}`<br>log: `{run['log']}`"
    lines.append(
        "| {name} | {status} | {failureClass} | {phases} | {gateStatus} | {blockers} | {artifacts} |".format(
            name=run["name"],
            status=run["status"],
            failureClass=run["failureClass"],
            phases=phase_text,
            gateStatus=run.get("gateStatus", "-"),
            blockers=blockers,
            artifacts=artifacts,
        )
    )
summary_md.write_text("\n".join(lines) + "\n")

print(summary_md.read_text())
PY

echo "Desktop action canary summary written to ${SUMMARY_JSON}"
exit "${status}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_REPEAT_COUNT:-1}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
LEGACY_INTEGRATION="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_LEGACY_INTEGRATION:-0}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_desktop_action_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"
FIXTURE_TARGET=0
FIXTURE_APP_PATH="${CAVERNO_MACOS_COMPUTER_USE_MVP_FIXTURE_APP_PATH:-}"
LAUNCH_FIXTURE=0
RESTORE_DEBUG_APP="${CAVERNO_MACOS_COMPUTER_USE_RESTORE_DEBUG_APP_AFTER_CANARY:-0}"
LAUNCH_CAVERNO_APP="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_LAUNCH_CAVERNO:-0}"

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
    --fixture-target|--mvp-fixture)
      FIXTURE_TARGET=1
      shift
      ;;
    --launch-fixture)
      FIXTURE_TARGET=1
      LAUNCH_FIXTURE=1
      shift
      ;;
    --fixture-app-path)
      require_value "$@"
      FIXTURE_APP_PATH="$2"
      shift 2
      ;;
    --skip-restore-debug-app)
      RESTORE_DEBUG_APP=0
      shift
      ;;
    --launch-caverno)
      LAUNCH_CAVERNO_APP=1
      shift
      ;;
    --legacy-integration)
      LEGACY_INTEGRATION=1
      shift
      ;;
    --help)
      cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_desktop_action_canary.sh [options]

Options:
  --repeat COUNT       Run the canary multiple times.
  --report-root PATH   Report root directory.
  --device DEVICE      Flutter device id.
  --reporter REPORTER  Flutter test reporter.
  --fixture-target     Mark the MVP fixture app as the intended safe target.
  --launch-fixture     Build and launch the MVP fixture before the user-operated canary.
  --fixture-app-path PATH
                       Record an already built MVP fixture app path.
  --skip-restore-debug-app
                       Do not rebuild the normal Debug Caverno.app after the canary.
  --launch-caverno     Also launch Caverno.app from this script. By default the
                       no-build probe requires Caverno.app to be already running
                       so the script does not trigger main-app TCC prompts.
  --legacy-integration
                       Run the old Flutter integration-test canary path.

This canary is user-operated. It requires the user to grant TCC permissions and
to prepare a safe click target before running. The default path does not rebuild
or auto-launch Caverno.app, so it does not invalidate or trigger main-app TCC
permissions.
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

if [[ "${LAUNCH_FIXTURE}" == "1" ]]; then
  echo "Building and launching MVP fixture app"
  fixture_output="$(bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_fixture.sh" --print-path --launch)"
  echo "${fixture_output}"
  FIXTURE_APP_PATH="$(printf '%s\n' "${fixture_output}" | awk '/\.app$/ { path = $0 } END { print path }')"
fi

echo "Running macOS Computer Use desktop action canary"
echo "  Purpose: observe the screen, click once, and observe again"
echo "  TCC boundary: user-operated manual verification only"
echo "  Safety: prepare a safe click target before running"
echo "  Safe target: use a visible, harmless target such as an empty text field or test window"
echo "  Avoid: destructive buttons, purchase flows, send buttons, system controls, and private data"
echo "  Success phases: pre_observe_image, click_sent, post_observe_image"
echo "  MVP fixture target: ${FIXTURE_TARGET}"
if [[ "${FIXTURE_TARGET}" == "1" ]]; then
  echo "  Fixture preparation: bash tool/run_macos_computer_use_mvp_fixture.sh --launch"
  echo "  Fixture safe target: Safe Click Target"
  echo "  Fixture expected outcome: status label changes to Clicked"
  echo "  Fixture app path: ${FIXTURE_APP_PATH:-not recorded}"
  echo "  Manual step: bring the fixture window forward and confirm Safe Click Target is the click target."
fi
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  No-rebuild helper probe: $([[ "${LEGACY_INTEGRATION}" == "1" ]] && echo false || echo true)"
echo "  Auto-launch Caverno.app: ${LAUNCH_CAVERNO_APP}"
echo "  Restore normal Debug app after canary: ${RESTORE_DEBUG_APP}"
echo "  Report dir: ${RUN_DIR}"

status=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_name="$(printf "run_%02d" "${index}")"
  run_report="${RUN_DIR}/${run_name}.json"
  run_log="${RUN_DIR}/${run_name}.log"
  echo "Running ${run_name}/${REPEAT_COUNT}"
  set +e
  if [[ "${LEGACY_INTEGRATION}" == "1" ]]; then
    CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${run_report}" \
      bash "${ROOT_DIR}/tool/run_macos_computer_use_smoke_test.sh" \
        --desktop-action-canary \
        --device "${DEVICE}" \
        --reporter "${REPORTER}" \
        >"${run_log}" 2>&1
  else
    probe_args=(
      "${ROOT_DIR}/tool/macos_computer_use_existing_helper_probe.swift"
      --report "${run_report}"
      --desktop-action-canary
      --require-capture
      --require-input
      --require-helper-path-match
      --replace-helper
    )
    if [[ "${LAUNCH_CAVERNO_APP}" != "1" ]]; then
      probe_args+=(--no-launch-app)
    fi
    if [[ "${FIXTURE_TARGET}" == "1" ]]; then
      probe_args+=(--fixture-target)
    fi
    swift "${probe_args[@]}" >"${run_log}" 2>&1
  fi
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    status=1
  fi
done

RUN_DIR="${RUN_DIR}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" FIXTURE_TARGET="${FIXTURE_TARGET}" FIXTURE_APP_PATH="${FIXTURE_APP_PATH}" LAUNCH_FIXTURE="${LAUNCH_FIXTURE}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
fixture_target = os.environ["FIXTURE_TARGET"] == "1"
fixture_app_path = os.environ.get("FIXTURE_APP_PATH", "")
launch_fixture = os.environ["LAUNCH_FIXTURE"] == "1"
runs = []


fixture_app = {
    "name": "Caverno Computer Use MVP Fixture",
    "bundleIdentifier": "com.noguwo.apps.caverno.computer-use-mvp-fixture",
    "windowTitle": "Caverno Computer Use MVP Fixture",
    "buildCommand": "bash tool/run_macos_computer_use_mvp_fixture.sh --print-path",
    "manualLaunchCommand": "bash tool/run_macos_computer_use_mvp_fixture.sh --launch",
    "appPath": fixture_app_path or None,
    "safeTarget": {
        "label": "Safe Click Target",
        "accessibilityIdentifier": "safeClickTargetButton",
        "expectedOutcome": "Status label changes to Clicked.",
    },
    "typeConfirmTarget": {
        "label": "MVP Fixture Text Field",
        "accessibilityIdentifier": "mvpInputField",
        "confirmationButton": "Echo Text",
        "expectedOutcome": "Echo label changes to Echo: caverno-mvp-canary.",
    },
    "refusedTargets": [
        {
            "label": "Danger Zone",
            "accessibilityIdentifier": "disabledDangerZoneButton",
            "reason": "Disabled destructive target.",
        }
    ],
}


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
        "Use a visible, harmless target such as the MVP fixture Safe Click Target, an empty text field, or a test window.",
        "Avoid destructive buttons, purchase flows, send buttons, system controls, and private data.",
        "Keep the pointer target stable until the post-click observation completes.",
    ],
    "fixtureTarget": fixture_target,
    "fixtureLaunchRequested": launch_fixture,
    "fixtureApp": fixture_app if fixture_target else None,
    "safeTarget": fixture_app["safeTarget"] if fixture_target else None,
    "fixtureExpectedOutcomes": {
        "safeClick": fixture_app["safeTarget"]["expectedOutcome"],
        "typeConfirm": fixture_app["typeConfirmTarget"]["expectedOutcome"],
        "evidencePolicy": "post_observe_image_only",
    } if fixture_target else None,
    "expectedOutcome": fixture_app["safeTarget"]["expectedOutcome"] if fixture_target else None,
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
    f"- MVP fixture target: {str(fixture_target).lower()}",
    f"- Fixture launch requested: {str(launch_fixture).lower()}",
    f"- Stable: {str(summary['stable']).lower()}",
    f"- Run count: {len(runs)}",
    f"- Passed: {passed_count}",
    f"- Failed: {failed_count}",
    f"- Pass rate: {summary['passRate'] * 100:.1f}%",
]
if fixture_target:
    lines.extend([
        f"- Fixture app: {fixture_app['name']}",
        f"- Fixture launch command: `{fixture_app['manualLaunchCommand']}`",
        f"- Fixture safe target: {fixture_app['safeTarget']['label']}",
        f"- Fixture expected outcome: {fixture_app['safeTarget']['expectedOutcome']}",
        f"- Fixture type outcome: {fixture_app['typeConfirmTarget']['expectedOutcome']}",
        "- Fixture evidence policy: post_observe_image_only",
    ])
lines.extend([
    "",
    "| Run | Status | Failure Class | Phases | Gate | Blockers | Artifacts |",
    "| --- | --- | --- | --- | --- | --- | --- |",
])
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
if [[ "${RESTORE_DEBUG_APP}" == "1" ]]; then
  echo "Restoring normal Debug Caverno.app after integration-test canary build"
  set +e
  (cd "${ROOT_DIR}" && flutter build macos --debug)
  restore_status=$?
  set -e
  if [[ "${restore_status}" -ne 0 ]]; then
    echo "Failed to restore normal Debug Caverno.app after the canary."
    status=1
  fi
fi
exit "${status}"

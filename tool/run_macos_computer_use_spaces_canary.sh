#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_SPACES_CANARY_REPEAT_COUNT:-1}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_spaces_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"
SUMMARY_EXIT_STATUS="${RUN_DIR}/summary_exit_status"
LAUNCH_CAVERNO_APP="${CAVERNO_MACOS_COMPUTER_USE_SPACES_LAUNCH_CAVERNO:-0}"
REQUIRE_INACTIVE_SPACE_WINDOW="${CAVERNO_MACOS_COMPUTER_USE_SPACES_REQUIRE_INACTIVE_WINDOW:-0}"
REQUIRE_HELPER_PATH_MATCH="${CAVERNO_MACOS_COMPUTER_USE_SPACES_REQUIRE_HELPER_PATH_MATCH:-0}"
REPLACE_HELPER="${CAVERNO_MACOS_COMPUTER_USE_SPACES_REPLACE_HELPER:-0}"

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
    --launch-caverno)
      LAUNCH_CAVERNO_APP=1
      shift
      ;;
    --require-inactive-space-window)
      REQUIRE_INACTIVE_SPACE_WINDOW=1
      shift
      ;;
    --require-helper-path-match)
      REQUIRE_HELPER_PATH_MATCH=1
      shift
      ;;
    --replace-helper)
      REPLACE_HELPER=1
      shift
      ;;
    --release-helper-signoff)
      REQUIRE_HELPER_PATH_MATCH=1
      REPLACE_HELPER=1
      shift
      ;;
    --help)
      cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_spaces_canary.sh [options]

Options:
  --repeat COUNT       Run the canary multiple times.
  --report-root PATH   Report root directory.
  --launch-caverno     Also launch Caverno.app from this script. By default the
                       no-build probe requires Caverno.app to be already running
                       so the script does not trigger main-app TCC prompts.
  --require-inactive-space-window
                       Require at least one window marked outside the active
                       Space. Prepare two macOS Spaces manually before running.
  --require-helper-path-match
                       Fail when the running helper is not the embedded helper.
  --replace-helper     Stop a mismatched running helper before probing.
  --release-helper-signoff
                       Equivalent to --require-helper-path-match --replace-helper.

This canary is observe-only. It validates computer_list_windows with
space_scope=all_spaces and verifies that macOS Spaces metadata keeps Space
switching and input behind explicit approval plus a fresh observation.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_spaces_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_SPACES_CANARY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use Spaces canary"
echo "  Purpose: validate macOS Spaces window discovery metadata"
echo "  TCC boundary: user-operated manual verification only"
echo "  Desktop action boundary: no desktop action observe-only"
echo "  Scope: computer_list_windows space_scope=all_spaces"
echo "  Manual setup: prepare a harmless target window on another Space when requiring inactive Space evidence"
echo "  Success phases: active_space_window_inventory, all_spaces_window_inventory, space_metadata_present"
echo "  Auto-launch Caverno.app: ${LAUNCH_CAVERNO_APP}"
echo "  Require inactive Space window: ${REQUIRE_INACTIVE_SPACE_WINDOW}"
echo "  Require helper path match: ${REQUIRE_HELPER_PATH_MATCH}"
echo "  Replace helper if mismatched: ${REPLACE_HELPER}"
echo "  Report dir: ${RUN_DIR}"

status=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_name="$(printf "run_%02d" "${index}")"
  run_report="${RUN_DIR}/${run_name}.json"
  run_log="${RUN_DIR}/${run_name}.log"
  echo "Running ${run_name}/${REPEAT_COUNT}"
  probe_args=(
    "${ROOT_DIR}/tool/macos_computer_use_existing_helper_probe.swift"
    --report "${run_report}"
    --spaces-canary
  )
  if [[ "${LAUNCH_CAVERNO_APP}" != "1" ]]; then
    probe_args+=(--no-launch-app)
  fi
  if [[ "${REQUIRE_INACTIVE_SPACE_WINDOW}" == "1" ]]; then
    probe_args+=(--require-inactive-space-window)
  fi
  if [[ "${REQUIRE_HELPER_PATH_MATCH}" == "1" ]]; then
    probe_args+=(--require-helper-path-match)
  fi
  if [[ "${REPLACE_HELPER}" == "1" ]]; then
    probe_args+=(--replace-helper)
  fi
  set +e
  swift "${probe_args[@]}" >"${run_log}" 2>&1
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    status=1
  fi
done

RUN_DIR="${RUN_DIR}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" SUMMARY_EXIT_STATUS="${SUMMARY_EXIT_STATUS}" REQUIRE_INACTIVE_SPACE_WINDOW="${REQUIRE_INACTIVE_SPACE_WINDOW}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
summary_exit_status = Path(os.environ["SUMMARY_EXIT_STATUS"])
require_inactive = os.environ["REQUIRE_INACTIVE_SPACE_WINDOW"] == "1"
runs = []

for report_file in sorted(run_dir.glob("run_*.json")):
    try:
        report = json.loads(report_file.read_text())
    except Exception as error:
        runs.append({
            "name": report_file.stem,
            "ok": False,
            "code": "invalid_report",
            "error": str(error),
            "path": str(report_file),
        })
        continue
    gate = report.get("spacesCanaryGate", {})
    runs.append({
        "name": report_file.stem,
        "ok": bool(report.get("ok")) and bool(gate.get("ok")),
        "path": str(report_file),
        "gateStatus": gate.get("status", "unknown"),
        "blockers": gate.get("blockers", []),
        "activeSpaceWindowCount": gate.get("activeSpaceWindowCount", 0),
        "allSpacesWindowCount": gate.get("allSpacesWindowCount", 0),
        "inactiveSpaceWindowCount": gate.get("inactiveSpaceWindowCount", 0),
        "requiresApprovedInputBeforeSwitching": gate.get(
            "requiresApprovedInputBeforeSwitching",
            False,
        ),
    })

failed = [run for run in runs if not run.get("ok")]
inactive_seen = any((run.get("inactiveSpaceWindowCount") or 0) > 0 for run in runs)
ready = bool(runs) and not failed and (inactive_seen or not require_inactive)
summary = {
    "schemaName": "macos_computer_use_spaces_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_spaces_canary",
    "status": "ready" if ready else "blocked",
    "ok": ready,
    "desktopModel": "macos_spaces",
    "spaceScope": "all_spaces",
    "desktopActionBoundary": "no_desktop_action_observe_only",
    "tccBoundary": "manual_user_operated",
    "requireInactiveSpaceWindow": require_inactive,
    "runCount": len(runs),
    "passedRunCount": len(runs) - len(failed),
    "failedRunCount": len(failed),
    "inactiveSpaceWindowObserved": inactive_seen,
    "phaseStatus": {
        "active_space_window_inventory": bool(runs),
        "all_spaces_window_inventory": bool(runs) and not failed,
        "space_metadata_present": bool(runs) and not failed,
        "inactive_space_window_candidate": inactive_seen,
    },
    "runs": runs,
    "nextAction": (
        "Spaces canary passed. Use focus or approved Control-Left/Right Space switching only after a fresh observe."
        if ready
        else "Prepare a harmless window on another macOS Space when required, keep Caverno.app and the helper running, then rerun the Spaces canary."
    ),
}
summary_json.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
summary_exit_status.write_text("0\n" if summary["ok"] else "1\n")
summary_md.write_text(
    "\n".join([
        "# macOS Computer Use Spaces Canary",
        "",
        f"- Status: {summary['status']}",
        f"- Runs: {summary['passedRunCount']}/{summary['runCount']} passed",
        f"- Require inactive Space window: {summary['requireInactiveSpaceWindow']}",
        f"- Inactive Space window observed: {summary['inactiveSpaceWindowObserved']}",
        f"- Desktop action boundary: {summary['desktopActionBoundary']}",
        f"- Next action: {summary['nextAction']}",
        "",
    ])
)
print(json.dumps(summary, indent=2, sort_keys=True))
PY

summary_exit_status="$(<"${SUMMARY_EXIT_STATUS}")"
if [[ "${summary_exit_status}" != "0" ]]; then
  status=1
fi

echo "Spaces canary summary: ${SUMMARY_JSON}"
exit "${status}"

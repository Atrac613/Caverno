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
FOCUS_INACTIVE_SPACE_WINDOW="${CAVERNO_MACOS_COMPUTER_USE_SPACES_FOCUS_INACTIVE_WINDOW:-0}"
SWITCH_SPACE_DIRECTION="${CAVERNO_MACOS_COMPUTER_USE_SPACES_SWITCH_DIRECTION:-}"
REQUIRE_HELPER_PATH_MATCH="${CAVERNO_MACOS_COMPUTER_USE_SPACES_REQUIRE_HELPER_PATH_MATCH:-0}"
REPLACE_HELPER="${CAVERNO_MACOS_COMPUTER_USE_SPACES_REPLACE_HELPER:-0}"
HANDOFF_ONLY=0

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value."
    exit 2
  fi
}

desktop_action_boundary_text() {
  if [[ "${FOCUS_INACTIVE_SPACE_WINDOW}" == "1" && -n "${SWITCH_SPACE_DIRECTION}" ]]; then
    echo "user-operated focus and Space switch, no pointer or text input"
  elif [[ "${FOCUS_INACTIVE_SPACE_WINDOW}" == "1" ]]; then
    echo "user-operated focus only, no pointer or text input"
  elif [[ -n "${SWITCH_SPACE_DIRECTION}" ]]; then
    echo "user-operated Space switch keypress, no pointer or text input"
  else
    echo "no desktop action observe-only"
  fi
}

print_spaces_canary_context() {
  local desktop_action_boundary
  desktop_action_boundary="$(desktop_action_boundary_text)"
  echo "Running macOS Computer Use Spaces canary"
  echo "  Purpose: validate macOS Spaces window discovery metadata"
  echo "  TCC boundary: user-operated manual verification only"
  echo "  Desktop action boundary: ${desktop_action_boundary}"
  echo "  Scope: computer_list_windows space_scope=all_spaces"
  echo "  Manual setup: prepare a harmless target window on another Space when requiring inactive Space evidence"
  echo "  Success phases: active_space_window_inventory, all_spaces_window_inventory, space_metadata_present"
  echo "  Focus inactive Space window: ${FOCUS_INACTIVE_SPACE_WINDOW}"
  echo "  Switch Space direction: ${SWITCH_SPACE_DIRECTION:-not requested}"
  echo "  Auto-launch Caverno.app: ${LAUNCH_CAVERNO_APP}"
  echo "  Require inactive Space window: ${REQUIRE_INACTIVE_SPACE_WINDOW}"
  echo "  Require helper path match: ${REQUIRE_HELPER_PATH_MATCH}"
  echo "  Replace helper if mismatched: ${REPLACE_HELPER}"
  echo "  Report dir: ${RUN_DIR}"
  echo "  Summary JSON: ${SUMMARY_JSON}"
  echo "  Summary Markdown: ${SUMMARY_MD}"
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
    --focus-inactive-space-window|--spaces-focus-canary)
      REQUIRE_INACTIVE_SPACE_WINDOW=1
      FOCUS_INACTIVE_SPACE_WINDOW=1
      shift
      ;;
    --switch-space-next|--switch-next-space)
      SWITCH_SPACE_DIRECTION=next
      shift
      ;;
    --switch-space-previous|--switch-previous-space)
      SWITCH_SPACE_DIRECTION=previous
      shift
      ;;
    --switch-space)
      require_value "$@"
      SWITCH_SPACE_DIRECTION="$2"
      shift 2
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
    --handoff-only)
      HANDOFF_ONLY=1
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
  --focus-inactive-space-window
                       User-operated focus canary: focus the first inactive
                       Space window, then list active Space windows again.
                       This requires Accessibility and may switch Spaces.
  --switch-space-next  User-operated Space switch canary: send Control-Right,
                       then list active Space windows again. Prepare an
                       adjacent Space and enable Mission Control shortcuts.
  --switch-space-previous
                       User-operated Space switch canary: send Control-Left,
                       then list active Space windows again. Prepare an
                       adjacent Space and enable Mission Control shortcuts.
  --switch-space next|previous
                       Equivalent explicit Space switch direction.
  --require-helper-path-match
                       Fail when the running helper is not the embedded helper.
  --replace-helper     Stop a mismatched running helper before probing.
  --release-helper-signoff
                       Equivalent to --require-helper-path-match --replace-helper.
  --handoff-only       Print the Spaces setup checklist and expected report
                       paths without running the canary.

This canary is observe-only by default. It validates computer_list_windows with
space_scope=all_spaces and verifies that macOS Spaces metadata keeps Space
switching and input behind explicit approval plus a fresh observation. With
--focus-inactive-space-window it performs one explicit user-operated
focusWindow action, then observes the active Space inventory again.
With --switch-space-next or --switch-space-previous it performs one explicit
user-operated Control-Left/Right keypress, then observes the active Space
inventory again. The switch canary does not move the pointer or type text.
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
SUMMARY_EXIT_STATUS="${RUN_DIR}/summary_exit_status"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_SPACES_CANARY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

case "${SWITCH_SPACE_DIRECTION}" in
  "")
    ;;
  next|right)
    SWITCH_SPACE_DIRECTION=next
    ;;
  previous|prev|left)
    SWITCH_SPACE_DIRECTION=previous
    ;;
  *)
    echo "Space switch direction must be next or previous."
    exit 2
    ;;
esac

if [[ "${HANDOFF_ONLY}" == "1" ]]; then
  print_spaces_canary_context
  echo "  Handoff only: no Spaces canary was executed."
  exit 0
fi

mkdir -p "${RUN_DIR}"

desktop_action_boundary="$(desktop_action_boundary_text)"

print_spaces_canary_context

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
  if [[ "${FOCUS_INACTIVE_SPACE_WINDOW}" == "1" ]]; then
    probe_args+=(--focus-inactive-space-window)
  fi
  if [[ -n "${SWITCH_SPACE_DIRECTION}" ]]; then
    probe_args+=(--switch-space "${SWITCH_SPACE_DIRECTION}")
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

RUN_DIR="${RUN_DIR}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" SUMMARY_EXIT_STATUS="${SUMMARY_EXIT_STATUS}" REQUIRE_INACTIVE_SPACE_WINDOW="${REQUIRE_INACTIVE_SPACE_WINDOW}" FOCUS_INACTIVE_SPACE_WINDOW="${FOCUS_INACTIVE_SPACE_WINDOW}" SWITCH_SPACE_DIRECTION="${SWITCH_SPACE_DIRECTION}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
summary_exit_status = Path(os.environ["SUMMARY_EXIT_STATUS"])
require_inactive = os.environ["REQUIRE_INACTIVE_SPACE_WINDOW"] == "1"
focus_inactive = os.environ["FOCUS_INACTIVE_SPACE_WINDOW"] == "1"
switch_direction = os.environ["SWITCH_SPACE_DIRECTION"] or None
switch_space = switch_direction is not None
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
    focus_gate = report.get("spacesFocusCanaryGate", {})
    switch_gate = report.get("spacesSwitchCanaryGate", {})
    runs.append({
        "name": report_file.stem,
        "ok": bool(report.get("ok")) and bool(gate.get("ok")) and (
            bool(focus_gate.get("ok")) if focus_inactive else True
        ) and (
            bool(switch_gate.get("ok")) if switch_space else True
        ),
        "path": str(report_file),
        "gateStatus": gate.get("status", "unknown"),
        "focusGateStatus": focus_gate.get("status", "not_run"),
        "switchGateStatus": switch_gate.get("status", "not_run"),
        "blockers": gate.get("blockers", []),
        "focusBlockers": focus_gate.get("blockers", []),
        "switchBlockers": switch_gate.get("blockers", []),
        "activeSpaceWindowCount": gate.get("activeSpaceWindowCount", 0),
        "allSpacesWindowCount": gate.get("allSpacesWindowCount", 0),
        "inactiveSpaceWindowCount": gate.get("inactiveSpaceWindowCount", 0),
        "focusWindowSent": focus_gate.get("focusWindowSent", False),
        "postFocusTargetVisible": focus_gate.get("postFocusTargetVisible", False),
        "switchKeySent": switch_gate.get("switchKeySent", False),
        "switchKeyOk": switch_gate.get("switchKeyOk", False),
        "postSwitchActiveSpaceObserved": switch_gate.get(
            "postSwitchActiveSpaceObserved",
            False,
        ),
        "activeWindowInventoryChanged": switch_gate.get(
            "activeWindowInventoryChanged",
            False,
        ),
        "beforeActiveWindowCount": switch_gate.get("beforeActiveWindowCount", 0),
        "postSwitchActiveWindowCount": switch_gate.get(
            "postSwitchActiveWindowCount",
            0,
        ),
        "requiresApprovedInputBeforeSwitching": gate.get(
            "requiresApprovedInputBeforeSwitching",
            False,
        ),
    })

failed = [run for run in runs if not run.get("ok")]
inactive_seen = any((run.get("inactiveSpaceWindowCount") or 0) > 0 for run in runs)
focus_ready = (not focus_inactive) or all(
    run.get("focusWindowSent") and run.get("postFocusTargetVisible")
    for run in runs
)
switch_ready = (not switch_space) or all(
    run.get("switchKeySent") and
    run.get("switchKeyOk") and
    run.get("postSwitchActiveSpaceObserved") and
    run.get("activeWindowInventoryChanged")
    for run in runs
)
ready = (
    bool(runs) and
    not failed and
    (inactive_seen or not require_inactive) and
    focus_ready and
    switch_ready
)
if focus_inactive and switch_space:
    desktop_action_boundary = "user_operated_focus_and_space_switch_no_pointer_or_text"
elif focus_inactive:
    desktop_action_boundary = "user_operated_focus_only_no_pointer_or_text"
elif switch_space:
    desktop_action_boundary = "user_operated_space_switch_keypress_no_pointer_or_text"
else:
    desktop_action_boundary = "no_desktop_action_observe_only"

if ready and focus_inactive and switch_space:
    next_action = (
        "Spaces focus and switch canaries passed. Run computer_vision_observe "
        "before any pointer or keyboard input."
    )
elif ready and switch_space:
    next_action = (
        "Spaces switch canary passed. Run computer_vision_observe before any "
        "pointer or keyboard input."
    )
elif ready and focus_inactive:
    next_action = (
        "Spaces focus canary passed. Run computer_vision_observe before any "
        "pointer or keyboard input."
    )
elif ready:
    next_action = (
        "Spaces canary passed. Use focus or approved Control-Left/Right Space "
        "switching only after a fresh observe."
    )
else:
    next_action = (
        "Prepare a harmless window on another macOS Space when required, keep "
        "Caverno.app and the helper running, then rerun the Spaces canary."
    )
summary = {
    "schemaName": "macos_computer_use_spaces_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_spaces_canary",
    "status": "ready" if ready else "blocked",
    "ok": ready,
    "desktopModel": "macos_spaces",
    "spaceScope": "all_spaces",
    "desktopActionBoundary": desktop_action_boundary,
    "tccBoundary": "manual_user_operated",
    "requireInactiveSpaceWindow": require_inactive,
    "focusInactiveSpaceWindow": focus_inactive,
    "switchSpaceCanary": switch_space,
    "switchSpaceDirection": switch_direction,
    "runCount": len(runs),
    "passedRunCount": len(runs) - len(failed),
    "failedRunCount": len(failed),
    "inactiveSpaceWindowObserved": inactive_seen,
    "focusCanaryReady": focus_ready,
    "switchCanaryReady": switch_ready,
    "phaseStatus": {
        "active_space_window_inventory": bool(runs),
        "all_spaces_window_inventory": bool(runs) and not failed,
        "space_metadata_present": bool(runs) and not failed,
        "inactive_space_window_candidate": inactive_seen,
        "focus_inactive_space_window": focus_ready if focus_inactive else None,
        "switch_space_keypress": switch_ready if switch_space else None,
    },
    "runs": runs,
    "nextAction": next_action,
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
        f"- Focus inactive Space window: {summary['focusInactiveSpaceWindow']}",
        f"- Switch Space direction: {summary['switchSpaceDirection']}",
        f"- Inactive Space window observed: {summary['inactiveSpaceWindowObserved']}",
        f"- Focus canary ready: {summary['focusCanaryReady']}",
        f"- Switch canary ready: {summary['switchCanaryReady']}",
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

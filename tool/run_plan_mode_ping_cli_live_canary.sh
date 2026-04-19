#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${1:-${CAVERNO_PLAN_MODE_USER_PROMPT:-}}"
RUN_COUNT="${CAVERNO_PLAN_MODE_REPEAT_COUNT:-5}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORT_PREFIX="plan_mode_live_suite_${DEVICE}"
CANARY_DIR="${ROOT_DIR}/build/integration_test_reports/plan_mode_ping_cli_canary_$(date +%s)"
PLANNING_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS:-180}"
EXECUTION_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS:-180}"
EXECUTION_STALL_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS:-45}"
RUN_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS:-$((PLANNING_TIMEOUT_SECONDS + EXECUTION_TIMEOUT_SECONDS + 60))}"
STARTUP_HEARTBEAT_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_STARTUP_HEARTBEAT_TIMEOUT_SECONDS:-45}"
FOREGROUND_RECOVERY_GRACE_SECONDS="${CAVERNO_PLAN_MODE_FOREGROUND_RECOVERY_GRACE_SECONDS:-15}"

if [[ -z "${PROMPT}" ]]; then
  echo "Pass the target user prompt as the first argument or set CAVERNO_PLAN_MODE_USER_PROMPT."
  exit 1
fi

mkdir -p "${CANARY_DIR}"

cleanup_live_plan_mode_processes() {
  pkill -f "${ROOT_DIR}/build/macos/Build/Products/Debug/Caverno.app/Contents/MacOS/Caverno" >/dev/null 2>&1 || true
  pkill -f "flutter test integration_test/plan_mode_scenario_test.dart" >/dev/null 2>&1 || true
}

append_canary_marker() {
  local run_log_path="$1"
  local stage="$2"
  local detail="${3:-}"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [[ -n "${detail}" ]]; then
    echo "[CanaryRunner] stage=${stage} at=${timestamp} detail=${detail}" >> "${run_log_path}"
  else
    echo "[CanaryRunner] stage=${stage} at=${timestamp}" >> "${run_log_path}"
  fi
}

write_failure_suite_report() {
  local output_path="$1"
  local heartbeat_path="$2"
  local run_log_path="$3"
  local failure_class="$4"
  local budget_phase="$5"
  local duration_ms="$6"
  local error_message="$7"
  local heartbeat_json='{}'

  if [[ -f "${heartbeat_path}" ]]; then
    heartbeat_json="$(cat "${heartbeat_path}")"
  fi

  cat > "${output_path}" <<EOF
{
  "generatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "suite": "${REPORT_PREFIX}",
  "mode": "live",
  "scenarioCount": 1,
  "passedCount": 0,
  "failedCount": 1,
  "scenarios": [
    {
      "scenario": "live_ping_cli_completion",
      "status": "failed",
      "failureClass": "${failure_class}",
      "budgetPhase": "${budget_phase}",
      "durationMs": ${duration_ms},
      "error": "${error_message}",
      "scenarioLog": "${run_log_path}",
      "phaseTimings": {},
      "budgets": {
        "planningTimeoutMs": $((PLANNING_TIMEOUT_SECONDS * 1000)),
        "executionTimeoutMs": $((EXECUTION_TIMEOUT_SECONDS * 1000)),
        "executionStallTimeoutMs": $((EXECUTION_STALL_TIMEOUT_SECONDS * 1000)),
        "overallTimeoutMs": $((RUN_TIMEOUT_SECONDS * 1000))
      },
      "diagnostics": {
        "failureClass": "${failure_class}",
        "budgetPhase": "${budget_phase}",
        "lastHeartbeat": ${heartbeat_json},
        "budgets": {
          "planningTimeoutMs": $((PLANNING_TIMEOUT_SECONDS * 1000)),
          "executionTimeoutMs": $((EXECUTION_TIMEOUT_SECONDS * 1000)),
          "executionStallTimeoutMs": $((EXECUTION_STALL_TIMEOUT_SECONDS * 1000)),
          "overallTimeoutMs": $((RUN_TIMEOUT_SECONDS * 1000))
        },
        "recentLogTail": []
      }
    }
  ]
}
EOF
}

run_live_canary_iteration() {
  local prompt="$1"
  local heartbeat_path="$2"
  local run_log_path="$3"
  local run_pid
  local elapsed=0
  local build_started=0
  local build_finished=0
  local test_started=0
  local foreground_failed=0
  local first_heartbeat_seen=0
  local build_finished_elapsed=-1
  local foreground_failed_elapsed=-1

  rm -f "${heartbeat_path}"
  rm -f "${run_log_path}"
  append_canary_marker "${run_log_path}" "runStarted"
  CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS="${PLANNING_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS="${EXECUTION_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS="${EXECUTION_STALL_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_HEARTBEAT_PATH="${heartbeat_path}" \
  "${ROOT_DIR}/tool/run_plan_mode_ping_cli_live_test.sh" "${prompt}" \
    >> "${run_log_path}" 2>&1 &
  run_pid=$!

  while kill -0 "${run_pid}" >/dev/null 2>&1; do
    if [[ "${build_started}" -eq 0 ]] && grep -q "Building macOS application" "${run_log_path}" 2>/dev/null; then
      build_started=1
      append_canary_marker "${run_log_path}" "buildStarted"
    fi
    if [[ "${build_finished}" -eq 0 ]] && grep -q "✓ Built " "${run_log_path}" 2>/dev/null; then
      build_finished=1
      build_finished_elapsed="${elapsed}"
      append_canary_marker "${run_log_path}" "buildFinished"
    fi
    if [[ "${test_started}" -eq 0 ]] && grep -q "\[ScenarioSuite\] Running" "${run_log_path}" 2>/dev/null; then
      test_started=1
      append_canary_marker "${run_log_path}" "testStarted"
    fi
    if [[ "${first_heartbeat_seen}" -eq 0 ]] && [[ -f "${heartbeat_path}" ]]; then
      first_heartbeat_seen=1
      append_canary_marker "${run_log_path}" "firstHeartbeatSeen"
      if [[ "${foreground_failed}" -eq 1 ]]; then
        append_canary_marker "${run_log_path}" "foregroundRecovered"
      fi
    fi
    if [[ "${foreground_failed}" -eq 0 ]] && grep -q "Failed to foreground app; open returned 1" "${run_log_path}" 2>/dev/null; then
      foreground_failed=1
      foreground_failed_elapsed="${elapsed}"
      append_canary_marker "${run_log_path}" "foregroundFailed" "open returned 1"
    fi
    if [[ "${foreground_failed}" -eq 1 ]] &&
      [[ "${first_heartbeat_seen}" -eq 0 ]] &&
      [[ "${foreground_failed_elapsed}" -ge 0 ]] &&
      [[ $((elapsed - foreground_failed_elapsed)) -ge "${FOREGROUND_RECOVERY_GRACE_SECONDS}" ]]; then
      append_canary_marker "${run_log_path}" "foregroundFailureTimeout"
      kill "${run_pid}" >/dev/null 2>&1 || true
      cleanup_live_plan_mode_processes
      wait "${run_pid}" >/dev/null 2>&1 || true
      return 125
    fi
    if [[ "${build_finished}" -eq 1 ]] &&
      [[ "${first_heartbeat_seen}" -eq 0 ]] &&
      [[ "${build_finished_elapsed}" -ge 0 ]] &&
      [[ $((elapsed - build_finished_elapsed)) -ge "${STARTUP_HEARTBEAT_TIMEOUT_SECONDS}" ]]; then
      append_canary_marker "${run_log_path}" "firstHeartbeatTimeout"
      kill "${run_pid}" >/dev/null 2>&1 || true
      cleanup_live_plan_mode_processes
      wait "${run_pid}" >/dev/null 2>&1 || true
      return 126
    fi
    if [[ "${elapsed}" -ge "${RUN_TIMEOUT_SECONDS}" ]]; then
      echo "Run timed out after ${RUN_TIMEOUT_SECONDS}s; terminating leftover processes."
      append_canary_marker "${run_log_path}" "overallTimeout"
      kill "${run_pid}" >/dev/null 2>&1 || true
      cleanup_live_plan_mode_processes
      wait "${run_pid}" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  wait "${run_pid}"
}

trap cleanup_live_plan_mode_processes EXIT

overall_exit=0
for run_index in $(seq 1 "${RUN_COUNT}"); do
  run_label="$(printf 'run_%02d' "${run_index}")"
  heartbeat_path="${CANARY_DIR}/${run_label}_heartbeat.json"
  run_log_path="${CANARY_DIR}/${run_label}_run.log"
  echo "Running ${run_label}/${RUN_COUNT}"
  cleanup_live_plan_mode_processes
  rm -f "${ROOT_DIR}/build/integration_test_reports/${REPORT_PREFIX}_report.json"

  set +e
  run_live_canary_iteration "${PROMPT}" "${heartbeat_path}" "${run_log_path}"
  run_exit=$?
  set -e

  if [[ ${run_exit} -ne 0 ]]; then
    overall_exit=1
  fi

  report_path="${ROOT_DIR}/build/integration_test_reports/${REPORT_PREFIX}_report.json"
  if [[ ${run_exit} -eq 124 ]]; then
    write_failure_suite_report \
      "${CANARY_DIR}/${run_label}_suite_report.json" \
      "${heartbeat_path}" \
      "${run_log_path}" \
      "overallTimeout" \
      "overall" \
      "$((RUN_TIMEOUT_SECONDS * 1000))" \
      "Overall live run timed out after ${RUN_TIMEOUT_SECONDS}s."
  elif [[ ${run_exit} -eq 125 ]]; then
    write_failure_suite_report \
      "${CANARY_DIR}/${run_label}_suite_report.json" \
      "${heartbeat_path}" \
      "${run_log_path}" \
      "appForegroundFailure" \
      "startup" \
      "$((STARTUP_HEARTBEAT_TIMEOUT_SECONDS * 1000))" \
      "App failed to foreground before the first live heartbeat."
  elif [[ ${run_exit} -eq 126 ]]; then
    write_failure_suite_report \
      "${CANARY_DIR}/${run_label}_suite_report.json" \
      "${heartbeat_path}" \
      "${run_log_path}" \
      "appLaunchTimeout" \
      "startup" \
      "$((STARTUP_HEARTBEAT_TIMEOUT_SECONDS * 1000))" \
      "App launch timed out before the first live heartbeat."
  elif [[ -f "${report_path}" ]]; then
    cp "${report_path}" "${CANARY_DIR}/${run_label}_suite_report.json"
  fi
  cleanup_live_plan_mode_processes
done

set +e
dart run "${ROOT_DIR}/tool/plan_mode_canary_summary.dart" "${CANARY_DIR}"
summary_exit=$?
set -e

if [[ ${summary_exit} -ne 0 ]]; then
  overall_exit=1
fi

exit "${overall_exit}"

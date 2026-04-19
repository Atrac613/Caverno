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

if [[ -z "${PROMPT}" ]]; then
  echo "Pass the target user prompt as the first argument or set CAVERNO_PLAN_MODE_USER_PROMPT."
  exit 1
fi

mkdir -p "${CANARY_DIR}"

cleanup_live_plan_mode_processes() {
  pkill -f "${ROOT_DIR}/build/macos/Build/Products/Debug/Caverno.app/Contents/MacOS/Caverno" >/dev/null 2>&1 || true
  pkill -f "flutter test integration_test/plan_mode_scenario_test.dart" >/dev/null 2>&1 || true
}

write_timeout_suite_report() {
  local output_path="$1"
  local heartbeat_path="$2"
  local run_log_path="$3"
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
      "failureClass": "overallTimeout",
      "budgetPhase": "overall",
      "durationMs": $((RUN_TIMEOUT_SECONDS * 1000)),
      "error": "Overall live run timed out after ${RUN_TIMEOUT_SECONDS}s.",
      "scenarioLog": "${run_log_path}",
      "phaseTimings": {},
      "budgets": {
        "planningTimeoutMs": $((PLANNING_TIMEOUT_SECONDS * 1000)),
        "executionTimeoutMs": $((EXECUTION_TIMEOUT_SECONDS * 1000)),
        "executionStallTimeoutMs": $((EXECUTION_STALL_TIMEOUT_SECONDS * 1000)),
        "overallTimeoutMs": $((RUN_TIMEOUT_SECONDS * 1000))
      },
      "diagnostics": {
        "failureClass": "overallTimeout",
        "budgetPhase": "overall",
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

  rm -f "${heartbeat_path}"
  rm -f "${run_log_path}"
  CAVERNO_PLAN_MODE_PLANNING_TIMEOUT_SECONDS="${PLANNING_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS="${EXECUTION_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_EXECUTION_STALL_TIMEOUT_SECONDS="${EXECUTION_STALL_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_HEARTBEAT_PATH="${heartbeat_path}" \
  "${ROOT_DIR}/tool/run_plan_mode_ping_cli_live_test.sh" "${prompt}" \
    > "${run_log_path}" 2>&1 &
  run_pid=$!

  while kill -0 "${run_pid}" >/dev/null 2>&1; do
    if [[ "${elapsed}" -ge "${RUN_TIMEOUT_SECONDS}" ]]; then
      echo "Run timed out after ${RUN_TIMEOUT_SECONDS}s; terminating leftover processes."
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
    write_timeout_suite_report "${CANARY_DIR}/${run_label}_suite_report.json" "${heartbeat_path}" "${run_log_path}"
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

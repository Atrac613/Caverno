#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${1:-${CAVERNO_PLAN_MODE_USER_PROMPT:-}}"
RUN_COUNT="${CAVERNO_PLAN_MODE_REPEAT_COUNT:-5}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORT_PREFIX="plan_mode_live_suite_${DEVICE}"
CANARY_DIR="${ROOT_DIR}/build/integration_test_reports/plan_mode_ping_cli_canary_$(date +%s)"
RUN_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS:-360}"

if [[ -z "${PROMPT}" ]]; then
  echo "Pass the target user prompt as the first argument or set CAVERNO_PLAN_MODE_USER_PROMPT."
  exit 1
fi

mkdir -p "${CANARY_DIR}"

cleanup_live_plan_mode_processes() {
  pkill -f "${ROOT_DIR}/build/macos/Build/Products/Debug/Caverno.app/Contents/MacOS/Caverno" >/dev/null 2>&1 || true
  pkill -f "flutter test integration_test/plan_mode_scenario_test.dart" >/dev/null 2>&1 || true
}

run_live_canary_iteration() {
  local prompt="$1"
  local run_pid
  local elapsed=0

  "${ROOT_DIR}/tool/run_plan_mode_ping_cli_live_test.sh" "${prompt}" &
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
  echo "Running ${run_label}/${RUN_COUNT}"
  cleanup_live_plan_mode_processes

  set +e
  run_live_canary_iteration "${PROMPT}"
  run_exit=$?
  set -e

  if [[ ${run_exit} -ne 0 ]]; then
    overall_exit=1
  fi

  report_path="${ROOT_DIR}/build/integration_test_reports/${REPORT_PREFIX}_report.json"
  if [[ -f "${report_path}" ]]; then
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

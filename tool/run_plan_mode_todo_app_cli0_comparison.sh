#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the CLI0 comparison.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the CLI0 comparison.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the CLI0 comparison.}"

HEADLESS_REPEAT_COUNT="${CAVERNO_CLI0_HEADLESS_REPEAT_COUNT:-3}"
if ! [[ "${HEADLESS_REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${HEADLESS_REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_CLI0_HEADLESS_REPEAT_COUNT must be a positive integer." >&2
  exit 2
fi

EXECUTION_TIMEOUT_SECONDS="${CAVERNO_CLI0_EXECUTION_TIMEOUT_SECONDS:-900}"
RUN_TIMEOUT_SECONDS="${CAVERNO_CLI0_RUN_TIMEOUT_SECONDS:-1380}"
if ! [[ "${EXECUTION_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${EXECUTION_TIMEOUT_SECONDS}" -lt 1 ]]; then
  echo "CAVERNO_CLI0_EXECUTION_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi
if ! [[ "${RUN_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${RUN_TIMEOUT_SECONDS}" -le "${EXECUTION_TIMEOUT_SECONDS}" ]]; then
  echo "CAVERNO_CLI0_RUN_TIMEOUT_SECONDS must exceed the execution timeout." >&2
  exit 2
fi

REPORT_ROOT="${CAVERNO_PLAN_MODE_TODO_CLI0_COMPARISON_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/plan_mode_todo_app_cli0_comparison_$(date +%s)"
HEADLESS_ROOT="${RUN_DIR}/headless"
MACOS_ROOT="${RUN_DIR}/macos"
SUMMARY_PATH="${RUN_DIR}/cli0_comparison_summary.json"
HEADLESS_RUNNER="${CAVERNO_CLI0_HEADLESS_RUNNER:-${ROOT_DIR}/tool/run_plan_mode_todo_app_headless_live_canary.sh}"
MACOS_RUNNER="${CAVERNO_CLI0_MACOS_RUNNER:-${ROOT_DIR}/tool/run_plan_mode_todo_app_live_canary.sh}"
SUMMARY_RUNNER="${CAVERNO_CLI0_COMPARISON_SUMMARY_RUNNER:-}"

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  DART_CMD=(fvm dart)
else
  DART_CMD=(dart)
fi

mkdir -p "${HEADLESS_ROOT}" "${MACOS_ROOT}"

echo "Running CLI0 headless and macOS comparison"
echo "  Scenario: live_todo_app_plan_completion"
echo "  Headless runs: ${HEADLESS_REPEAT_COUNT}"
echo "  macOS runs: 1"
echo "  Execution timeout: ${EXECUTION_TIMEOUT_SECONDS}s"
echo "  Overall timeout: ${RUN_TIMEOUT_SECONDS}s"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"

for ((iteration = 1; iteration <= HEADLESS_REPEAT_COUNT; iteration += 1)); do
  echo
  echo "Running headless TODO canary ${iteration}/${HEADLESS_REPEAT_COUNT}"
  CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS="${EXECUTION_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS}" \
  CAVERNO_PLAN_MODE_TODO_HEADLESS_REPORT_ROOT="${HEADLESS_ROOT}" \
    "${HEADLESS_RUNNER}"
done

echo
echo "Running macOS application-path TODO canary 1/1"
CAVERNO_PLAN_MODE_EXECUTION_TIMEOUT_SECONDS="${EXECUTION_TIMEOUT_SECONDS}" \
CAVERNO_PLAN_MODE_RUN_TIMEOUT_SECONDS="${RUN_TIMEOUT_SECONDS}" \
CAVERNO_PLAN_MODE_TODO_REPORT_ROOT="${MACOS_ROOT}" \
  "${MACOS_RUNNER}"

MACOS_SUITE_REPORT="$(find "${MACOS_ROOT}" -type f -name 'plan_mode_live_suite_macos_report.json' | sort | tail -1)"
if [[ -z "${MACOS_SUITE_REPORT}" ]]; then
  echo "Missing macOS TODO canary suite report under ${MACOS_ROOT}." >&2
  exit 1
fi

SUMMARY_ARGUMENTS=(
  --headless-root "${HEADLESS_ROOT}"
  --macos-suite-report "${MACOS_SUITE_REPORT}"
  --macos-session-log-root "${MACOS_ROOT}"
  --expected-headless-count "${HEADLESS_REPEAT_COUNT}"
  --out "${SUMMARY_PATH}"
)

if [[ -n "${SUMMARY_RUNNER}" ]]; then
  "${SUMMARY_RUNNER}" "${SUMMARY_ARGUMENTS[@]}"
else
  "${DART_CMD[@]}" run "${ROOT_DIR}/tool/plan_mode_cli0_comparison_summary.dart" \
    "${SUMMARY_ARGUMENTS[@]}"
fi

if [[ ! -f "${SUMMARY_PATH}" ]]; then
  echo "CLI0 comparison summarizer did not create ${SUMMARY_PATH}." >&2
  exit 1
fi

echo
echo "CLI0 headless and macOS comparison passed."
echo "  Report directory: ${RUN_DIR}"
echo "  Summary: ${SUMMARY_PATH}"

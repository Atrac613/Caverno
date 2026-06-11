#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEFAULT_BASE_URL="http://192.168.100.241:1234/v1"
DEFAULT_API_KEY="no-key"
DEFAULT_MODEL="qwen3.6-35b-a3b-vision"

CAVERNO_LLM_BASE_URL="${CAVERNO_QWEN36_MAIN_LLM_BASE_URL:-${CAVERNO_LLM_BASE_URL:-${DEFAULT_BASE_URL}}}"
CAVERNO_LLM_API_KEY="${CAVERNO_QWEN36_MAIN_LLM_API_KEY:-${CAVERNO_LLM_API_KEY:-${DEFAULT_API_KEY}}}"
CAVERNO_LLM_MODEL="${CAVERNO_QWEN36_MAIN_LLM_MODEL:-${CAVERNO_LLM_MODEL:-${DEFAULT_MODEL}}}"

EXACT_HELPER="${CAVERNO_QWEN36_MAIN_LLM_EXACT_HELPER:-${ROOT_DIR}/tool/run_plan_mode_live_test.sh}"
PM5_HELPER="${CAVERNO_QWEN36_MAIN_LLM_PM5_HELPER:-${ROOT_DIR}/tool/run_plan_mode_pm5_live_gate.sh}"
CHAT_HELPER="${CAVERNO_QWEN36_MAIN_LLM_CHAT_HELPER:-${ROOT_DIR}/tool/run_chat_live_llm_canary.sh}"
TOOL_RESULT_BUDGET_HELPER="${CAVERNO_QWEN36_MAIN_LLM_TOOL_RESULT_BUDGET_HELPER:-${ROOT_DIR}/tool/run_tool_result_budget_live_canary.sh}"

DEVICE="${CAVERNO_QWEN36_MAIN_LLM_DEVICE:-${CAVERNO_PLAN_MODE_DEVICE:-macos}}"
REPORTER="${CAVERNO_QWEN36_MAIN_LLM_REPORTER:-${CAVERNO_PLAN_MODE_REPORTER:-compact}}"
FAIL_ON_WARNINGS="${CAVERNO_QWEN36_MAIN_LLM_FAIL_ON_WARNINGS:-1}"
PREFLIGHT_TIMEOUT_SECONDS="${CAVERNO_QWEN36_MAIN_LLM_PREFLIGHT_TIMEOUT_SECONDS:-20}"
REPORT_ROOT="${CAVERNO_QWEN36_MAIN_LLM_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports/qwen36_main_llm_gate}}"
DEFAULT_REPORT_ROOT="${ROOT_DIR}/build/integration_test_reports"

RUN_PM5="${CAVERNO_QWEN36_MAIN_LLM_RUN_PM5:-0}"
PM5_PING_REPEAT_COUNT="${CAVERNO_QWEN36_MAIN_LLM_PM5_PING_REPEAT_COUNT:-1}"
SKIP_EXACT="${CAVERNO_QWEN36_MAIN_LLM_SKIP_EXACT:-0}"
SKIP_CHAT="${CAVERNO_QWEN36_MAIN_LLM_SKIP_CHAT:-0}"
SKIP_TOOL_RESULT_BUDGET="${CAVERNO_QWEN36_MAIN_LLM_SKIP_TOOL_RESULT_BUDGET:-0}"

latest_report_file_in_root() {
  local root="$1"
  local pattern="$2"
  local path_pattern="${3:-}"
  if [[ ! -d "${root}" ]]; then
    return 0
  fi
  if [[ -n "${path_pattern}" ]]; then
    find "${root}" \
      -type f -path "${path_pattern}" -name "${pattern}" -print 2>/dev/null \
      | sort \
      | tail -n 1
  else
    find "${root}" \
      -type f -name "${pattern}" -print 2>/dev/null \
      | sort \
      | tail -n 1
  fi
}

latest_report_file() {
  local pattern="$1"
  local path_pattern="${2:-}"
  local path
  path="$(latest_report_file_in_root "${REPORT_ROOT}" "${pattern}" "${path_pattern}")"
  if [[ -n "${path}" ]]; then
    echo "${path}"
    return 0
  fi
  if [[ "${REPORT_ROOT}" != "${DEFAULT_REPORT_ROOT}" ]]; then
    latest_report_file_in_root "${DEFAULT_REPORT_ROOT}" "${pattern}" "${path_pattern}"
  fi
}

print_report_file() {
  local label="$1"
  local pattern="$2"
  local path_pattern="${3:-}"
  local path
  path="$(latest_report_file "${pattern}" "${path_pattern}")"
  if [[ -n "${path}" ]]; then
    echo "  ${label}: ${path}"
  else
    echo "  ${label}: not found"
  fi
}

print_gate_artifacts() {
  local status_label="$1"
  echo
  echo "Qwen3.6 main LLM gate artifacts (${status_label})"
  echo "  Report root: ${REPORT_ROOT}"
  print_report_file "Exact preservation Plan Mode report JSON" "plan_mode_live_suite*_report.json"
  print_report_file "Exact preservation Plan Mode report Markdown" "plan_mode_live_suite*_report.md"
  if [[ "${SKIP_CHAT}" == "1" ]]; then
    echo "  Chat canary summary JSON: skipped"
    echo "  Chat canary summary Markdown: skipped"
  else
    print_report_file \
      "Chat canary summary JSON" \
      "canary_summary.json" \
      "*/qwen36_main_llm_chat_canary_*/canary_summary.json"
    print_report_file \
      "Chat canary summary Markdown" \
      "canary_summary.md" \
      "*/qwen36_main_llm_chat_canary_*/canary_summary.md"
  fi
  if [[ "${SKIP_TOOL_RESULT_BUDGET}" == "1" ]]; then
    echo "  Tool-result budget summary JSON: skipped"
    echo "  Tool-result budget summary Markdown: skipped"
  else
    print_report_file \
      "Tool-result budget summary JSON" \
      "canary_summary.json" \
      "*/tool_result_budget_live_canary_*/canary_summary.json"
    print_report_file \
      "Tool-result budget summary Markdown" \
      "canary_summary.md" \
      "*/tool_result_budget_live_canary_*/canary_summary.md"
  fi
  echo "  Coverage guide: ${ROOT_DIR}/docs/live_llm_canary_coverage.md"
  echo "  Model matrix: ${ROOT_DIR}/docs/plan_mode_live_llm_model_canary_matrix.md"
}

run_step() {
  local label="$1"
  shift
  echo
  echo "==> ${label}"
  set +e
  "$@"
  local step_exit=$?
  set -e
  if [[ "${step_exit}" -ne 0 ]]; then
    echo
    echo "Qwen3.6 main LLM gate failed during: ${label}" >&2
    print_gate_artifacts "failed"
    exit "${step_exit}"
  fi
}

export CAVERNO_LLM_BASE_URL
export CAVERNO_LLM_API_KEY
export CAVERNO_LLM_MODEL

echo "Running Qwen3.6 main LLM gate"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Fail on warnings: ${FAIL_ON_WARNINGS}"
echo "  Run PM5 gate: ${RUN_PM5}"
echo "  Report root: ${REPORT_ROOT}"

cd "${ROOT_DIR}"
mkdir -p "${REPORT_ROOT}"

if [[ "${SKIP_EXACT}" == "1" ]]; then
  echo
  echo "==> Exact preservation Plan Mode canary skipped"
else
  run_step "Exact preservation Plan Mode canary" env \
    CAVERNO_PLAN_MODE_SCENARIOS="live_exact_preservation_readme" \
    CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}" \
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_REPORTER="${REPORTER}" \
    CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS="${PREFLIGHT_TIMEOUT_SECONDS}" \
    CAVERNO_PLAN_MODE_REPORT_ROOT="${REPORT_ROOT}" \
    "${EXACT_HELPER}"
fi

if [[ "${RUN_PM5}" == "1" ]]; then
  run_step "PM5 Plan Mode live gate" env \
    CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}" \
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_REPORTER="${REPORTER}" \
    CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT="${PM5_PING_REPEAT_COUNT}" \
    CAVERNO_PLAN_MODE_REPORT_ROOT="${REPORT_ROOT}" \
    "${PM5_HELPER}"
else
  echo
  echo "==> PM5 Plan Mode live gate skipped"
fi

if [[ "${SKIP_CHAT}" == "1" ]]; then
  echo
  echo "==> Chat live canary skipped"
else
  run_step "Chat live canary" env \
    CAVERNO_CHAT_LIVE_CANARY_NAME="qwen36_main_llm_chat_canary" \
    CAVERNO_CHAT_LIVE_CANARY_REPORT_ROOT="${REPORT_ROOT}" \
    "${CHAT_HELPER}"
fi

if [[ "${SKIP_TOOL_RESULT_BUDGET}" == "1" ]]; then
  echo
  echo "==> Tool-result budget live canary skipped"
else
  run_step "Tool-result budget live canary" env \
    CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY_REPORT_ROOT="${REPORT_ROOT}" \
    "${TOOL_RESULT_BUDGET_HELPER}"
fi

echo
echo "Qwen3.6 main LLM gate completed."
print_gate_artifacts "completed"

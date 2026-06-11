#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the live Plan mode suite.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the live Plan mode suite.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the live Plan mode suite.}"

BASE_URL="${CAVERNO_LLM_BASE_URL}"
API_KEY="${CAVERNO_LLM_API_KEY}"
MODEL="${CAVERNO_LLM_MODEL}"
SCENARIOS="${CAVERNO_PLAN_MODE_SCENARIOS:-}"
TAGS="${CAVERNO_PLAN_MODE_TAGS:-}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORTER="${CAVERNO_PLAN_MODE_REPORTER:-compact}"
FAIL_ON_WARNINGS="${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-0}"
PREFLIGHT="${CAVERNO_PLAN_MODE_PREFLIGHT:-1}"
PREFLIGHT_TIMEOUT_SECONDS="${CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS:-5}"
LOG_TOOL_SCHEMAS="${CAVERNO_LLM_LOG_TOOL_SCHEMAS:-0}"
REPORT_ROOT="${CAVERNO_PLAN_MODE_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"

echo "Running Plan mode live scenarios"
echo "  Base URL: ${BASE_URL}"
echo "  Model: ${MODEL}"
echo "  Device: ${DEVICE}"
echo "  Fail on warnings: ${FAIL_ON_WARNINGS}"
echo "  Log tool schemas: ${LOG_TOOL_SCHEMAS}"
echo "  Report root: ${REPORT_ROOT}"
if [[ -n "${SCENARIOS}" ]]; then
  echo "  Scenarios: ${SCENARIOS}"
fi
if [[ -n "${TAGS}" ]]; then
  echo "  Tags: ${TAGS}"
fi
echo "  Endpoint preflight: ${PREFLIGHT}"

if [[ "${PREFLIGHT}" != "0" && "${PREFLIGHT}" != "false" && "${PREFLIGHT}" != "False" ]]; then
  MODELS_URL="${BASE_URL%/}/models"
  echo "Checking live endpoint: ${MODELS_URL}"
  if ! curl -fsS --max-time "${PREFLIGHT_TIMEOUT_SECONDS}" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${MODELS_URL}" >/dev/null; then
    echo "Live endpoint preflight failed: could not reach ${MODELS_URL}." >&2
    echo "Start the OpenAI-compatible server or set CAVERNO_PLAN_MODE_PREFLIGHT=0 to skip this check." >&2
    exit 78
  fi
  echo "Live endpoint preflight passed"
fi

cd "${ROOT_DIR}"

DART_DEFINES=()
if [[ "${LOG_TOOL_SCHEMAS}" == "1" || "${LOG_TOOL_SCHEMAS}" == "true" || "${LOG_TOOL_SCHEMAS}" == "True" ]]; then
  DART_DEFINES+=("--dart-define=CAVERNO_LLM_LOG_TOOL_SCHEMAS=true")
fi

export CAVERNO_PLAN_MODE_LIVE_LLM=1
export CAVERNO_LLM_BASE_URL="${BASE_URL}"
export CAVERNO_LLM_API_KEY="${API_KEY}"
export CAVERNO_LLM_MODEL="${MODEL}"
export CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}"
export CAVERNO_PLAN_MODE_TAGS="${TAGS}"
export CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}"
export CAVERNO_PLAN_MODE_REPORT_ROOT="${REPORT_ROOT}"

if [[ ${#DART_DEFINES[@]} -gt 0 ]]; then
  flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}" "${DART_DEFINES[@]}"
else
  flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"
fi

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Coding Weather Code live canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Coding Weather Code live canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Coding Weather Code live canary.}"

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
  DART_CMD=(fvm dart)
else
  FLUTTER_CMD=(flutter)
  DART_CMD=(dart)
fi

REPORT_ROOT="${CAVERNO_CODING_WEATHER_CODE_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/coding_weather_code_live_canary_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
REPORTER="json"

echo "Running Coding Weather Code live canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

set +e
CAVERNO_CODING_WEATHER_CODE_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
"${FLUTTER_CMD[@]}" test \
  tool/canaries/coding_weather_code_live_canary_test.dart \
  -r "${REPORTER}" > "${LOG_PATH}" 2>&1
TEST_STATUS=$?
set -e

set +e
"${DART_CMD[@]}" run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name coding_weather_code_live_canary \
  --surface coding_weather_code \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "tool/run_coding_weather_code_live_canary.sh"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Coding Weather Code live canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the browser save live canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the browser save live canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the browser save live canary.}"

REPORT_ROOT="${CAVERNO_BROWSER_SAVE_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/browser_save_live_canary_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
REPORTER="json"

echo "Running browser save live LLM canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"
echo "  Report directory: ${RUN_DIR}"
echo "  Fixture: tool/fixtures/browser_save_live_canary"
echo "  Safety boundary: no external website, no default Downloads write"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

set +e
CAVERNO_BROWSER_SAVE_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
flutter test tool/canaries/browser_save_live_llm_canary_test.dart -r "${REPORTER}" > "${LOG_PATH}" 2>&1
TEST_STATUS=$?
set -e

set +e
dart run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name browser_save_live_canary \
  --surface browser \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "tool/run_browser_save_live_canary.sh"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Browser save live LLM canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

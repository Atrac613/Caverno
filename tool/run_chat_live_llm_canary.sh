#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CANARY_NAME="${CAVERNO_CHAT_LIVE_CANARY_NAME:-chat_live_llm_canary}"
CANARY_COMMAND="${CAVERNO_CHAT_LIVE_CANARY_COMMAND:-tool/run_chat_live_llm_canary.sh}"
LLM_PROVIDER="${CAVERNO_LLM_PROVIDER:-openAiCompatible}"
if [[ "${LLM_PROVIDER}" == "appleFoundationModels" || "${LLM_PROVIDER}" == "apple_foundation_models" || "${LLM_PROVIDER}" == "foundation_models" ]]; then
  LLM_PROVIDER="appleFoundationModels"
  CAVERNO_LLM_BASE_URL="apple-foundation-models://local"
  CAVERNO_LLM_API_KEY=""
  CAVERNO_LLM_MODEL="apple-foundation-models"
  CAVERNO_FOUNDATION_MODELS_LIVE_CANARY=1
  FLUTTER_DEVICE_ARGS=(-d macos)
  TEST_TARGET="integration_test/chat_live_llm_canary_test.dart"
else
  LLM_PROVIDER="openAiCompatible"
  : "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Chat live LLM canary.}"
  : "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Chat live LLM canary.}"
  : "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Chat live LLM canary.}"
  CAVERNO_FOUNDATION_MODELS_LIVE_CANARY=0
  FLUTTER_DEVICE_ARGS=()
  TEST_TARGET="tool/canaries/chat_live_llm_canary_test.dart"
fi

REPORT_ROOT="${CAVERNO_CHAT_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/${CANARY_NAME}_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
REPORTER="json"

echo "Running Chat live LLM canary"
echo "  Canary: ${CANARY_NAME}"
echo "  Provider: ${LLM_PROVIDER}"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

set +e
FLUTTER_TEST_COMMAND=(flutter test)
if [[ "${#FLUTTER_DEVICE_ARGS[@]}" -gt 0 ]]; then
  FLUTTER_TEST_COMMAND+=("${FLUTTER_DEVICE_ARGS[@]}")
fi
FLUTTER_TEST_COMMAND+=("${TEST_TARGET}" -r "${REPORTER}")

CAVERNO_CHAT_LIVE_CANARY=1 \
CAVERNO_LLM_PROVIDER="${LLM_PROVIDER}" \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
CAVERNO_FOUNDATION_MODELS_LIVE_CANARY="${CAVERNO_FOUNDATION_MODELS_LIVE_CANARY:-0}" \
CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX="${CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX:-0}" \
"${FLUTTER_TEST_COMMAND[@]}" > "${LOG_PATH}" 2>&1
TEST_STATUS=$?
set -e

set +e
dart run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name "${CANARY_NAME}" \
  --surface chat \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "${CANARY_COMMAND}"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Chat live LLM canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

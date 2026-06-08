#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PROVIDER_NAME="${CAVERNO_LLM_PROVIDER:-openAiCompatible}"
if [[ "${PROVIDER_NAME}" == "appleFoundationModels" || "${PROVIDER_NAME}" == "apple_foundation_models" || "${PROVIDER_NAME}" == "foundation_models" ]]; then
  CAVERNO_LLM_PROVIDER="appleFoundationModels"
  CAVERNO_LLM_BASE_URL="apple-foundation-models://local"
  CAVERNO_LLM_API_KEY=""
  CAVERNO_LLM_MODEL="apple-foundation-models"
else
  CAVERNO_LLM_PROVIDER="openAiCompatible"
  : "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the chat background-process live canary.}"
  : "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the chat background-process live canary.}"
  : "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the chat background-process live canary.}"
fi

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
  DART_CMD=(fvm dart)
else
  FLUTTER_CMD=(flutter)
  DART_CMD=(dart)
fi

REPORT_ROOT="${CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/chat_background_process_live_canary_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
REPORTER="json"
REPEAT_COUNT="${CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT:-1}"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

echo "Running chat background-process live canary"
echo "  Provider: ${CAVERNO_LLM_PROVIDER}"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"
: > "${LOG_PATH}"

TEST_STATUS=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_label="$(printf 'run_%02d' "${index}")"
  run_log_path="${RUN_DIR}/${run_label}_flutter_test.jsonl"
  echo "Running ${run_label}/${REPEAT_COUNT}"

  set +e
  CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_CANARY=1 \
  CAVERNO_LLM_PROVIDER="${CAVERNO_LLM_PROVIDER}" \
  CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
  CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
  CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
  "${FLUTTER_CMD[@]}" test tool/canaries/chat_background_process_live_canary_test.dart -r "${REPORTER}" > "${run_log_path}" 2>&1
  run_status=$?
  set -e

  {
    echo "[CanaryRunner] ${run_label}"
    cat "${run_log_path}"
    if [[ "${run_status}" -ne 0 ]] && ! grep -Eq '"type"[[:space:]]*:[[:space:]]*"done"' "${run_log_path}"; then
      printf '{"success":false,"type":"done","time":0}\n'
    fi
  } >> "${LOG_PATH}"

  if [[ "${run_status}" -ne 0 ]]; then
    TEST_STATUS="${run_status}"
  fi
done

set +e
"${DART_CMD[@]}" run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name chat_background_process_live_canary \
  --surface chat_background_process \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT=${REPEAT_COUNT} tool/run_chat_background_process_live_canary.sh"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Chat background-process live canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Coding Verification Feedback live canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Coding Verification Feedback live canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Coding Verification Feedback live canary.}"

if [[ "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK:-}" != "1" ]]; then
  echo "Set CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 after confirming this live canary may send prompts, temporary code-edit context, and tool results to ${CAVERNO_LLM_BASE_URL}." >&2
  exit 64
fi

REPORT_ROOT="${CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/coding_verification_feedback_live_canary_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
WORK_ROOT="${RUN_DIR}/workspace"
REPORTER="json"
REPEAT_COUNT="${CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT:-1}"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

echo "Running Coding Verification Feedback live canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report directory: ${RUN_DIR}"
echo "  Workspace root: ${WORK_ROOT}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"
: > "${LOG_PATH}"

TEST_STATUS=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_label="$(printf 'run_%02d' "${index}")"
  run_log_path="${RUN_DIR}/${run_label}_flutter_test.jsonl"
  run_work_root="${WORK_ROOT}/${run_label}"
  echo "Running ${run_label}/${REPEAT_COUNT}"

  set +e
  CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_CANARY=1 \
  CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_RUN_LABEL="${run_label}" \
  CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_WORK_ROOT="${run_work_root}" \
  CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
  CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
  CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
  flutter test tool/canaries/coding_verification_feedback_live_canary_test.dart -r "${REPORTER}" > "${run_log_path}" 2>&1
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
dart run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name coding_verification_feedback_live_canary \
  --surface coding_verification_feedback \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT=${REPEAT_COUNT} tool/run_coding_verification_feedback_live_canary.sh"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Coding Verification Feedback live canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

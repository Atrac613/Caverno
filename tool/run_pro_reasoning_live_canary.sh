#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK:?Set CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 after approving live LLM data export.}"
if [[ "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK}" != "1" ]]; then
  echo "CAVERNO_LIVE_LLM_DATA_EXPORT_ACK must equal 1." >&2
  exit 2
fi
: "${CAVERNO_LLM_BASE_URL:?Set the primary loaded-model endpoint.}"
: "${CAVERNO_LLM_API_KEY:?Set the primary endpoint API key.}"
: "${CAVERNO_LLM_MODEL:?Set the primary loaded model.}"
: "${CAVERNO_PRO_REASONING_SECONDARY_BASE_URL:?Set the secondary loaded-model endpoint.}"
: "${CAVERNO_PRO_REASONING_SECONDARY_API_KEY:?Set the secondary endpoint API key.}"
: "${CAVERNO_PRO_REASONING_SECONDARY_MODEL:?Set the secondary loaded model.}"

REPORT_ROOT="${CAVERNO_PRO_REASONING_LIVE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_DIR="${REPORT_ROOT}/pro_reasoning_live_canary_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.log"
SCENARIOS="${CAVERNO_PRO_REASONING_SCENARIOS:-multi_host,single_host,cancel}"

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

echo "Running Pro Reasoning live canary"
echo "  Primary base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Primary model: ${CAVERNO_LLM_MODEL}"
echo "  Secondary base URL: ${CAVERNO_PRO_REASONING_SECONDARY_BASE_URL}"
echo "  Secondary model: ${CAVERNO_PRO_REASONING_SECONDARY_MODEL}"
echo "  Scenarios: ${SCENARIOS}"
echo "  Report directory: ${RUN_DIR}"

FLUTTER_TEST=(flutter test)
if command -v fvm >/dev/null 2>&1; then
  FLUTTER_TEST=(fvm flutter test)
fi

set +e
CAVERNO_PRO_REASONING_LIVE_CANARY=1 \
CAVERNO_PRO_REASONING_LIVE_CANARY_DIR="${RUN_DIR}" \
CAVERNO_PRO_REASONING_SCENARIOS="${SCENARIOS}" \
CAVERNO_SESSION_LOG_DIR="${RUN_DIR}/session_logs" \
"${FLUTTER_TEST[@]}" tool/canaries/pro_reasoning_live_canary_test.dart \
  --reporter expanded 2>&1 | tee "${LOG_PATH}"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [[ "${TEST_STATUS}" -ne 0 ]]; then
  echo "Pro Reasoning live canary failed. Log: ${LOG_PATH}" >&2
  exit "${TEST_STATUS}"
fi

echo "Pro Reasoning live canary passed."
echo "Evidence: ${RUN_DIR}/canary_evidence.json"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the LL22 canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the LL22 canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the LL22 canary.}"

ARM="${CAVERNO_LL22_WARMUP_ARM:-warm}"
if [[ "${ARM}" != "cold" && "${ARM}" != "warm" ]]; then
  echo "CAVERNO_LL22_WARMUP_ARM must be cold or warm." >&2
  exit 64
fi

REPORT_ROOT="${CAVERNO_LL22_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_DIR="${CAVERNO_LL22_REPORT_DIR:-${REPORT_ROOT}/ll22_production_warmup_${ARM}_$(date +%s)}"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
mkdir -p "${RUN_DIR}"

echo "Running LL22 production warm-up canary"
echo "  Arm: ${ARM}"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
CAVERNO_LL22_PRODUCTION_WARMUP_CANARY=1 \
CAVERNO_LL22_WARMUP_ARM="${ARM}" \
CAVERNO_LL22_REPORT_DIR="${RUN_DIR}" \
CAVERNO_LL22_PROJECT_ROOT="${CAVERNO_LL22_PROJECT_ROOT:-${ROOT_DIR}}" \
CAVERNO_LL22_MCP_CONFIG_PATH="${CAVERNO_LL22_MCP_CONFIG_PATH:-}" \
fvm flutter test tool/canaries/chat_live_llm_canary_test.dart \
  --plain-name "LL22 production warm-up primes the first ChatNotifier turn" \
  -r json > "${LOG_PATH}" 2>&1

echo "LL22 artifact: ${RUN_DIR}/ll22_production_warmup.json"

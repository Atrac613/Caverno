#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the chat search grounding eval.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the chat search grounding eval.}"

MODEL_LIST="${CAVERNO_CHAT_SEARCH_GROUNDING_MODELS:-qwen3.6-27b-mtp-vision qwen3.6-35b-a3b-vision}"
TEMPERATURE="${CAVERNO_CHAT_SEARCH_GROUNDING_TEMPERATURE:-0.2}"
MAX_TOKENS="${CAVERNO_CHAT_SEARCH_GROUNDING_MAX_TOKENS:-8192}"
TIMEOUT_SECONDS="${CAVERNO_CHAT_SEARCH_GROUNDING_TIMEOUT_SECONDS:-180}"
REPORT_ROOT="${CAVERNO_CHAT_SEARCH_GROUNDING_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports/chat_search_grounding_eval}}"
RUN_DIR="${REPORT_ROOT}/chat_search_grounding_eval_$(date +%s)"

read -r -a MODELS <<< "${MODEL_LIST}"
if [[ "${#MODELS[@]}" -eq 0 ]]; then
  echo "No models configured in CAVERNO_CHAT_SEARCH_GROUNDING_MODELS." >&2
  exit 64
fi

echo "Running chat search grounding eval"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Models: ${MODELS[*]}"
echo "  Temperature: ${TEMPERATURE}"
echo "  Max tokens: ${MAX_TOKENS}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

ARGS=(
  run
  "${ROOT_DIR}/tool/chat_search_grounding_eval.dart"
  --base-url "${CAVERNO_LLM_BASE_URL}"
  --api-key "${CAVERNO_LLM_API_KEY}"
  --out-dir "${RUN_DIR}"
  --temperature "${TEMPERATURE}"
  --max-tokens "${MAX_TOKENS}"
  --timeout-seconds "${TIMEOUT_SECONDS}"
)

for model in "${MODELS[@]}"; do
  ARGS+=(--model "${model}")
done

dart "${ARGS[@]}"


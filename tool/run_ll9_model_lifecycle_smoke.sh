#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

REPORT_ROOT="${CAVERNO_LL9_MODEL_LIFECYCLE_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/ll9_model_lifecycle_smoke_$(date +%s)"
OUT_JSON="${RUN_DIR}/canary_summary.json"
OUT_MD="${RUN_DIR}/canary_summary.md"
BASE_URL="${CAVERNO_LLM_BASE_URL:-http://localhost:1234/v1}"
FROM_MODEL="${CAVERNO_LL9_FROM_MODEL:-}"
TO_MODEL="${CAVERNO_LL9_TO_MODEL:-}"
RESTORE="${CAVERNO_LL9_RESTORE:-1}"
POLL_TIMEOUT_SECONDS="${CAVERNO_LL9_POLL_TIMEOUT_SECONDS:-180}"
POLL_INTERVAL_MS="${CAVERNO_LL9_POLL_INTERVAL_MS:-2000}"

echo "Running LL9 model lifecycle smoke"
echo "  Base URL: ${BASE_URL}"
echo "  From model: ${FROM_MODEL}"
echo "  To model: ${TO_MODEL}"
echo "  Restore: ${RESTORE}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

ARGS=(
  run
  "${ROOT_DIR}/tool/ll9_model_lifecycle_smoke.dart"
  --base-url
  "${BASE_URL}"
  --from-model
  "${FROM_MODEL}"
  --to-model
  "${TO_MODEL}"
  --poll-timeout-seconds
  "${POLL_TIMEOUT_SECONDS}"
  --poll-interval-ms
  "${POLL_INTERVAL_MS}"
  --out-json
  "${OUT_JSON}"
  --out-md
  "${OUT_MD}"
)

if [[ -n "${CAVERNO_LLM_API_KEY:-}" ]]; then
  ARGS+=(--api-key "${CAVERNO_LLM_API_KEY}")
fi

if [[ "${RESTORE}" == "1" ||
  "${RESTORE}" == "true" ||
  "${RESTORE}" == "yes" ]]; then
  ARGS+=(--restore)
else
  ARGS+=(--no-restore)
fi

dart "${ARGS[@]}"

echo "LL9 model lifecycle smoke JSON: ${OUT_JSON}"
echo "LL9 model lifecycle smoke Markdown: ${OUT_MD}"

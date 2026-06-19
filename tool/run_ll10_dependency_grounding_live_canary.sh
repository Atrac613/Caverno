#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FIXTURE_RESPONSE="${CAVERNO_LL10_DEPENDENCY_GROUNDING_LIVE_CANARY_FIXTURE_RESPONSE:-0}"
if [[ "${FIXTURE_RESPONSE}" != "1" ]]; then
  : "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the LL10 dependency grounding live canary.}"
  : "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the LL10 dependency grounding live canary.}"
fi

REPORT_ROOT="${CAVERNO_LL10_DEPENDENCY_GROUNDING_LIVE_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/ll10_dependency_grounding_live_canary_$(date +%s)"
OUT_JSON="${RUN_DIR}/canary_summary.json"
OUT_MD="${RUN_DIR}/canary_summary.md"

echo "Running LL10 dependency grounding live canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL:-fixture-response}"
echo "  Model: ${CAVERNO_LLM_MODEL:-fixture-response}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

ARGS=(
  run
  "${ROOT_DIR}/tool/ll10_dependency_grounding_live_canary.dart"
  --out-json
  "${OUT_JSON}"
  --out-md
  "${OUT_MD}"
)

if [[ "${FIXTURE_RESPONSE}" == "1" ]]; then
  ARGS+=(--fixture-response)
else
  ARGS+=(
    --base-url
    "${CAVERNO_LLM_BASE_URL}"
    --api-key
    "${CAVERNO_LLM_API_KEY:-}"
    --model
    "${CAVERNO_LLM_MODEL}"
  )
fi

dart "${ARGS[@]}"

echo "LL10 dependency grounding live canary JSON: ${OUT_JSON}"
echo "LL10 dependency grounding live canary Markdown: ${OUT_MD}"

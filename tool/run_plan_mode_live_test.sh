#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

BASE_URL="${CAVERNO_LLM_BASE_URL:-http://192.168.100.241:1234/v1}"
API_KEY="${CAVERNO_LLM_API_KEY:-no-key}"
MODEL="${CAVERNO_LLM_MODEL:-gemma-4-26B-A4B-it-Q4_K_M.gguf}"
SCENARIOS="${CAVERNO_PLAN_MODE_SCENARIOS:-}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORTER="${CAVERNO_PLAN_MODE_REPORTER:-compact}"

echo "Running Plan mode live scenarios"
echo "  Base URL: ${BASE_URL}"
echo "  Model: ${MODEL}"
echo "  Device: ${DEVICE}"
if [[ -n "${SCENARIOS}" ]]; then
  echo "  Scenarios: ${SCENARIOS}"
fi

cd "${ROOT_DIR}"

CAVERNO_PLAN_MODE_LIVE_LLM=1 \
CAVERNO_LLM_BASE_URL="${BASE_URL}" \
CAVERNO_LLM_API_KEY="${API_KEY}" \
CAVERNO_LLM_MODEL="${MODEL}" \
CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}" \
flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"

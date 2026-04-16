#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the live Plan mode suite.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the live Plan mode suite.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the live Plan mode suite.}"

BASE_URL="${CAVERNO_LLM_BASE_URL}"
API_KEY="${CAVERNO_LLM_API_KEY}"
MODEL="${CAVERNO_LLM_MODEL}"
SCENARIOS="${CAVERNO_PLAN_MODE_SCENARIOS:-}"
TAGS="${CAVERNO_PLAN_MODE_TAGS:-}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORTER="${CAVERNO_PLAN_MODE_REPORTER:-compact}"
FAIL_ON_WARNINGS="${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-0}"

echo "Running Plan mode live scenarios"
echo "  Base URL: ${BASE_URL}"
echo "  Model: ${MODEL}"
echo "  Device: ${DEVICE}"
echo "  Fail on warnings: ${FAIL_ON_WARNINGS}"
if [[ -n "${SCENARIOS}" ]]; then
  echo "  Scenarios: ${SCENARIOS}"
fi
if [[ -n "${TAGS}" ]]; then
  echo "  Tags: ${TAGS}"
fi

cd "${ROOT_DIR}"

CAVERNO_PLAN_MODE_LIVE_LLM=1 \
CAVERNO_LLM_BASE_URL="${BASE_URL}" \
CAVERNO_LLM_API_KEY="${API_KEY}" \
CAVERNO_LLM_MODEL="${MODEL}" \
CAVERNO_PLAN_MODE_SCENARIOS="${SCENARIOS}" \
CAVERNO_PLAN_MODE_TAGS="${TAGS}" \
CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}" \
flutter test integration_test/plan_mode_scenario_test.dart -d "${DEVICE}" -r "${REPORTER}"

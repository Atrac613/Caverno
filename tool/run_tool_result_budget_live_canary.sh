#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the tool result budget live canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the tool result budget live canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the tool result budget live canary.}"

cd "${ROOT_DIR}"

CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY=1 \
flutter test tool/canaries/tool_result_budget_live_llm_canary_test.dart -r compact

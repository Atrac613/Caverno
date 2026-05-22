#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Chat live LLM canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Chat live LLM canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Chat live LLM canary.}"

REPORTER="${CAVERNO_CHAT_LIVE_CANARY_REPORTER:-compact}"

echo "Running Chat live LLM canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Reporter: ${REPORTER}"

cd "${ROOT_DIR}"

CAVERNO_CHAT_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
flutter test tool/canaries/chat_live_llm_canary_test.dart -r "${REPORTER}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export CAVERNO_LLM_PROVIDER="appleFoundationModels"
export CAVERNO_FOUNDATION_MODELS_LIVE_CANARY=1
export CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX=1
export CAVERNO_CHAT_LIVE_CANARY_NAME="${CAVERNO_CHAT_LIVE_CANARY_NAME:-foundation_models_live_canary}"
export CAVERNO_CHAT_LIVE_CANARY_COMMAND="tool/run_foundation_models_live_canary.sh"

exec "${ROOT_DIR}/tool/run_chat_live_llm_canary.sh"

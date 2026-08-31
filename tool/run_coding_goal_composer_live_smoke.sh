#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Coding Goal composer live smoke.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Coding Goal composer live smoke.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Coding Goal composer live smoke.}"

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
else
  FLUTTER_CMD=(flutter)
fi

BUILD_COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
BUILD_DIRTY=false
if ! git -C "${ROOT_DIR}" diff --quiet ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet ||
  [ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]; then
  BUILD_DIRTY=true
fi
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Running Coding Goal composer live smoke"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"

SESSION_LOG_ROOT="${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}/coding_goal_composer_live_smoke_$(date +%s)/session_logs"
echo "  Session logs: ${SESSION_LOG_ROOT}"

cd "${ROOT_DIR}"
mkdir -p "${SESSION_LOG_ROOT}"

CAVERNO_CODING_GOAL_COMPOSER_LIVE_SMOKE=1 \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
"${FLUTTER_CMD[@]}" test \
  --dart-define="CAVERNO_BUILD_COMMIT=${BUILD_COMMIT}" \
  --dart-define="CAVERNO_BUILD_DIRTY=${BUILD_DIRTY}" \
  --dart-define="CAVERNO_BUILD_TIME=${BUILD_TIME}" \
  tool/canaries/coding_goal_composer_live_smoke_test.dart \
  --reporter expanded

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the exact-short Markdown TOC live canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the exact-short Markdown TOC live canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the exact-short Markdown TOC live canary.}"

REPORT_ROOT="${CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/coding_markdown_toc_exact_short_live_canary_$(date +%s)"
WORK_ROOT="${RUN_DIR}/workspace"
SESSION_LOG_ROOT="${RUN_DIR}/session_logs"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
  DART_CMD=(fvm dart)
else
  FLUTTER_CMD=(flutter)
  DART_CMD=(dart)
fi

BUILD_COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
BUILD_DIRTY=false
if ! git -C "${ROOT_DIR}" diff --quiet ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet ||
  [ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]; then
  BUILD_DIRTY=true
fi
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "Running Coding Markdown TOC exact-short live canary"
echo "  Prompt: exact short Japanese"
echo "  Language: Dart"
echo "  Fixture: markdown_toc_generator.md"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${WORK_ROOT}" "${SESSION_LOG_ROOT}"

set +e
CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
CAVERNO_CODING_GOAL_TODO_WORK_ROOT="${WORK_ROOT}" \
CAVERNO_CODING_GOAL_TODO_SESSION_LOG_ROOT="${SESSION_LOG_ROOT}" \
CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
"${FLUTTER_CMD[@]}" test \
  --dart-define="CAVERNO_BUILD_COMMIT=${BUILD_COMMIT}" \
  --dart-define="CAVERNO_BUILD_DIRTY=${BUILD_DIRTY}" \
  --dart-define="CAVERNO_BUILD_TIME=${BUILD_TIME}" \
  tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart \
  --plain-name "live LLM assembles the markdown_toc_generator.md MVP from the exact short prompt" \
  -r json >"${LOG_PATH}" 2>&1
TEST_STATUS=$?
set -e

set +e
"${DART_CMD[@]}" run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name coding_markdown_toc_exact_short_live_canary \
  --surface coding_mvp \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "tool/run_coding_markdown_toc_exact_short_live_canary.sh"
SUMMARY_STATUS=$?
set -e

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Coding Markdown TOC exact-short live canary failed."
  echo "  Flutter JSON log: ${LOG_PATH}"
  echo "  Session logs: ${SESSION_LOG_ROOT}"
  exit "${TEST_STATUS}"
fi

echo "Coding Markdown TOC exact-short live canary passed."
echo "  Flutter JSON log: ${LOG_PATH}"
echo "  Session logs: ${SESSION_LOG_ROOT}"
exit "${SUMMARY_STATUS}"

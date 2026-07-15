#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the headless TODO canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the headless TODO canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the headless TODO canary.}"

REPORT_ROOT="${CAVERNO_PLAN_MODE_TODO_HEADLESS_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/plan_mode_todo_app_headless_live_canary_$(date +%s)"
SESSION_LOG_ROOT="${RUN_DIR}/session_logs"
PLAN_REPORT_ROOT="${RUN_DIR}/plan_mode"
SUMMARY_PATH="${RUN_DIR}/headless_canary_summary.json"

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  DART_CMD=(fvm dart)
else
  DART_CMD=(dart)
fi

mkdir -p "${SESSION_LOG_ROOT}" "${PLAN_REPORT_ROOT}"

echo "Running headless TODO app Live canary"
echo "  Scenario: live_todo_app_plan_completion"
echo "  Prompt: exact short Japanese"
echo "  Language: Dart"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"
echo "  Session logs: ${SESSION_LOG_ROOT}"

cd "${ROOT_DIR}"

CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
CAVERNO_PLAN_MODE_REPORT_ROOT="${PLAN_REPORT_ROOT}" \
CAVERNO_PLAN_MODE_SCENARIOS=live_todo_app_plan_completion \
CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1 \
CAVERNO_PLAN_MODE_DEVICE=headless \
"${ROOT_DIR}/tool/run_plan_mode_live_test.sh"

SUITE_REPORT="${PLAN_REPORT_ROOT}/plan_mode_live_suite_headless_report.json"
python3 - "${SUITE_REPORT}" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
if not report_path.is_file():
    print(f"Missing headless TODO canary suite report: {report_path}", file=sys.stderr)
    sys.exit(1)

report = json.loads(report_path.read_text())
quality = report.get("reportQualitySummary") or {}
blocker_count = quality.get("blockerCount")
if quality.get("ready") is not True or blocker_count != 0:
    print(
        f"Headless TODO canary report quality is blocked: {blocker_count} blocker(s)",
        file=sys.stderr,
    )
    sys.exit(1)
PY

"${DART_CMD[@]}" run "${ROOT_DIR}/tool/plan_mode_headless_canary_summary.dart" \
  --suite-report "${SUITE_REPORT}" \
  --session-log-root "${SESSION_LOG_ROOT}" \
  --out "${SUMMARY_PATH}"

echo "Headless TODO app Live canary passed."
echo "  Report directory: ${RUN_DIR}"
echo "  Summary: ${SUMMARY_PATH}"

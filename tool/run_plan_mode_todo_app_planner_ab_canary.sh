#!/usr/bin/env bash
#
# Planner A/B canary: runs the production-path TODO plan-mode scenario once and
# reports the numbers the two arms are compared on.
#
#   Baseline arm : primary model drafts the plan it will execute.
#   Planner arm  : set CAVERNO_PLANNING_BASE_URL + CAVERNO_PLANNING_MODEL
#                  (+ CAVERNO_PLANNING_API_KEY) to route plan drafting to
#                  another endpoint while execution stays on the primary.
#
# The arm is verified against the session logs after the run, not assumed: a
# mis-wired harness that quietly ran both phases on one model would otherwise
# produce a confident, wrong measurement.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL (execution endpoint).}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY (execution endpoint).}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL (execution model).}"

PLANNING_MODEL="${CAVERNO_PLANNING_MODEL:-}"
PLANNING_BASE_URL="${CAVERNO_PLANNING_BASE_URL:-}"
if [[ -n "${PLANNING_MODEL}" && -n "${PLANNING_BASE_URL}" ]]; then
  ARM="planner"
  EXPECTED_PLANNING_MODEL="${PLANNING_MODEL}"
else
  ARM="baseline"
  EXPECTED_PLANNING_MODEL="${CAVERNO_LLM_MODEL}"
fi

REPORT_ROOT="${CAVERNO_PLAN_MODE_TODO_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/plan_mode_todo_planner_ab_${ARM}_$(date +%s)"
SESSION_LOG_ROOT="${RUN_DIR}/session_logs"
PLAN_REPORT_ROOT="${RUN_DIR}/plan_mode"

mkdir -p "${SESSION_LOG_ROOT}" "${PLAN_REPORT_ROOT}"

echo "Running planner A/B TODO canary"
echo "  Arm: ${ARM}"
echo "  Execution model: ${CAVERNO_LLM_MODEL} @ ${CAVERNO_LLM_BASE_URL}"
echo "  Planning model:  ${EXPECTED_PLANNING_MODEL} @ ${PLANNING_BASE_URL:-${CAVERNO_LLM_BASE_URL}}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"

STARTED_AT=$(date +%s)
set +e
CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
CAVERNO_PLAN_MODE_REPORT_ROOT="${PLAN_REPORT_ROOT}" \
CAVERNO_PLAN_MODE_SCENARIOS=live_todo_app_plan_completion \
CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=0 \
"${ROOT_DIR}/tool/run_plan_mode_live_test.sh"
RUN_STATUS=$?
set -e
FINISHED_AT=$(date +%s)

python3 "${ROOT_DIR}/tool/plan_mode_planner_ab_summary.py" \
  --session-logs "${SESSION_LOG_ROOT}" \
  --suite-report "${PLAN_REPORT_ROOT}/plan_mode_live_suite_macos_report.json" \
  --arm "${ARM}" \
  --expected-planning-model "${EXPECTED_PLANNING_MODEL}" \
  --expected-execution-model "${CAVERNO_LLM_MODEL}" \
  --wall-clock-seconds "$((FINISHED_AT - STARTED_AT))" \
  --run-status "${RUN_STATUS}" \
  --output "${RUN_DIR}/planner_ab_summary.json"

echo "Summary written to ${RUN_DIR}/planner_ab_summary.json"
exit "${RUN_STATUS}"

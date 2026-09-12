#!/usr/bin/env bash

# Runs the planning half and the Anabasis parent turn as one live canary, then
# decides the Anabasis half from the session log rather than from the app log.
#
# The split is forced by the request logger, which truncates message content at
# 200 characters: the parent's delegation queue and the saved task contract are
# system-prompt and child-prompt text, so they never reach the app log the
# scenario's own expectations read. They do reach the session log, which is why
# check_fix_firings.py runs here against this run's own log directory.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Anabasis delegation canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Anabasis delegation canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Anabasis delegation canary.}"

REPORT_ROOT="${CAVERNO_ANABASIS_DELEGATION_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/anabasis_delegation_live_canary_$(date +%s)"
SESSION_LOG_ROOT="${RUN_DIR}/session_logs"
PLAN_REPORT_ROOT="${RUN_DIR}/plan_mode"

mkdir -p "${SESSION_LOG_ROOT}" "${PLAN_REPORT_ROOT}"

echo "Running Anabasis delegation Live canary"
echo "  Scenario: live_anabasis_delegation_admission"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"
echo "  Session logs: ${SESSION_LOG_ROOT}"

cd "${ROOT_DIR}"

CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
CAVERNO_PLAN_MODE_REPORT_ROOT="${PLAN_REPORT_ROOT}" \
CAVERNO_PLAN_MODE_SCENARIOS=live_anabasis_delegation_admission \
CAVERNO_PLAN_MODE_DEVICE=headless \
"${ROOT_DIR}/tool/run_plan_mode_live_test.sh"

# The canary's own question, and the one the scenario cannot answer: was the
# child bound to a ready saved task, or merely spawned? A spawn proves
# delegation happened; only the admitted contract proves planned work was
# selected from the queue.
echo
echo "Checking the delegation admission signatures against this run's logs"
FIRINGS_OUTPUT="$(python3 "${ROOT_DIR}/tool/check_fix_firings.py" --dir "${SESSION_LOG_ROOT}")"
echo "${FIRINGS_OUTPUT}"

if ! printf '%s\n' "${FIRINGS_OUTPUT}" | grep -q '^\[FIRED\] anabasis_delegation_admitted'; then
  echo >&2
  echo "Anabasis delegation canary failed: the parent never delegated a ready saved task." >&2
  echo "  A spawned child alone does not close ANA2's evidence gap." >&2
  echo "  Session logs: ${SESSION_LOG_ROOT}" >&2
  exit 1
fi

echo
echo "Anabasis delegation Live canary passed."
echo "  Report directory: ${RUN_DIR}"
echo "  Session logs: ${SESSION_LOG_ROOT}"

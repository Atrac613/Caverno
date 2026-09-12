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

RUN_LOG="${RUN_DIR}/scenario_run.log"
# The scenario is allowed to fail here. Its failure is one input to the verdict
# below, not the verdict: a run whose plan offered nothing to delegate fails the
# scenario and still says nothing about the parent. Without this, pipefail would
# abort before the case this script exists to tell apart.
set +e
CAVERNO_SESSION_LOG_DIR="${SESSION_LOG_ROOT}" \
CAVERNO_PLAN_MODE_REPORT_ROOT="${PLAN_REPORT_ROOT}" \
CAVERNO_PLAN_MODE_SCENARIOS=live_anabasis_delegation_admission \
CAVERNO_PLAN_MODE_DEVICE=headless \
"${ROOT_DIR}/tool/run_plan_mode_live_test.sh" 2>&1 | tee "${RUN_LOG}"
SCENARIO_STATUS="${PIPESTATUS[0]}"
set -e

# Three outcomes, not two. Whether the ready queue is non-empty depends on the
# plan the model wrote -- an independent task opens it, a pure chain does not --
# so an empty queue is inconclusive about the parent and must not be reported as
# a regression. Only a queue that was offered and not taken is a failure.
QUEUE_SIZE="$(sed -n 's/.*\[Scenario\] Delegation queue offers \([0-9]\{1,\}\) ready task.*/\1/p' "${RUN_LOG}" | tail -1 || true)"
QUEUE_SIZE="${QUEUE_SIZE:-0}"

echo
echo "Checking the delegation admission signatures against this run's logs"
FIRINGS_OUTPUT="$(python3 "${ROOT_DIR}/tool/check_fix_firings.py" --dir "${SESSION_LOG_ROOT}")"
echo "${FIRINGS_OUTPUT}"

ADMITTED=0
if printf '%s\n' "${FIRINGS_OUTPUT}" | grep -q '^\[FIRED\] anabasis_delegation_admitted'; then
  ADMITTED=1
fi

ACCEPTED=0
if printf '%s\n' "${FIRINGS_OUTPUT}" | grep -q '^\[FIRED\] anabasis_acceptance_recorded'; then
  ACCEPTED=1
fi

echo
echo "  Ready tasks offered to the parent: ${QUEUE_SIZE}"
echo "  Delegation admitted: ${ADMITTED}"
echo "  Acceptance recorded: ${ACCEPTED}"

# Reported, not gated. Delegation is the one thing this run can demand: whether
# the parent also gets as far as recording a judgement depends on a longer chain
# the canary does not control, and failing on it would retire a working gate for
# a model's pacing. Surfacing the refusal codes is what makes a run that stopped
# short diagnosable instead of merely short.
if [[ "${ACCEPTED}" == "0" ]]; then
  # `|| true` is load-bearing: a grep that matches nothing exits 1, and under
  # `set -e` an assignment from it aborts the script -- which killed the
  # inconclusive branch below and reported a run with no ready task as a
  # failure, the exact confusion the three-way verdict exists to prevent.
  REFUSALS="$(grep -rhoE '"code":"acceptance_[a-z_]+"' "${SESSION_LOG_ROOT}" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
  # Whether the question was even asked. The elicitation prompt is queued
  # rather than sent when the delegation turn is still streaming, so two runs
  # reported "never attempted" for a turn the model never received -- a claim
  # about the model that neither run had earned.
  DELIVERED="$(sed -n 's/.*\[Scenario\] Extra follow-up turns delivered=\([0-9]\{1,\}\)\/\([0-9]\{1,\}\).*/\1 \2/p' "${RUN_LOG}" | tail -1 || true)"
  DELIVERED_COUNT="${DELIVERED%% *}"
  WANTED_COUNT="${DELIVERED##* }"
  # Attempts, from the app log. A refusal that fires before the handler carries
  # none of the acceptance_* codes above -- the parent authority guard refused
  # accept_task in 0 ms once -- so a run that reported "never attempted" had in
  # fact attempted and been refused by something this capture could not see.
  ATTEMPTS="$(grep -c '\[Tool\] Executing tool: accept_task' "${RUN_LOG}" 2>/dev/null || true)"
  ATTEMPTS="${ATTEMPTS:-0}"
  if [[ -n "${REFUSALS}" ]]; then
    echo "  Acceptance refused with: ${REFUSALS}"
  elif [[ "${ATTEMPTS}" != "0" ]]; then
    echo "  Acceptance attempted ${ATTEMPTS} time(s) and recorded none:"
    echo "    something refused it before the acceptance handler. Read the"
    echo "    refusal codes in the session log."
  elif [[ -n "${WANTED_COUNT}" && "${WANTED_COUNT}" != "0" && "${DELIVERED_COUNT}" == "0" ]]; then
    echo "  The parent was never asked: the acceptance turn was not delivered"
    echo "    (${DELIVERED_COUNT}/${WANTED_COUNT}); the delegation turn was still"
    echo "    in flight, so this run says nothing about acceptance."
  else
    echo "  The parent never attempted an acceptance."
  fi
fi

if [[ "${ADMITTED}" == "1" ]]; then
  echo
  echo "Anabasis delegation Live canary passed."
  echo "  Report directory: ${RUN_DIR}"
  echo "  Session logs: ${SESSION_LOG_ROOT}"
  exit 0
fi

if [[ "${QUEUE_SIZE}" == "0" ]]; then
  echo >&2
  echo "Anabasis delegation canary inconclusive: the saved plan offered no ready task." >&2
  echo "  The parent was shown nothing to delegate, so this run says nothing about it." >&2
  echo "  Re-run; a plan with an independent first task opens the queue." >&2
  echo "  Session logs: ${SESSION_LOG_ROOT}" >&2
  exit 77
fi

echo >&2
echo "Anabasis delegation canary FAILED: ${QUEUE_SIZE} ready task(s) were offered" >&2
echo "  and the parent delegated none of them through the admission gate." >&2
echo "  A spawned child alone does not close ANA2's evidence gap." >&2
echo "  Scenario status: ${SCENARIO_STATUS}" >&2
echo "  Session logs: ${SESSION_LOG_ROOT}" >&2
exit 1

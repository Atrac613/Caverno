#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the PM5 live gate.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the PM5 live gate.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the PM5 live gate.}"

LIVE_TEST_HELPER="${CAVERNO_PLAN_MODE_LIVE_TEST_HELPER:-${ROOT_DIR}/tool/run_plan_mode_live_test.sh}"
PING_CANARY_HELPER="${CAVERNO_PLAN_MODE_PING_CLI_CANARY_HELPER:-${ROOT_DIR}/tool/run_plan_mode_ping_cli_live_canary.sh}"
DEVICE="${CAVERNO_PLAN_MODE_DEVICE:-macos}"
REPORTER="${CAVERNO_PLAN_MODE_REPORTER:-compact}"
FAIL_ON_WARNINGS="${CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS:-1}"
SMOKE_SCENARIOS="${CAVERNO_PLAN_MODE_PM5_SMOKE_SCENARIOS:-}"
SMOKE_TAGS="${CAVERNO_PLAN_MODE_PM5_SMOKE_TAGS:-smoke}"
PING_REPEAT_COUNT="${CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT:-${CAVERNO_PLAN_MODE_REPEAT_COUNT:-1}}"
REPORT_ROOT="${CAVERNO_PLAN_MODE_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
DEFAULT_PING_PROMPT="Create a Python CLI script that pings a specific host. Generate a reviewable plan first. The approved plan must contain exactly one implementation task. That task must create only the root-level ping_cli.py file. Do not create README.md, requirements.txt, test files, or any other project files. Implement until that single approved task finishes, validate with python3 ping_cli.py --help, then provide a final answer summarizing ping_cli.py and validation evidence unless you are genuinely blocked."
PING_PROMPT="${1:-${CAVERNO_PLAN_MODE_USER_PROMPT:-${DEFAULT_PING_PROMPT}}}"
SKIP_SMOKE="${CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE:-0}"
SKIP_PING_CANARY="${CAVERNO_PLAN_MODE_PM5_SKIP_PING_CANARY:-0}"

latest_report_file() {
  local pattern="$1"
  if [[ ! -d "${REPORT_ROOT}" ]]; then
    return 0
  fi
  find "${REPORT_ROOT}" -type f -name "${pattern}" -print 2>/dev/null | sort | tail -n 1
}

print_report_file() {
  local label="$1"
  local pattern="$2"
  local path
  path="$(latest_report_file "${pattern}")"
  if [[ -n "${path}" ]]; then
    echo "  ${label}: ${path}"
  else
    echo "  ${label}: not found (${REPORT_ROOT}/${pattern})"
  fi
}

print_pm5_gate_artifacts() {
  local status_label="$1"
  echo
  echo "PM5 live gate triage artifacts (${status_label})"
  echo "  Report root: ${REPORT_ROOT}"
  print_report_file "Live suite JSON" "plan_mode_live_suite*_report.json"
  print_report_file "Live suite Markdown" "plan_mode_live_suite*_report.md"
  print_report_file "Ping canary summary JSON" "canary_summary.json"
  print_report_file "Ping canary summary Markdown" "canary_summary.md"
  print_report_file "Ping canary run suite report" "run_*_suite_report.json"
  print_report_file "Ping canary run log" "run_*_run.log"
  echo "  Release checklist: ${ROOT_DIR}/docs/plan_mode_release_readiness_checklist.md"
  echo "  Stabilization playbook: ${ROOT_DIR}/docs/plan_mode_ping_cli_stabilization_playbook.md"
  echo
  echo "Investigation order"
  echo "  1. Check endpoint/model prerequisites if no report artifacts were written."
  echo "  2. Open the latest canary_summary.md for failed run rows and failure classes."
  echo "  3. Open the matching canary_summary.json for warning, quality, and task drift fields."
  echo "  4. Open the run_*_suite_report.json linked by the failed row."
  echo "  5. Open the run_*_run.log only after the structured report identifies the branch."
}

run_step() {
  local label="$1"
  shift
  echo
  echo "==> ${label}"
  set +e
  "$@"
  local step_exit=$?
  set -e
  if [[ "${step_exit}" -ne 0 ]]; then
    echo
    echo "PM5 live gate failed during: ${label}" >&2
    print_pm5_gate_artifacts "failed"
    exit "${step_exit}"
  fi
}

echo "Running PM5 Plan mode live gate"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Fail on warnings: ${FAIL_ON_WARNINGS}"
echo "  Smoke scenarios: ${SMOKE_SCENARIOS:-all smoke-tagged live scenarios}"
echo "  Smoke tags: ${SMOKE_TAGS}"
echo "  Ping canary repeat count: ${PING_REPEAT_COUNT}"
echo "  Report root: ${REPORT_ROOT}"

cd "${ROOT_DIR}"

if [[ "${SKIP_SMOKE}" == "1" ]]; then
  echo
  echo "==> Live smoke suite skipped"
else
  run_step "Live smoke suite" env \
    CAVERNO_PLAN_MODE_SCENARIOS="${SMOKE_SCENARIOS}" \
    CAVERNO_PLAN_MODE_TAGS="${SMOKE_TAGS}" \
    CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}" \
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_REPORTER="${REPORTER}" \
    "${LIVE_TEST_HELPER}"
fi

if [[ "${SKIP_PING_CANARY}" == "1" ]]; then
  echo
  echo "==> Ping CLI live canary skipped"
else
  run_step "Ping CLI live canary" env \
    CAVERNO_PLAN_MODE_REPEAT_COUNT="${PING_REPEAT_COUNT}" \
    CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS="${FAIL_ON_WARNINGS}" \
    CAVERNO_PLAN_MODE_DEVICE="${DEVICE}" \
    CAVERNO_PLAN_MODE_REPORTER="${REPORTER}" \
    "${PING_CANARY_HELPER}" "${PING_PROMPT}"
fi

echo
echo "PM5 Plan mode live gate completed."
print_pm5_gate_artifacts "completed"

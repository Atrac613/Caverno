#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_FIXTURE_LLM_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_REPEAT_COUNT:-1}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_fixture_llm_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"
CLICK_FIXTURE_RESPONSE=""
TYPE_FIXTURE_RESPONSE=""

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh [options]

Options:
  --root PATH                    Report root directory.
  --repeat COUNT                 Run each LLM scenario multiple times.
  --fixture-response-click PATH  Use a local response for the safe-click scenario.
  --fixture-response-type PATH   Use a local response for the type-and-confirm scenario.
  --help                         Show this help.

This aggregate canary runs the MVP fixture LLM decision scenarios. It does not
grant TCC, operate System Settings, move the pointer, click, or type.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --repeat)
      require_value "$@"
      REPEAT_COUNT="$2"
      shift 2
      ;;
    --fixture-response-click)
      require_value "$@"
      CLICK_FIXTURE_RESPONSE="$2"
      shift 2
      ;;
    --fixture-response-type)
      require_value "$@"
      TYPE_FIXTURE_RESPONSE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

if [[ -z "${CLICK_FIXTURE_RESPONSE}" || -z "${TYPE_FIXTURE_RESPONSE}" ]]; then
  : "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the macOS Computer Use MVP fixture LLM canary.}"
  : "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the macOS Computer Use MVP fixture LLM canary.}"
  : "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the macOS Computer Use MVP fixture LLM canary.}"
fi

RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_fixture_llm_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"
CLICK_ROOT="${RUN_DIR}/safe_click"
TYPE_ROOT="${RUN_DIR}/type_confirm"
mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use MVP fixture LLM canary"
echo "  Purpose: validate fixture safe-click and type-and-confirm planning"
echo "  LLM base URL: ${CAVERNO_LLM_BASE_URL:-not set}"
echo "  LLM model: ${CAVERNO_LLM_MODEL:-not set}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report dir: ${RUN_DIR}"
echo "  TCC boundary: no TCC operation"
echo "  Desktop action boundary: no pointer, keyboard, or click operation"

click_args=(
  --root "${CLICK_ROOT}"
  --repeat "${REPEAT_COUNT}"
  --scenario mvp-fixture
)
if [[ -n "${CLICK_FIXTURE_RESPONSE}" ]]; then
  click_args+=(--fixture-response "${CLICK_FIXTURE_RESPONSE}")
fi

type_args=(
  --root "${TYPE_ROOT}"
  --repeat "${REPEAT_COUNT}"
  --scenario mvp-fixture-type-confirm
)
if [[ -n "${TYPE_FIXTURE_RESPONSE}" ]]; then
  type_args+=(--fixture-response "${TYPE_FIXTURE_RESPONSE}")
fi

status=0
set +e
bash "${ROOT_DIR}/tool/run_macos_computer_use_llm_decision_canary.sh" "${click_args[@]}"
click_exit=$?
bash "${ROOT_DIR}/tool/run_macos_computer_use_llm_decision_canary.sh" "${type_args[@]}"
type_exit=$?
set -e

if [[ "${click_exit}" -ne 0 || "${type_exit}" -ne 0 ]]; then
  status=1
fi

RUN_DIR="${RUN_DIR}" CLICK_ROOT="${CLICK_ROOT}" TYPE_ROOT="${TYPE_ROOT}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" CLICK_EXIT="${click_exit}" TYPE_EXIT="${type_exit}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
click_root = Path(os.environ["CLICK_ROOT"])
type_root = Path(os.environ["TYPE_ROOT"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
click_exit = int(os.environ["CLICK_EXIT"])
type_exit = int(os.environ["TYPE_EXIT"])


def latest_summary(root):
    candidates = sorted(root.glob("macos_computer_use_llm_decision_canary_*/canary_summary.json"))
    if not candidates:
        return None, None
    path = candidates[-1]
    try:
        return path, json.loads(path.read_text())
    except Exception:
        return path, None


click_path, click_summary = latest_summary(click_root)
type_path, type_summary = latest_summary(type_root)


def scenario_status(summary, exit_code):
    if summary is None:
        return "missing"
    if exit_code == 0 and summary.get("failedCount") == 0:
        return "passed"
    return "blocked"


scenarios = [
    {
        "scenario": "mvp-fixture",
        "status": scenario_status(click_summary, click_exit),
        "exitCode": click_exit,
        "summaryPath": str(click_path) if click_path else None,
        "runCount": 0 if click_summary is None else click_summary.get("runCount", 0),
        "failedCount": None if click_summary is None else click_summary.get("failedCount"),
        "selectedTarget": None if click_summary is None else click_summary.get("selectedTarget"),
    },
    {
        "scenario": "mvp-fixture-type-confirm",
        "status": scenario_status(type_summary, type_exit),
        "exitCode": type_exit,
        "summaryPath": str(type_path) if type_path else None,
        "runCount": 0 if type_summary is None else type_summary.get("runCount", 0),
        "failedCount": None if type_summary is None else type_summary.get("failedCount"),
        "selectedTarget": None if type_summary is None else type_summary.get("selectedTarget"),
        "requiresUserTextInput": None if type_summary is None else type_summary.get("requiresUserTextInput"),
    },
]
passed = sum(1 for scenario in scenarios if scenario["status"] == "passed")
failed = len(scenarios) - passed
summary = {
    "schemaName": "macos_computer_use_mvp_fixture_llm_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_mvp_fixture_llm_canary",
    "tccBoundary": "no_tcc_operation",
    "desktopActionBoundary": "no_desktop_action",
    "ready": failed == 0,
    "runCount": sum(scenario["runCount"] for scenario in scenarios),
    "scenarioCount": len(scenarios),
    "passed": passed,
    "failed": failed,
    "failedCount": failed,
    "passRate": 0 if not scenarios else passed / len(scenarios),
    "requiresUserClick": all(
        summary is not None and summary.get("requiresUserClick") is True
        for summary in [click_summary, type_summary]
    ),
    "requiresUserTextInput": (
        type_summary is not None and type_summary.get("requiresUserTextInput") is True
    ),
    "fixtureApp": None if click_summary is None else click_summary.get("fixtureApp"),
    "scenarios": scenarios,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use MVP Fixture LLM Canary Summary",
    "",
    "- Purpose: validate fixture safe-click and type-and-confirm planning",
    "- TCC boundary: no TCC operation",
    "- Desktop action boundary: no pointer, keyboard, or click operation",
    f"- Ready: {str(summary['ready']).lower()}",
    f"- Passed: {passed}",
    f"- Failed: {failed}",
    "",
    "| Scenario | Status | Exit | Failed Count | Summary |",
    "| --- | --- | --- | --- | --- |",
]
for scenario in scenarios:
    lines.append(
        "| {scenario} | {status} | {exitCode} | {failedCount} | {summaryPath} |".format(
            scenario=scenario["scenario"],
            status=scenario["status"],
            exitCode=scenario["exitCode"],
            failedCount=scenario["failedCount"],
            summaryPath=f"`{scenario['summaryPath']}`" if scenario["summaryPath"] else "-",
        )
    )
summary_md.write_text("\n".join(lines) + "\n")
print(summary_md.read_text())
PY

echo "MVP fixture LLM canary summary written to ${SUMMARY_JSON}"
exit "${status}"

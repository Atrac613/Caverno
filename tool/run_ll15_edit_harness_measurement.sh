#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the LL15 edit harness measurement.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the LL15 edit harness measurement.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the LL15 edit harness measurement.}"

REPORT_ROOT="${CAVERNO_LL15_EDIT_HARNESS_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports/ll15_edit_harness_measurement_$(date +%s)}"
REPEAT_COUNT="${CAVERNO_LL15_EDIT_HARNESS_REPEAT_COUNT:-1}"
OUTPUT_PATH="${CAVERNO_LL15_EDIT_HARNESS_OUTPUT:-${REPORT_ROOT}/ll15_edit_harness_measurement.json}"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_LL15_EDIT_HARNESS_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

run_phase() {
  local phase="$1"
  local tool_call_style="$2"
  local structured_output="$3"
  local edit_format="$4"
  local phase_root="${REPORT_ROOT}/${phase}"

  mkdir -p "${phase_root}"
  echo "Running LL15 ${phase} canary"
  echo "  Tool call style: ${tool_call_style}"
  echo "  Structured output: ${structured_output}"
  echo "  Edit format: ${edit_format}"
  echo "  Report root: ${phase_root}"

  set +e
  CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY_REPORT_ROOT="${phase_root}" \
  CAVERNO_CODING_GOAL_LIVE_EDIT_REPEAT_COUNT="${REPEAT_COUNT}" \
  CAVERNO_LLM_MODEL_TOOL_CALL_STYLE="${tool_call_style}" \
  CAVERNO_LLM_MODEL_STRUCTURED_OUTPUT="${structured_output}" \
  CAVERNO_LLM_MODEL_EDIT_FORMAT="${edit_format}" \
  "${ROOT_DIR}/tool/run_coding_goal_live_edit_canary.sh"
  local status=$?
  set -e

  local summary
  summary="$(find "${phase_root}" -name canary_summary.json -print | sort | tail -n 1)"
  if [[ -z "${summary}" ]]; then
    echo "No canary_summary.json was produced for phase ${phase}." >&2
    exit 65
  fi

  printf '%s\n' "${summary}" > "${phase_root}/latest_summary_path.txt"
  printf '%s\n' "${status}" > "${phase_root}/exit_status.txt"
}

mkdir -p "${REPORT_ROOT}"

run_phase \
  baseline \
  "${CAVERNO_LL15_BASELINE_TOOL_CALL_STYLE:-nativeToolCalls}" \
  "${CAVERNO_LL15_BASELINE_STRUCTURED_OUTPUT:-jsonSchema}" \
  "${CAVERNO_LL15_BASELINE_EDIT_FORMAT:-wholeFile}"
BASELINE_STATUS="$(cat "${REPORT_ROOT}/baseline/exit_status.txt")"
BASELINE_SUMMARY="$(cat "${REPORT_ROOT}/baseline/latest_summary_path.txt")"

run_phase \
  current \
  "${CAVERNO_LL15_CURRENT_TOOL_CALL_STYLE:-embeddedToolTags}" \
  "${CAVERNO_LL15_CURRENT_STRUCTURED_OUTPUT:-none}" \
  "${CAVERNO_LL15_CURRENT_EDIT_FORMAT:-searchReplace}"
CURRENT_STATUS="$(cat "${REPORT_ROOT}/current/exit_status.txt")"
CURRENT_SUMMARY="$(cat "${REPORT_ROOT}/current/latest_summary_path.txt")"

dart run "${ROOT_DIR}/tool/ll15_edit_harness_measurement.dart" \
  --baseline-summary "${BASELINE_SUMMARY}" \
  --current-summary "${CURRENT_SUMMARY}" \
  --output "${OUTPUT_PATH}" \
  --format markdown

if [[ "${BASELINE_STATUS}" -ne 0 || "${CURRENT_STATUS}" -ne 0 ]]; then
  echo "LL15 measurement completed with canary failures."
  echo "  Baseline status: ${BASELINE_STATUS}"
  echo "  Current status: ${CURRENT_STATUS}"
  echo "  Measurement JSON: ${OUTPUT_PATH}"
  exit 1
fi

echo "LL15 measurement completed successfully."
echo "  Measurement JSON: ${OUTPUT_PATH}"

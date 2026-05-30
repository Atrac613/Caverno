#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the Coding Verification Feedback release gate.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the Coding Verification Feedback release gate.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the Coding Verification Feedback release gate.}"

if [[ "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK:-}" != "1" ]]; then
  echo "Set CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 after confirming this release gate may send prompts, temporary code-edit context, and tool results to ${CAVERNO_LLM_BASE_URL}." >&2
  exit 64
fi

REPORT_ROOT="${CAVERNO_CODING_VERIFICATION_FEEDBACK_RELEASE_GATE_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/coding_verification_feedback_release_gate_$(date +%s)"
LIVE_REPORT_ROOT="${RUN_DIR}/live"
REPEAT_COUNT="${CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT:-3}"
GATE_JSON="${RUN_DIR}/release_gate.json"
GATE_MARKDOWN="${RUN_DIR}/release_gate.md"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

echo "Running Coding Verification Feedback release gate"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report directory: ${RUN_DIR}"

mkdir -p "${RUN_DIR}"

set +e
CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_CANARY_REPORT_ROOT="${LIVE_REPORT_ROOT}" \
CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_REPEAT_COUNT="${REPEAT_COUNT}" \
CAVERNO_LIVE_LLM_DATA_EXPORT_ACK="${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK}" \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
"${ROOT_DIR}/tool/run_coding_verification_feedback_live_canary.sh"
CANARY_STATUS=$?
set -e

SUMMARY_PATH="$(
  if [[ -d "${LIVE_REPORT_ROOT}" ]]; then
    find "${LIVE_REPORT_ROOT}" -type f -name canary_summary.json -print 2>/dev/null \
      | sort \
      | tail -n 1
  fi
)"

if [[ -z "${SUMMARY_PATH}" ]]; then
  echo "Coding Verification Feedback release gate failed: canary_summary.json was not produced." >&2
  if [[ "${CANARY_STATUS}" -ne 0 ]]; then
    exit "${CANARY_STATUS}"
  fi
  exit 1
fi

set +e
dart run "${ROOT_DIR}/tool/coding_verification_feedback_release_gate.dart" \
  --summary "${SUMMARY_PATH}" \
  --min-repeat-count "${REPEAT_COUNT}" \
  --out-json "${GATE_JSON}" \
  --out-md "${GATE_MARKDOWN}"
GATE_STATUS=$?
set -e

echo "Coding Verification Feedback live summary: ${SUMMARY_PATH}"
echo "Coding Verification Feedback release gate JSON: ${GATE_JSON}"
echo "Coding Verification Feedback release gate Markdown: ${GATE_MARKDOWN}"

if [[ "${CANARY_STATUS}" -ne 0 ]]; then
  exit "${CANARY_STATUS}"
fi

exit "${GATE_STATUS}"

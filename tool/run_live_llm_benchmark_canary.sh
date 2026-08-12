#!/usr/bin/env bash
#
# LL39 headless benchmark canary.
#
# Runs the same LiveLlmDiagnosticService the app runs, against a real endpoint,
# and writes the scored report to build/integration_test_reports/. Use it to
# validate the probes against a real model and to measure the run-to-run spread
# in one command instead of over several nights of unattended calibration.
#
# LAN note: this runs under flutter_tester, which cannot reach a LAN address
# directly on macOS (Local Network Privacy applies to the test host, not the
# app bundle). Point CAVERNO_LLM_BASE_URL at a loopback tunnel, e.g.
#   ssh -N -L 1234:192.168.100.241:1234 <host>
#   export CAVERNO_LLM_BASE_URL=http://127.0.0.1:1234/v1

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

CANARY_NAME="${CAVERNO_BENCHMARK_CANARY_NAME:-live_llm_benchmark_canary}"
CANARY_COMMAND="${CAVERNO_BENCHMARK_CANARY_COMMAND:-tool/run_live_llm_benchmark_canary.sh}"
REPEAT_COUNT="${CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT:-1}"
LLM_PROVIDER="${CAVERNO_LLM_PROVIDER:-openAiCompatible}"

if [[ "${LLM_PROVIDER}" == "appleFoundationModels" || "${LLM_PROVIDER}" == "apple_foundation_models" || "${LLM_PROVIDER}" == "foundation_models" ]]; then
  LLM_PROVIDER="appleFoundationModels"
  CAVERNO_LLM_BASE_URL="apple-foundation-models://local"
  CAVERNO_LLM_API_KEY=""
  CAVERNO_LLM_MODEL="apple-foundation-models"
  # Foundation Models needs the real host app, not flutter_tester.
  FLUTTER_DEVICE_ARGS=(-d macos)
else
  LLM_PROVIDER="openAiCompatible"
  : "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the benchmark canary.}"
  : "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the benchmark canary (use no-key for a local server).}"
  : "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the benchmark canary.}"
  FLUTTER_DEVICE_ARGS=()
fi

TEST_TARGET="tool/canaries/live_llm_benchmark_canary_test.dart"
REPORT_ROOT="${CAVERNO_BENCHMARK_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/${CANARY_NAME}_$(date +%s)"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
REPORTER="json"

echo "Running live LLM benchmark canary"
echo "  Canary: ${CANARY_NAME}"
echo "  Provider: ${LLM_PROVIDER}"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Repeats: ${REPEAT_COUNT}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

set +e
FLUTTER_TEST_COMMAND=(flutter test)
if [[ "${#FLUTTER_DEVICE_ARGS[@]}" -gt 0 ]]; then
  FLUTTER_TEST_COMMAND+=("${FLUTTER_DEVICE_ARGS[@]}")
fi
FLUTTER_TEST_COMMAND+=("${TEST_TARGET}" -r "${REPORTER}")

CAVERNO_BENCHMARK_CANARY=1 \
CAVERNO_BENCHMARK_CANARY_REPORT_DIR="${RUN_DIR}" \
CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT="${REPEAT_COUNT}" \
CAVERNO_BENCHMARK_CANARY_PROBE_IDS="${CAVERNO_BENCHMARK_CANARY_PROBE_IDS:-}" \
CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS="${CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS:-}" \
CAVERNO_BENCHMARK_CANARY_MIN_POINTS="${CAVERNO_BENCHMARK_CANARY_MIN_POINTS:-}" \
CAVERNO_LLM_PROVIDER="${LLM_PROVIDER}" \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
"${FLUTTER_TEST_COMMAND[@]}" > "${LOG_PATH}" 2>&1
TEST_STATUS=$?
set -e

set +e
dart run "${ROOT_DIR}/tool/live_llm_canary_summary.dart" \
  --log "${LOG_PATH}" \
  --out-dir "${RUN_DIR}" \
  --canary-name "${CANARY_NAME}" \
  --surface chat \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --command "${CANARY_COMMAND}"
SUMMARY_STATUS=$?
set -e

BENCHMARK_ARTIFACT="${RUN_DIR}/benchmark_run.json"
if [ -f "${BENCHMARK_ARTIFACT}" ]; then
  echo "Benchmark artifact: ${BENCHMARK_ARTIFACT}"
else
  echo "No benchmark artifact was written; see ${LOG_PATH}"
fi

if [ "${TEST_STATUS}" -ne 0 ]; then
  echo "Live LLM benchmark canary failed. Flutter JSON log: ${LOG_PATH}"
  exit "${TEST_STATUS}"
fi

exit "${SUMMARY_STATUS}"

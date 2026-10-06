#!/usr/bin/env bash
set -euo pipefail

quiet=false
if [[ "${1:-}" == "--quiet-output" ]]; then quiet=true; shift; fi
if [[ "$#" != 0 ]]; then
  echo 'Usage: tool/run_farm_step_recovery_live_canary.sh [--quiet-output]' >&2
  exit 64
fi
: "${CAVERNO_LLM_BASE_URL:?Set the LLM API base URL}"
: "${CAVERNO_LLM_API_KEY:?Set the LLM API key}"
: "${CAVERNO_LLM_MODEL:?Set the exact loaded model ID}"
if [[ "${CAVERNO_LIVE_LLM_DATA_EXPORT_ACK:-}" != 1 ]]; then
  echo 'Set CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 to authorize synthetic fixture export.' >&2
  exit 64
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This canary requires the macOS native command containment route.' >&2
  exit 64
fi
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
mkdir -p "${REPORT_ROOT}"
RUN_DIR="$(mktemp -d "${REPORT_ROOT}/farm_step_recovery_live_canary.XXXXXX")"
LOG_PATH="${RUN_DIR}/flutter_test.jsonl"
mkdir -p "${RUN_DIR}/session_logs"
BUILD_COMMIT="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
BUILD_DIRTY=false
if ! git -C "${ROOT_DIR}" diff --quiet ||
  ! git -C "${ROOT_DIR}" diff --cached --quiet ||
  [[ -n "$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard)" ]]; then
  BUILD_DIRTY=true
fi
printf 'Farm step recovery canary: model=%s reports=%s\n' "${CAVERNO_LLM_MODEL}" "${RUN_DIR}"
cd "${ROOT_DIR}"
set +e
CAVERNO_FARM_STEP_LIVE_CANARY=1 \
CAVERNO_FARM_STEP_REPORT_DIR="${RUN_DIR}/fixtures" \
CAVERNO_SESSION_LOG_DIR="${RUN_DIR}/session_logs" \
fvm flutter test --no-pub --concurrency=1 \
  --dart-define="CAVERNO_BUILD_COMMIT=${BUILD_COMMIT}" \
  --dart-define="CAVERNO_BUILD_DIRTY=${BUILD_DIRTY}" \
  --dart-define="CAVERNO_BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  tool/canaries/farm_step_recovery_live_canary_test.dart -r json >"${LOG_PATH}" 2>&1
TEST_STATUS=$?
fvm dart run tool/live_llm_canary_summary.dart \
  --log "${LOG_PATH}" --out-dir "${RUN_DIR}" \
  --canary-name farm_step_recovery_live_canary --surface project_task_step \
  --base-url "${CAVERNO_LLM_ORIGIN_BASE_URL:-${CAVERNO_LLM_BASE_URL}}" \
  --effective-base-url "${CAVERNO_LLM_BASE_URL}" \
  --relay-mode "${CAVERNO_LLM_RELAY_MODE:-direct}" --model "${CAVERNO_LLM_MODEL}" \
  --session-log-dir "${RUN_DIR}/session_logs" \
  --command 'tool/with_live_llm_loopback.sh -- tool/run_farm_step_recovery_live_canary.sh --quiet-output' \
  >"${RUN_DIR}/summary.log" 2>&1
SUMMARY_STATUS=$?
fvm dart run tool/farm_step_canary_evidence.dart "${RUN_DIR}" >"${RUN_DIR}/evidence_gate.log" 2>&1
EVIDENCE_STATUS=$?
set -e
if ! "${quiet}"; then cat "${RUN_DIR}/summary.log" "${RUN_DIR}/evidence_gate.log"; fi
printf 'Farm step canary: tests=%s summary=%s evidence=%s artifact=%s/canary_summary.json\n' \
  "${TEST_STATUS}" "${SUMMARY_STATUS}" "${EVIDENCE_STATUS}" "${RUN_DIR}"
if [[ "${TEST_STATUS}" != 0 ]]; then exit "${TEST_STATUS}"; fi
if [[ "${SUMMARY_STATUS}" != 0 ]]; then exit "${SUMMARY_STATUS}"; fi
exit "${EVIDENCE_STATUS}"

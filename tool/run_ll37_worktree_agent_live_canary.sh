#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the LL37 worktree-agent canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the LL37 worktree-agent canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the LL37 worktree-agent canary.}"

if [[ "${CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT:-}" != "1" ]]; then
  echo "Set CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1 after explicit user approval." >&2
  exit 64
fi

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
  DART_CMD=(fvm dart)
else
  FLUTTER_CMD=(flutter)
  DART_CMD=(dart)
fi

REPORT_ROOT="${CAVERNO_LL37_WORKTREE_AGENT_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/ll37_worktree_agent_live_canary_$(date +%s)"
CAPTURE_DIR="${RUN_DIR}/capture"
EVIDENCE_DIR="${RUN_DIR}/evidence"
LOG_PATH="${RUN_DIR}/flutter_test.log"
PROBE_JSON="${RUN_DIR}/ll37_probe_report.json"
PROBE_MD="${RUN_DIR}/ll37_probe_report.md"

echo "Running LL37 worktree-agent live canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Report directory: ${RUN_DIR}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

CAVERNO_LL37_WORKTREE_AGENT_LIVE_CANARY=1 \
CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1 \
CAVERNO_LL37_WORKTREE_AGENT_CAPTURE_DIR="${CAPTURE_DIR}" \
CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
"${FLUTTER_CMD[@]}" test \
  tool/canaries/ll37_worktree_agent_live_canary_test.dart \
  -r expanded > "${LOG_PATH}" 2>&1

"${DART_CMD[@]}" run tool/ll37_worktree_agent_history_export.dart \
  --tasks-json "${CAPTURE_DIR}/tasks.json" \
  --selection "${CAPTURE_DIR}/selection.json" \
  --out-dir "${EVIDENCE_DIR}"

set +e
"${DART_CMD[@]}" run tool/ll37_verifier_fidelity_probe.dart \
  --case "${EVIDENCE_DIR}/candidate-a_case.json" \
  --case "${EVIDENCE_DIR}/candidate-b_case.json" \
  --base-url "${CAVERNO_LLM_BASE_URL}" \
  --api-key "${CAVERNO_LLM_API_KEY}" \
  --model "${CAVERNO_LLM_MODEL}" \
  --timeout-seconds 180 \
  --out-json "${PROBE_JSON}" \
  --out-md "${PROBE_MD}"
PROBE_STATUS=$?
set -e

python3 - "${PROBE_JSON}" "${PROBE_STATUS}" <<'PY'
import json
import sys

report_path = sys.argv[1]
probe_status = int(sys.argv[2])
with open(report_path, encoding="utf-8") as handle:
    report = json.load(handle)

results = report.get("results", [])
if len(results) != 2:
    raise SystemExit("Expected exactly two LL37 worktree-agent results.")
if any(item.get("matchesExpected") is not True for item in results):
    raise SystemExit("LL37 worktree-agent verifier mismatch.")
metrics = report.get("eligibleCases", {})
if metrics.get("invalidCount") != 0 or metrics.get("unverifiableCount") != 0:
    raise SystemExit("LL37 worktree-agent verifier output was unreliable.")
if probe_status not in (0, 1):
    raise SystemExit(f"LL37 probe failed with unexpected status {probe_status}.")
print("LL37 worktree-agent pair matched 2/2 with reliable output.")
print(f"Gate remains: {report.get('gate')}")
PY

echo "LL37 worktree-agent live canary passed."
echo "  Capture: ${CAPTURE_DIR}"
echo "  Evidence: ${EVIDENCE_DIR}"
echo "  Probe report: ${PROBE_JSON}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the LL37 remaining-pairs canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the LL37 remaining-pairs canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the LL37 remaining-pairs canary.}"
: "${CAVERNO_LL37_LL13_CORRECT_CASE:?Set the accepted LL13 correct case path.}"
: "${CAVERNO_LL37_LL13_BROKEN_CASE:?Set the accepted LL13 broken case path.}"
: "${CAVERNO_LL37_ROUTINE_BASELINE_CORRECT_CASE:?Set the accepted Routine baseline correct case path.}"
: "${CAVERNO_LL37_ROUTINE_BASELINE_BROKEN_CASE:?Set the accepted Routine baseline broken case path.}"

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

REPORT_ROOT="${CAVERNO_LL37_REMAINING_PAIRS_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${CAVERNO_LL37_REMAINING_PAIRS_RUN_DIR:-${REPORT_ROOT}/ll37_remaining_pairs_live_canary_$(date +%s)}"
if [[ "${RUN_DIR}" != /* ]]; then
  RUN_DIR="${ROOT_DIR}/${RUN_DIR}"
fi
PROBE_JSON="${RUN_DIR}/ll37_ten_case_probe_report.json"
PROBE_MD="${RUN_DIR}/ll37_ten_case_probe_report.md"
SCENARIOS=(feature_flag retry_limit display_format)
CASE_ARGS=(
  --case "${CAVERNO_LL37_LL13_CORRECT_CASE}"
  --case "${CAVERNO_LL37_LL13_BROKEN_CASE}"
  --case "${CAVERNO_LL37_ROUTINE_BASELINE_CORRECT_CASE}"
  --case "${CAVERNO_LL37_ROUTINE_BASELINE_BROKEN_CASE}"
)

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"

for scenario in "${SCENARIOS[@]}"; do
  SCENARIO_DIR="${RUN_DIR}/${scenario}"
  CAPTURE_DIR="${SCENARIO_DIR}/capture"
  EVIDENCE_DIR="${SCENARIO_DIR}/evidence"
  if [[ -f "${EVIDENCE_DIR}/candidate-a_case.json" && -f "${EVIDENCE_DIR}/candidate-b_case.json" ]]; then
    echo "Reusing completed LL37 scenario: ${scenario}"
    CASE_ARGS+=(
      --case "${EVIDENCE_DIR}/candidate-a_case.json"
      --case "${EVIDENCE_DIR}/candidate-b_case.json"
    )
    continue
  fi
  if [[ -e "${SCENARIO_DIR}" ]]; then
    echo "Refusing to replace incomplete LL37 scenario directory: ${SCENARIO_DIR}" >&2
    exit 73
  fi
  mkdir -p "${SCENARIO_DIR}"

  CAVERNO_LL37_ROUTINE_LIVE_CANARY=1 \
  CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1 \
  CAVERNO_LL37_ROUTINE_CAPTURE_DIR="${CAPTURE_DIR}" \
  CAVERNO_LL37_ROUTINE_SCENARIO="${scenario}" \
  CAVERNO_LLM_BASE_URL="${CAVERNO_LLM_BASE_URL}" \
  CAVERNO_LLM_API_KEY="${CAVERNO_LLM_API_KEY}" \
  CAVERNO_LLM_MODEL="${CAVERNO_LLM_MODEL}" \
  "${FLUTTER_CMD[@]}" test \
    tool/canaries/ll37_routine_live_canary_test.dart \
    -r expanded > "${SCENARIO_DIR}/flutter_test.log" 2>&1

  "${DART_CMD[@]}" run tool/ll37_routine_history_export.dart \
    --routines-json "${CAPTURE_DIR}/routines.json" \
    --selection "${CAPTURE_DIR}/selection.json" \
    --out-dir "${EVIDENCE_DIR}"

  CASE_ARGS+=(
    --case "${EVIDENCE_DIR}/candidate-a_case.json"
    --case "${EVIDENCE_DIR}/candidate-b_case.json"
  )
done

set +e
"${DART_CMD[@]}" run tool/ll37_verifier_fidelity_probe.dart \
  "${CASE_ARGS[@]}" \
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
metrics = report.get("eligibleCases", {})
if probe_status != 0 or report.get("gate") != "go":
    raise SystemExit("LL37 ten-case decision gate did not pass.")
if len(results) != 10 or any(item.get("matchesExpected") is not True for item in results):
    raise SystemExit("Expected ten matching LL37 results.")
if any(item.get("mechanicalVerificationPassed") is not True for item in results):
    raise SystemExit("Every LL37 decision case must be mechanically green.")
if metrics.get("correctCaseCount") != 5 or metrics.get("brokenCaseCount") != 5:
    raise SystemExit("Expected five correct and five broken eligible cases.")
if report.get("eligiblePairCount") != 5 or report.get("eligibleObjectiveCount") != 5:
    raise SystemExit("Expected five eligible pairs with distinct objectives.")
if report.get("eligibleSourceSurfaces", 0) < 2:
    raise SystemExit("Expected at least two eligible unattended surfaces.")
if metrics.get("invalidCount") != 0 or metrics.get("unverifiableCount") != 0:
    raise SystemExit("LL37 decision output was unreliable.")
if metrics.get("falseRefuteRate", 1) > 0.1 or metrics.get("brokenRecall", 0) < 0.8:
    raise SystemExit("LL37 fidelity thresholds were not met.")
print("LL37 ten-case decision gate passed.")
PY

echo "LL37 remaining-pairs live canary passed."
echo "  Report directory: ${RUN_DIR}"
echo "  Decision report: ${PROBE_JSON}"

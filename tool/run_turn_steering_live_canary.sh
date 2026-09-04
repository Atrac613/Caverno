#!/usr/bin/env bash
#
# Live canary for mid-turn interruption (steering).
#
# Two arms per run: an interrupt arm and a queued control arm. The verdict is
# read from the sandbox filesystem, not from the model's prose. See the header
# of tool/canaries/turn_steering_live_canary_test.dart for the scenario.
#
# This asserts a probabilistic model behavior, so a single run is a sample and
# not a measurement. Use CAVERNO_TURN_STEERING_REPEAT_COUNT and read the
# printed rate at the end.
#
# The base URL must be reachable from flutter_tester. On macOS a LAN address is
# not: Local Network Privacy blocks it, so tunnel the endpoint to 127.0.0.1
# first and point CAVERNO_LLM_BASE_URL at the loopback port.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT_DIR}/tool/agent_output.sh"
OUTPUT_MODE="${CAVERNO_AGENT_OUTPUT_MODE:-raw}"

usage() {
  cat <<'USAGE'
Usage: tool/run_turn_steering_live_canary.sh [options]

Options:
  --quiet-output  Save full Flutter output and print bounded status heartbeats.
  --raw-output    Stream full Flutter output (default).
  -h, --help      Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet-output)
      OUTPUT_MODE="quiet"
      shift
      ;;
    --raw-output)
      OUTPUT_MODE="raw"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "${OUTPUT_MODE}" in
  quiet|raw)
    ;;
  *)
    echo "CAVERNO_AGENT_OUTPUT_MODE must be quiet or raw." >&2
    exit 64
    ;;
esac

: "${CAVERNO_LLM_BASE_URL:?Set CAVERNO_LLM_BASE_URL before running the turn steering canary.}"
: "${CAVERNO_LLM_API_KEY:?Set CAVERNO_LLM_API_KEY before running the turn steering canary.}"
: "${CAVERNO_LLM_MODEL:?Set CAVERNO_LLM_MODEL before running the turn steering canary.}"

REPORT_ROOT="${CAVERNO_TURN_STEERING_CANARY_REPORT_ROOT:-${CAVERNO_LIVE_LLM_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}}"
RUN_DIR="${REPORT_ROOT}/turn_steering_live_canary_$(date +%s)"
WORK_ROOT="${RUN_DIR}/workspace"
SNAPSHOT_PATH="${RUN_DIR}/snapshots.jsonl"
REPEAT_COUNT="${CAVERNO_TURN_STEERING_REPEAT_COUNT:-1}"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_TURN_STEERING_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

echo "Running turn steering live canary"
echo "  Base URL: ${CAVERNO_LLM_BASE_URL}"
echo "  Model: ${CAVERNO_LLM_MODEL}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Report directory: ${RUN_DIR}"
echo "  Flutter output: ${OUTPUT_MODE}"

cd "${ROOT_DIR}"
mkdir -p "${RUN_DIR}"
: > "${SNAPSHOT_PATH}"

TEST_STATUS=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_label="$(printf 'run_%02d' "${index}")"
  run_log_path="${RUN_DIR}/${run_label}_flutter_test.log"
  echo "Running ${run_label}/${REPEAT_COUNT}"

  run_status=0
  agent_output_run \
    "${run_log_path}" \
    "turn steering ${run_label}/${REPEAT_COUNT}" \
    "${OUTPUT_MODE}" \
    env \
    CAVERNO_TURN_STEERING_LIVE_CANARY=1 \
    CAVERNO_TURN_STEERING_RUN_LABEL="${run_label}" \
    CAVERNO_TURN_STEERING_WORK_ROOT="${WORK_ROOT}/${run_label}" \
    flutter test tool/canaries/turn_steering_live_canary_test.dart \
    --reporter expanded || run_status=$?

  grep -h 'TURN_STEERING_CANARY_SNAPSHOT ' "${run_log_path}" \
    | sed 's/.*TURN_STEERING_CANARY_SNAPSHOT //' >> "${SNAPSHOT_PATH}" || true

  if [[ "${run_status}" -ne 0 ]]; then
    TEST_STATUS="${run_status}"
    echo "${run_label} failed with status ${run_status}"
  fi
done

echo
echo "Snapshots: ${SNAPSHOT_PATH}"
python3 - "${SNAPSHOT_PATH}" <<'PY'
import json
import sys

path = sys.argv[1]
rows = []
with open(path) as handle:
    for line in handle:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

if not rows:
    print("No snapshots recorded.")
    sys.exit(0)

for arm in ("steer", "queue"):
    arm_rows = [row for row in rows if row.get("arm") == arm]
    if not arm_rows:
        continue
    redirected = sum(1 for row in arm_rows if row.get("redirected"))
    print(f"{arm}: {redirected}/{len(arm_rows)} runs matched the expected outcome")
    if arm == "steer":
        carried = sum(1 for row in arm_rows if row.get("steerCarriedInRequests"))
        directive = sum(
            1 for row in arm_rows if row.get("directiveCarriedInRequests")
        )
        # Delivery is mechanical. Anything below the run count here means the
        # interruption never reached the model, so its obedience rate is not
        # what needs fixing.
        print(f"  delivery: steer text carried in {carried}/{len(arm_rows)}, "
              f"directive carried in {directive}/{len(arm_rows)}")
        stray = sum(1 for row in arm_rows if row.get("alphaCreated"))
        print(f"  original file still created in {stray}/{len(arm_rows)}")
PY

exit "${TEST_STATUS}"

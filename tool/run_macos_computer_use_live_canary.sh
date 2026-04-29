#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPEAT_COUNT:-1}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
PRESET="${CAVERNO_MACOS_COMPUTER_USE_CANARY_PRESET:-local}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_live_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value."
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repeat)
      require_value "$@"
      REPEAT_COUNT="$2"
      shift 2
      ;;
    --report-root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --device)
      require_value "$@"
      DEVICE="$2"
      shift 2
      ;;
    --reporter)
      require_value "$@"
      REPORTER="$2"
      shift 2
      ;;
    --ci)
      PRESET="ci"
      shift
      ;;
    --manual|--local)
      PRESET="local"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_live_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

case "${PRESET}" in
  ci|local)
    ;;
  *)
    echo "CAVERNO_MACOS_COMPUTER_USE_CANARY_PRESET must be ci or local."
    exit 2
    ;;
esac

mkdir -p "${RUN_DIR}"

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_CANARY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

echo "Running macOS Computer Use live canary"
echo "  Purpose: helper launch, IPC, ping, permission reporting, and cleanup"
echo "  TCC boundary: user-operated manual verification only"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Preset: ${PRESET}"
echo "  Report dir: ${RUN_DIR}"
if [[ "${PRESET}" == "local" ]]; then
  echo "  Manual TCC follow-up: use docs/macos_computer_use_helper_architecture.md after the user grants permissions."
fi

status=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_name="$(printf "run_%02d" "${index}")"
  run_report="${RUN_DIR}/${run_name}.json"
  run_log="${RUN_DIR}/${run_name}.log"
  echo "Running ${run_name}/${REPEAT_COUNT}"
  set +e
  CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${run_report}" \
    bash "${ROOT_DIR}/tool/run_macos_computer_use_smoke_test.sh" \
      --computer-use-live-canary \
      --device "${DEVICE}" \
      --reporter "${REPORTER}" \
      >"${run_log}" 2>&1
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    status=1
  fi
done

RUN_DIR="${RUN_DIR}" PRESET="${PRESET}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
preset = os.environ["PRESET"]
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
runs = []


def classify_failure(gate, blockers):
    if not gate:
        return "canary_gate_missing"

    blocker_classes = {
        "helper_status": "helper_status_failed",
        "helper_ipc_ready": "ipc_not_ready",
        "helper_ping": "helper_ping_failed",
        "permission_status": "permission_status_failed",
        "stop_helper_work": "cleanup_failed",
    }
    for blocker in blocker_classes:
        if blocker in blockers:
            return blocker_classes[blocker]
    return "computer_use_live_canary_blocked"


for report_path in sorted(run_dir.glob("run_*.json")):
    name = report_path.stem
    log_path = report_path.with_suffix(".log")
    try:
        report = json.loads(report_path.read_text())
    except Exception as error:
        runs.append({
            "name": name,
            "status": "failed",
            "failureClass": "report_unreadable",
            "error": str(error),
            "report": str(report_path),
            "log": str(log_path),
        })
        continue

    raw_gate = report.get("computerUseLiveCanaryGate")
    gate = raw_gate if isinstance(raw_gate, dict) else {}
    blockers = gate.get("blockers")
    blockers = blockers if isinstance(blockers, list) else []
    passed = report.get("ok") is True and gate.get("status") == "ready"
    failure_class = "passed" if passed else classify_failure(gate, blockers)
    runs.append({
        "name": name,
        "status": "passed" if passed else "failed",
        "failureClass": failure_class,
        "gateStatus": gate.get("status", "missing"),
        "blockers": blockers,
        "helperPath": gate.get("helperPath"),
        "selectedIpcTransport": gate.get("selectedIpcTransport"),
        "report": str(report_path),
        "log": str(log_path),
    })

passed_count = sum(1 for run in runs if run["status"] == "passed")
failed_count = len(runs) - passed_count
failure_classes = {}
for run in runs:
    failure_class = run["failureClass"]
    failure_classes[failure_class] = failure_classes.get(failure_class, 0) + 1
summary = {
    "schemaName": "macos_computer_use_live_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_helper_runtime_canary",
    "tccBoundary": "manual_user_operated",
    "preset": preset,
    "runCount": len(runs),
    "passed": passed_count,
    "failed": failed_count,
    "passRate": 0 if not runs else passed_count / len(runs),
    "failureClasses": failure_classes,
    "runs": runs,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use Live Canary Summary",
    "",
    "- Purpose: helper launch, IPC, ping, permission reporting, and cleanup",
    "- TCC boundary: user-operated manual verification only",
    f"- Preset: {preset}",
    f"- Run count: {len(runs)}",
    f"- Passed: {passed_count}",
    f"- Failed: {failed_count}",
    f"- Pass rate: {summary['passRate'] * 100:.1f}%",
    "",
    "| Run | Status | Failure Class | Gate | Blockers | IPC | Artifacts |",
    "| --- | --- | --- | --- | --- | --- | --- |",
]
for run in runs:
    blockers = ", ".join(str(item) for item in run.get("blockers") or []) or "-"
    artifacts = f"report: `{run['report']}`<br>log: `{run['log']}`"
    lines.append(
        "| {name} | {status} | {failureClass} | {gateStatus} | {blockers} | {ipc} | {artifacts} |".format(
            name=run["name"],
            status=run["status"],
            failureClass=run["failureClass"],
            gateStatus=run.get("gateStatus", "-"),
            blockers=blockers,
            ipc=run.get("selectedIpcTransport") or "-",
            artifacts=artifacts,
        )
    )
summary_md.write_text("\n".join(lines) + "\n")

print(summary_md.read_text())
PY

echo "Canary summary written to ${SUMMARY_JSON}"
exit "${status}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPEAT_COUNT:-1}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_live_canary_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/canary_summary.json"
SUMMARY_MD="${RUN_DIR}/canary_summary.md"

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
echo "  Report dir: ${RUN_DIR}"

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

RUN_DIR="${RUN_DIR}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
runs = []

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

    gate = report.get("computerUseLiveCanaryGate")
    gate = gate if isinstance(gate, dict) else {}
    blockers = gate.get("blockers")
    blockers = blockers if isinstance(blockers, list) else []
    passed = report.get("ok") is True and gate.get("status") == "ready"
    runs.append({
        "name": name,
        "status": "passed" if passed else "failed",
        "failureClass": "passed" if passed else "computer_use_live_canary_blocked",
        "gateStatus": gate.get("status", "missing"),
        "blockers": blockers,
        "helperPath": gate.get("helperPath"),
        "selectedIpcTransport": gate.get("selectedIpcTransport"),
        "report": str(report_path),
        "log": str(log_path),
    })

passed_count = sum(1 for run in runs if run["status"] == "passed")
failed_count = len(runs) - passed_count
summary = {
    "schemaName": "macos_computer_use_live_canary_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_helper_runtime_canary",
    "tccBoundary": "manual_user_operated",
    "runCount": len(runs),
    "passed": passed_count,
    "failed": failed_count,
    "passRate": 0 if not runs else passed_count / len(runs),
    "runs": runs,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use Live Canary Summary",
    "",
    "- Purpose: helper launch, IPC, ping, permission reporting, and cleanup",
    "- TCC boundary: user-operated manual verification only",
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

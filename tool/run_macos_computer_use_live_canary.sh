#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPEAT_COUNT:-1}"
STABILITY_REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_STABILITY_REPEAT_COUNT:-3}"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_CANARY_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
PRESET="${CAVERNO_MACOS_COMPUTER_USE_CANARY_PRESET:-local}"
STABILITY_MODE=0
REPEAT_COUNT_EXPLICIT=0
RUN_OVERLAY_CANARY="${CAVERNO_MACOS_COMPUTER_USE_CANARY_OVERLAY:-0}"
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
      REPEAT_COUNT_EXPLICIT=1
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
    --stability)
      PRESET="ci"
      STABILITY_MODE=1
      shift
      ;;
    --manual|--local)
      PRESET="local"
      shift
      ;;
    --overlay|--overlay-canary|--permission-overlay)
      RUN_OVERLAY_CANARY=1
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

if [[ "${STABILITY_MODE}" == "1" && "${REPEAT_COUNT_EXPLICIT}" == "0" ]]; then
  REPEAT_COUNT="${STABILITY_REPEAT_COUNT}"
fi

if ! [[ "${STABILITY_REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${STABILITY_REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_CANARY_STABILITY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_CANARY_REPEAT_COUNT must be a positive integer."
  exit 2
fi

mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use live canary"
echo "  Purpose: helper launch, IPC, ping, permission reporting, and cleanup"
echo "  TCC boundary: user-operated manual verification only"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  Preset: ${PRESET}"
echo "  Stability mode: ${STABILITY_MODE}"
echo "  Overlay foreground canary: ${RUN_OVERLAY_CANARY}"
echo "  Report dir: ${RUN_DIR}"
if [[ "${PRESET}" == "local" ]]; then
  echo "  Manual TCC follow-up: ask the user to run bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff"
  echo "  Manual TCC parser: dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report-or-summary.json>"
fi
if [[ "${RUN_OVERLAY_CANARY}" == "1" ]]; then
  echo "  Overlay scope: opens System Settings and validates overlay foreground diagnostics without granting TCC."
fi

status=0
for index in $(seq 1 "${REPEAT_COUNT}"); do
  run_name="$(printf "run_%02d" "${index}")"
  run_report="${RUN_DIR}/${run_name}.json"
  run_log="${RUN_DIR}/${run_name}.log"
  smoke_args=(
    --computer-use-live-canary
    --device "${DEVICE}"
    --reporter "${REPORTER}"
  )
  if [[ "${RUN_OVERLAY_CANARY}" == "1" ]]; then
    smoke_args+=(--overlay-smoke --require-overlay)
  fi
  echo "Running ${run_name}/${REPEAT_COUNT}"
  set +e
  CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${run_report}" \
    bash "${ROOT_DIR}/tool/run_macos_computer_use_smoke_test.sh" \
      "${smoke_args[@]}" \
      >"${run_log}" 2>&1
  exit_code=$?
  set -e
  if [[ "${exit_code}" -ne 0 ]]; then
    status=1
  fi
done

RUN_DIR="${RUN_DIR}" PRESET="${PRESET}" STABILITY_MODE="${STABILITY_MODE}" RUN_OVERLAY_CANARY="${RUN_OVERLAY_CANARY}" SUMMARY_JSON="${SUMMARY_JSON}" SUMMARY_MD="${SUMMARY_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


run_dir = Path(os.environ["RUN_DIR"])
preset = os.environ["PRESET"]
stability_mode = os.environ["STABILITY_MODE"] == "1"
overlay_canary = os.environ["RUN_OVERLAY_CANARY"] == "1"
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
        "helper_process_policy": "helper_process_policy_failed",
        "permission_overlay_foreground": "overlay_foreground_failed",
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
    raw_helper_policy = report.get("helperProcessPolicyGate")
    helper_policy = raw_helper_policy if isinstance(raw_helper_policy, dict) else {}
    raw_overlay_smoke = report.get("overlaySmoke")
    overlay_smoke = raw_overlay_smoke if isinstance(raw_overlay_smoke, dict) else {}
    raw_manual_handoff = report.get("manualTccHandoff")
    manual_handoff = dict(raw_manual_handoff) if isinstance(raw_manual_handoff, dict) else {}
    if manual_handoff and not manual_handoff.get("handoffCommand"):
        manual_handoff["handoffCommand"] = "bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only"
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
        "helperProcessPolicy": {
            "status": helper_policy.get("status", "missing"),
            "maxHelperRunningProcessCount": helper_policy.get("maxHelperRunningProcessCount"),
            "helperPathMismatch": helper_policy.get("helperPathMismatch"),
            "helperPathMatchesRunningHelper": helper_policy.get("helperPathMatchesRunningHelper"),
            "preservedMismatchedHelperPath": helper_policy.get("preservedMismatchedHelperPath"),
            "mismatchedHelperPaths": helper_policy.get("mismatchedHelperPaths") or [],
            "helperPathMismatchTerminationTimedOut": helper_policy.get("helperPathMismatchTerminationTimedOut"),
            "singleInstanceLockStatus": helper_policy.get("singleInstanceLockStatus"),
            "helperDockPolicy": helper_policy.get("helperDockPolicy"),
        },
        "overlayForegroundCanary": bool(gate.get("overlayForegroundCanary")),
        "overlaySmokeStatus": overlay_smoke.get("status", "not_run"),
        "manualTccHandoff": manual_handoff,
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
    "overlayForegroundCanary": overlay_canary,
    "preset": preset,
    "stabilityMode": stability_mode,
    "stable": failed_count == 0,
    "runCount": len(runs),
    "passed": passed_count,
    "failed": failed_count,
    "passRate": 0 if not runs else passed_count / len(runs),
    "failureClasses": failure_classes,
    "manualTccHandoff": next((run.get("manualTccHandoff") for run in runs if run.get("manualTccHandoff")), {
        "status": "manual_required",
        "automationBoundary": "user_operated_tcc_only",
        "handoffCommand": "bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only",
        "manualCommand": "bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff",
        "summaryCommand": "dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report-or-summary.json>",
    }),
    "runs": runs,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use Live Canary Summary",
    "",
    "- Purpose: helper launch, IPC, ping, permission reporting, and cleanup",
    "- TCC boundary: user-operated manual verification only",
    f"- Overlay foreground canary: {str(overlay_canary).lower()}",
    f"- Preset: {preset}",
    f"- Stability mode: {str(stability_mode).lower()}",
    f"- Stable: {str(summary['stable']).lower()}",
    f"- Run count: {len(runs)}",
    f"- Passed: {passed_count}",
    f"- Failed: {failed_count}",
    f"- Pass rate: {summary['passRate'] * 100:.1f}%",
]
manual = summary["manualTccHandoff"]
if manual:
    lines.extend([
        f"- Manual TCC handoff command: `{manual.get('handoffCommand', '-')}`",
        f"- Manual TCC command: `{manual.get('manualCommand', '-')}`",
        f"- Manual TCC parser: `{manual.get('summaryCommand', '-')}`",
    ])
lines.extend([
    "",
    "| Run | Status | Failure Class | Gate | Blockers | Helper Policy | Overlay | IPC | Artifacts |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
])
for run in runs:
    blockers = ", ".join(str(item) for item in run.get("blockers") or []) or "-"
    helper_policy = run.get("helperProcessPolicy") or {}
    preserved_mismatch = helper_policy.get("preservedMismatchedHelperPath") is True
    path_mismatch = helper_policy.get("helperPathMismatch") is True
    path_match = helper_policy.get("helperPathMatchesRunningHelper") is True
    helper_identity = (
        "preserved_running_helper" if preserved_mismatch else
        "path_mismatch" if path_mismatch else
        "matched" if path_match else
        "unknown"
    )
    helper_bits = [
        f"status={helper_policy.get('status', '-')}",
        f"identity={helper_identity}",
        f"count={helper_policy.get('maxHelperRunningProcessCount', '-')}",
        f"pathMismatch={str(helper_policy.get('helperPathMismatch')).lower()}",
        f"pathMatch={str(helper_policy.get('helperPathMatchesRunningHelper')).lower()}",
        f"preserved={str(helper_policy.get('preservedMismatchedHelperPath')).lower()}",
        f"lock={helper_policy.get('singleInstanceLockStatus', '-')}",
        f"dock={helper_policy.get('helperDockPolicy', '-')}",
    ]
    if helper_policy.get("helperPathMismatchTerminationTimedOut"):
        helper_bits.append("terminationTimedOut=true")
    mismatched_paths = helper_policy.get("mismatchedHelperPaths") or []
    if mismatched_paths:
        helper_bits.append("mismatchedPaths=" + ", ".join(str(item) for item in mismatched_paths))
    helper_summary = "<br>".join(helper_bits)
    artifacts = f"report: `{run['report']}`<br>log: `{run['log']}`"
    lines.append(
        "| {name} | {status} | {failureClass} | {gateStatus} | {blockers} | {helper} | {overlay} | {ipc} | {artifacts} |".format(
            name=run["name"],
            status=run["status"],
            failureClass=run["failureClass"],
            gateStatus=run.get("gateStatus", "-"),
            blockers=blockers,
            helper=helper_summary,
            overlay=run.get("overlaySmokeStatus") or "-",
            ipc=run.get("selectedIpcTransport") or "-",
            artifacts=artifacts,
        )
    )
summary_md.write_text("\n".join(lines) + "\n")

print(summary_md.read_text())
PY

echo "Canary summary written to ${SUMMARY_JSON}"
exit "${status}"

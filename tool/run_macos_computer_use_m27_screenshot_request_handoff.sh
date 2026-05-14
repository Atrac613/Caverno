#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M27_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m27_screenshot_request_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/screenshot_request_handoff.json"
SUMMARY_MD="${RUN_DIR}/screenshot_request_handoff.md"
M26_PACKET=""
SCREENSHOT_PATH=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m27_screenshot_request_handoff.sh [options]

Options:
  --root PATH                    Report root directory.
  --m26-packet PATH              M26 observe restart packet JSON.
  --screenshot PATH              Optional user-provided screenshot path.
  --help                         Show this help.

This M27 handoff is report-only. It reads a ready M26 observe restart packet
and freezes the manual screenshot request needed for the next M14 observe-only
pass. It does not call an LLM, grant TCC, open apps, operate System Settings,
capture screens, move the pointer, click, type, submit, post, purchase, or
perform desktop actions.
USAGE
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --m26-packet)
      require_value "$@"
      M26_PACKET="$2"
      shift 2
      ;;
    --screenshot)
      require_value "$@"
      SCREENSHOT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m27_screenshot_request_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/screenshot_request_handoff.json"
SUMMARY_MD="${RUN_DIR}/screenshot_request_handoff.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M26_PACKET}" ]]; then
  M26_PACKET="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m26_observe_restart_packet_*/observe_restart_packet.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M26_PACKET}" ]]; then
  echo "M26 observe restart packet not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M26_PACKET}" ]]; then
  echo "M26 observe restart packet not found: ${M26_PACKET}" >&2
  exit 66
fi
if [[ -n "${SCREENSHOT_PATH}" && ! -f "${SCREENSHOT_PATH}" ]]; then
  echo "Screenshot not found: ${SCREENSHOT_PATH}" >&2
  exit 66
fi

echo "Running macOS Computer Use M27 screenshot request handoff"
echo "  Purpose: prepare the user-operated screenshot request for the next M14 observe pass"
echo "  M26 packet: ${M26_PACKET}"
echo "  Screenshot: ${SCREENSHOT_PATH:-user-provided later}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
REPORT_ROOT="${REPORT_ROOT}" \
M26_PACKET="${M26_PACKET}" \
SCREENSHOT_PATH="${SCREENSHOT_PATH}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
report_root = os.environ["REPORT_ROOT"]
m26_packet_path = Path(os.environ["M26_PACKET"])
screenshot_path = os.environ["SCREENSHOT_PATH"].strip()

m26 = json.loads(m26_packet_path.read_text())
gate = m26.get("m26ObserveRestartPacketGate")
gate = gate if isinstance(gate, dict) else {}
next_observe = m26.get("nextObservePreparation")
next_observe = next_observe if isinstance(next_observe, dict) else {}
commands = m26.get("commands")
commands = commands if isinstance(commands, dict) else {}

target_app = str(m26.get("targetApp") or next_observe.get("targetApp") or "").strip()
target_intent = str(
    m26.get("targetIntent") or next_observe.get("targetIntent") or ""
).strip()
return_milestone = str(next_observe.get("returnMilestone") or "")
observe_boundary = str(next_observe.get("boundary") or "")
m14_handoff_command = str(commands.get("m14RealAppHandoff") or "").strip()
source_m14_observe_command = str(commands.get("m14ObserveCanary") or "").strip()


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


placeholder_screenshot = "<user-provided-real-app-screenshot.png>"

m14_observe_args = [
    "bash",
    "tool/run_macos_computer_use_real_app_observe_canary.sh",
    "--root",
    report_root,
    "--screenshot",
    screenshot_path or placeholder_screenshot,
    "--target-app",
    target_app or "<target-app>",
    "--target-intent",
    target_intent or "<target-intent>",
]
m14_observe_command = shell_join(m14_observe_args)
artifact_index_command = shell_join(
    [
        "dart",
        "run",
        "tool/macos_computer_use_readiness_artifact_index.dart",
        "--root",
        report_root,
    ]
)
signoff_dry_run_command = shell_join(
    [
        "bash",
        "tool/run_macos_computer_use_mvp_signoff.sh",
        "--dry-run",
        "--root",
        report_root,
    ]
)

checks = [
    {
        "id": "m26_packet_schema_valid",
        "ok": m26.get("schemaName") == "macos_computer_use_m26_observe_restart_packet"
        and m26.get("milestone") == "M26",
        "nextAction": "Select a valid M26 observe_restart_packet.json before preparing the screenshot request.",
    },
    {
        "id": "m26_packet_ready",
        "ok": bool(m26.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M26 observe restart packet until m26ObserveRestartPacketGate.status is ready.",
    },
    {
        "id": "m26_return_m14",
        "ok": return_milestone == "M14",
        "nextAction": "Use an M26 packet whose nextObservePreparation.returnMilestone is M14.",
    },
    {
        "id": "m26_observe_boundary",
        "ok": observe_boundary == "observe_only_no_desktop_action",
        "nextAction": "Keep the screenshot request pointed at observe-only M14 evidence.",
    },
    {
        "id": "target_app_present",
        "ok": bool(target_app),
        "nextAction": "Provide the target app name before asking for a manual screenshot.",
    },
    {
        "id": "target_intent_present",
        "ok": bool(target_intent),
        "nextAction": "Provide the target intent before asking for a manual screenshot.",
    },
    {
        "id": "screenshot_required",
        "ok": next_observe.get("screenshotRequired") is True,
        "nextAction": "Keep the next M14 observe pass gated by a user-provided screenshot.",
    },
    {
        "id": "m14_observe_command_present",
        "ok": bool(source_m14_observe_command or m14_observe_command),
        "nextAction": "Prepare the M14 observe-only canary command before requesting the screenshot.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": m26.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M27 must only prepare a screenshot request; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m26.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M27.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m26.get("llmBoundary") == "no_llm_call",
        "nextAction": "M27 screenshot request handoff must not call an LLM.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Ask the user to manually prepare the target app, capture the requested screenshot, and run the M14 observe-only canary command."
    if ready
    else "Resolve M27 screenshot request handoff blockers before asking for the manual screenshot."
)

summary = {
    "schemaName": "macos_computer_use_m27_screenshot_request_handoff",
    "schemaVersion": 1,
    "purpose": "computer_use_m27_screenshot_request_handoff",
    "milestone": "M27",
    "previousMilestone": "M26",
    "ready": ready,
    "sourceM26ObserveRestartPacket": str(m26_packet_path),
    "executionBoundary": "manual_screenshot_request_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "targetApp": target_app,
    "targetIntent": target_intent,
    "screenshotPath": screenshot_path or None,
    "userScreenshotRequest": {
        "required": True,
        "provided": bool(screenshot_path),
        "targetApp": target_app,
        "targetIntent": target_intent,
        "returnMilestone": "M14",
        "boundary": "observe_only_no_desktop_action",
        "preparationSteps": [
            "Manually open the target app.",
            "Manually prepare the app state described by the target intent.",
            "Manually capture a screenshot of that state.",
            "Run the M14 observe-only canary with the user-provided screenshot.",
        ],
    },
    "commands": {
        "m14RealAppHandoff": m14_handoff_command,
        "m14ObserveCanary": m14_observe_command,
        "artifactIndex": artifact_index_command,
        "mvpSignoffDryRun": signoff_dry_run_command,
    },
    "m27ScreenshotRequestHandoffGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This handoff only prepares a user-operated screenshot request.",
        "It does not start M14.",
        "The screenshot must be prepared by the user.",
        "TCC, System Settings, LLM calls, app launches, screenshots, clicks, typing, submits, posts, and purchases remain outside this script.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M27 Screenshot Request Handoff",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M26 observe restart packet: `{m26_packet_path}`",
    "- Boundary: report-only manual screenshot request, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Target app: {target_app or '-'}",
    f"- Target intent: {target_intent or '-'}",
    f"- Screenshot: {screenshot_path or 'user-provided later'}",
    "",
    "## Gate",
    "",
]
for check in checks:
    status = "ready" if check["ok"] else "blocked"
    md_lines.append(
        f"- `{check['id']}`: {status}"
        + ("" if check["ok"] else f" - {check['nextAction']}")
    )

md_lines.extend(
    [
        "",
        "## User Screenshot Request",
        "",
        "1. Manually open the target app.",
        "2. Manually prepare the app state described by the target intent.",
        "3. Manually capture a screenshot of that state.",
        "4. Run the M14 observe-only canary command below.",
        "",
        "## Commands",
        "",
        "M14 observe-only canary:",
        "",
        "```bash",
        m14_observe_command,
        "```",
        "",
        "Readiness rehearsal:",
        "",
        "```bash",
        artifact_index_command,
        signoff_dry_run_command,
        "```",
        "",
        "## Request Details",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Return milestone | {cell('M14')} |",
        f"| Boundary | {cell('observe_only_no_desktop_action')} |",
        f"| Target app | {cell(target_app)} |",
        f"| Target intent | {cell(target_intent)} |",
        f"| Screenshot provided | {cell(bool(screenshot_path))} |",
        "",
        "## Manual Boundary",
        "",
        "This handoff only prepares the user screenshot request for the next",
        "observe-only pass. It does not start M14, open apps, capture screens,",
        "click, type, submit, post, purchase, grant TCC, operate System Settings,",
        "or call an LLM.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M27 screenshot request handoff written to {summary_json}")
print(f"M27 screenshot request handoff Markdown written to {summary_md}")
print(f"Gate status: {summary['m27ScreenshotRequestHandoffGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Target app: {target_app or '-'}")
print(f"Target intent: {target_intent or '-'}")
print(f"M14 observe command: {m14_observe_command}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

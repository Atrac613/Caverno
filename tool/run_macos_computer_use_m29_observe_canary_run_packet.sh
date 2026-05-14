#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M29_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m29_observe_canary_run_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_canary_run_packet.json"
SUMMARY_MD="${RUN_DIR}/observe_canary_run_packet.md"
M28_INTAKE=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m29_observe_canary_run_packet.sh [options]

Options:
  --root PATH                    Report root directory.
  --m28-intake PATH              M28 screenshot evidence intake JSON.
  --help                         Show this help.

This M29 run packet is report-only. It reads a ready M28 screenshot evidence
intake, rechecks the user-provided screenshot path, and freezes the exact M14
observe-only canary command the user can run next. It does not call an LLM,
grant TCC, open apps, operate System Settings, capture screens, move the
pointer, click, type, submit, post, purchase, or perform desktop actions.
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
    --m28-intake)
      require_value "$@"
      M28_INTAKE="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m29_observe_canary_run_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_canary_run_packet.json"
SUMMARY_MD="${RUN_DIR}/observe_canary_run_packet.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M28_INTAKE}" ]]; then
  M28_INTAKE="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m28_screenshot_evidence_intake_*/screenshot_evidence_intake.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M28_INTAKE}" ]]; then
  echo "M28 screenshot evidence intake not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M28_INTAKE}" ]]; then
  echo "M28 screenshot evidence intake not found: ${M28_INTAKE}" >&2
  exit 66
fi

echo "Running macOS Computer Use M29 observe canary run packet"
echo "  Purpose: freeze the next user-operated M14 observe-only canary command"
echo "  M28 intake: ${M28_INTAKE}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
REPORT_ROOT="${REPORT_ROOT}" \
M28_INTAKE="${M28_INTAKE}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
report_root = os.environ["REPORT_ROOT"]
m28_intake_path = Path(os.environ["M28_INTAKE"])

m28 = json.loads(m28_intake_path.read_text())
gate = m28.get("m28ScreenshotEvidenceIntakeGate")
gate = gate if isinstance(gate, dict) else {}
evidence = m28.get("screenshotEvidence")
evidence = evidence if isinstance(evidence, dict) else {}
next_input = m28.get("nextObserveInput")
next_input = next_input if isinstance(next_input, dict) else {}
commands = m28.get("commands")
commands = commands if isinstance(commands, dict) else {}

target_app = str(m28.get("targetApp") or next_input.get("targetApp") or "").strip()
target_intent = str(
    m28.get("targetIntent") or next_input.get("targetIntent") or ""
).strip()
return_milestone = str(next_input.get("returnMilestone") or "")
observe_boundary = str(next_input.get("boundary") or "")
screenshot_path_text = str(evidence.get("path") or next_input.get("screenshotPath") or "")
screenshot_path = Path(screenshot_path_text) if screenshot_path_text else None
screenshot_exists = bool(screenshot_path and screenshot_path.is_file())
screenshot_size_bytes = screenshot_path.stat().st_size if screenshot_exists else 0
screenshot_suffix = screenshot_path.suffix.lower() if screenshot_path else ""
source_m14_observe_command = str(commands.get("m14ObserveCanary") or "").strip()


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


m14_observe_args = [
    "bash",
    "tool/run_macos_computer_use_real_app_observe_canary.sh",
    "--root",
    report_root,
    "--screenshot",
    screenshot_path_text or "<user-provided-real-app-screenshot.png>",
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
        "id": "m28_intake_schema_valid",
        "ok": m28.get("schemaName") == "macos_computer_use_m28_screenshot_evidence_intake"
        and m28.get("milestone") == "M28",
        "nextAction": "Select a valid M28 screenshot_evidence_intake.json before preparing the M14 run packet.",
    },
    {
        "id": "m28_intake_ready",
        "ok": bool(m28.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M28 screenshot evidence intake until m28ScreenshotEvidenceIntakeGate.status is ready.",
    },
    {
        "id": "m28_return_m14",
        "ok": return_milestone == "M14",
        "nextAction": "Use an M28 intake whose nextObserveInput.returnMilestone is M14.",
    },
    {
        "id": "m28_observe_boundary",
        "ok": observe_boundary == "observe_only_no_desktop_action",
        "nextAction": "Keep the run packet pointed at observe-only M14 evidence.",
    },
    {
        "id": "target_app_present",
        "ok": bool(target_app),
        "nextAction": "Provide the target app name before preparing the M14 run packet.",
    },
    {
        "id": "target_intent_present",
        "ok": bool(target_intent),
        "nextAction": "Provide the target intent before preparing the M14 run packet.",
    },
    {
        "id": "screenshot_evidence_present",
        "ok": bool(screenshot_path_text),
        "nextAction": "Use an M28 intake with screenshotEvidence.path populated.",
    },
    {
        "id": "screenshot_file_present",
        "ok": screenshot_exists,
        "nextAction": "Keep the user-provided screenshot file available before asking the user to run M14.",
    },
    {
        "id": "screenshot_file_non_empty",
        "ok": screenshot_size_bytes > 0,
        "nextAction": "Use a non-empty user-provided screenshot file.",
    },
    {
        "id": "screenshot_file_extension_known",
        "ok": screenshot_suffix in {".png", ".jpg", ".jpeg", ".heic", ".tiff", ".webp"},
        "nextAction": "Use a screenshot file with a common image extension.",
    },
    {
        "id": "m14_observe_command_present",
        "ok": bool(source_m14_observe_command or m14_observe_command),
        "nextAction": "Prepare an M14 observe-only canary command.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": m28.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M29 must only prepare the run packet; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m28.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M29.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m28.get("llmBoundary") == "no_llm_call",
        "nextAction": "M29 observe canary run packet must not call an LLM.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Ask the user to run the M14 observe-only canary command with the recorded screenshot, then review the new M14 evidence."
    if ready
    else "Resolve M29 observe canary run packet blockers before asking the user to run M14."
)

summary = {
    "schemaName": "macos_computer_use_m29_observe_canary_run_packet",
    "schemaVersion": 1,
    "purpose": "computer_use_m29_observe_canary_run_packet",
    "milestone": "M29",
    "previousMilestone": "M28",
    "ready": ready,
    "sourceM28ScreenshotEvidenceIntake": str(m28_intake_path),
    "executionBoundary": "m14_observe_canary_run_packet_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "targetApp": target_app,
    "targetIntent": target_intent,
    "screenshotEvidence": {
        "path": screenshot_path_text,
        "exists": screenshot_exists,
        "sizeBytes": screenshot_size_bytes,
        "extension": screenshot_suffix,
        "source": "m28_screenshot_evidence_intake",
    },
    "m14ObserveRunPacket": {
        "required": True,
        "readyForUserOperation": ready,
        "userOperated": True,
        "returnMilestone": "M14",
        "boundary": "observe_only_no_desktop_action",
        "targetApp": target_app,
        "targetIntent": target_intent,
        "screenshotPath": screenshot_path_text,
        "command": m14_observe_command,
    },
    "commands": {
        "m14ObserveCanary": m14_observe_command,
        "artifactIndex": artifact_index_command,
        "mvpSignoffDryRun": signoff_dry_run_command,
    },
    "m29ObserveCanaryRunPacketGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This packet only freezes the user-operated M14 observe-only command.",
        "It does not start M14.",
        "The user remains responsible for running the command and providing the resulting evidence.",
        "TCC, System Settings, LLM calls, app launches, screenshots, clicks, typing, submits, posts, and purchases remain outside this script.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M29 Observe Canary Run Packet",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M28 screenshot evidence intake: `{m28_intake_path}`",
    "- Boundary: report-only M14 observe canary run packet, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Target app: {target_app or '-'}",
    f"- Target intent: {target_intent or '-'}",
    f"- Screenshot: `{screenshot_path_text or '-'}`",
    f"- Screenshot bytes: {screenshot_size_bytes}",
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
        "## M14 Observe Run Packet",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Return milestone | {cell('M14')} |",
        f"| Boundary | {cell('observe_only_no_desktop_action')} |",
        f"| User operated | {cell(True)} |",
        f"| Target app | {cell(target_app)} |",
        f"| Target intent | {cell(target_intent)} |",
        f"| Screenshot path | {cell(screenshot_path_text)} |",
        f"| Screenshot bytes | {cell(screenshot_size_bytes)} |",
        "",
        "## Command For User",
        "",
        "```bash",
        m14_observe_command,
        "```",
        "",
        "## Readiness Rehearsal",
        "",
        "```bash",
        artifact_index_command,
        signoff_dry_run_command,
        "```",
        "",
        "## Manual Boundary",
        "",
        "This packet only freezes the user-operated M14 observe-only command.",
        "It does not start M14, open apps, capture screens, click, type, submit,",
        "post, purchase, grant TCC, operate System Settings, or call an LLM.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M29 observe canary run packet written to {summary_json}")
print(f"M29 observe canary run packet Markdown written to {summary_md}")
print(f"Gate status: {summary['m29ObserveCanaryRunPacketGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Target app: {target_app or '-'}")
print(f"Target intent: {target_intent or '-'}")
print(f"Screenshot bytes: {screenshot_size_bytes}")
print(f"M14 observe command: {m14_observe_command}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M28_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m28_screenshot_evidence_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/screenshot_evidence_intake.json"
SUMMARY_MD="${RUN_DIR}/screenshot_evidence_intake.md"
M27_HANDOFF=""
SCREENSHOT_PATH=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh [options]

Options:
  --root PATH                    Report root directory.
  --m27-handoff PATH             M27 screenshot request handoff JSON.
  --screenshot PATH              User-provided screenshot path.
  --help                         Show this help.

This M28 intake is report-only. It reads a ready M27 screenshot request
handoff, verifies that the user-provided screenshot file exists, and prepares
the M14 observe-only canary command with that screenshot path. It does not call
an LLM, grant TCC, open apps, operate System Settings, capture screens, move
the pointer, click, type, submit, post, purchase, or perform desktop actions.
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
    --m27-handoff)
      require_value "$@"
      M27_HANDOFF="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m28_screenshot_evidence_intake_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/screenshot_evidence_intake.json"
SUMMARY_MD="${RUN_DIR}/screenshot_evidence_intake.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M27_HANDOFF}" ]]; then
  M27_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m27_screenshot_request_handoff_*/screenshot_request_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M27_HANDOFF}" ]]; then
  echo "M27 screenshot request handoff not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M27_HANDOFF}" ]]; then
  echo "M27 screenshot request handoff not found: ${M27_HANDOFF}" >&2
  exit 66
fi
if [[ -z "${SCREENSHOT_PATH}" ]]; then
  echo "--screenshot is required for M28 screenshot evidence intake." >&2
  exit 64
fi
if [[ ! -f "${SCREENSHOT_PATH}" ]]; then
  echo "Screenshot not found: ${SCREENSHOT_PATH}" >&2
  exit 66
fi

echo "Running macOS Computer Use M28 screenshot evidence intake"
echo "  Purpose: bind the user-provided screenshot to the next M14 observe-only canary"
echo "  M27 handoff: ${M27_HANDOFF}"
echo "  Screenshot: ${SCREENSHOT_PATH}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
REPORT_ROOT="${REPORT_ROOT}" \
M27_HANDOFF="${M27_HANDOFF}" \
SCREENSHOT_PATH="${SCREENSHOT_PATH}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
report_root = os.environ["REPORT_ROOT"]
m27_handoff_path = Path(os.environ["M27_HANDOFF"])
screenshot_path = Path(os.environ["SCREENSHOT_PATH"])

m27 = json.loads(m27_handoff_path.read_text())
gate = m27.get("m27ScreenshotRequestHandoffGate")
gate = gate if isinstance(gate, dict) else {}
request = m27.get("userScreenshotRequest")
request = request if isinstance(request, dict) else {}
commands = m27.get("commands")
commands = commands if isinstance(commands, dict) else {}

target_app = str(m27.get("targetApp") or request.get("targetApp") or "").strip()
target_intent = str(
    m27.get("targetIntent") or request.get("targetIntent") or ""
).strip()
return_milestone = str(request.get("returnMilestone") or "")
observe_boundary = str(request.get("boundary") or "")
source_m14_handoff_command = str(commands.get("m14RealAppHandoff") or "").strip()
source_m14_observe_command = str(commands.get("m14ObserveCanary") or "").strip()

screenshot_exists = screenshot_path.is_file()
screenshot_size_bytes = screenshot_path.stat().st_size if screenshot_exists else 0
screenshot_suffix = screenshot_path.suffix.lower()


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


m14_observe_args = [
    "bash",
    "tool/run_macos_computer_use_real_app_observe_canary.sh",
    "--root",
    report_root,
    "--screenshot",
    str(screenshot_path),
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
        "id": "m27_handoff_schema_valid",
        "ok": m27.get("schemaName") == "macos_computer_use_m27_screenshot_request_handoff"
        and m27.get("milestone") == "M27",
        "nextAction": "Select a valid M27 screenshot_request_handoff.json before intaking screenshot evidence.",
    },
    {
        "id": "m27_handoff_ready",
        "ok": bool(m27.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M27 screenshot request handoff until m27ScreenshotRequestHandoffGate.status is ready.",
    },
    {
        "id": "m27_return_m14",
        "ok": return_milestone == "M14",
        "nextAction": "Use an M27 handoff whose userScreenshotRequest.returnMilestone is M14.",
    },
    {
        "id": "m27_observe_boundary",
        "ok": observe_boundary == "observe_only_no_desktop_action",
        "nextAction": "Keep the screenshot evidence pointed at observe-only M14 evidence.",
    },
    {
        "id": "target_app_present",
        "ok": bool(target_app),
        "nextAction": "Provide the target app name before intaking screenshot evidence.",
    },
    {
        "id": "target_intent_present",
        "ok": bool(target_intent),
        "nextAction": "Provide the target intent before intaking screenshot evidence.",
    },
    {
        "id": "screenshot_request_required",
        "ok": request.get("required") is True,
        "nextAction": "Keep M28 tied to an explicit M27 screenshot request.",
    },
    {
        "id": "screenshot_file_present",
        "ok": screenshot_exists,
        "nextAction": "Provide an existing user-captured screenshot path.",
    },
    {
        "id": "screenshot_file_non_empty",
        "ok": screenshot_size_bytes > 0,
        "nextAction": "Provide a non-empty screenshot file.",
    },
    {
        "id": "screenshot_file_extension_known",
        "ok": screenshot_suffix in {".png", ".jpg", ".jpeg", ".heic", ".tiff", ".webp"},
        "nextAction": "Provide a screenshot file with a common image extension.",
    },
    {
        "id": "m14_observe_command_prepared",
        "ok": bool(source_m14_observe_command or m14_observe_command),
        "nextAction": "Prepare the M14 observe-only canary command with the screenshot path.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": m27.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M28 must only intake screenshot evidence; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m27.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M28.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m27.get("llmBoundary") == "no_llm_call",
        "nextAction": "M28 screenshot evidence intake must not call an LLM.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Run the M14 observe-only canary with the user-provided screenshot, then continue the approval-bound observe/action cycle."
    if ready
    else "Resolve M28 screenshot evidence intake blockers before running the M14 observe-only canary."
)

summary = {
    "schemaName": "macos_computer_use_m28_screenshot_evidence_intake",
    "schemaVersion": 1,
    "purpose": "computer_use_m28_screenshot_evidence_intake",
    "milestone": "M28",
    "previousMilestone": "M27",
    "ready": ready,
    "sourceM27ScreenshotRequestHandoff": str(m27_handoff_path),
    "executionBoundary": "manual_screenshot_evidence_intake_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "targetApp": target_app,
    "targetIntent": target_intent,
    "screenshotEvidence": {
        "path": str(screenshot_path),
        "exists": screenshot_exists,
        "sizeBytes": screenshot_size_bytes,
        "extension": screenshot_suffix,
        "source": "user_provided",
    },
    "nextObserveInput": {
        "required": True,
        "provided": screenshot_exists and screenshot_size_bytes > 0,
        "returnMilestone": "M14",
        "boundary": "observe_only_no_desktop_action",
        "targetApp": target_app,
        "targetIntent": target_intent,
        "screenshotPath": str(screenshot_path),
    },
    "commands": {
        "m14RealAppHandoff": source_m14_handoff_command,
        "m14ObserveCanary": m14_observe_command,
        "artifactIndex": artifact_index_command,
        "mvpSignoffDryRun": signoff_dry_run_command,
    },
    "m28ScreenshotEvidenceIntakeGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This intake only binds a user-provided screenshot to the next M14 observe-only command.",
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
    "# macOS Computer Use M28 Screenshot Evidence Intake",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M27 screenshot request handoff: `{m27_handoff_path}`",
    "- Boundary: report-only screenshot evidence intake, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Target app: {target_app or '-'}",
    f"- Target intent: {target_intent or '-'}",
    f"- Screenshot: `{screenshot_path}`",
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
        "## Next Observe Input",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Return milestone | {cell('M14')} |",
        f"| Boundary | {cell('observe_only_no_desktop_action')} |",
        f"| Target app | {cell(target_app)} |",
        f"| Target intent | {cell(target_intent)} |",
        f"| Screenshot path | {cell(screenshot_path)} |",
        f"| Screenshot bytes | {cell(screenshot_size_bytes)} |",
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
        "## Manual Boundary",
        "",
        "This intake only binds a user-provided screenshot to the next",
        "observe-only pass. It does not start M14, open apps, capture screens,",
        "click, type, submit, post, purchase, grant TCC, operate System Settings,",
        "or call an LLM.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M28 screenshot evidence intake written to {summary_json}")
print(f"M28 screenshot evidence intake Markdown written to {summary_md}")
print(f"Gate status: {summary['m28ScreenshotEvidenceIntakeGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Target app: {target_app or '-'}")
print(f"Target intent: {target_intent or '-'}")
print(f"Screenshot bytes: {screenshot_size_bytes}")
print(f"M14 observe command: {m14_observe_command}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

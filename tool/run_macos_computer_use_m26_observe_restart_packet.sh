#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M26_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m26_observe_restart_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_restart_packet.json"
SUMMARY_MD="${RUN_DIR}/observe_restart_packet.md"
M25_HANDOFF=""
TARGET_APP="${CAVERNO_MACOS_COMPUTER_USE_M26_TARGET_APP:-Safari}"
TARGET_INTENT=""
SCREENSHOT_PATH=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m26_observe_restart_packet.sh [options]

Options:
  --root PATH                    Report root directory.
  --m25-handoff PATH             M25 next-cycle seed handoff JSON.
  --target-app NAME              Target app for the next M14 observe pass.
  --target-intent TEXT           Override target intent; defaults to the M25 seed note.
  --screenshot PATH              Optional user-provided screenshot path for generated commands.
  --help                         Show this help.

This M26 packet is report-only. It reads a ready M25 next-cycle seed and
prepares the next M14 observe-only command set. It does not call an LLM, grant
TCC, open apps, operate System Settings, capture screens, move the pointer,
click, type, submit, post, purchase, or perform desktop actions.
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
    --m25-handoff)
      require_value "$@"
      M25_HANDOFF="$2"
      shift 2
      ;;
    --target-app)
      require_value "$@"
      TARGET_APP="$2"
      shift 2
      ;;
    --target-intent)
      require_value "$@"
      TARGET_INTENT="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m26_observe_restart_packet_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/observe_restart_packet.json"
SUMMARY_MD="${RUN_DIR}/observe_restart_packet.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M25_HANDOFF}" ]]; then
  M25_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m25_next_cycle_seed_handoff_*/next_cycle_seed_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M25_HANDOFF}" ]]; then
  echo "M25 next-cycle seed handoff not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M25_HANDOFF}" ]]; then
  echo "M25 next-cycle seed handoff not found: ${M25_HANDOFF}" >&2
  exit 66
fi
if [[ -n "${SCREENSHOT_PATH}" && ! -f "${SCREENSHOT_PATH}" ]]; then
  echo "Screenshot not found: ${SCREENSHOT_PATH}" >&2
  exit 66
fi

echo "Running macOS Computer Use M26 observe restart packet"
echo "  Purpose: prepare the next M14 observe-only command set from ready M25 seed evidence"
echo "  M25 handoff: ${M25_HANDOFF}"
echo "  Target app: ${TARGET_APP:-not set}"
echo "  Target intent: ${TARGET_INTENT:-from M25 seed note}"
echo "  Screenshot: ${SCREENSHOT_PATH:-user-provided later}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
REPORT_ROOT="${REPORT_ROOT}" \
M25_HANDOFF="${M25_HANDOFF}" \
TARGET_APP="${TARGET_APP}" \
TARGET_INTENT="${TARGET_INTENT}" \
SCREENSHOT_PATH="${SCREENSHOT_PATH}" \
python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
report_root = os.environ["REPORT_ROOT"]
m25_handoff_path = Path(os.environ["M25_HANDOFF"])

m25 = json.loads(m25_handoff_path.read_text())
gate = m25.get("m25NextCycleSeedHandoffGate")
gate = gate if isinstance(gate, dict) else {}
seed_inputs = m25.get("seedInputs")
seed_inputs = seed_inputs if isinstance(seed_inputs, dict) else {}
next_cycle_seed = m25.get("nextCycleSeed")
next_cycle_seed = next_cycle_seed if isinstance(next_cycle_seed, dict) else {}

target_app = os.environ["TARGET_APP"].strip()
target_intent_override = os.environ["TARGET_INTENT"].strip()
screenshot_path = os.environ["SCREENSHOT_PATH"].strip()
seed_note = str(next_cycle_seed.get("note") or "").strip()
target_intent = target_intent_override or seed_note
return_milestone = str(next_cycle_seed.get("returnMilestone") or "")
seed_boundary = str(next_cycle_seed.get("boundary") or "")
seed_accepted = str(seed_inputs.get("seedAccepted") or "").strip().lower()


def shell_join(parts):
    return " ".join(shlex.quote(str(part)) for part in parts)


placeholder_screenshot = "<user-provided-real-app-screenshot.png>"

m14_handoff_args = [
    "bash",
    "tool/run_macos_computer_use_m14_real_app_handoff.sh",
    "--root",
    report_root,
    "--target-app",
    target_app or "<target-app>",
    "--target-intent",
    target_intent or "<target-intent>",
]
if screenshot_path:
    m14_handoff_args.extend(["--screenshot", screenshot_path])

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

artifact_index_args = [
    "dart",
    "run",
    "tool/macos_computer_use_readiness_artifact_index.dart",
    "--root",
    report_root,
]
signoff_dry_run_args = [
    "bash",
    "tool/run_macos_computer_use_mvp_signoff.sh",
    "--dry-run",
    "--root",
    report_root,
]

m14_handoff_command = shell_join(m14_handoff_args)
m14_observe_command = shell_join(m14_observe_args)
artifact_index_command = shell_join(artifact_index_args)
signoff_dry_run_command = shell_join(signoff_dry_run_args)

checks = [
    {
        "id": "m25_handoff_schema_valid",
        "ok": m25.get("schemaName") == "macos_computer_use_m25_next_cycle_seed_handoff"
        and m25.get("milestone") == "M25",
        "nextAction": "Select a valid M25 next_cycle_seed_handoff.json before preparing the restart packet.",
    },
    {
        "id": "m25_handoff_ready",
        "ok": bool(m25.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M25 next-cycle seed handoff until m25NextCycleSeedHandoffGate.status is ready.",
    },
    {
        "id": "m25_seed_accepted",
        "ok": seed_accepted == "yes",
        "nextAction": "Accept the next M14 seed in M25 before preparing the M26 restart packet.",
    },
    {
        "id": "m25_return_m14",
        "ok": return_milestone == "M14",
        "nextAction": "Use an M25 seed whose nextCycleSeed.returnMilestone is M14.",
    },
    {
        "id": "m25_seed_boundary_observe_only",
        "ok": seed_boundary == "observe_only_no_desktop_action",
        "nextAction": "Keep the restart packet pointed at observe-only M14 evidence.",
    },
    {
        "id": "m25_seed_note_present",
        "ok": bool(seed_note),
        "nextAction": "Record the next observe seed note in M25 before preparing M26.",
    },
    {
        "id": "target_app_present",
        "ok": bool(target_app),
        "nextAction": "Provide the target app name for the next M14 observe pass.",
    },
    {
        "id": "target_intent_present",
        "ok": bool(target_intent),
        "nextAction": "Provide the target intent or a non-empty M25 seed note for the next M14 observe pass.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": m25.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M26 must only read M25 evidence and prepare commands; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m25.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M26.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m25.get("llmBoundary") == "no_llm_call",
        "nextAction": "M26 observe restart packet must not call an LLM.",
    },
    {
        "id": "m14_commands_prepared",
        "ok": bool(m14_handoff_command) and bool(m14_observe_command),
        "nextAction": "Prepare the report-only M14 handoff and user-operated observe canary commands.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Ask the user to manually prepare the target app, capture a screenshot, and run the M14 observe-only canary command."
    if ready
    else "Resolve M26 observe restart packet blockers before asking for a new M14 screenshot."
)

summary = {
    "schemaName": "macos_computer_use_m26_observe_restart_packet",
    "schemaVersion": 1,
    "purpose": "computer_use_m26_observe_restart_packet",
    "milestone": "M26",
    "previousMilestone": "M25",
    "ready": ready,
    "sourceM25NextCycleSeedHandoff": str(m25_handoff_path),
    "executionBoundary": "m14_observe_restart_packet_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "targetApp": target_app,
    "targetIntent": target_intent,
    "screenshotPath": screenshot_path or None,
    "sourceSeedInputs": seed_inputs,
    "sourceNextCycleSeed": next_cycle_seed,
    "nextObservePreparation": {
        "required": True,
        "returnMilestone": "M14",
        "boundary": "observe_only_no_desktop_action",
        "targetApp": target_app,
        "targetIntent": target_intent,
        "screenshotRequired": True,
        "screenshotProvided": bool(screenshot_path),
        "userOperatedPreparationSteps": [
            "Manually open the target app.",
            "Manually prepare the app state described by the target intent.",
            "Manually capture a screenshot of that state.",
            "Run the M14 real-app observe canary with the user-provided screenshot.",
        ],
    },
    "commands": {
        "m14RealAppHandoff": m14_handoff_command,
        "m14ObserveCanary": m14_observe_command,
        "artifactIndex": artifact_index_command,
        "mvpSignoffDryRun": signoff_dry_run_command,
    },
    "m26ObserveRestartPacketGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This packet does not start M14.",
        "It only prepares the next M14 observe-only command set from ready M25 seed evidence.",
        "The screenshot must be prepared by the user.",
        "TCC, System Settings, LLM calls, app launches, screenshots, clicks, typing, submits, posts, and purchases remain outside this script.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M26 Observe Restart Packet",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M25 next-cycle seed handoff: `{m25_handoff_path}`",
    "- Boundary: report-only M14 observe restart packet, no LLM call, no TCC, no System Settings, no desktop actions",
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
        "## User-Operated Preparation",
        "",
        "1. Manually open the target app.",
        "2. Manually prepare the app state described by the target intent.",
        "3. Manually capture a screenshot of that state.",
        "4. Run the M14 observe-only canary command below.",
        "",
        "## Commands",
        "",
        "M14 real-app handoff:",
        "",
        "```bash",
        m14_handoff_command,
        "```",
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
        "## Next Observe Preparation",
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
        "This packet only prepares commands and instructions for the next",
        "observe-only pass. It does not start M14, open apps, capture screens,",
        "click, type, submit, post, purchase, grant TCC, operate System Settings,",
        "or call an LLM.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M26 observe restart packet written to {summary_json}")
print(f"M26 observe restart packet Markdown written to {summary_md}")
print(f"Gate status: {summary['m26ObserveRestartPacketGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Target app: {target_app or '-'}")
print(f"Target intent: {target_intent or '-'}")
print(f"M14 observe command: {m14_observe_command}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

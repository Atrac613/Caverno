#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M25_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m25_next_cycle_seed_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/next_cycle_seed_handoff.json"
SUMMARY_MD="${RUN_DIR}/next_cycle_seed_handoff.md"
M23_HANDOFF=""
SEED_ACCEPTED="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh [options]

Options:
  --root PATH                    Report root directory.
  --m23-handoff PATH             M23 cycle outcome handoff JSON.
  --seed-accepted VALUE          yes or no.
  --help                         Show this help.

This M25 handoff is report-only. It reads a ready M23 cycle outcome handoff
that requires a new observe-only pass and freezes the next M14 seed. It does
not call an LLM, grant TCC, open apps, operate System Settings, move the
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
    --m23-handoff)
      require_value "$@"
      M23_HANDOFF="$2"
      shift 2
      ;;
    --seed-accepted)
      require_value "$@"
      SEED_ACCEPTED="$2"
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m25_next_cycle_seed_handoff_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/next_cycle_seed_handoff.json"
SUMMARY_MD="${RUN_DIR}/next_cycle_seed_handoff.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M23_HANDOFF}" ]]; then
  M23_HANDOFF="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m23_cycle_outcome_handoff_*/cycle_outcome_handoff.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M23_HANDOFF}" ]]; then
  echo "M23 cycle outcome handoff not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M23_HANDOFF}" ]]; then
  echo "M23 cycle outcome handoff not found: ${M23_HANDOFF}" >&2
  exit 66
fi

echo "Running macOS Computer Use M25 next-cycle seed handoff"
echo "  Purpose: freeze the next M14 observe-only seed from ready M23 restart evidence"
echo "  M23 handoff: ${M23_HANDOFF}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M23_HANDOFF="${M23_HANDOFF}" \
SEED_ACCEPTED="${SEED_ACCEPTED}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m23_handoff_path = Path(os.environ["M23_HANDOFF"])

m23 = json.loads(m23_handoff_path.read_text())
gate = m23.get("m23CycleOutcomeHandoffGate")
gate = gate if isinstance(gate, dict) else {}
handoff_inputs = m23.get("handoffInputs")
handoff_inputs = handoff_inputs if isinstance(handoff_inputs, dict) else {}
next_observe_seed = m23.get("nextObserveSeed")
next_observe_seed = next_observe_seed if isinstance(next_observe_seed, dict) else {}

seed_accepted = os.environ["SEED_ACCEPTED"].strip().lower()
seed_note = str(next_observe_seed.get("note") or "").strip()
return_milestone = str(next_observe_seed.get("returnMilestone") or "")
seed_boundary = str(next_observe_seed.get("boundary") or "")
cycle_outcome = str(m23.get("cycleOutcome") or "unknown")

checks = [
    {
        "id": "m23_handoff_schema_valid",
        "ok": m23.get("schemaName") == "macos_computer_use_m23_cycle_outcome_handoff"
        and m23.get("milestone") == "M23",
        "nextAction": "Select a valid M23 cycle_outcome_handoff.json before preparing the next-cycle seed.",
    },
    {
        "id": "m23_handoff_ready",
        "ok": bool(m23.get("ready")) and gate.get("status") == "ready",
        "nextAction": "Run the M23 cycle outcome handoff until m23CycleOutcomeHandoffGate.status is ready.",
    },
    {
        "id": "m23_restart_cycle",
        "ok": cycle_outcome == "restart_observe_action_cycle",
        "nextAction": "M25 is only required when M23 restarts the observe/action cycle.",
    },
    {
        "id": "next_observe_seed_required",
        "ok": next_observe_seed.get("required") is True,
        "nextAction": "Use an M23 handoff whose nextObserveSeed.required value is true.",
    },
    {
        "id": "next_observe_return_m14",
        "ok": return_milestone == "M14",
        "nextAction": "Keep the next observe seed pointed at M14.",
    },
    {
        "id": "next_observe_boundary",
        "ok": seed_boundary == "observe_only_no_desktop_action",
        "nextAction": "Keep the next observe seed inside the observe-only no-desktop-action boundary.",
    },
    {
        "id": "next_observe_note_present",
        "ok": bool(seed_note),
        "nextAction": "Record the follow-up note that should seed the next M14 observe-only pass.",
    },
    {
        "id": "seed_accepted",
        "ok": seed_accepted == "yes",
        "nextAction": "Ask the user to accept the next M14 seed before preparing follow-up evidence.",
    },
    {
        "id": "desktop_boundary_no_action",
        "ok": m23.get("desktopActionBoundary") == "no_desktop_action",
        "nextAction": "M25 must only read M23 evidence; it must not execute desktop actions.",
    },
    {
        "id": "tcc_boundary_no_tcc",
        "ok": m23.get("tccBoundary") == "no_tcc_operation",
        "nextAction": "TCC and System Settings must remain outside M25.",
    },
    {
        "id": "llm_boundary_no_llm",
        "ok": m23.get("llmBoundary") == "no_llm_call",
        "nextAction": "M25 next-cycle seed handoff must not call an LLM.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
gate_next_action = (
    "Start a new M14 observe-only evidence pass using the recorded next-cycle seed."
    if ready
    else "Resolve M25 next-cycle seed blockers before starting the next observe-only pass."
)

summary = {
    "schemaName": "macos_computer_use_m25_next_cycle_seed_handoff",
    "schemaVersion": 1,
    "purpose": "computer_use_m25_next_cycle_seed_handoff",
    "milestone": "M25",
    "previousMilestone": "M23",
    "ready": ready,
    "sourceM23CycleOutcomeHandoff": str(m23_handoff_path),
    "executionBoundary": "next_cycle_seed_report_only",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceCycleOutcome": cycle_outcome,
    "sourceNextObserveSeed": next_observe_seed,
    "seedInputs": {
        "seedAccepted": seed_accepted,
    },
    "nextCycleSeed": {
        "required": True,
        "source": "m25_next_cycle_seed_handoff",
        "sourceM23CycleOutcomeHandoff": str(m23_handoff_path),
        "returnMilestone": "M14",
        "boundary": "observe_only_no_desktop_action",
        "note": seed_note,
        "requiresNewApprovalCycle": True,
        "mustNotExecuteDesktopAction": True,
    },
    "m25NextCycleSeedHandoffGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": gate_next_action,
    },
    "manualBoundary": [
        "This handoff does not execute desktop actions.",
        "It only freezes the next M14 observe-only seed from ready M23 evidence.",
        "TCC, System Settings, LLM calls, clicks, typing, submits, posts, and purchases remain outside this script.",
        "The next runtime action still requires a fresh observe, proposal, approval, rehearsal, and user-operated handoff cycle.",
    ],
}

summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


md_lines = [
    "# macOS Computer Use M25 Next-Cycle Seed Handoff",
    "",
    f"- Ready: {str(ready).lower()}",
    f"- Source M23 cycle outcome handoff: `{m23_handoff_path}`",
    "- Boundary: report-only next-cycle seed handoff, no LLM call, no TCC, no System Settings, no desktop actions",
    f"- Source cycle outcome: {cycle_outcome}",
    f"- Next M14 seed accepted: {seed_accepted}",
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
        "## Next-Cycle Seed",
        "",
        f"- Return milestone: M14",
        f"- Boundary: observe_only_no_desktop_action",
        f"- Note: {seed_note or '-'}",
        "- Requires new approval cycle: true",
        "",
        "## Source M23 Inputs",
        "",
        "| Input | Value |",
        "| --- | --- |",
    ]
)
for key, value in handoff_inputs.items():
    md_lines.append(f"| {cell(key)} | {cell(value)} |")

md_lines.extend(
    [
        "",
        "## Manual Boundary",
        "",
        "This next-cycle seed handoff only records the observe-only seed for",
        "the next approval-bound cycle. It does not start M14, open apps,",
        "capture screens, click, type, submit, post, purchase, grant TCC,",
        "operate System Settings, or call an LLM.",
        "",
    ]
)

summary_md.write_text("\n".join(md_lines) + "\n")

print(f"M25 next-cycle seed handoff written to {summary_json}")
print(f"M25 next-cycle seed handoff Markdown written to {summary_md}")
print(f"Gate status: {summary['m25NextCycleSeedHandoffGate']['status']}")
print(f"Execution boundary: {summary['executionBoundary']}")
print(f"Next M14 seed note: {seed_note or '-'}")
if blockers:
    print("Blockers: " + ", ".join(blockers))

raise SystemExit(0 if ready else 1)
PY

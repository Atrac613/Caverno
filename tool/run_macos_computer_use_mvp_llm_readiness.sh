#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_LLM_READINESS_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_llm_readiness_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/mvp_llm_readiness_summary.json"
SUMMARY_MD="${RUN_DIR}/mvp_llm_readiness_summary.md"
READINESS_JSON="${RUN_DIR}/macos_computer_use_mvp_llm_readiness.json"
READINESS_MD="${RUN_DIR}/macos_computer_use_mvp_llm_readiness.md"
HANDOFF_MD="${RUN_DIR}/macos_computer_use_mvp_llm_handoff.md"
CLICK_FIXTURE_RESPONSE=""
TYPE_FIXTURE_RESPONSE=""
REPEAT_COUNT="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_REPEAT_COUNT:-1}"

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_llm_readiness.sh [options]

Options:
  --root PATH                    Report root directory.
  --repeat COUNT                 Run each LLM scenario multiple times.
  --fixture-response-click PATH  Use a local response for the safe-click scenario.
  --fixture-response-type PATH   Use a local response for the type-and-confirm scenario.
  --help                         Show this help.

This runner creates automation-safe MVP LLM evidence, feeds it into release
readiness, and writes an MVP handoff dry-run. It does not grant TCC, operate
System Settings, move the pointer, click, or type.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --repeat)
      require_value "$@"
      REPEAT_COUNT="$2"
      shift 2
      ;;
    --fixture-response-click)
      require_value "$@"
      CLICK_FIXTURE_RESPONSE="$2"
      shift 2
      ;;
    --fixture-response-type)
      require_value "$@"
      TYPE_FIXTURE_RESPONSE="$2"
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

if ! [[ "${REPEAT_COUNT}" =~ ^[0-9]+$ ]] || [[ "${REPEAT_COUNT}" -lt 1 ]]; then
  echo "CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_REPEAT_COUNT must be a positive integer." >&2
  exit 64
fi

RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_llm_readiness_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/mvp_llm_readiness_summary.json"
SUMMARY_MD="${RUN_DIR}/mvp_llm_readiness_summary.md"
READINESS_JSON="${RUN_DIR}/macos_computer_use_mvp_llm_readiness.json"
READINESS_MD="${RUN_DIR}/macos_computer_use_mvp_llm_readiness.md"
HANDOFF_MD="${RUN_DIR}/macos_computer_use_mvp_llm_handoff.md"
mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use MVP LLM readiness flow"
echo "  Report root: ${REPORT_ROOT}"
echo "  Run dir: ${RUN_DIR}"
echo "  Repeat count: ${REPEAT_COUNT}"
echo "  TCC boundary: no TCC operation"
echo "  Desktop action boundary: no pointer, keyboard, or click operation"

canary_args=(
  --root "${REPORT_ROOT}"
  --repeat "${REPEAT_COUNT}"
)
if [[ -n "${CLICK_FIXTURE_RESPONSE}" ]]; then
  canary_args+=(--fixture-response-click "${CLICK_FIXTURE_RESPONSE}")
fi
if [[ -n "${TYPE_FIXTURE_RESPONSE}" ]]; then
  canary_args+=(--fixture-response-type "${TYPE_FIXTURE_RESPONSE}")
fi

set +e
bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_fixture_llm_canary.sh" "${canary_args[@]}"
llm_canary_exit=$?
set -e

LLM_SUMMARY_PATH="$(
  REPORT_ROOT="${REPORT_ROOT}" python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["REPORT_ROOT"])
candidates = sorted(
    root.glob("macos_computer_use_mvp_fixture_llm_canary_*/canary_summary.json")
)
print(candidates[-1] if candidates else "")
PY
)"

readiness_exit=66
signoff_dry_run_exit=66
if [[ -n "${LLM_SUMMARY_PATH}" && -f "${LLM_SUMMARY_PATH}" ]]; then
  set +e
  bash "${ROOT_DIR}/tool/run_macos_computer_use_release_readiness.sh" \
    --signoff \
    --no-refresh \
    --root "${REPORT_ROOT}" \
    --llm-canary-summary "${LLM_SUMMARY_PATH}" \
    --output-json "${READINESS_JSON}" \
    --output-md "${READINESS_MD}"
  readiness_exit=$?

  bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_signoff.sh" \
    --dry-run \
    --root "${REPORT_ROOT}" \
    --llm-canary-summary "${LLM_SUMMARY_PATH}" \
    --handoff-md "${HANDOFF_MD}"
  signoff_dry_run_exit=$?
  set -e
else
  echo "LLM canary summary was not produced." >&2
fi

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
LLM_SUMMARY_PATH="${LLM_SUMMARY_PATH}" \
READINESS_JSON="${READINESS_JSON}" \
READINESS_MD="${READINESS_MD}" \
HANDOFF_MD="${HANDOFF_MD}" \
LLM_CANARY_EXIT="${llm_canary_exit}" \
READINESS_EXIT="${readiness_exit}" \
SIGNOFF_DRY_RUN_EXIT="${signoff_dry_run_exit}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
llm_summary_path = Path(os.environ["LLM_SUMMARY_PATH"]) if os.environ["LLM_SUMMARY_PATH"] else None
readiness_json = Path(os.environ["READINESS_JSON"])
readiness_md = Path(os.environ["READINESS_MD"])
handoff_md = Path(os.environ["HANDOFF_MD"])
llm_canary_exit = int(os.environ["LLM_CANARY_EXIT"])
readiness_exit = int(os.environ["READINESS_EXIT"])
signoff_dry_run_exit = int(os.environ["SIGNOFF_DRY_RUN_EXIT"])


def read_json(path):
    if path is None or not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


llm_summary = read_json(llm_summary_path)
readiness = read_json(readiness_json)
gates = readiness.get("gates") if isinstance(readiness, dict) else []
gates = gates if isinstance(gates, list) else []
llm_gate = next(
    (
        gate
        for gate in gates
        if isinstance(gate, dict) and gate.get("id") == "llm_canary"
    ),
    None,
)
blocked_gate_ids = [
    str(gate.get("id"))
    for gate in gates
    if isinstance(gate, dict) and gate.get("ready") is not True
]
manual_gate_ids = {"release_artifact", "computer_use_canary", "manual_tcc", "desktop_action_canary"}
unexpected_blocked = [
    gate_id
    for gate_id in blocked_gate_ids
    if gate_id not in manual_gate_ids and gate_id != "llm_canary"
]
llm_ready = bool(llm_summary and llm_summary.get("ready") is True)
llm_gate_ready = bool(llm_gate and llm_gate.get("ready") is True)
automation_ready = (
    llm_canary_exit == 0
    and signoff_dry_run_exit == 0
    and llm_ready
    and llm_gate_ready
    and not unexpected_blocked
)
summary = {
    "schemaName": "macos_computer_use_mvp_llm_readiness_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_mvp_llm_readiness",
    "automationBoundary": "no_tcc_no_desktop_action",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "ready": automation_ready,
    "llmCanaryExitCode": llm_canary_exit,
    "readinessExitCode": readiness_exit,
    "signoffDryRunExitCode": signoff_dry_run_exit,
    "llmCanarySummaryPath": str(llm_summary_path) if llm_summary_path else None,
    "readinessJsonPath": str(readiness_json) if readiness_json.exists() else None,
    "readinessMarkdownPath": str(readiness_md) if readiness_md.exists() else None,
    "handoffMarkdownPath": str(handoff_md) if handoff_md.exists() else None,
    "llmReady": llm_ready,
    "llmGateReady": llm_gate_ready,
    "blockedGateIds": blocked_gate_ids,
    "unexpectedBlockedGateIds": unexpected_blocked,
    "nextUserActions": [
        "Ask the user to run bash tool/run_macos_computer_use_manual_tcc_signoff.sh and provide manual_tcc_report_summary.json.",
        "Ask the user to prepare the fixture and run bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target, then provide canary_summary.json.",
        "Run final MVP aggregation with manual TCC, desktop action, and LLM canary summaries.",
    ],
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use MVP LLM Readiness Summary",
    "",
    "- Automation boundary: no TCC operation and no desktop action",
    f"- Ready: {str(automation_ready).lower()}",
    f"- LLM canary exit code: {llm_canary_exit}",
    f"- Release readiness exit code: {readiness_exit}",
    f"- MVP sign-off dry-run exit code: {signoff_dry_run_exit}",
    f"- LLM ready: {str(llm_ready).lower()}",
    f"- LLM gate ready: {str(llm_gate_ready).lower()}",
    f"- Blocked gates: {', '.join(blocked_gate_ids) if blocked_gate_ids else 'none'}",
    f"- Unexpected blocked gates: {', '.join(unexpected_blocked) if unexpected_blocked else 'none'}",
    "",
    "## Artifacts",
    "",
    f"- LLM canary summary: `{summary['llmCanarySummaryPath'] or 'not available'}`",
    f"- Readiness JSON: `{summary['readinessJsonPath'] or 'not available'}`",
    f"- Readiness Markdown: `{summary['readinessMarkdownPath'] or 'not available'}`",
    f"- Handoff Markdown: `{summary['handoffMarkdownPath'] or 'not available'}`",
    "",
    "## Next User Actions",
    "",
]
lines.extend(f"- {action}" for action in summary["nextUserActions"])
summary_md.write_text("\n".join(lines) + "\n")
print(summary_md.read_text())

if not automation_ready:
    raise SystemExit(1)
PY

echo "MVP LLM readiness summary written to ${SUMMARY_JSON}"

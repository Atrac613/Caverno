#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RELEASE_READINESS_WRAPPER="${CAVERNO_MACOS_COMPUTER_USE_READINESS_WRAPPER:-tool/run_macos_computer_use_release_readiness.sh}"
MANUAL_TCC_REPORT="${CAVERNO_MACOS_COMPUTER_USE_MANUAL_TCC_REPORT:-}"
DESKTOP_ACTION_CANARY_SUMMARY="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_SUMMARY:-}"
LLM_CANARY_SUMMARY="${CAVERNO_MACOS_COMPUTER_USE_LLM_CANARY_SUMMARY:-}"
REFRESH_SAFE_INPUTS=0
REFRESH_LLM_CANARY=0
DRY_RUN=0
FINAL_SIGNOFF=0
OUTPUT_JSON=""
OUTPUT_MD=""
HANDOFF_MD=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_signoff.sh [options]

Options:
  --root PATH                         Report root directory.
  --manual-tcc-report PATH            User-produced manual TCC report or summary.
  --desktop-action-canary-summary PATH User-produced desktop action canary summary.
  --llm-canary-summary PATH           Computer Use LLM canary summary.
  --refresh-safe-inputs               Refresh non-TCC M7/history inputs.
  --refresh-llm-canary                Refresh aggregate fixture LLM canary when CAVERNO_LLM_* is set.
  --final-signoff                     Refresh safe inputs and LLM evidence, then aggregate.
  --dry-run                           Write handoff and print aggregation command only.
  --output-json PATH                  Override MVP readiness JSON output.
  --output-md PATH                    Override MVP readiness Markdown output.
  --handoff-md PATH                   Override user handoff Markdown output.
  --help                              Show this help.

This wrapper never grants TCC, edits TCC, operates System Settings, or runs the
desktop action canary. It prints the user-operated commands and aggregates
reports that the user provides.
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
    --manual-tcc-report)
      require_value "$@"
      MANUAL_TCC_REPORT="$2"
      shift 2
      ;;
    --desktop-action-canary-summary)
      require_value "$@"
      DESKTOP_ACTION_CANARY_SUMMARY="$2"
      shift 2
      ;;
    --llm-canary-summary)
      require_value "$@"
      LLM_CANARY_SUMMARY="$2"
      shift 2
      ;;
    --refresh-safe-inputs)
      REFRESH_SAFE_INPUTS=1
      shift
      ;;
    --refresh-llm-canary)
      REFRESH_LLM_CANARY=1
      shift
      ;;
    --final-signoff)
      FINAL_SIGNOFF=1
      REFRESH_SAFE_INPUTS=1
      REFRESH_LLM_CANARY=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --output-json)
      require_value "$@"
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-md)
      require_value "$@"
      OUTPUT_MD="$2"
      shift 2
      ;;
    --handoff-md)
      require_value "$@"
      HANDOFF_MD="$2"
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

if [[ -z "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${REPORT_ROOT}/macos_computer_use_mvp_readiness.json"
fi
if [[ -z "${OUTPUT_MD}" ]]; then
  OUTPUT_MD="${REPORT_ROOT}/macos_computer_use_mvp_readiness.md"
fi
if [[ -z "${HANDOFF_MD}" ]]; then
  HANDOFF_MD="${REPORT_ROOT}/macos_computer_use_mvp_handoff.md"
fi

mkdir -p "${REPORT_ROOT}"

discovered_artifacts="$(
  REPORT_ROOT="${REPORT_ROOT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


report_root = Path(os.environ["REPORT_ROOT"])


def read_json(path):
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def json_files():
    if not report_root.exists():
        return []
    return [path for path in report_root.rglob("*.json") if path.is_file()]


def latest_matching(matches):
    candidates = []
    for path in json_files():
        decoded = read_json(path)
        if decoded is None or not matches(path, decoded):
            continue
        candidates.append((path.stat().st_mtime, str(path), path))
    candidates.sort()
    return candidates[-1][2] if candidates else None


manual = latest_matching(
    lambda _path, decoded: decoded.get("schemaName")
    == "macos_computer_use_manual_tcc_report_summary"
    or "releaseRuntimeSignoffGate" in decoded
)
desktop = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_desktop_action_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_desktop_action_canary_summary"
)
vision = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith(
        "macos_computer_use_mvp_fixture_vision_llm_canary_"
    )
    and decoded.get("schemaName")
    == "macos_computer_use_mvp_fixture_vision_llm_canary_summary"
)
aggregate = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_mvp_fixture_llm_canary_")
    and decoded.get("schemaName")
    == "macos_computer_use_mvp_fixture_llm_canary_summary"
)
decision = latest_matching(
    lambda path, decoded: path.name == "canary_summary.json"
    and path.parent.name.startswith("macos_computer_use_llm_decision_canary_")
    and str(decoded.get("scenario", "")).startswith("mvp-fixture")
)
llm = vision or aggregate or decision

for name, path in [
    ("DISCOVERED_MANUAL_TCC_REPORT", manual),
    ("DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY", desktop),
    ("DISCOVERED_LLM_CANARY_SUMMARY", llm),
]:
    print(f"{name}={shlex.quote(str(path) if path else '')}")
PY
)"
eval "${discovered_artifacts}"

manual_tcc_status="not provided"
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  if [[ -f "${MANUAL_TCC_REPORT}" ]]; then
    manual_tcc_status="provided"
  else
    manual_tcc_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_MANUAL_TCC_REPORT:-}" ]]; then
  MANUAL_TCC_REPORT="${DISCOVERED_MANUAL_TCC_REPORT}"
  manual_tcc_status="discovered"
fi

desktop_action_status="not provided"
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  if [[ -f "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
    desktop_action_status="provided"
  else
    desktop_action_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY:-}" ]]; then
  DESKTOP_ACTION_CANARY_SUMMARY="${DISCOVERED_DESKTOP_ACTION_CANARY_SUMMARY}"
  desktop_action_status="discovered"
fi

llm_canary_status="discovery only"
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  if [[ -f "${LLM_CANARY_SUMMARY}" ]]; then
    llm_canary_status="provided"
  else
    llm_canary_status="provided path not found"
  fi
elif [[ -n "${DISCOVERED_LLM_CANARY_SUMMARY:-}" ]]; then
  LLM_CANARY_SUMMARY="${DISCOVERED_LLM_CANARY_SUMMARY}"
  llm_canary_status="discovered"
fi

shell_join() {
  local output=""
  local part
  for part in "$@"; do
    if [[ -n "${output}" ]]; then
      output+=" "
    fi
    printf -v part "%q" "${part}"
    output+="${part}"
  done
  printf '%s' "${output}"
}

final_mvp_args=(
  bash
  tool/run_macos_computer_use_mvp_signoff.sh
  --final-signoff
  --root "${REPORT_ROOT}"
)
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  final_mvp_args+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  final_mvp_args+=(--desktop-action-canary-summary "${DESKTOP_ACTION_CANARY_SUMMARY}")
fi
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  final_mvp_args+=(--llm-canary-summary "${LLM_CANARY_SUMMARY}")
fi
FINAL_MVP_AGGREGATION_COMMAND="$(shell_join "${final_mvp_args[@]}")"
required_input_evidence_ready=0
if [[ ("${manual_tcc_status}" == "provided" || "${manual_tcc_status}" == "discovered") && ("${desktop_action_status}" == "provided" || "${desktop_action_status}" == "discovered") && ("${llm_canary_status}" == "provided" || "${llm_canary_status}" == "discovered") ]]; then
  required_input_evidence_ready=1
fi

LLM_EVIDENCE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_mvp_llm_evidence_handoff.md"
llm_evidence_values="$(
  LLM_CANARY_SUMMARY="${LLM_CANARY_SUMMARY}" LLM_EVIDENCE_FRAGMENT="${LLM_EVIDENCE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["LLM_CANARY_SUMMARY"]) if os.environ["LLM_CANARY_SUMMARY"] else None
fragment_path = Path(os.environ["LLM_EVIDENCE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    if path is None or not path.exists():
        return None
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


summary = read_json(summary_path)
gate = summary.get("mvpEvidenceGate") if isinstance(summary, dict) else None
gate = gate if isinstance(gate, dict) else None
checks = gate.get("checks") if isinstance(gate, dict) else []
checks = checks if isinstance(checks, list) else []
blockers = gate.get("blockers") if isinstance(gate, dict) else []
blockers = blockers if isinstance(blockers, list) else []
phases = (
    summary.get("expectedUserOperatedRuntimePhases")
    if isinstance(summary, dict)
    else []
)
phases = phases if isinstance(phases, list) else []
status = str(gate.get("status")) if gate and gate.get("status") else "not available"
blocker_text = ", ".join(str(blocker) for blocker in blockers) if blockers else "none"
phase_text = ", ".join(str(phase) for phase in phases) if phases else "not available"

lines = [
    "",
    "## LLM Evidence Gate",
    "",
    f"- LLM evidence summary: `{summary_path if summary_path else 'not provided'}`",
    f"- MVP evidence gate: {status}",
    f"- MVP evidence blockers: {blocker_text}",
    f"- Expected user-operated runtime phases: {phase_text}",
]
if checks:
    lines.extend([
        "",
        "| Check | Status | Next Action |",
        "| --- | --- | --- |",
    ])
    for check in checks:
        if not isinstance(check, dict):
            continue
        check_id = check.get("id", "unknown")
        check_status = "passed" if check.get("ok") is True else "blocked"
        next_action = check.get("nextAction") or "-"
        lines.append(f"| {check_id} | {check_status} | {next_action} |")
elif summary_path:
    lines.extend([
        "",
        "- No MVP evidence gate was present in the selected LLM summary.",
    ])
else:
    lines.extend([
        "",
        "- No LLM summary is selected yet.",
    ])

fragment_path.write_text("\n".join(lines) + "\n")
print(f"LLM_EVIDENCE_STATUS={shlex.quote(status)}")
print(f"LLM_EVIDENCE_BLOCKERS={shlex.quote(blocker_text)}")
print(f"LLM_EVIDENCE_PHASES={shlex.quote(phase_text)}")
PY
)"
eval "${llm_evidence_values}"

DESKTOP_ACTION_EVIDENCE_FRAGMENT="${REPORT_ROOT}/macos_computer_use_mvp_desktop_action_evidence_handoff.md"
desktop_action_evidence_values="$(
  DESKTOP_ACTION_CANARY_SUMMARY="${DESKTOP_ACTION_CANARY_SUMMARY}" DESKTOP_ACTION_EVIDENCE_FRAGMENT="${DESKTOP_ACTION_EVIDENCE_FRAGMENT}" python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path


summary_path = Path(os.environ["DESKTOP_ACTION_CANARY_SUMMARY"]) if os.environ["DESKTOP_ACTION_CANARY_SUMMARY"] else None
fragment_path = Path(os.environ["DESKTOP_ACTION_EVIDENCE_FRAGMENT"])
fragment_path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path):
    if path is None or not path.exists():
        return None
    try:
        decoded = json.loads(path.read_text())
    except Exception:
        return None
    return decoded if isinstance(decoded, dict) else None


def as_list(value):
    return value if isinstance(value, list) else []


def cell(value):
    text = "-" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", "<br>")


summary = read_json(summary_path)
runs = as_list(summary.get("runs") if isinstance(summary, dict) else [])
phases = as_list(summary.get("expectedPhases") if isinstance(summary, dict) else [])
guidance = as_list(summary.get("safeTargetGuidance") if isinstance(summary, dict) else [])
stable = summary.get("stable") if isinstance(summary, dict) else None
failed = summary.get("failed") if isinstance(summary, dict) else None
run_count = summary.get("runCount") if isinstance(summary, dict) else None
status = "not provided"
if summary_path and summary is None:
    status = "unreadable"
elif isinstance(summary, dict):
    status = "passed" if run_count and failed == 0 and stable is True else "blocked"

lines = [
    "",
    "## Desktop Action Evidence",
    "",
    f"- Desktop action summary: `{summary_path if summary_path else 'not provided'}`",
    f"- Desktop action status: {status}",
    f"- Desktop action runs: {run_count if run_count is not None else 'not available'}",
    f"- Desktop action failures: {failed if failed is not None else 'not available'}",
]
if phases:
    lines.append(
        "- Expected phases: " + ", ".join(f"`{str(phase)}`" for phase in phases)
    )
else:
    lines.append("- Expected phases: not available")
if guidance:
    lines.append(
        "- Safe target guidance: " + "; ".join(str(item) for item in guidance)
    )
if runs:
    lines.extend([
        "",
        "| Run | Status | Failure Class | Pre Observe | Click | Post Observe | Changed Evidence |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ])
    for run in runs:
        if not isinstance(run, dict):
            continue
        phase_status = run.get("phaseStatus")
        phase_status = phase_status if isinstance(phase_status, dict) else {}
        lines.append(
            "| {name} | {status} | {failure} | {pre} | {click} | {post} | {changed} |".format(
                name=cell(run.get("name")),
                status=cell(run.get("status")),
                failure=cell(run.get("failureClass")),
                pre=cell(phase_status.get("preObserve")),
                click=cell(phase_status.get("click")),
                post=cell(phase_status.get("postObserve")),
                changed=cell(phase_status.get("changedEvidence")),
            )
        )
elif summary_path:
    lines.extend([
        "",
        "- No run-level desktop action evidence was present in the selected summary.",
    ])
else:
    lines.extend([
        "",
        "- No desktop action summary is selected yet.",
    ])

fragment_path.write_text("\n".join(lines) + "\n")
print(f"DESKTOP_ACTION_EVIDENCE_STATUS={shlex.quote(status)}")
print(f"DESKTOP_ACTION_EVIDENCE_RUNS={shlex.quote(str(run_count) if run_count is not None else 'not available')}")
print(f"DESKTOP_ACTION_EVIDENCE_FAILURES={shlex.quote(str(failed) if failed is not None else 'not available')}")
PY
)"
eval "${desktop_action_evidence_values}"

cat >"${HANDOFF_MD}" <<EOF
# macOS Computer Use MVP Handoff

- Automation boundary: user-operated TCC and desktop action only
- MVP checklist: \`docs/macos_computer_use_mvp_checklist.md\`
- Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}
- Manual TCC status: ${manual_tcc_status}
- Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}
- Desktop action canary status: ${desktop_action_status}
- LLM canary summary: ${LLM_CANARY_SUMMARY:-discovery only}
- LLM canary status: ${llm_canary_status}

## Current Manual Input Status

- \`manual_tcc\`: ${manual_tcc_status}
- \`desktop_action_canary\`: ${desktop_action_status}
- \`llm_canary\`: ${llm_canary_status}

## User-Operated Commands

1. Manual TCC sign-off:

   \`\`\`bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh
   \`\`\`

2. Desktop action canary after preparing a safe click target:

   \`\`\`bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh
   \`\`\`

3. Final MVP aggregation:

   \`\`\`bash
   bash tool/run_macos_computer_use_mvp_signoff.sh \\
     --manual-tcc-report <manual-tcc-report-or-summary.json> \\
     --desktop-action-canary-summary <desktop-action-canary-summary.json> \\
     --llm-canary-summary <llm-canary-summary.json>
   \`\`\`

## Final MVP Aggregation Command

\`\`\`bash
${FINAL_MVP_AGGREGATION_COMMAND}
\`\`\`

## Automation-Safe Commands

\`\`\`bash
bash tool/run_macos_computer_use_release_readiness.sh --ci
bash tool/run_macos_computer_use_live_canary.sh --overlay
bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh
bash tool/run_macos_computer_use_mvp_llm_readiness.sh
\`\`\`
EOF

cat "${LLM_EVIDENCE_FRAGMENT}" >>"${HANDOFF_MD}"
cat "${DESKTOP_ACTION_EVIDENCE_FRAGMENT}" >>"${HANDOFF_MD}"

{
  echo
  echo "## Missing Input Next Actions"
  echo
  if [[ "${manual_tcc_status}" != "provided" && "${manual_tcc_status}" != "discovered" ]]; then
    echo "- Ask the user to run \`bash tool/run_macos_computer_use_manual_tcc_signoff.sh\` and provide \`manual_tcc_report_summary.json\`."
  fi
  if [[ "${desktop_action_status}" != "provided" && "${desktop_action_status}" != "discovered" ]]; then
    echo "- Ask the user to prepare a safe click target, run \`bash tool/run_macos_computer_use_desktop_action_canary.sh\`, and provide \`canary_summary.json\`."
  fi
  if [[ "${llm_canary_status}" != "provided" && "${llm_canary_status}" != "discovered" ]]; then
    echo "- Rerun \`bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh\` or provide an existing aggregate LLM canary summary."
  fi
  if [[ "${required_input_evidence_ready}" == "1" ]]; then
    echo "- No required input evidence is missing from this wrapper invocation. If readiness still fails, inspect the blocked gate details in the Markdown report."
  fi
} >>"${HANDOFF_MD}"

echo "Running macOS Computer Use MVP sign-off aggregator"
echo "  Report root: ${REPORT_ROOT}"
echo "  Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}"
echo "  Manual TCC status: ${manual_tcc_status}"
echo "  Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}"
echo "  Desktop action canary status: ${desktop_action_status}"
echo "  LLM canary summary: ${LLM_CANARY_SUMMARY:-discovery only}"
echo "  LLM canary status: ${llm_canary_status}"
echo "  LLM evidence gate: ${LLM_EVIDENCE_STATUS}"
echo "  LLM evidence blockers: ${LLM_EVIDENCE_BLOCKERS}"
echo "  LLM evidence phases: ${LLM_EVIDENCE_PHASES}"
echo "  Desktop action evidence status: ${DESKTOP_ACTION_EVIDENCE_STATUS}"
echo "  Desktop action evidence runs: ${DESKTOP_ACTION_EVIDENCE_RUNS}"
echo "  Desktop action evidence failures: ${DESKTOP_ACTION_EVIDENCE_FAILURES}"
echo "  Refresh safe inputs: ${REFRESH_SAFE_INPUTS}"
echo "  Refresh LLM canary: ${REFRESH_LLM_CANARY}"
echo "  Final sign-off mode: ${FINAL_SIGNOFF}"
echo "  Dry run: ${DRY_RUN}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Handoff Markdown: ${HANDOFF_MD}"
echo "  Release readiness wrapper: ${RELEASE_READINESS_WRAPPER}"
echo "  TCC boundary: user-operated manual verification only"
echo "  Desktop action boundary: user-operated safe click target only"
echo "  Final MVP aggregation command: ${FINAL_MVP_AGGREGATION_COMMAND}"

echo
echo "User-operated commands:"
echo "  bash tool/run_macos_computer_use_manual_tcc_signoff.sh"
echo "  bash tool/run_macos_computer_use_desktop_action_canary.sh"
echo
echo "MVP handoff next actions:"
if [[ "${manual_tcc_status}" != "provided" && "${manual_tcc_status}" != "discovered" ]]; then
  echo "  manual_tcc: ask the user for manual_tcc_report_summary.json"
fi
if [[ "${desktop_action_status}" != "provided" && "${desktop_action_status}" != "discovered" ]]; then
  echo "  desktop_action_canary: ask the user for canary_summary.json"
fi
if [[ "${llm_canary_status}" != "provided" && "${llm_canary_status}" != "discovered" ]]; then
  echo "  llm_canary: provide an existing aggregate canary_summary.json or rerun the fixture LLM canary"
fi
if [[ "${required_input_evidence_ready}" == "1" ]]; then
  echo "  all required input evidence was provided or discovered by this wrapper"
fi

cd "${ROOT_DIR}"

readiness_args=(
  --signoff
  --root "${REPORT_ROOT}"
  --output-json "${OUTPUT_JSON}"
  --output-md "${OUTPUT_MD}"
)

if [[ "${REFRESH_SAFE_INPUTS}" == "0" ]]; then
  readiness_args+=(--no-refresh)
fi
if [[ "${REFRESH_LLM_CANARY}" == "1" ]]; then
  readiness_args+=(--refresh-llm-canary)
fi
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  readiness_args+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  readiness_args+=(--desktop-action-canary-summary "${DESKTOP_ACTION_CANARY_SUMMARY}")
fi
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  readiness_args+=(--llm-canary-summary "${LLM_CANARY_SUMMARY}")
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  printf 'Dry run: would execute: bash %q' "${RELEASE_READINESS_WRAPPER}"
  printf ' %q' "${readiness_args[@]}"
  printf '\n'
  exit 0
fi

set +e
bash "${RELEASE_READINESS_WRAPPER}" "${readiness_args[@]}"
readiness_exit=$?
set -e

if [[ -f "${OUTPUT_JSON}" ]]; then
  OUTPUT_JSON="${OUTPUT_JSON}" HANDOFF_MD="${HANDOFF_MD}" python3 - <<'PY'
import json
import os
from pathlib import Path


output_json = Path(os.environ["OUTPUT_JSON"])
handoff_md = Path(os.environ["HANDOFF_MD"])
summary = json.loads(output_json.read_text())
gates = summary.get("gates")
gates = gates if isinstance(gates, list) else []
blocked = [gate for gate in gates if isinstance(gate, dict) and not gate.get("ready")]
ready = [gate for gate in gates if isinstance(gate, dict) and gate.get("ready")]

lines = [
    "",
    "## Final Readiness Next Actions",
    "",
    f"- Readiness status: {summary.get('status', 'unknown')}",
    f"- Ready gates: {', '.join(str(gate.get('id')) for gate in ready) if ready else 'none'}",
    f"- Blocked gates: {', '.join(str(gate.get('id')) for gate in blocked) if blocked else 'none'}",
    "",
]
if blocked:
    for gate in blocked:
        gate_id = gate.get("id", "unknown")
        status = gate.get("status", "unknown")
        next_action = gate.get("nextAction", "Inspect the readiness report.")
        artifact = gate.get("artifactPath") or "not available"
        lines.append(f"- `{gate_id}` ({status}): {next_action} Artifact: `{artifact}`")
else:
    lines.append("- No blocked gates remain. MVP sign-off evidence is ready.")

with handoff_md.open("a") as handle:
    handle.write("\n".join(lines) + "\n")

print("\n".join(lines))
PY
else
  {
    echo
    echo "## Final Readiness Next Actions"
    echo
    echo "- Readiness report was not written. Inspect the release readiness command output."
  } >>"${HANDOFF_MD}"
fi

exit "${readiness_exit}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_DEMO_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_demo_readiness_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/mvp_demo_readiness_summary.json"
SUMMARY_MD="${RUN_DIR}/mvp_demo_readiness_summary.md"
HANDOFF_MD="${RUN_DIR}/mvp_demo_handoff.md"
SCREENSHOT_PATH=""
VISION_FIXTURE_RESPONSE=""
LLM_CANARY_SUMMARY=""
MANUAL_TCC_REPORT=""
DESKTOP_ACTION_CANARY_SUMMARY=""
SKIP_FIXTURE_BUILD=0
FINAL_SIGNOFF=0

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_demo_readiness.sh [options]

Options:
  --root PATH                          Report root directory.
  --screenshot PATH                    User-provided fixture screenshot for live vision LLM readiness.
  --vision-fixture-response PATH       Use a local fixture vision LLM response.
  --llm-canary-summary PATH            Use an existing LLM canary summary.
  --manual-tcc-report PATH             User-produced manual TCC report or summary.
  --desktop-action-canary-summary PATH User-produced desktop action canary summary.
  --final-signoff                      Run final MVP aggregation after preflight.
  --skip-fixture-build                 Do not build the deterministic fixture app.
  --help                               Show this help.

This guided MVP wrapper prepares the automation-safe Computer Use demo evidence
path. It does not capture the screen, grant TCC, operate System Settings, move
the pointer, click, type, or launch the fixture app.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --screenshot)
      require_value "$@"
      SCREENSHOT_PATH="$2"
      shift 2
      ;;
    --vision-fixture-response)
      require_value "$@"
      VISION_FIXTURE_RESPONSE="$2"
      shift 2
      ;;
    --llm-canary-summary)
      require_value "$@"
      LLM_CANARY_SUMMARY="$2"
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
    --final-signoff)
      FINAL_SIGNOFF=1
      shift
      ;;
    --skip-fixture-build)
      SKIP_FIXTURE_BUILD=1
      shift
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

RUN_DIR="${REPORT_ROOT}/macos_computer_use_mvp_demo_readiness_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/mvp_demo_readiness_summary.json"
SUMMARY_MD="${RUN_DIR}/mvp_demo_readiness_summary.md"
HANDOFF_MD="${RUN_DIR}/mvp_demo_handoff.md"
mkdir -p "${RUN_DIR}"

echo "Running macOS Computer Use MVP demo readiness guide"
echo "  Report root: ${REPORT_ROOT}"
echo "  Run dir: ${RUN_DIR}"
echo "  Screenshot: ${SCREENSHOT_PATH:-not provided}"
echo "  Existing LLM summary: ${LLM_CANARY_SUMMARY:-not provided}"
echo "  Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}"
echo "  Desktop action summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}"
echo "  Final sign-off: ${FINAL_SIGNOFF}"
echo "  TCC boundary: no TCC operation"
echo "  Desktop action boundary: no pointer, keyboard, click, type, or launch operation"

fixture_app_path=""
fixture_build_exit=0
if [[ "${SKIP_FIXTURE_BUILD}" == "0" ]]; then
  set +e
  fixture_output="$(bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_fixture.sh" --print-path 2>&1)"
  fixture_build_exit=$?
  set -e
  echo "${fixture_output}"
  fixture_app_path="$(printf '%s\n' "${fixture_output}" | tail -n 1)"
else
  echo "Skipping fixture build"
fi

llm_readiness_exit=66
llm_readiness_summary=""
llm_summary_path="${LLM_CANARY_SUMMARY}"
llm_args=(
  --root "${REPORT_ROOT}"
)
if [[ -n "${SCREENSHOT_PATH}" ]]; then
  llm_args+=(--screenshot "${SCREENSHOT_PATH}")
fi
if [[ -n "${VISION_FIXTURE_RESPONSE}" ]]; then
  llm_args+=(--vision-fixture-response "${VISION_FIXTURE_RESPONSE}")
fi
if [[ -n "${LLM_CANARY_SUMMARY}" ]]; then
  llm_args+=(--llm-canary-summary "${LLM_CANARY_SUMMARY}")
fi

set +e
bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_llm_readiness.sh" "${llm_args[@]}"
llm_readiness_exit=$?
set -e

llm_readiness_summary="$(
  REPORT_ROOT="${REPORT_ROOT}" python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["REPORT_ROOT"])
candidates = sorted(root.glob("macos_computer_use_mvp_llm_readiness_*/mvp_llm_readiness_summary.json"))
print(candidates[-1] if candidates else "")
PY
)"

if [[ -z "${llm_summary_path}" && -n "${llm_readiness_summary}" && -f "${llm_readiness_summary}" ]]; then
  llm_summary_path="$(
    LLM_READINESS_SUMMARY="${llm_readiness_summary}" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["LLM_READINESS_SUMMARY"])
summary = json.loads(path.read_text())
print(summary.get("llmCanarySummaryPath") or "")
PY
  )"
fi

mvp_signoff_exit=66
mvp_signoff_json="${RUN_DIR}/mvp_demo_final_readiness.json"
mvp_signoff_md="${RUN_DIR}/mvp_demo_final_readiness.md"
mvp_signoff_handoff="${RUN_DIR}/mvp_demo_final_handoff.md"
signoff_args=(
  --root "${REPORT_ROOT}"
  --handoff-md "${mvp_signoff_handoff}"
  --output-json "${mvp_signoff_json}"
  --output-md "${mvp_signoff_md}"
)
if [[ "${FINAL_SIGNOFF}" == "0" ]]; then
  signoff_args+=(--dry-run)
else
  signoff_args+=(--final-signoff)
fi
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  signoff_args+=(--manual-tcc-report "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${DESKTOP_ACTION_CANARY_SUMMARY}" ]]; then
  signoff_args+=(--desktop-action-canary-summary "${DESKTOP_ACTION_CANARY_SUMMARY}")
fi
if [[ -n "${llm_summary_path}" ]]; then
  signoff_args+=(--llm-canary-summary "${llm_summary_path}")
fi

set +e
bash "${ROOT_DIR}/tool/run_macos_computer_use_mvp_signoff.sh" "${signoff_args[@]}"
mvp_signoff_exit=$?
set -e

RUN_DIR="${RUN_DIR}" \
SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
HANDOFF_MD="${HANDOFF_MD}" \
FIXTURE_APP_PATH="${fixture_app_path}" \
FIXTURE_BUILD_EXIT="${fixture_build_exit}" \
LLM_READINESS_EXIT="${llm_readiness_exit}" \
LLM_READINESS_SUMMARY="${llm_readiness_summary}" \
LLM_CANARY_SUMMARY_PATH="${llm_summary_path}" \
MVP_SIGNOFF_EXIT="${mvp_signoff_exit}" \
MVP_SIGNOFF_JSON="${mvp_signoff_json}" \
MVP_SIGNOFF_MD="${mvp_signoff_md}" \
MVP_SIGNOFF_HANDOFF="${mvp_signoff_handoff}" \
MANUAL_TCC_REPORT="${MANUAL_TCC_REPORT}" \
DESKTOP_ACTION_CANARY_SUMMARY="${DESKTOP_ACTION_CANARY_SUMMARY}" \
FINAL_SIGNOFF="${FINAL_SIGNOFF}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
handoff_md = Path(os.environ["HANDOFF_MD"])
fixture_build_exit = int(os.environ["FIXTURE_BUILD_EXIT"])
llm_readiness_exit = int(os.environ["LLM_READINESS_EXIT"])
mvp_signoff_exit = int(os.environ["MVP_SIGNOFF_EXIT"])
final_signoff = os.environ["FINAL_SIGNOFF"] == "1"
manual_tcc_report = os.environ["MANUAL_TCC_REPORT"]
desktop_action_summary = os.environ["DESKTOP_ACTION_CANARY_SUMMARY"]
llm_summary_path = os.environ["LLM_CANARY_SUMMARY_PATH"]


def path_or_none(value):
    return value if value else None


next_user_actions = []
if not llm_summary_path:
    next_user_actions.append(
        "Provide a user-captured fixture screenshot and run this wrapper with --screenshot, or pass --llm-canary-summary."
    )
if not manual_tcc_report:
    next_user_actions.append(
        "Ask the user to run bash tool/run_macos_computer_use_manual_tcc_signoff.sh and provide manual_tcc_report_summary.json."
    )
if not desktop_action_summary:
    next_user_actions.append(
        "Ask the user to prepare the fixture, run bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target, and provide canary_summary.json."
    )
if manual_tcc_report and desktop_action_summary and llm_summary_path and not final_signoff:
    next_user_actions.append(
        "Run this wrapper with --final-signoff to aggregate the final MVP readiness report."
    )

summary = {
    "schemaName": "macos_computer_use_mvp_demo_readiness_summary",
    "schemaVersion": 1,
    "purpose": "computer_use_mvp_demo_readiness",
    "automationBoundary": "no_tcc_no_desktop_action",
    "desktopActionBoundary": "no_pointer_keyboard_click_type_or_launch",
    "tccBoundary": "no_tcc_operation",
    "ready": fixture_build_exit == 0
    and llm_readiness_exit == 0
    and (mvp_signoff_exit == 0 or not final_signoff),
    "fixtureAppPath": path_or_none(os.environ["FIXTURE_APP_PATH"]),
    "fixtureBuildExitCode": fixture_build_exit,
    "llmReadinessExitCode": llm_readiness_exit,
    "llmReadinessSummaryPath": path_or_none(os.environ["LLM_READINESS_SUMMARY"]),
    "llmCanarySummaryPath": path_or_none(llm_summary_path),
    "mvpSignoffExitCode": mvp_signoff_exit,
    "mvpSignoffJsonPath": path_or_none(os.environ["MVP_SIGNOFF_JSON"]),
    "mvpSignoffMarkdownPath": path_or_none(os.environ["MVP_SIGNOFF_MD"]),
    "mvpSignoffHandoffPath": path_or_none(os.environ["MVP_SIGNOFF_HANDOFF"]),
    "manualTccReportPath": path_or_none(manual_tcc_report),
    "desktopActionCanarySummaryPath": path_or_none(desktop_action_summary),
    "finalSignoff": final_signoff,
    "nextUserActions": next_user_actions,
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")

lines = [
    "# macOS Computer Use MVP Demo Readiness",
    "",
    "- Automation boundary: no TCC operation and no desktop action",
    f"- Ready: {str(summary['ready']).lower()}",
    f"- Fixture build exit code: {fixture_build_exit}",
    f"- LLM readiness exit code: {llm_readiness_exit}",
    f"- MVP sign-off exit code: {mvp_signoff_exit}",
    f"- Final sign-off: {str(final_signoff).lower()}",
    "",
    "## Artifacts",
    "",
    f"- Fixture app: `{summary['fixtureAppPath'] or 'not available'}`",
    f"- LLM readiness summary: `{summary['llmReadinessSummaryPath'] or 'not available'}`",
    f"- LLM canary summary: `{summary['llmCanarySummaryPath'] or 'not available'}`",
    f"- MVP sign-off JSON: `{summary['mvpSignoffJsonPath'] or 'not available'}`",
    f"- MVP sign-off Markdown: `{summary['mvpSignoffMarkdownPath'] or 'not available'}`",
    f"- MVP sign-off handoff: `{summary['mvpSignoffHandoffPath'] or 'not available'}`",
    "",
    "## Next User Actions",
    "",
]
if next_user_actions:
    lines.extend(f"- {action}" for action in next_user_actions)
else:
    lines.append("- No user action is missing from this wrapper invocation.")
summary_md.write_text("\n".join(lines) + "\n")

handoff_lines = list(lines)
handoff_lines.extend(
    [
        "",
        "## User-Operated Commands",
        "",
        "```bash",
        "bash tool/run_macos_computer_use_mvp_fixture.sh --launch",
        "bash tool/run_macos_computer_use_manual_tcc_signoff.sh",
        "bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target",
        "bash tool/run_macos_computer_use_mvp_demo_readiness.sh \\",
        "  --manual-tcc-report <manual-tcc-report-or-summary.json> \\",
        "  --desktop-action-canary-summary <desktop-action-canary-summary.json> \\",
        "  --llm-canary-summary <llm-canary-summary.json> \\",
        "  --final-signoff",
        "```",
    ]
)
handoff_md.write_text("\n".join(handoff_lines) + "\n")
print(summary_md.read_text())
PY

echo "MVP demo readiness summary written to ${SUMMARY_JSON}"

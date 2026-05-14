#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M14_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
TARGET_APP="${CAVERNO_MACOS_COMPUTER_USE_REAL_APP_OBSERVE_TARGET_APP:-Safari}"
TARGET_INTENT="${CAVERNO_MACOS_COMPUTER_USE_REAL_APP_OBSERVE_TARGET_INTENT:-Observe Safari for a future X post task.}"
SCREENSHOT_PATH=""
OUTPUT_MD=""

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m14_real_app_handoff.sh [options]

Options:
  --root PATH           Report root directory.
  --screenshot PATH     Optional user-provided screenshot path to include in commands.
  --target-app NAME     Expected app name to observe. Defaults to Safari.
  --target-intent TEXT  User intent to evaluate without executing it.
  --output-md PATH      Override handoff Markdown output.
  --help                Show this help.

This handoff is report-only. It does not grant TCC, open apps, operate System
Settings, move the pointer, click, type, submit, post, or call an LLM.
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
    --screenshot)
      require_value "$@"
      SCREENSHOT_PATH="$2"
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
    --output-md)
      require_value "$@"
      OUTPUT_MD="$2"
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

if [[ -z "${OUTPUT_MD}" ]]; then
  OUTPUT_MD="${REPORT_ROOT}/macos_computer_use_m14_real_app_handoff.md"
fi

mkdir -p "${REPORT_ROOT}"

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

canary_args=(
  bash
  tool/run_macos_computer_use_real_app_observe_canary.sh
  --root "${REPORT_ROOT}"
)
if [[ -n "${SCREENSHOT_PATH}" ]]; then
  canary_args+=(--screenshot "${SCREENSHOT_PATH}")
else
  canary_args+=(--screenshot "<user-provided-real-app-screenshot.png>")
fi
canary_args+=(
  --target-app "${TARGET_APP}"
  --target-intent "${TARGET_INTENT}"
)

CANARY_COMMAND="$(shell_join "${canary_args[@]}")"
ARTIFACT_INDEX_COMMAND="$(shell_join \
  dart run tool/macos_computer_use_readiness_artifact_index.dart \
  --root "${REPORT_ROOT}")"
SIGNOFF_DRY_RUN_COMMAND="$(shell_join \
  bash tool/run_macos_computer_use_mvp_signoff.sh \
  --dry-run \
  --root "${REPORT_ROOT}")"

cat >"${OUTPUT_MD}" <<EOF
# macOS Computer Use M14 Real App Handoff

- Milestone: M14
- Target app: ${TARGET_APP}
- Target intent: ${TARGET_INTENT}
- Report root: ${REPORT_ROOT}
- Screenshot: ${SCREENSHOT_PATH:-user-provided}
- Automation boundary: report-only, no TCC, no System Settings, no desktop actions

## User-Operated Preparation

1. Manually open the target app and prepare the real app state.
2. Manually capture a screenshot of that state.
3. Provide the screenshot path before running the observe canary.

## Observe-Only Canary

\`\`\`bash
${CANARY_COMMAND}
\`\`\`

Expected output:

- \`macos_computer_use_real_app_observe_canary_<timestamp>/canary_summary.json\`
- \`m14EvidenceGate.status\`: \`ready\`
- \`desktopActionBoundary\`: \`no_desktop_action\`
- \`tccBoundary\`: \`no_tcc_operation\`

## Readiness Rehearsal

\`\`\`bash
${ARTIFACT_INDEX_COMMAND}
${SIGNOFF_DRY_RUN_COMMAND}
\`\`\`

Expected readiness result:

- Artifact index selects the M14 real-app observe summary as \`llm_canary\`.
- MVP final sign-off rehearsal is ready once manual TCC, desktop action, canary
  history, release artifact, and M14 LLM evidence are all present.
- Blocked \`m14EvidenceGate\` output must block readiness instead of being
  treated as passing LLM evidence.

## Manual Boundary

Do not automate app navigation, clicking, typing, posting, purchases, TCC
grants, or System Settings operations for this milestone. Ask the user to
prepare fresh app state and screenshots manually when needed.
EOF

echo "M14 real app handoff written to ${OUTPUT_MD}"
echo "  Report root: ${REPORT_ROOT}"
echo "  Target app: ${TARGET_APP}"
echo "  Target intent: ${TARGET_INTENT}"
echo "  Screenshot: ${SCREENSHOT_PATH:-user-provided}"
echo "  Canary command: ${CANARY_COMMAND}"
echo "  Artifact index command: ${ARTIFACT_INDEX_COMMAND}"
echo "  Sign-off dry-run command: ${SIGNOFF_DRY_RUN_COMMAND}"
echo "  Boundary: report-only, no TCC, no System Settings, no desktop actions"

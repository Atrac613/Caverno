#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MVP_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
MANUAL_TCC_REPORT="${CAVERNO_MACOS_COMPUTER_USE_MANUAL_TCC_REPORT:-}"
DESKTOP_ACTION_CANARY_SUMMARY="${CAVERNO_MACOS_COMPUTER_USE_DESKTOP_ACTION_CANARY_SUMMARY:-}"
REFRESH_SAFE_INPUTS=0
REFRESH_LLM_CANARY=0
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
  --refresh-safe-inputs               Refresh non-TCC M7/history inputs.
  --refresh-llm-canary                Refresh LLM canary when CAVERNO_LLM_* is set.
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
    --refresh-safe-inputs)
      REFRESH_SAFE_INPUTS=1
      shift
      ;;
    --refresh-llm-canary)
      REFRESH_LLM_CANARY=1
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

cat >"${HANDOFF_MD}" <<EOF
# macOS Computer Use MVP Handoff

- Automation boundary: user-operated TCC and desktop action only
- MVP checklist: \`docs/macos_computer_use_mvp_checklist.md\`
- Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}
- Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}

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
     --desktop-action-canary-summary <desktop-action-canary-summary.json>
   \`\`\`

## Automation-Safe Commands

\`\`\`bash
bash tool/run_macos_computer_use_release_readiness.sh --ci
bash tool/run_macos_computer_use_live_canary.sh --overlay
\`\`\`
EOF

echo "Running macOS Computer Use MVP sign-off aggregator"
echo "  Report root: ${REPORT_ROOT}"
echo "  Manual TCC report: ${MANUAL_TCC_REPORT:-not provided}"
echo "  Desktop action canary summary: ${DESKTOP_ACTION_CANARY_SUMMARY:-not provided}"
echo "  Refresh safe inputs: ${REFRESH_SAFE_INPUTS}"
echo "  Refresh LLM canary: ${REFRESH_LLM_CANARY}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Handoff Markdown: ${HANDOFF_MD}"
echo "  TCC boundary: user-operated manual verification only"
echo "  Desktop action boundary: user-operated safe click target only"

echo
echo "User-operated commands:"
echo "  bash tool/run_macos_computer_use_manual_tcc_signoff.sh"
echo "  bash tool/run_macos_computer_use_desktop_action_canary.sh"

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

bash tool/run_macos_computer_use_release_readiness.sh "${readiness_args[@]}"

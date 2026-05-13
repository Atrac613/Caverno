#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M39_BETA_SIGNOFF_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m39_beta_signoff_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m39_beta_signoff.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m39_beta_signoff.md"
MANUAL_BETA_CHECKLIST=""
M36_LIVE_LLM_EVAL=""
M23_CYCLE_OUTCOME=""
INSTALL_MIGRATION_DIAGNOSTICS=""
EXIT_POLICY="strict"
WRITE_TEMPLATE="no"
TEMPLATE_PATH=""

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m39_beta_signoff.sh [options]

Options:
  --root PATH                         Report root directory.
  --manual-beta-checklist PATH        M39 manual beta checklist JSON.
  --m36-live-llm-eval PATH            M36 Live LLM evaluation canary_summary.json.
  --m23-cycle-outcome PATH            M23 cycle_outcome_handoff.json.
  --install-migration-diagnostics PATH
                                      Diagnostics JSON containing M38 migration guardrails.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a manual checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M39 gate is blocked.
  --help                              Show this help.

M39 is report-only. It reads existing evidence for clean install, upgrade,
permission grant, permission revocation, helper restart, XPC fallback
observability, Live LLM observe-only canaries, and one user-operated
observe-approve-execute-review cycle. It performs no desktop actions and does
not grant TCC, open System Settings, capture screens, move the pointer, click,
type, submit, post, purchase, or operate desktop apps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --manual-beta-checklist)
      require_value "$@"
      MANUAL_BETA_CHECKLIST="$2"
      shift 2
      ;;
    --m36-live-llm-eval)
      require_value "$@"
      M36_LIVE_LLM_EVAL="$2"
      shift 2
      ;;
    --m23-cycle-outcome)
      require_value "$@"
      M23_CYCLE_OUTCOME="$2"
      shift 2
      ;;
    --install-migration-diagnostics)
      require_value "$@"
      INSTALL_MIGRATION_DIAGNOSTICS="$2"
      shift 2
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
    --write-template)
      WRITE_TEMPLATE="yes"
      if [[ $# -ge 2 && -n "${2:-}" && "${2}" != --* ]]; then
        TEMPLATE_PATH="$2"
        shift 2
      else
        shift 1
      fi
      ;;
    --report-only)
      EXIT_POLICY="report-only"
      shift 1
      ;;
    --strict)
      EXIT_POLICY="strict"
      shift 1
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

mkdir -p "${RUN_DIR}"

args=(
  "run"
  "tool/macos_computer_use_beta_signoff.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M39 manual beta checklist template"
  echo "  Report root: ${REPORT_ROOT}"
  dart "${args[@]}"
  exit $?
fi

args+=(
  "--output-json"
  "${OUTPUT_JSON}"
  "--output-md"
  "${OUTPUT_MD}"
  "--exit-policy"
  "${EXIT_POLICY}"
)

if [[ -n "${MANUAL_BETA_CHECKLIST}" ]]; then
  args+=("--manual-beta-checklist" "${MANUAL_BETA_CHECKLIST}")
fi
if [[ -n "${M36_LIVE_LLM_EVAL}" ]]; then
  args+=("--m36-live-llm-eval" "${M36_LIVE_LLM_EVAL}")
fi
if [[ -n "${M23_CYCLE_OUTCOME}" ]]; then
  args+=("--m23-cycle-outcome" "${M23_CYCLE_OUTCOME}")
fi
if [[ -n "${INSTALL_MIGRATION_DIAGNOSTICS}" ]]; then
  args+=("--install-migration-diagnostics" "${INSTALL_MIGRATION_DIAGNOSTICS}")
fi

echo "Running macOS Computer Use M39 internal beta sign-off"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated TCC and desktop actions"

dart "${args[@]}"

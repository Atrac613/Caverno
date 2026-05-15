#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M54_ROLLOUT_EXPANSION_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m54_rollout_expansion_gate_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m54_rollout_expansion_gate.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m54_rollout_expansion_gate.md"
ROLLOUT_EXPANSION_CHECKLIST=""
M53_POST_RELEASE_GUARDRAILS=""
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
Usage: bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh [options]

Options:
  --root PATH                         Report root directory.
  --rollout-expansion-checklist PATH       M54 rollout expansion checklist JSON.
  --m53-post-release-guardrails PATH  M53 post-release guardrails JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a rollout expansion checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M54 gate is blocked.
  --help                              Show this help.

M54 is report-only. It reads M53 post-release guardrails evidence and
rollout expansion checklist evidence. It performs no desktop actions and does not
grant TCC, notarize, staple, open System Settings, capture screens, move the
pointer, click, type, submit, post, purchase, export raw payloads, or operate desktop apps.
Cohort expansion, support capacity review, rollback, rollout pause, hotfix,
and escalation validation remain user-operated rollout expansion steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --rollout-expansion-checklist)
      require_value "$@"
      ROLLOUT_EXPANSION_CHECKLIST="$2"
      shift 2
      ;;
    --m53-post-release-guardrails)
      require_value "$@"
      M53_POST_RELEASE_GUARDRAILS="$2"
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
  "tool/macos_computer_use_m54_rollout_expansion_gate.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M54 rollout expansion checklist template"
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

if [[ -n "${ROLLOUT_EXPANSION_CHECKLIST}" ]]; then
  args+=("--rollout-expansion-checklist" "${ROLLOUT_EXPANSION_CHECKLIST}")
fi
if [[ -n "${M53_POST_RELEASE_GUARDRAILS}" ]]; then
  args+=("--m53-post-release-guardrails" "${M53_POST_RELEASE_GUARDRAILS}")
fi

echo "Running macOS Computer Use M54 rollout expansion gate"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated cohort expansion, support, rollback, hotfix, TCC, and desktop actions"

dart "${args[@]}"

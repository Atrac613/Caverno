#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M55_POST_EXPANSION_MONITORING_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m55_post_expansion_monitoring_gate_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m55_post_expansion_monitoring_gate.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m55_post_expansion_monitoring_gate.md"
POST_EXPANSION_MONITORING_CHECKLIST=""
M54_ROLLOUT_EXPANSION_GATE=""
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
Usage: bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh [options]

Options:
  --root PATH                         Report root directory.
  --post-expansion-monitoring-checklist PATH
                                      M55 post-expansion monitoring checklist JSON.
  --m54-rollout-expansion-gate PATH   M54 rollout expansion gate JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a post-expansion monitoring checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M55 gate is blocked.
  --help                              Show this help.

M55 is report-only. It reads M54 rollout expansion gate evidence and
post-expansion monitoring checklist evidence. It performs no desktop actions and does not
grant TCC, notarize, staple, open System Settings, capture screens, move the
pointer, click, type, submit, post, purchase, export raw payloads, or operate desktop apps.
Cohort expansion, support capacity review, rollback, rollout pause, hotfix,
and escalation validation remain user-operated post-expansion monitoring steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --post-expansion-monitoring-checklist)
      require_value "$@"
      POST_EXPANSION_MONITORING_CHECKLIST="$2"
      shift 2
      ;;
    --m54-rollout-expansion-gate)
      require_value "$@"
      M54_ROLLOUT_EXPANSION_GATE="$2"
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
  "tool/macos_computer_use_m55_post_expansion_monitoring_gate.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M55 post-expansion monitoring checklist template"
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

if [[ -n "${POST_EXPANSION_MONITORING_CHECKLIST}" ]]; then
  args+=("--post-expansion-monitoring-checklist" "${POST_EXPANSION_MONITORING_CHECKLIST}")
fi
if [[ -n "${M54_ROLLOUT_EXPANSION_GATE}" ]]; then
  args+=("--m54-rollout-expansion-gate" "${M54_ROLLOUT_EXPANSION_GATE}")
fi

echo "Running macOS Computer Use M55 post-expansion monitoring gate"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated continuation decision, support, rollback, hotfix, TCC, and desktop actions"

dart "${args[@]}"

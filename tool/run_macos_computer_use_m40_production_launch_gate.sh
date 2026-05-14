#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M40_PRODUCTION_LAUNCH_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m40_production_launch_gate_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m40_production_launch_gate.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m40_production_launch_gate.md"
LAUNCH_CHECKLIST=""
RELEASE_ARTIFACT_REPORT=""
RELEASE_PACKAGING_REPORT=""
MANUAL_TCC_REPORT=""
M36_LIVE_LLM_EVAL=""
M39_BETA_SIGNOFF=""
DIAGNOSTICS=""
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
Usage: bash tool/run_macos_computer_use_m40_production_launch_gate.sh [options]

Options:
  --root PATH                         Report root directory.
  --launch-checklist PATH             M40 launch checklist JSON.
  --release-artifact-report PATH      M7 release artifact sign-off JSON.
  --release-packaging-report PATH     M33 release packaging JSON.
  --manual-tcc-report PATH            Manual TCC summary or runtime sign-off JSON.
  --m36-live-llm-eval PATH            M36 Live LLM evaluation canary_summary.json.
  --m39-beta-signoff PATH             M39 beta sign-off JSON.
  --diagnostics PATH                  Computer Use diagnostics JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a launch checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M40 gate is blocked.
  --help                              Show this help.

M40 is report-only. It reads signed artifact, notarization, helper identity,
manual TCC runbook, Live LLM, audit export, emergency stop, privacy copy,
support diagnostics, and M39 beta sign-off evidence. It performs no desktop
actions and does not notarize, grant TCC, open System Settings, capture
screens, move the pointer, click, type, submit, post, purchase, or operate
desktop apps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --launch-checklist)
      require_value "$@"
      LAUNCH_CHECKLIST="$2"
      shift 2
      ;;
    --release-artifact-report)
      require_value "$@"
      RELEASE_ARTIFACT_REPORT="$2"
      shift 2
      ;;
    --release-packaging-report)
      require_value "$@"
      RELEASE_PACKAGING_REPORT="$2"
      shift 2
      ;;
    --manual-tcc-report)
      require_value "$@"
      MANUAL_TCC_REPORT="$2"
      shift 2
      ;;
    --m36-live-llm-eval)
      require_value "$@"
      M36_LIVE_LLM_EVAL="$2"
      shift 2
      ;;
    --m39-beta-signoff)
      require_value "$@"
      M39_BETA_SIGNOFF="$2"
      shift 2
      ;;
    --diagnostics)
      require_value "$@"
      DIAGNOSTICS="$2"
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
  "tool/macos_computer_use_production_launch_gate.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M40 launch checklist template"
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

if [[ -n "${LAUNCH_CHECKLIST}" ]]; then
  args+=("--launch-checklist" "${LAUNCH_CHECKLIST}")
fi
if [[ -n "${RELEASE_ARTIFACT_REPORT}" ]]; then
  args+=("--release-artifact-report" "${RELEASE_ARTIFACT_REPORT}")
fi
if [[ -n "${RELEASE_PACKAGING_REPORT}" ]]; then
  args+=("--release-packaging-report" "${RELEASE_PACKAGING_REPORT}")
fi
if [[ -n "${MANUAL_TCC_REPORT}" ]]; then
  args+=("--manual-tcc-report" "${MANUAL_TCC_REPORT}")
fi
if [[ -n "${M36_LIVE_LLM_EVAL}" ]]; then
  args+=("--m36-live-llm-eval" "${M36_LIVE_LLM_EVAL}")
fi
if [[ -n "${M39_BETA_SIGNOFF}" ]]; then
  args+=("--m39-beta-signoff" "${M39_BETA_SIGNOFF}")
fi
if [[ -n "${DIAGNOSTICS}" ]]; then
  args+=("--diagnostics" "${DIAGNOSTICS}")
fi

echo "Running macOS Computer Use M40 production launch gate"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated notarization, TCC, and desktop actions"

dart "${args[@]}"

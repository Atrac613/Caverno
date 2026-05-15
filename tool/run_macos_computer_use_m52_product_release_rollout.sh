#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M52_PRODUCT_RELEASE_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m52_product_release_rollout_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m52_product_release_rollout.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m52_product_release_rollout.md"
PRODUCT_RELEASE_CHECKLIST=""
M51_PRODUCTION_LAUNCH_GATE=""
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
Usage: bash tool/run_macos_computer_use_m52_product_release_rollout.sh [options]

Options:
  --root PATH                         Report root directory.
  --product-release-checklist PATH    M52 product release checklist JSON.
  --m51-production-launch-gate PATH   M51 production launch gate JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a product release checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M52 gate is blocked.
  --help                              Show this help.

M52 is report-only. It reads M51 production launch evidence and product release
rollout checklist evidence. It performs no desktop actions and does not grant
TCC, notarize, staple, open System Settings, capture screens, move the pointer,
click, type, submit, post, purchase, export raw payloads, or operate desktop apps.
Advanced settings rollout, rollback, support, monitoring, and emergency stop
validation remain user-operated release steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --product-release-checklist)
      require_value "$@"
      PRODUCT_RELEASE_CHECKLIST="$2"
      shift 2
      ;;
    --m51-production-launch-gate)
      require_value "$@"
      M51_PRODUCTION_LAUNCH_GATE="$2"
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
  "tool/macos_computer_use_m52_product_release_rollout.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M52 product release checklist template"
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

if [[ -n "${PRODUCT_RELEASE_CHECKLIST}" ]]; then
  args+=("--product-release-checklist" "${PRODUCT_RELEASE_CHECKLIST}")
fi
if [[ -n "${M51_PRODUCTION_LAUNCH_GATE}" ]]; then
  args+=("--m51-production-launch-gate" "${M51_PRODUCTION_LAUNCH_GATE}")
fi

echo "Running macOS Computer Use M52 product release rollout"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated Advanced rollout, rollback, support, TCC, and desktop actions"

dart "${args[@]}"

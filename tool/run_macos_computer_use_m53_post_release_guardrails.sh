#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M53_POST_RELEASE_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m53_post_release_guardrails_${RUN_ID}"
OUTPUT_JSON="${RUN_DIR}/macos_computer_use_m53_post_release_guardrails.json"
OUTPUT_MD="${RUN_DIR}/macos_computer_use_m53_post_release_guardrails.md"
POST_RELEASE_CHECKLIST=""
M52_PRODUCT_RELEASE_ROLLOUT=""
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
Usage: bash tool/run_macos_computer_use_m53_post_release_guardrails.sh [options]

Options:
  --root PATH                         Report root directory.
  --post-release-checklist PATH       M53 post-release checklist JSON.
  --m52-product-release-rollout PATH  M52 product release rollout JSON.
  --output-json PATH                  Output summary JSON path.
  --output-md PATH                    Output summary Markdown path.
  --write-template [PATH]             Write a post-release checklist template and exit.
  --report-only                       Always exit 0 after writing the report.
  --strict                            Exit non-zero when any M53 gate is blocked.
  --help                              Show this help.

M53 is report-only. It reads M52 product release rollout evidence and
post-release checklist evidence. It performs no desktop actions and does not
grant TCC, notarize, staple, open System Settings, capture screens, move the
pointer, click, type, submit, post, purchase, export raw payloads, or operate desktop apps.
Monitoring, support diagnostics review, rollback, hotfix, and
escalation validation remain user-operated post-release steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --post-release-checklist)
      require_value "$@"
      POST_RELEASE_CHECKLIST="$2"
      shift 2
      ;;
    --m52-product-release-rollout)
      require_value "$@"
      M52_PRODUCT_RELEASE_ROLLOUT="$2"
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
  "tool/macos_computer_use_m53_post_release_guardrails.dart"
  "--root"
  "${REPORT_ROOT}"
)

if [[ "${WRITE_TEMPLATE}" == "yes" ]]; then
  args+=("--write-template")
  if [[ -n "${TEMPLATE_PATH}" ]]; then
    args+=("${TEMPLATE_PATH}")
  fi
  echo "Writing M53 post-release checklist template"
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

if [[ -n "${POST_RELEASE_CHECKLIST}" ]]; then
  args+=("--post-release-checklist" "${POST_RELEASE_CHECKLIST}")
fi
if [[ -n "${M52_PRODUCT_RELEASE_ROLLOUT}" ]]; then
  args+=("--m52-product-release-rollout" "${M52_PRODUCT_RELEASE_ROLLOUT}")
fi

echo "Running macOS Computer Use M53 post-release guardrails"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only, user-operated monitoring, support, rollback, hotfix, TCC, and desktop actions"

dart "${args[@]}"

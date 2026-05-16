#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_MANUAL_TCC_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_manual_tcc_${RUN_ID}"
REPORT_PATH="${RUN_DIR}/manual_tcc_runtime_signoff.json"
SUMMARY_JSON="${RUN_DIR}/manual_tcc_report_summary.json"
SUMMARY_MD="${RUN_DIR}/manual_tcc_report_summary.md"
RELEASE_APP_PATH="${ROOT_DIR}/build/macos/Build/Products/Release/Caverno.app"
RELEASE_HELPER_PATH="${RELEASE_APP_PATH}/Contents/Helpers/Caverno Computer Use.app"
REBUILD_RELEASE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report-root)
      if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
        echo "--report-root requires a value."
        exit 2
      fi
      REPORT_ROOT="$2"
      shift 2
      ;;
    --rebuild-release)
      REBUILD_RELEASE=1
      shift
      ;;
    --help|-h)
      echo "Usage: bash tool/run_macos_computer_use_manual_tcc_signoff.sh [--report-root path] [--rebuild-release]"
      echo
      echo "This user-operated wrapper measures macOS TCC state only."
      echo "It does not grant permissions, edit TCC, or operate System Settings."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_manual_tcc_${RUN_ID}"
REPORT_PATH="${RUN_DIR}/manual_tcc_runtime_signoff.json"
SUMMARY_JSON="${RUN_DIR}/manual_tcc_report_summary.json"
SUMMARY_MD="${RUN_DIR}/manual_tcc_report_summary.md"

mkdir -p "${RUN_DIR}"

echo "macOS Computer Use manual TCC sign-off"
echo "  Boundary: user-operated manual verification only"
echo "  This wrapper does not grant permissions, edit TCC, or operate System Settings."
echo "  Before running, grant the release Caverno Computer Use helper in:"
echo "    System Settings > Privacy & Security > Accessibility"
echo "    System Settings > Privacy & Security > Screen & System Audio Recording"
echo "  Release helper: ${RELEASE_HELPER_PATH}"
echo "  Report: ${REPORT_PATH}"
echo "  Summary JSON: ${SUMMARY_JSON}"
echo "  Summary Markdown: ${SUMMARY_MD}"

smoke_args=(
  --reporter compact
  --m8-runtime-signoff
)
if [[ "${REBUILD_RELEASE}" == "1" ]]; then
  smoke_args+=(--rebuild-release)
fi

status=0
set +e
CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${REPORT_PATH}" \
  bash "${ROOT_DIR}/tool/run_macos_computer_use_smoke_test.sh" "${smoke_args[@]}"
status=$?
set -e

if [[ -f "${REPORT_PATH}" ]]; then
  set +e
  dart run tool/macos_computer_use_manual_tcc_report.dart \
    "${REPORT_PATH}" \
    --output-json "${SUMMARY_JSON}" \
    --output-md "${SUMMARY_MD}"
  parser_status=$?
  set -e
  if [[ "${status}" == "0" && "${parser_status}" != "0" ]]; then
    status="${parser_status}"
  fi
else
  echo "Manual TCC report was not produced: ${REPORT_PATH}"
fi

echo
echo "Manual TCC handoff"
echo "  Release helper: ${RELEASE_HELPER_PATH}"
echo "  Report: ${REPORT_PATH}"
echo "  Parser: dart run tool/macos_computer_use_manual_tcc_report.dart ${REPORT_PATH}"
echo "  Summary JSON: ${SUMMARY_JSON}"
echo "  Summary Markdown: ${SUMMARY_MD}"

exit "${status}"

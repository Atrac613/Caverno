#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_SIGNING_PREFLIGHT_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
OUTPUT_JSON="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_SIGNING_PREFLIGHT_JSON:-${REPORT_ROOT}/macos_computer_use_release_signing_preflight.json}"
OUTPUT_MD="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_SIGNING_PREFLIGHT_MD:-${REPORT_ROOT}/macos_computer_use_release_signing_preflight.md}"

echo "Running macOS Computer Use release signing preflight"
echo "  Project root: ${ROOT_DIR}"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: report-only signing setup check"
echo "  It does not sign, notarize, staple, grant TCC, or operate desktop apps."

cd "${ROOT_DIR}"
dart run tool/macos_computer_use_release_signing_preflight.dart \
  --project-root "${ROOT_DIR}" \
  --root "${REPORT_ROOT}" \
  --output-json "${OUTPUT_JSON}" \
  --output-md "${OUTPUT_MD}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_PACKAGING_REPORT_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
OUTPUT_JSON="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_PACKAGING_JSON:-${REPORT_ROOT}/macos_computer_use_release_packaging.json}"
OUTPUT_MD="${CAVERNO_MACOS_COMPUTER_USE_RELEASE_PACKAGING_MD:-${REPORT_ROOT}/macos_computer_use_release_packaging.md}"

echo "Running macOS Computer Use M33 release packaging checks"
echo "  Project root: ${ROOT_DIR}"
echo "  Report root: ${REPORT_ROOT}"
echo "  Output JSON: ${OUTPUT_JSON}"
echo "  Output Markdown: ${OUTPUT_MD}"
echo "  Boundary: static project checks only"
echo "  External signing: provide DEVELOPMENT_TEAM and identity through Signing.local.xcconfig"
echo "  Notarization: user-operated release pipeline evidence required before distribution"

cd "${ROOT_DIR}"
dart run tool/macos_computer_use_release_packaging.dart \
  --project-root "${ROOT_DIR}" \
  --root "${REPORT_ROOT}" \
  --output-json "${OUTPUT_JSON}" \
  --output-md "${OUTPUT_MD}"

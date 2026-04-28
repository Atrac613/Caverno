#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_PATH="${CAVERNO_MACOS_COMPUTER_USE_EXISTING_HELPER_REPORT_PATH:-/tmp/caverno-macos-computer-use-existing-helper-probe.json}"

cd "${ROOT_DIR}"

echo "Running macOS computer-use existing-helper probe"
echo "  Rebuild: disabled"
echo "  Report: ${REPORT_PATH}"

/usr/bin/swift tool/macos_computer_use_existing_helper_probe.swift \
  --report "${REPORT_PATH}" \
  "$@"

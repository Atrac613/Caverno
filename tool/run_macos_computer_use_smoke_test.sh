#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
STRICT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --reporter)
      REPORTER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 2
      ;;
  esac
done

echo "Running macOS computer-use live smoke"
echo "  Device: ${DEVICE}"
echo "  Reporter: ${REPORTER}"
echo "  Strict: ${STRICT}"

cd "${ROOT_DIR}"

flutter test integration_test/macos_computer_use_smoke_test.dart \
  -d "${DEVICE}" \
  -r "${REPORTER}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT="${STRICT}"

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
STRICT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT:-0}"
UNSAFE_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED:-0}"
UNSAFE_CLICK_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED:-0}"
UNSAFE_TEXT_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED:-0}"
REGISTER_XPC_AGENT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT:-0}"
REPORT_PATH="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH:-/tmp/caverno-macos-computer-use-smoke.json}"

dart_bool_define() {
  case "$1" in
    1|true|TRUE|yes|YES)
      echo "true"
      ;;
    *)
      echo "false"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --unsafe-armed)
      UNSAFE_ARMED=1
      shift
      ;;
    --unsafe-click-armed)
      UNSAFE_ARMED=1
      UNSAFE_CLICK_ARMED=1
      shift
      ;;
    --unsafe-text-armed)
      UNSAFE_ARMED=1
      UNSAFE_TEXT_ARMED=1
      shift
      ;;
    --register-xpc-agent)
      REGISTER_XPC_AGENT=1
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
echo "  Unsafe armed: ${UNSAFE_ARMED}"
echo "  Unsafe click armed: ${UNSAFE_CLICK_ARMED}"
echo "  Unsafe text armed: ${UNSAFE_TEXT_ARMED}"
echo "  Register XPC agent: ${REGISTER_XPC_AGENT}"
echo "  Report: ${REPORT_PATH}"

STRICT_DART="$(dart_bool_define "${STRICT}")"
UNSAFE_ARMED_DART="$(dart_bool_define "${UNSAFE_ARMED}")"
UNSAFE_CLICK_ARMED_DART="$(dart_bool_define "${UNSAFE_CLICK_ARMED}")"
UNSAFE_TEXT_ARMED_DART="$(dart_bool_define "${UNSAFE_TEXT_ARMED}")"
REGISTER_XPC_AGENT_DART="$(dart_bool_define "${REGISTER_XPC_AGENT}")"

cd "${ROOT_DIR}"

flutter test integration_test/macos_computer_use_smoke_test.dart \
  -d "${DEVICE}" \
  -r "${REPORTER}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT="${STRICT_DART}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED="${UNSAFE_ARMED_DART}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED="${UNSAFE_CLICK_ARMED_DART}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED="${UNSAFE_TEXT_ARMED_DART}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT="${REGISTER_XPC_AGENT_DART}" \
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${REPORT_PATH}"

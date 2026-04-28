#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE="${CAVERNO_MACOS_COMPUTER_USE_DEVICE:-macos}"
REPORTER="${CAVERNO_MACOS_COMPUTER_USE_REPORTER:-compact}"
BUILD_MODE="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_BUILD_MODE:-debug}"
STRICT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT:-0}"
STRICT_XPC="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT_XPC:-0}"
UNSAFE_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED:-0}"
UNSAFE_CLICK_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED:-0}"
UNSAFE_TEXT_ARMED="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED:-0}"
REGISTER_XPC_AGENT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT:-0}"
CLEANUP_XPC_AGENT="${CAVERNO_MACOS_COMPUTER_USE_SMOKE_CLEANUP_XPC_AGENT:-0}"
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
    --strict-xpc)
      STRICT_XPC=1
      REGISTER_XPC_AGENT=1
      shift
      ;;
    --debug|--profile|--release)
      BUILD_MODE="${1#--}"
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
    --cleanup-xpc-agent|--unregister-xpc-agent)
      CLEANUP_XPC_AGENT=1
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
echo "  Build mode: ${BUILD_MODE}"
echo "  Strict: ${STRICT}"
echo "  Strict XPC: ${STRICT_XPC}"
echo "  Unsafe armed: ${UNSAFE_ARMED}"
echo "  Unsafe click armed: ${UNSAFE_CLICK_ARMED}"
echo "  Unsafe text armed: ${UNSAFE_TEXT_ARMED}"
echo "  Register XPC agent: ${REGISTER_XPC_AGENT}"
echo "  Cleanup XPC agent: ${CLEANUP_XPC_AGENT}"
echo "  Report: ${REPORT_PATH}"

STRICT_DART="$(dart_bool_define "${STRICT}")"
STRICT_XPC_DART="$(dart_bool_define "${STRICT_XPC}")"
UNSAFE_ARMED_DART="$(dart_bool_define "${UNSAFE_ARMED}")"
UNSAFE_CLICK_ARMED_DART="$(dart_bool_define "${UNSAFE_CLICK_ARMED}")"
UNSAFE_TEXT_ARMED_DART="$(dart_bool_define "${UNSAFE_TEXT_ARMED}")"
REGISTER_XPC_AGENT_DART="$(dart_bool_define "${REGISTER_XPC_AGENT}")"
CLEANUP_XPC_AGENT_DART="$(dart_bool_define "${CLEANUP_XPC_AGENT}")"

cd "${ROOT_DIR}"

COMMON_DART_DEFINES=(
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT="${STRICT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_STRICT_XPC="${STRICT_XPC_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED="${UNSAFE_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED="${UNSAFE_CLICK_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED="${UNSAFE_TEXT_ARMED_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REGISTER_XPC_AGENT="${REGISTER_XPC_AGENT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_CLEANUP_XPC_AGENT="${CLEANUP_XPC_AGENT_DART}"
  --dart-define=CAVERNO_MACOS_COMPUTER_USE_SMOKE_REPORT_PATH="${REPORT_PATH}"
)

case "${BUILD_MODE}" in
  debug)
    flutter test integration_test/macos_computer_use_smoke_test.dart \
      -d "${DEVICE}" \
      -r "${REPORTER}" \
      "${COMMON_DART_DEFINES[@]}"
    ;;
  profile)
    flutter drive \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/macos_computer_use_smoke_test.dart \
      --"${BUILD_MODE}" \
      -d "${DEVICE}" \
      "${COMMON_DART_DEFINES[@]}"
    ;;
  release)
    flutter build macos --release "${COMMON_DART_DEFINES[@]}"
    RELEASE_APP="${ROOT_DIR}/build/macos/Build/Products/Release/Caverno.app"
    RELEASE_HELPER="${RELEASE_APP}/Contents/Helpers/Caverno Computer Use.app"
    RELEASE_AGENT="${RELEASE_APP}/Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist"
    test -d "${RELEASE_APP}"
    test -d "${RELEASE_HELPER}"
    test -f "${RELEASE_AGENT}"
    /usr/bin/plutil -lint "${RELEASE_AGENT}"
    /usr/libexec/PlistBuddy \
      -c "Print :MachServices:com.noguwo.apps.caverno.computer-use.xpc" \
      "${RELEASE_AGENT}"
    /usr/bin/codesign --verify --deep --strict "${RELEASE_APP}"
    RELEASE_REPORT_PATH="${REPORT_PATH}" \
    RELEASE_APP="${RELEASE_APP}" \
    RELEASE_HELPER="${RELEASE_HELPER}" \
    RELEASE_AGENT="${RELEASE_AGENT}" \
    STRICT_DART="${STRICT_DART}" \
    STRICT_XPC_DART="${STRICT_XPC_DART}" \
    REGISTER_XPC_AGENT_DART="${REGISTER_XPC_AGENT_DART}" \
    CLEANUP_XPC_AGENT_DART="${CLEANUP_XPC_AGENT_DART}" \
      python3 - <<'PY'
import datetime
import json
import os
from pathlib import Path

report_path = os.environ["RELEASE_REPORT_PATH"]
app = os.environ["RELEASE_APP"]
helper = os.environ["RELEASE_HELPER"]
agent = os.environ["RELEASE_AGENT"]
report = {
    "schemaName": "macos_computer_use_release_bundle_smoke",
    "schemaVersion": 1,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    "buildMode": "release",
    "strict": os.environ["STRICT_DART"] == "true",
    "strictXpc": os.environ["STRICT_XPC_DART"] == "true",
    "registerXpcAgent": os.environ["REGISTER_XPC_AGENT_DART"] == "true",
    "cleanupXpcAgent": os.environ["CLEANUP_XPC_AGENT_DART"] == "true",
    "ok": True,
    "releaseBundle": {
        "appExists": os.path.isdir(app),
        "helperExists": os.path.isdir(helper),
        "launchAgentExists": os.path.isfile(agent),
        "launchAgentPlistValid": True,
        "machServiceDeclared": True,
        "codesignVerified": True,
        "appPath": app,
        "helperPath": helper,
        "launchAgentPath": agent,
        "xpcServiceName": "com.noguwo.apps.caverno.computer-use.xpc",
    },
    "reportPath": report_path,
}
encoded = json.dumps(report, indent=2)
if report_path:
    path = Path(report_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(encoded)
print(f"CAVERNO_MACOS_COMPUTER_USE_SMOKE_JSON={encoded}")
PY
    echo "Release bundle XPC artifacts verified"
    ;;
  *)
    echo "Unknown build mode: ${BUILD_MODE}"
    exit 2
    ;;
esac

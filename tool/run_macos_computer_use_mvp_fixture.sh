#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PATH="${ROOT_DIR}/tool/fixtures/macos_computer_use_mvp_fixture/MacOSComputerUseMvpFixtureApp.swift"
BUILD_ROOT="${CAVERNO_MACOS_COMPUTER_USE_FIXTURE_BUILD_ROOT:-${ROOT_DIR}/build/macos_computer_use_mvp_fixture}"
APP_NAME="Caverno Computer Use MVP Fixture"
APP_BUNDLE="${BUILD_ROOT}/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
MODULE_CACHE_PATH="${BUILD_ROOT}/ModuleCache"
LAUNCH_APP=0
PRINT_PATH=0

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_mvp_fixture.sh [options]

Options:
  --build-root PATH  Build the fixture app under PATH.
  --launch           Launch the built fixture app after compiling it.
  --print-path       Print the built app bundle path.
  --help             Show this help.

This fixture app is a deterministic macOS target for Computer Use MVP canaries.
Launching it opens a harmless window with a safe click button, a text field,
and a disabled destructive target. This script does not grant TCC permissions.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-root)
      require_value "$@"
      BUILD_ROOT="$2"
      shift 2
      ;;
    --launch)
      LAUNCH_APP=1
      shift
      ;;
    --print-path)
      PRINT_PATH=1
      shift
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

APP_BUNDLE="${BUILD_ROOT}/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
MODULE_CACHE_PATH="${BUILD_ROOT}/ModuleCache"

mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources" "${MODULE_CACHE_PATH}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.noguwo.apps.caverno.computer-use-mvp-fixture</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

CLANG_MODULE_CACHE_PATH="${MODULE_CACHE_PATH}" \
  swiftc -parse-as-library -module-cache-path "${MODULE_CACHE_PATH}" "${SOURCE_PATH}" -o "${EXECUTABLE_PATH}"

echo "Built Computer Use MVP fixture app"
echo "  App bundle: ${APP_BUNDLE}"
echo "  TCC boundary: no TCC operation"
echo "  Desktop action boundary: launch only when --launch is provided"

if [[ "${PRINT_PATH}" == "1" ]]; then
  echo "${APP_BUNDLE}"
fi

if [[ "${LAUNCH_APP}" == "1" ]]; then
  echo "Launching fixture app"
  open "${APP_BUNDLE}"
fi

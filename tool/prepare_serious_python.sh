#!/usr/bin/env bash
#
# Prepare serious_python's native interpreter directories for a build.
#
# serious_python ships the embedded CPython + its stdlib native modules per
# platform; the app must stage them before building:
#
#   * iOS:     dist_ios/site-xcframeworks   (created by the plugin's sync)
#   * macOS:   dist_macos/site-packages     (created by the plugin's sync)
#   * Android: $SERIOUS_PYTHON_SITE_PACKAGES/<abi>, zipped at gradle time
#
# Caverno vendors only PURE-PYTHON dependencies (worker/__pypackages__), so the
# staged site-packages are empty — the sync still copies the stdlib native
# modules the interpreter needs at runtime (_ssl, _socket, ...). For NATIVE
# packages, use `dart run serious_python:main package ... -p <platform> -r <pkg>`
# instead.
#
# Run once after `flutter pub get` (re-run after a pub-cache wipe):
#
#     tool/prepare_serious_python.sh
#
# iOS / macOS are then fully prepared — just build. For ANDROID you must also
# export SERIOUS_PYTHON_SITE_PACKAGES when building (the gradle plugin reads it
# live and errors if unset):
#
#     export SERIOUS_PYTHON_SITE_PACKAGES="$(pwd)/build/serious_python_site"
#     flutter run -d <android>        # or: flutter build apk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

# Empty stub site-packages — one dir per iOS arch and per Android ABI. Pure-
# Python deps ride in the worker bundle, so these stay empty.
SITE="$ROOT/build/serious_python_site"
mkdir -p \
  "$SITE/iphoneos.arm64" \
  "$SITE/iphonesimulator.arm64" \
  "$SITE/iphonesimulator.x86_64" \
  "$SITE/arm64-v8a" \
  "$SITE/armeabi-v7a" \
  "$SITE/x86_64"

# --- Apple (iOS + macOS): pre-populate the plugin's dist dirs via its sync ----
if [ -d "$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin" ]; then
  DARWIN="$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin"
else
  PC="${PUB_CACHE:-$HOME/.pub-cache}"
  DARWIN="$(ls -d "$PC"/hosted/pub.dev/serious_python_darwin-*/darwin 2>/dev/null | sort | tail -1 || true)"
fi

if [ -n "${DARWIN:-}" ] && [ -f "$DARWIN/sync_site_packages.sh" ]; then
  echo "Apple plugin: $DARWIN"
  # iOS branch: the stub contains the three iOS arch dirs.
  SERIOUS_PYTHON_SITE_PACKAGES="$SITE" bash "$DARWIN/sync_site_packages.sh" || true
  # macOS branch: a dir WITHOUT the iOS arch dirs.
  MACSITE="$ROOT/build/serious_python_site_macos"
  mkdir -p "$MACSITE"
  SERIOUS_PYTHON_SITE_PACKAGES="$MACSITE" bash "$DARWIN/sync_site_packages.sh" || true

  IOS_COUNT="$(ls "$DARWIN/dist_ios/site-xcframeworks" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${IOS_COUNT:-0}" -gt 0 ]; then
    echo "  iOS:   dist_ios/site-xcframeworks ready ($IOS_COUNT xcframeworks)."
  else
    echo "  error: dist_ios/site-xcframeworks was not populated." >&2
    exit 1
  fi
  if [ -d "$DARWIN/dist_macos/site-packages" ]; then
    echo "  macOS: dist_macos/site-packages ready."
  fi
else
  echo "warning: serious_python_darwin not found; run 'flutter pub get' first." >&2
fi

echo
echo "iOS / macOS: ready — just build."
echo "Android: export SERIOUS_PYTHON_SITE_PACKAGES=\"$SITE\" before building."

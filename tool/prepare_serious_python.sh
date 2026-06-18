#!/usr/bin/env bash
#
# Prepare serious_python's native interpreter directories for a build.
#
# serious_python ships the embedded CPython + its stdlib native modules per
# platform. With serious_python 2.x the Apple dist is split into:
#
#   * dist_<plat>/xcframeworks/   Python.xcframework  -> vendored_frameworks
#   * dist_<plat>/stdlib/         compiled stdlib      -> resource_bundle
#   * dist_<plat>/site-packages/  user packages        -> resource_bundle
#
# (where <plat> is `ios` or `macos`), plus Android:
#
#   * Android: $SERIOUS_PYTHON_SITE_PACKAGES/<abi>, zipped at gradle time
#
# The plugin's prepare_<plat>.sh downloads + extracts the xcframeworks/stdlib on
# first run and is a no-op once present. The podspec runs them as its
# prepare_command at pod install, so a plain `flutter build` stages them too;
# running them here keeps the documented "prepare once, then build" contract and
# lets the script validate the result.
#
# Caverno vendors only PURE-PYTHON dependencies (worker/__pypackages__), so the
# per-arch site-packages stay empty — the interpreter still ships the stdlib
# native modules it needs at runtime (_ssl, _socket, ...). For NATIVE packages,
# use `dart run serious_python:main package ... -p <platform> -r <pkg>` instead.
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

dir_has_entries() { [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

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

# --- Apple (iOS + macOS): stage the embedded interpreter via the plugin -------
if [ -d "$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin" ]; then
  DARWIN="$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin"
else
  PC="${PUB_CACHE:-$HOME/.pub-cache}"
  DARWIN="$(ls -d "$PC"/hosted/pub.dev/serious_python_darwin-*/darwin 2>/dev/null | sort | tail -1 || true)"
fi

if [ -n "${DARWIN:-}" ] && [ -f "$DARWIN/prepare_ios.sh" ]; then
  echo "Apple plugin: $DARWIN"

  # Keep the interpreter version in lockstep with the podspec.
  PYV="$(sed -nE 's/.*python_version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
    "$DARWIN/serious_python_darwin.podspec" 2>/dev/null | head -1)"
  PYV="${PYV:-3.12}"

  # Download + extract Python.xcframework and the stdlib (no-op once staged).
  ( cd "$DARWIN" && bash prepare_ios.sh "$PYV" )
  ( cd "$DARWIN" && bash prepare_macos.sh "$PYV" )

  # sync_site_packages.sh copies USER native site-packages from the stub dirs
  # into the dist. Caverno keeps those empty, so the script logs a benign
  # "cp: .../iphoneos.arm64/*: No such file" while converting zero dylibs and an
  # empty macOS rsync ("total size is 0"). Both are expected here — ignore them.
  if [ -f "$DARWIN/sync_site_packages.sh" ]; then
    echo "Syncing user site-packages (empty for Caverno — the 'No such file' /" \
      "'total size is 0' lines below are expected)..."
    SERIOUS_PYTHON_SITE_PACKAGES="$SITE" bash "$DARWIN/sync_site_packages.sh" || true
    MACSITE="$ROOT/build/serious_python_site_macos"
    mkdir -p "$MACSITE"
    SERIOUS_PYTHON_SITE_PACKAGES="$MACSITE" bash "$DARWIN/sync_site_packages.sh" || true
  fi

  # Validate the directories the podspec actually vendors/bundles.
  apple_ok=1
  for plat in ios macos; do
    fw="$DARWIN/dist_$plat/xcframeworks"
    std="$DARWIN/dist_$plat/stdlib"
    if dir_has_entries "$fw" && dir_has_entries "$std"; then
      fw_count="$(ls "$fw" 2>/dev/null | wc -l | tr -d ' ')"
      echo "  $plat: dist_$plat staged ($fw_count xcframework(s) + stdlib)."
    else
      echo "  error: dist_$plat is not staged (missing xcframeworks/ or stdlib/)." >&2
      apple_ok=0
    fi
  done
  [ "$apple_ok" -eq 1 ] || exit 1
else
  echo "warning: serious_python_darwin not found; run 'flutter pub get' first." >&2
fi

echo
echo "iOS / macOS: native interpreter staged — just build."
echo "Android: export SERIOUS_PYTHON_SITE_PACKAGES=\"$SITE\" before building."

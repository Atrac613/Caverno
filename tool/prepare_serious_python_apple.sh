#!/usr/bin/env bash
#
# Prepare serious_python's iOS native-framework directory for the build.
#
# The serious_python_darwin pod has a build phase that bundles the embedded
# interpreter's stdlib native modules (and any native site-packages) from
# `dist_ios/site-xcframeworks`. That directory is created by the plugin's
# `sync_site_packages.sh`, which only runs when SERIOUS_PYTHON_SITE_PACKAGES
# points at a folder containing the three iOS arch subdirs. Caverno vendors only
# pure-Python dependencies (in the worker's __pypackages__), so empty arch dirs
# are enough — the sync still copies the stdlib native modules (_ssl, _socket,
# ...) which the interpreter needs at runtime.
#
# Run this once per machine after `flutter pub get` (re-run only if the
# serious_python_darwin version changes or you wipe the pub cache), before
# building or running on iOS:
#
#     tool/prepare_serious_python_apple.sh
#
# Without it the iOS build fails in the serious_python_darwin build phase with:
#     find: .../dist_ios/site-xcframeworks: No such file or directory
#
# For NATIVE (non-pure-Python) packages on iOS, use the official packager
# instead, which also fills site-xcframeworks from prebuilt mobile wheels:
#     dart run serious_python:main package \
#       lib/core/services/script_runtime/worker \
#       -a assets/python/app.zip -p iOS -r <package>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"

# Locate the serious_python_darwin plugin (project symlink first, then cache).
PLUGIN=""
if [ -d "$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin" ]; then
  PLUGIN="$ROOT/ios/.symlinks/plugins/serious_python_darwin/darwin"
else
  PC="${PUB_CACHE:-$HOME/.pub-cache}"
  PLUGIN="$(ls -d "$PC"/hosted/pub.dev/serious_python_darwin-*/darwin 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "$PLUGIN" ] || [ ! -f "$PLUGIN/sync_site_packages.sh" ]; then
  echo "error: serious_python_darwin plugin not found; run 'flutter pub get' first." >&2
  exit 1
fi

SITE="$ROOT/build/serious_python_site"
mkdir -p \
  "$SITE/iphoneos.arm64" \
  "$SITE/iphonesimulator.arm64" \
  "$SITE/iphonesimulator.x86_64"

echo "Plugin:            $PLUGIN"
echo "Site-packages stub: $SITE"
SERIOUS_PYTHON_SITE_PACKAGES="$SITE" bash "$PLUGIN/sync_site_packages.sh"

COUNT="$(ls "$PLUGIN/dist_ios/site-xcframeworks" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$COUNT" -gt 0 ]; then
  echo "OK: dist_ios/site-xcframeworks now has $COUNT xcframeworks."
else
  echo "error: site-xcframeworks was not populated." >&2
  exit 1
fi

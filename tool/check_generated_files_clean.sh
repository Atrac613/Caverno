#!/usr/bin/env bash
# Verify that a fresh `flutter pub get` + `build_runner build` left the working
# tree clean, i.e. every generated artifact in the repository is committed.
#
# pubspec.lock is checked separately from the generated Dart files because the
# two failures have different causes. Dependabot resolves pubspec.lock with a
# stock Dart pub that has no knowledge of the packages the pinned Flutter SDK
# vendors (vector_math, meta, intl, matcher, test*), so it writes versions that
# `flutter pub get` immediately reverts. That drift is structural: it shows up
# on every Dependabot pub PR, including no-op patch bumps, and it is not a
# defect in the bump itself. Set ALLOW_LOCK_DRIFT=1 to downgrade the lock
# mismatch to a warning; generated Dart files stay strict either way.
set -euo pipefail

allow_lock_drift="${ALLOW_LOCK_DRIFT:-0}"

if ! git diff --quiet -- . ':(exclude)pubspec.lock'; then
  echo "Generated files are out of date. Run:" >&2
  echo "  dart run build_runner build --delete-conflicting-outputs" >&2
  echo "and commit the result." >&2
  git --no-pager diff -- . ':(exclude)pubspec.lock' >&2
  exit 1
fi

if git diff --quiet -- pubspec.lock; then
  exit 0
fi

if [ "$allow_lock_drift" != "1" ]; then
  echo "pubspec.lock does not match what 'flutter pub get' resolves." >&2
  echo "Run 'flutter pub get' with the .fvmrc Flutter version and commit the lock." >&2
  git --no-pager diff -- pubspec.lock >&2
  exit 1
fi

echo "::warning title=pubspec.lock needs regeneration::The committed pubspec.lock does not match the Flutter-resolved one. Run 'flutter pub get' with the .fvmrc Flutter version and amend this branch before merging."
git --no-pager diff --stat -- pubspec.lock
git --no-pager diff -- pubspec.lock

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_DOWNLOAD_URL_PREFIX="https://updates.example.invalid/caverno/macos/staging"
DEFAULT_S3_URI="s3://caverno-dummy-updates/macos/staging"

DOWNLOAD_URL_PREFIX="${CAVERNO_SPARKLE_STAGING_DOWNLOAD_URL_PREFIX:-${DEFAULT_DOWNLOAD_URL_PREFIX}}"
S3_URI="${CAVERNO_SPARKLE_STAGING_S3_URI:-${DEFAULT_S3_URI}}"
RELEASE_NOTES_PATH="${CAVERNO_SPARKLE_STAGING_RELEASE_NOTES_PATH:-${ROOT_DIR}/docs/releases/caverno-staging.md}"
NOTARY_PROFILE="${CAVERNO_SPARKLE_STAGING_NOTARY_PROFILE:-${CAVERNO_NOTARYTOOL_PROFILE:-caverno-notary}}"
PACKAGE_FORMAT="${CAVERNO_SPARKLE_STAGING_PACKAGE_FORMAT:-zip}"
DRY_RUN="yes"
SKIP_PREFLIGHT="yes"
SKIP_NOTARIZATION="yes"
EXTRA_ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_sparkle_staging_rehearsal.sh [options] [driver options]

Options:
  --download-url-prefix URL  Override the dummy HTTPS staging URL.
  --s3-uri URI               Override the dummy S3 staging destination.
  --release-notes PATH       Release notes passed to the release driver.
  --notary-profile NAME      notarytool profile for --with-notarization.
  --package zip|dmg          Artifact package format, default zip.
  --with-preflight           Run local release signing and packaging checks.
  --with-notarization        Run notarytool and stapler steps.
  --real-run                 Execute commands instead of printing them.
  --help                     Show this help.

By default this is a no-upload staging rehearsal. It passes dummy S3 and HTTPS
coordinates to the Sparkle release driver, keeps notarization disabled, and
forces dry-run mode so the publish path is visible without mutating S3.
USAGE
}

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --download-url-prefix)
      require_value "$@"
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --s3-uri)
      require_value "$@"
      S3_URI="$2"
      shift 2
      ;;
    --release-notes)
      require_value "$@"
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --notary-profile)
      require_value "$@"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --package)
      require_value "$@"
      PACKAGE_FORMAT="$2"
      shift 2
      ;;
    --with-preflight)
      SKIP_PREFLIGHT="no"
      shift 1
      ;;
    --with-notarization)
      SKIP_NOTARIZATION="no"
      shift 1
      ;;
    --real-run)
      DRY_RUN="no"
      shift 1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift 1
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift 1
      ;;
  esac
done

case "${PACKAGE_FORMAT}" in
  zip|dmg)
    ;;
  *)
    echo "--package must be zip or dmg." >&2
    exit 64
    ;;
esac

if [[ "${DRY_RUN}" != "yes" ]]; then
  if [[ "${DOWNLOAD_URL_PREFIX}" == "${DEFAULT_DOWNLOAD_URL_PREFIX}" ]]; then
    echo "Real runs require a non-dummy --download-url-prefix." >&2
    exit 64
  fi
  if [[ "${S3_URI}" == "${DEFAULT_S3_URI}" ]]; then
    echo "Real runs require a non-dummy --s3-uri." >&2
    exit 64
  fi
fi

driver_args=(
  bash
  "${ROOT_DIR}/tool/build_macos_sparkle_release.sh"
  --package
  "${PACKAGE_FORMAT}"
  --notary-profile
  "${NOTARY_PROFILE}"
  --download-url-prefix
  "${DOWNLOAD_URL_PREFIX}"
  --s3-uri
  "${S3_URI}"
  --release-notes
  "${RELEASE_NOTES_PATH}"
)

if [[ "${SKIP_PREFLIGHT}" == "yes" ]]; then
  driver_args+=(--skip-preflight)
fi
if [[ "${SKIP_NOTARIZATION}" == "yes" ]]; then
  driver_args+=(--skip-notarization)
fi
if [[ "${DRY_RUN}" == "yes" ]]; then
  driver_args+=(--dry-run)
fi
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  driver_args+=("${EXTRA_ARGS[@]}")
fi

exec "${driver_args[@]}"

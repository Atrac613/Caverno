#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="${CAVERNO_MACOS_PRODUCT_NAME:-Caverno}"
APP_PATH="${CAVERNO_MACOS_RELEASE_APP_PATH:-${ROOT_DIR}/build/macos/Build/Products/Release/${PRODUCT_NAME}.app}"
ARTIFACT_DIR="${CAVERNO_MACOS_SPARKLE_RELEASE_DIR:-${ROOT_DIR}/build/macos_sparkle_release}"
PACKAGE_FORMAT="${CAVERNO_MACOS_SPARKLE_PACKAGE_FORMAT:-zip}"
BUILD_NAME="${CAVERNO_MACOS_SPARKLE_BUILD_NAME:-}"
BUILD_NUMBER="${CAVERNO_MACOS_SPARKLE_BUILD_NUMBER:-}"
ARCHIVE_NAME="${CAVERNO_MACOS_SPARKLE_ARCHIVE_NAME:-}"
NOTARY_PROFILE="${CAVERNO_NOTARYTOOL_PROFILE:-}"
DOWNLOAD_URL_PREFIX="${CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
S3_URI="${CAVERNO_SPARKLE_S3_URI:-}"
RELEASE_NOTES_PATH="${CAVERNO_SPARKLE_RELEASE_NOTES_PATH:-}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_CHANNEL="${SPARKLE_CHANNEL:-}"
SPARKLE_MAXIMUM_DELTAS="${SPARKLE_MAXIMUM_DELTAS:-0}"
DRY_RUN="no"
SKIP_PREFLIGHT="no"
SKIP_BUILD="no"
SKIP_NOTARIZATION="no"
SKIP_ASSESS="no"
SKIP_PUBLISH="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/build_macos_sparkle_release.sh [options]

Options:
  --build-name VERSION             Override Flutter build name.
  --build-number NUMBER            Override Flutter build number.
  --archive-name NAME              Artifact base name without extension.
  --artifact-dir PATH              Output directory, default build/macos_sparkle_release.
  --app-path PATH                  Existing Caverno.app path for --skip-build flows.
  --package zip|dmg                Final artifact format, default zip.
  --notary-profile NAME            notarytool keychain profile.
  --download-url-prefix URL        HTTPS URL prefix passed to the publish helper.
  --s3-uri URI                     S3 destination passed to the publish helper.
  --release-notes PATH             Optional release notes passed to the publish helper.
  --sparkle-generate-appcast PATH  Sparkle generate_appcast path for publishing.
  --ed-key-file PATH               Sparkle EdDSA private key file for publishing.
  --channel NAME                   Optional Sparkle channel for publishing.
  --maximum-deltas COUNT           Sparkle delta count, default 0.
  --skip-preflight                 Skip local release signing and packaging checks.
  --skip-build                     Use --app-path instead of running Flutter release build.
  --skip-notarization              Package without notarytool or stapler.
  --skip-assess                    Skip Gatekeeper assessment after notarization.
  --skip-publish                   Do not call tool/publish_macos_sparkle_release.sh.
  --dry-run                        Print commands without executing them.
  --help                           Show this help.

The script builds a Developer ID signed macOS release app, notarizes and
staples it, packages it for Sparkle, then optionally publishes the artifact
through tool/publish_macos_sparkle_release.sh. It never stores credentials;
create the notarytool keychain profile yourself before running a real release.
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
    --build-name)
      require_value "$@"
      BUILD_NAME="$2"
      shift 2
      ;;
    --build-number)
      require_value "$@"
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --archive-name)
      require_value "$@"
      ARCHIVE_NAME="$2"
      shift 2
      ;;
    --artifact-dir)
      require_value "$@"
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --app-path)
      require_value "$@"
      APP_PATH="$2"
      shift 2
      ;;
    --package)
      require_value "$@"
      PACKAGE_FORMAT="$2"
      shift 2
      ;;
    --notary-profile)
      require_value "$@"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
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
    --sparkle-generate-appcast)
      require_value "$@"
      SPARKLE_GENERATE_APPCAST="$2"
      shift 2
      ;;
    --ed-key-file)
      require_value "$@"
      SPARKLE_ED_KEY_FILE="$2"
      shift 2
      ;;
    --channel)
      require_value "$@"
      SPARKLE_CHANNEL="$2"
      shift 2
      ;;
    --maximum-deltas)
      require_value "$@"
      SPARKLE_MAXIMUM_DELTAS="$2"
      shift 2
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT="yes"
      shift 1
      ;;
    --skip-build)
      SKIP_BUILD="yes"
      shift 1
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION="yes"
      shift 1
      ;;
    --skip-assess)
      SKIP_ASSESS="yes"
      shift 1
      ;;
    --skip-publish)
      SKIP_PUBLISH="yes"
      shift 1
      ;;
    --dry-run)
      DRY_RUN="yes"
      shift 1
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

case "${PACKAGE_FORMAT}" in
  zip|dmg)
    ;;
  *)
    echo "--package must be zip or dmg." >&2
    exit 64
    ;;
esac

if [[ "${SKIP_NOTARIZATION}" != "yes" && -z "${NOTARY_PROFILE}" ]]; then
  echo "Provide --notary-profile or set CAVERNO_NOTARYTOOL_PROFILE." >&2
  echo "Use --skip-notarization only for local packaging dry runs." >&2
  exit 64
fi

if [[ "${SKIP_PUBLISH}" != "yes" && -z "${DOWNLOAD_URL_PREFIX}" ]]; then
  echo "Provide --download-url-prefix or --skip-publish." >&2
  exit 64
fi

if [[ "${SKIP_PUBLISH}" != "yes" && -z "${S3_URI}" ]]; then
  echo "Provide --s3-uri or --skip-publish." >&2
  exit 64
fi

if [[ "${SKIP_PUBLISH}" != "yes" && "${DOWNLOAD_URL_PREFIX}" != https://* ]]; then
  echo "--download-url-prefix must use HTTPS." >&2
  exit 64
fi

if [[ "${DRY_RUN}" != "yes" && "${SKIP_BUILD}" == "yes" && ! -d "${APP_PATH}" ]]; then
  echo "App path not found: ${APP_PATH}" >&2
  exit 66
fi

if [[ "${DRY_RUN}" != "yes" && -n "${RELEASE_NOTES_PATH}" && ! -f "${RELEASE_NOTES_PATH}" ]]; then
  echo "Release notes not found: ${RELEASE_NOTES_PATH}" >&2
  exit 66
fi

if command -v fvm >/dev/null 2>&1 && { [[ -f "${ROOT_DIR}/.fvmrc" ]] || [[ -d "${ROOT_DIR}/.fvm" ]]; }; then
  FLUTTER_CMD=(fvm flutter)
else
  FLUTTER_CMD=(flutter)
fi

read_pubspec_version() {
  awk '/^version:[[:space:]]*/ { print $2; exit }' "${ROOT_DIR}/pubspec.yaml"
}

PUBSPEC_VERSION="$(read_pubspec_version)"
if [[ -z "${BUILD_NAME}" ]]; then
  BUILD_NAME="${PUBSPEC_VERSION%%+*}"
fi
if [[ -z "${BUILD_NUMBER}" ]]; then
  if [[ "${PUBSPEC_VERSION}" == *"+"* ]]; then
    BUILD_NUMBER="${PUBSPEC_VERSION##*+}"
  else
    BUILD_NUMBER="1"
  fi
fi
if [[ -z "${ARCHIVE_NAME}" ]]; then
  ARCHIVE_NAME="${PRODUCT_NAME}-${BUILD_NAME}-${BUILD_NUMBER}"
fi

ARTIFACT_PATH="${ARTIFACT_DIR}/${ARCHIVE_NAME}.${PACKAGE_FORMAT}"
NOTARY_ZIP_PATH="${ARTIFACT_DIR}/${ARCHIVE_NAME}-notary.zip"
DMG_STAGE_DIR="${ARTIFACT_DIR}/dmg-stage"

shell_join() {
  local first="yes"
  for arg in "$@"; do
    if [[ "${first}" == "yes" ]]; then
      first="no"
    else
      printf ' '
    fi
    printf '%q' "${arg}"
  done
}

run() {
  printf '+ '
  shell_join "$@"
  printf '\n'
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  "$@"
}

echo "Building macOS Sparkle release"
echo "  Product: ${PRODUCT_NAME}"
echo "  Build: ${BUILD_NAME}+${BUILD_NUMBER}"
echo "  App path: ${APP_PATH}"
echo "  Artifact: ${ARTIFACT_PATH}"
echo "  Package: ${PACKAGE_FORMAT}"
echo "  Notary profile: ${NOTARY_PROFILE:-<skipped>}"
echo "  Publish: $([[ "${SKIP_PUBLISH}" == "yes" ]] && echo skipped || echo enabled)"
echo "  Dry run: ${DRY_RUN}"

cd "${ROOT_DIR}"

if [[ "${SKIP_PREFLIGHT}" != "yes" ]]; then
  run bash "${ROOT_DIR}/tool/run_macos_computer_use_release_signing_preflight.sh"
  run bash "${ROOT_DIR}/tool/run_macos_computer_use_release_packaging.sh"
fi

if [[ "${SKIP_BUILD}" != "yes" ]]; then
  build_args=("${FLUTTER_CMD[@]}" build macos --release)
  if [[ -n "${BUILD_NAME}" ]]; then
    build_args+=(--build-name "${BUILD_NAME}")
  fi
  if [[ -n "${BUILD_NUMBER}" ]]; then
    build_args+=(--build-number "${BUILD_NUMBER}")
  fi
  run "${build_args[@]}"
fi

if [[ "${DRY_RUN}" != "yes" && ! -d "${APP_PATH}" ]]; then
  echo "Release app was not produced: ${APP_PATH}" >&2
  exit 66
fi

run /usr/bin/codesign --verify --deep --strict --verbose=4 "${APP_PATH}"

if [[ "${SKIP_NOTARIZATION}" != "yes" ]]; then
  run mkdir -p "${ARTIFACT_DIR}"
  run rm -f "${NOTARY_ZIP_PATH}"
  run /usr/bin/ditto -c -k --keepParent --sequesterRsrc --zlibCompressionLevel 9 \
    "${APP_PATH}" "${NOTARY_ZIP_PATH}"
  run xcrun notarytool submit "${NOTARY_ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait
  run xcrun stapler staple "${APP_PATH}"
  run xcrun stapler validate "${APP_PATH}"
  if [[ "${SKIP_ASSESS}" != "yes" ]]; then
    run /usr/sbin/spctl --assess --type execute --verbose "${APP_PATH}"
  fi
fi

run mkdir -p "${ARTIFACT_DIR}"

case "${PACKAGE_FORMAT}" in
  zip)
    run rm -f "${ARTIFACT_PATH}"
    run /usr/bin/ditto -c -k --keepParent --sequesterRsrc --zlibCompressionLevel 9 \
      "${APP_PATH}" "${ARTIFACT_PATH}"
    ;;
  dmg)
    run rm -rf "${DMG_STAGE_DIR}"
    run mkdir -p "${DMG_STAGE_DIR}"
    run /usr/bin/ditto "${APP_PATH}" "${DMG_STAGE_DIR}/${PRODUCT_NAME}.app"
    run rm -f "${ARTIFACT_PATH}"
    run hdiutil create -volname "${PRODUCT_NAME}" \
      -srcfolder "${DMG_STAGE_DIR}" \
      -ov \
      -format UDZO \
      "${ARTIFACT_PATH}"
    if [[ "${SKIP_NOTARIZATION}" != "yes" ]]; then
      run xcrun notarytool submit "${ARTIFACT_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
      run xcrun stapler staple "${ARTIFACT_PATH}"
      run xcrun stapler validate "${ARTIFACT_PATH}"
    fi
    ;;
esac

if [[ "${SKIP_PUBLISH}" != "yes" ]]; then
  publish_args=(
    bash
    "${ROOT_DIR}/tool/publish_macos_sparkle_release.sh"
    --artifact
    "${ARTIFACT_PATH}"
    --download-url-prefix
    "${DOWNLOAD_URL_PREFIX}"
    --s3-uri
    "${S3_URI}"
  )
  if [[ -n "${RELEASE_NOTES_PATH}" ]]; then
    publish_args+=(--release-notes "${RELEASE_NOTES_PATH}")
  fi
  if [[ -n "${SPARKLE_GENERATE_APPCAST}" ]]; then
    publish_args+=(--sparkle-generate-appcast "${SPARKLE_GENERATE_APPCAST}")
  fi
  if [[ -n "${SPARKLE_ED_KEY_FILE}" ]]; then
    publish_args+=(--ed-key-file "${SPARKLE_ED_KEY_FILE}")
  fi
  if [[ -n "${SPARKLE_CHANNEL}" ]]; then
    publish_args+=(--channel "${SPARKLE_CHANNEL}")
  fi
  publish_args+=(--maximum-deltas "${SPARKLE_MAXIMUM_DELTAS}")
  if [[ "${DRY_RUN}" == "yes" ]]; then
    publish_args+=(--dry-run)
  fi
  run "${publish_args[@]}"
fi

echo "macOS Sparkle release artifact ready: ${ARTIFACT_PATH}"

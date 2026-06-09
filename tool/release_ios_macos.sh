#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_NAME="${CAVERNO_RELEASE_BUILD_NAME:-}"
BUILD_NUMBER="${CAVERNO_RELEASE_BUILD_NUMBER:-}"
RUN_IOS="yes"
RUN_MACOS="yes"
DRY_RUN="no"
RUN_PUB_GET="yes"

IOS_SCHEME="${CAVERNO_IOS_SCHEME:-Runner}"
IOS_BUNDLE_ID="${CAVERNO_IOS_BUNDLE_ID:-com.noguwo.apps.caverno}"
IOS_TEAM_ID="${CAVERNO_IOS_TEAM_ID:-89UG59TBNX}"
IOS_EXPORT_DESTINATION="${CAVERNO_IOS_EXPORT_DESTINATION:-upload}"
IOS_EXPORT_ROOT="${CAVERNO_IOS_EXPORT_ROOT:-}"
IOS_SIGNING_STYLE="${CAVERNO_IOS_SIGNING_STYLE:-manual}"
IOS_PROVISIONING_PROFILE="${CAVERNO_IOS_PROVISIONING_PROFILE:-}"

MACOS_NOTARY_PROFILE="${CAVERNO_NOTARYTOOL_PROFILE:-caverno-notary}"
MACOS_PACKAGE="${CAVERNO_MACOS_SPARKLE_PACKAGE_FORMAT:-zip}"
MACOS_DOWNLOAD_URL_PREFIX="${CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX:-https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos}"
MACOS_S3_URI="${CAVERNO_SPARKLE_S3_URI:-s3://caverno-macos-releases/caverno/macos}"
MACOS_RELEASE_NOTES="${CAVERNO_SPARKLE_RELEASE_NOTES_PATH:-}"
RELEASE_LOG_DIR="${CAVERNO_RELEASE_LOG_DIR:-}"

usage() {
  cat <<'USAGE'
Usage: bash tool/release_ios_macos.sh [options]

Build and publish Caverno iOS and macOS releases with the current pubspec
version by default.

Options:
  --build-name VERSION          Override Flutter build name.
  --build-number NUMBER         Override Flutter build number.
  --only ios|macos              Run only one platform release lane.
  --skip-ios                    Skip the App Store Connect upload lane.
  --skip-macos                  Skip the macOS Sparkle S3 release lane.
  --ios-destination upload|export
                               ExportOptions destination, default upload.
  --ios-export-root PATH        iOS export working directory.
  --ios-team-id TEAMID          iOS App Store Connect team ID.
  --ios-bundle-id BUNDLE_ID     iOS bundle identifier.
  --ios-signing-style automatic|manual
                               ExportOptions signing style, default manual.
  --ios-provisioning-profile NAME
                               App Store provisioning profile name for manual signing.
  --macos-notary-profile NAME   notarytool keychain profile.
  --macos-package zip|dmg       macOS Sparkle artifact package.
  --macos-download-url-prefix URL
                               Sparkle public download URL prefix.
  --macos-s3-uri URI            Sparkle S3 destination.
  --macos-release-notes PATH    Release notes for Sparkle appcast.
  --release-log-dir PATH        Directory for per-lane release logs.
  --no-pub-get                  Skip flutter pub get.
  --dry-run                     Print commands without executing them.
  --help                        Show this help.

Examples:
  bash tool/release_ios_macos.sh --dry-run
  bash tool/release_ios_macos.sh --only ios
  bash tool/release_ios_macos.sh --only macos --macos-release-notes docs/releases/caverno-1.3.3.md
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
    --only)
      require_value "$@"
      case "$2" in
        ios)
          RUN_IOS="yes"
          RUN_MACOS="no"
          ;;
        macos)
          RUN_IOS="no"
          RUN_MACOS="yes"
          ;;
        *)
          echo "--only must be ios or macos." >&2
          exit 64
          ;;
      esac
      shift 2
      ;;
    --skip-ios)
      RUN_IOS="no"
      shift 1
      ;;
    --skip-macos)
      RUN_MACOS="no"
      shift 1
      ;;
    --ios-destination)
      require_value "$@"
      IOS_EXPORT_DESTINATION="$2"
      shift 2
      ;;
    --ios-export-root)
      require_value "$@"
      IOS_EXPORT_ROOT="$2"
      shift 2
      ;;
    --ios-team-id)
      require_value "$@"
      IOS_TEAM_ID="$2"
      shift 2
      ;;
    --ios-bundle-id)
      require_value "$@"
      IOS_BUNDLE_ID="$2"
      shift 2
      ;;
    --ios-signing-style)
      require_value "$@"
      IOS_SIGNING_STYLE="$2"
      shift 2
      ;;
    --ios-provisioning-profile)
      require_value "$@"
      IOS_PROVISIONING_PROFILE="$2"
      shift 2
      ;;
    --macos-notary-profile)
      require_value "$@"
      MACOS_NOTARY_PROFILE="$2"
      shift 2
      ;;
    --macos-package)
      require_value "$@"
      MACOS_PACKAGE="$2"
      shift 2
      ;;
    --macos-download-url-prefix)
      require_value "$@"
      MACOS_DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --macos-s3-uri)
      require_value "$@"
      MACOS_S3_URI="$2"
      shift 2
      ;;
    --macos-release-notes)
      require_value "$@"
      MACOS_RELEASE_NOTES="$2"
      shift 2
      ;;
    --release-log-dir)
      require_value "$@"
      RELEASE_LOG_DIR="$2"
      shift 2
      ;;
    --no-pub-get)
      RUN_PUB_GET="no"
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

case "${IOS_EXPORT_DESTINATION}" in
  upload|export)
    ;;
  *)
    echo "--ios-destination must be upload or export." >&2
    exit 64
    ;;
esac

case "${IOS_SIGNING_STYLE}" in
  automatic|manual)
    ;;
  *)
    echo "--ios-signing-style must be automatic or manual." >&2
    exit 64
    ;;
esac

case "${MACOS_PACKAGE}" in
  zip|dmg)
    ;;
  *)
    echo "--macos-package must be zip or dmg." >&2
    exit 64
    ;;
esac

if [[ "${RUN_IOS}" == "no" && "${RUN_MACOS}" == "no" ]]; then
  echo "Nothing to release. Enable at least one platform." >&2
  exit 64
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
if [[ -z "${PUBSPEC_VERSION}" ]]; then
  echo "Could not read version from pubspec.yaml." >&2
  exit 66
fi

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

if [[ -z "${IOS_EXPORT_ROOT}" ]]; then
  IOS_EXPORT_ROOT="/private/tmp/caverno-ios-appstore-${BUILD_NAME}-${BUILD_NUMBER}"
fi

if [[ -z "${RELEASE_LOG_DIR}" ]]; then
  RELEASE_LOG_DIR="${ROOT_DIR}/build/release_logs"
fi

if [[ -z "${MACOS_RELEASE_NOTES}" ]]; then
  DEFAULT_RELEASE_NOTES="${ROOT_DIR}/docs/releases/caverno-${BUILD_NAME}.md"
  if [[ -f "${DEFAULT_RELEASE_NOTES}" ]]; then
    MACOS_RELEASE_NOTES="${DEFAULT_RELEASE_NOTES}"
  fi
fi

if [[ "${DRY_RUN}" != "yes" && "${RUN_MACOS}" == "yes" && -n "${MACOS_RELEASE_NOTES}" && ! -f "${MACOS_RELEASE_NOTES}" ]]; then
  echo "macOS release notes not found: ${MACOS_RELEASE_NOTES}" >&2
  exit 66
fi

if [[ "${DRY_RUN}" != "yes" && "${RUN_IOS}" == "yes" ]]; then
  mkdir -p "${IOS_EXPORT_ROOT}"
  if [[ "${IOS_SIGNING_STYLE}" == "manual" && -z "${IOS_PROVISIONING_PROFILE}" ]]; then
    echo "Manual iOS export requires --ios-provisioning-profile or CAVERNO_IOS_PROVISIONING_PROFILE." >&2
    echo "Use the App Store provisioning profile for ${IOS_BUNDLE_ID}, not the development profile." >&2
    exit 66
  fi
fi

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

write_ios_export_options() {
  local output_path="$1"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    printf '+ write %q\n' "${output_path}"
    return 0
  fi
  cat >"${output_path}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>${IOS_EXPORT_DESTINATION}</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>${IOS_SIGNING_STYLE}</string>
$(if [[ "${IOS_SIGNING_STYLE}" == "manual" ]]; then cat <<PROFILE_PLIST
  <key>provisioningProfiles</key>
  <dict>
    <key>${IOS_BUNDLE_ID}</key>
    <string>${IOS_PROVISIONING_PROFILE}</string>
  </dict>
PROFILE_PLIST
fi)
  <key>teamID</key>
  <string>${IOS_TEAM_ID}</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST
}

run_pub_get() {
  if [[ "${RUN_PUB_GET}" == "yes" ]]; then
    run "${FLUTTER_CMD[@]}" pub get
  fi
}

IOS_RELEASE_LOG=""
MACOS_RELEASE_LOG=""
IOS_STATUS="skipped"
MACOS_STATUS="skipped"

run_release_lane() {
  local lane="$1"
  local failure_pattern="$2"
  shift 2

  if [[ "${DRY_RUN}" == "yes" ]]; then
    "$@"
    return 0
  fi

  mkdir -p "${RELEASE_LOG_DIR}"
  local log_path="${RELEASE_LOG_DIR}/${lane}-${BUILD_NAME}-${BUILD_NUMBER}-$(date +%Y%m%d%H%M%S).log"
  case "${lane}" in
    ios)
      IOS_RELEASE_LOG="${log_path}"
      ;;
    macos)
      MACOS_RELEASE_LOG="${log_path}"
      ;;
  esac

  echo "Release lane log (${lane}): ${log_path}"
  set +e
  "$@" 2>&1 | tee "${log_path}"
  local command_status="${PIPESTATUS[0]}"
  set -e

  if [[ -n "${failure_pattern}" ]] && grep -Eiq "${failure_pattern}" "${log_path}"; then
    echo "Detected ${lane} release failure marker in ${log_path}." >&2
    return 1
  fi
  return "${command_status}"
}

print_release_summary() {
  local overall="succeeded"
  if [[ "${IOS_STATUS}" == "failed" || "${MACOS_STATUS}" == "failed" ]]; then
    overall="partial_failure"
  fi

  echo "Release workflow summary:"
  echo "  iOS: ${IOS_STATUS}"
  if [[ -n "${IOS_RELEASE_LOG}" ]]; then
    echo "  iOS log: ${IOS_RELEASE_LOG}"
  fi
  echo "  macOS: ${MACOS_STATUS}"
  if [[ -n "${MACOS_RELEASE_LOG}" ]]; then
    echo "  macOS log: ${MACOS_RELEASE_LOG}"
  fi
  echo "  overall: ${overall}"

  if [[ "${overall}" == "partial_failure" ]]; then
    echo "Release workflow completed with one or more failed lanes." >&2
    return 1
  fi
  echo "Release workflow completed successfully."
  return 0
}

release_ios() {
  local export_options="${IOS_EXPORT_ROOT}/ExportOptions.plist"

  echo "Preparing iOS App Store Connect release"
  echo "  Scheme: ${IOS_SCHEME}"
  echo "  Bundle ID: ${IOS_BUNDLE_ID}"
  echo "  Build: ${BUILD_NAME}+${BUILD_NUMBER}"
  echo "  Destination: ${IOS_EXPORT_DESTINATION}"
  echo "  Export root: ${IOS_EXPORT_ROOT}"
  echo "  Signing style: ${IOS_SIGNING_STYLE}"
  if [[ "${IOS_SIGNING_STYLE}" == "manual" ]]; then
    echo "  Provisioning profile: ${IOS_PROVISIONING_PROFILE:-<required for real run>}"
  fi

  write_ios_export_options "${export_options}"
  run "${FLUTTER_CMD[@]}" build ipa \
    --release \
    --build-name "${BUILD_NAME}" \
    --build-number "${BUILD_NUMBER}" \
    --export-options-plist "${export_options}" \
    --no-pub
}

release_macos() {
  local args=(
    "${ROOT_DIR}/tool/build_macos_sparkle_release.sh"
    --build-name "${BUILD_NAME}"
    --build-number "${BUILD_NUMBER}"
    --notary-profile "${MACOS_NOTARY_PROFILE}"
    --package "${MACOS_PACKAGE}"
    --download-url-prefix "${MACOS_DOWNLOAD_URL_PREFIX}"
    --s3-uri "${MACOS_S3_URI}"
  )

  if [[ -n "${MACOS_RELEASE_NOTES}" ]]; then
    args+=(--release-notes "${MACOS_RELEASE_NOTES}")
  fi
  if [[ "${DRY_RUN}" == "yes" ]]; then
    args+=(--dry-run)
  fi

  echo "Preparing macOS Sparkle S3 release"
  echo "  Build: ${BUILD_NAME}+${BUILD_NUMBER}"
  echo "  Package: ${MACOS_PACKAGE}"
  echo "  Notary profile: ${MACOS_NOTARY_PROFILE}"
  echo "  Download URL prefix: ${MACOS_DOWNLOAD_URL_PREFIX}"
  echo "  S3 URI: ${MACOS_S3_URI}"
  if [[ -n "${MACOS_RELEASE_NOTES}" ]]; then
    echo "  Release notes: ${MACOS_RELEASE_NOTES}"
  else
    echo "  Release notes: none"
  fi

  run bash "${args[@]}"
}

echo "Caverno release"
echo "  Version: ${BUILD_NAME}+${BUILD_NUMBER}"
echo "  iOS: ${RUN_IOS}"
echo "  macOS: ${RUN_MACOS}"
echo "  Dry run: ${DRY_RUN}"

run_pub_get

if [[ "${RUN_IOS}" == "yes" ]]; then
  IOS_STATUS="succeeded"
  if ! run_release_lane \
    ios \
    'Encountered error while creating the IPA|error: exportArchive|The bundle version must be higher|Upload failed|App Store Connect.*(error|failed)|ITMS-[0-9]+|ipatool failed' \
    release_ios; then
    IOS_STATUS="failed"
  fi
fi

if [[ "${RUN_MACOS}" == "yes" ]]; then
  MACOS_STATUS="succeeded"
  if ! run_release_lane macos '' release_macos; then
    MACOS_STATUS="failed"
  fi
fi

print_release_summary

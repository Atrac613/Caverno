#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_PATH=""
RELEASE_NOTES_PATH=""
UPDATES_DIR="${CAVERNO_SPARKLE_UPDATES_DIR:-${ROOT_DIR}/build/macos_sparkle_updates}"
DOWNLOAD_URL_PREFIX="${CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
S3_URI="${CAVERNO_SPARKLE_S3_URI:-}"
APPCAST_FILENAME="${CAVERNO_SPARKLE_APPCAST_FILENAME:-appcast.xml}"
PUBLIC_VERIFY_SCRIPT="${CAVERNO_SPARKLE_PUBLIC_VERIFY_SCRIPT:-${ROOT_DIR}/tool/verify_macos_sparkle_public_release.sh}"
EXPECTED_VERSION="${CAVERNO_SPARKLE_EXPECTED_VERSION:-}"
EXPECTED_BUILD="${CAVERNO_SPARKLE_EXPECTED_BUILD:-}"
SPARKLE_GENERATE_APPCAST="${SPARKLE_GENERATE_APPCAST:-}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
SPARKLE_CHANNEL="${SPARKLE_CHANNEL:-}"
SPARKLE_MAXIMUM_DELTAS="${SPARKLE_MAXIMUM_DELTAS:-0}"
AWS_BIN="${AWS_BIN:-aws}"
DRY_RUN="no"
SKIP_UPLOAD="no"
SKIP_PUBLIC_VERIFY="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/publish_macos_sparkle_release.sh [options]

Options:
  --artifact PATH                 Notarized and stapled .dmg, .zip, or .tar.xz.
  --release-notes PATH            Optional .md or .html notes copied next to the artifact.
  --updates-dir PATH              Local Sparkle updates directory.
  --download-url-prefix URL       HTTPS URL prefix for generated appcast enclosure URLs.
  --s3-uri URI                    Optional destination such as s3://bucket/caverno/macos.
  --appcast-filename NAME         Appcast file name, default appcast.xml.
  --public-verify-script PATH     Public release verifier script path.
  --expected-version VERSION      Optional expected sparkle:shortVersionString.
  --expected-build BUILD          Optional expected sparkle:version.
  --sparkle-generate-appcast PATH Sparkle generate_appcast tool path.
  --ed-key-file PATH              Optional Sparkle EdDSA private key file.
  --channel NAME                  Optional Sparkle channel.
  --maximum-deltas COUNT          Delta update count passed to generate_appcast, default 0.
  --skip-upload                   Generate appcast locally without uploading to S3.
  --skip-public-verify            Do not verify public appcast after S3 upload.
  --dry-run                       Print commands without copying, generating, or uploading.
  --help                          Show this help.

The script expects the app artifact to already be Developer ID signed,
notarized, and stapled. It stages the artifact, runs Sparkle generate_appcast,
uploads the updates directory to S3 when --s3-uri is provided, then verifies the
public appcast unless verification is skipped.
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
    --artifact)
      require_value "$@"
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --release-notes)
      require_value "$@"
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --updates-dir)
      require_value "$@"
      UPDATES_DIR="$2"
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
    --appcast-filename)
      require_value "$@"
      APPCAST_FILENAME="$2"
      shift 2
      ;;
    --public-verify-script)
      require_value "$@"
      PUBLIC_VERIFY_SCRIPT="$2"
      shift 2
      ;;
    --expected-version)
      require_value "$@"
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --expected-build)
      require_value "$@"
      EXPECTED_BUILD="$2"
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
    --skip-upload)
      SKIP_UPLOAD="yes"
      shift 1
      ;;
    --skip-public-verify)
      SKIP_PUBLIC_VERIFY="yes"
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

if [[ -z "${ARTIFACT_PATH}" ]]; then
  echo "--artifact is required." >&2
  usage
  exit 64
fi

if [[ -z "${DOWNLOAD_URL_PREFIX}" ]]; then
  echo "--download-url-prefix is required." >&2
  usage
  exit 64
fi

if [[ "${DOWNLOAD_URL_PREFIX}" != https://* ]]; then
  echo "--download-url-prefix must use HTTPS." >&2
  exit 64
fi

if [[ "${SKIP_UPLOAD}" != "yes" && -z "${S3_URI}" ]]; then
  echo "Provide --s3-uri or --skip-upload." >&2
  usage
  exit 64
fi

if [[ "${DRY_RUN}" != "yes" && ! -f "${ARTIFACT_PATH}" ]]; then
  echo "Artifact not found: ${ARTIFACT_PATH}" >&2
  exit 66
fi

if [[ "${DRY_RUN}" != "yes" && -n "${RELEASE_NOTES_PATH}" && ! -f "${RELEASE_NOTES_PATH}" ]]; then
  echo "Release notes not found: ${RELEASE_NOTES_PATH}" >&2
  exit 66
fi

if [[ "${DRY_RUN}" != "yes" && "${SKIP_UPLOAD}" != "yes" && "${SKIP_PUBLIC_VERIFY}" != "yes" && ! -f "${PUBLIC_VERIFY_SCRIPT}" ]]; then
  echo "Public verifier not found: ${PUBLIC_VERIFY_SCRIPT}" >&2
  exit 66
fi

ARTIFACT_NAME="$(basename "${ARTIFACT_PATH}")"

validate_release_metadata() {
  if [[ -n "${EXPECTED_VERSION}" && -n "${EXPECTED_BUILD}" ]]; then
    local expected_token="${EXPECTED_VERSION}-${EXPECTED_BUILD}"
    if [[ "${ARTIFACT_NAME}" != *"${expected_token}"* ]]; then
      echo "Artifact name does not match the expected release metadata." >&2
      echo "  Expected token: ${expected_token}" >&2
      echo "  Artifact:       ${ARTIFACT_NAME}" >&2
      exit 65
    fi
  fi

  if [[ -n "${RELEASE_NOTES_PATH}" ]]; then
    case "${RELEASE_NOTES_PATH}" in
      *.md|*.html|*.htm)
        ;;
      *)
        echo "Release notes must be Markdown or HTML: ${RELEASE_NOTES_PATH}" >&2
        exit 64
        ;;
    esac
  fi
}

find_generate_appcast() {
  if [[ -n "${SPARKLE_GENERATE_APPCAST}" ]]; then
    echo "${SPARKLE_GENERATE_APPCAST}"
    return 0
  fi

  local candidates=(
    "${ROOT_DIR}/macos/Pods/Sparkle/bin/generate_appcast"
    "${ROOT_DIR}/macos/Pods/Sparkle/generate_appcast"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  if command -v generate_appcast >/dev/null 2>&1; then
    command -v generate_appcast
    return 0
  fi

  return 1
}

GENERATE_APPCAST_BIN=""
if ! GENERATE_APPCAST_BIN="$(find_generate_appcast)"; then
  if [[ "${DRY_RUN}" == "yes" ]]; then
    GENERATE_APPCAST_BIN="${SPARKLE_GENERATE_APPCAST:-generate_appcast}"
  else
    echo "Sparkle generate_appcast was not found." >&2
    echo "Set SPARKLE_GENERATE_APPCAST or run pod install after adding Sparkle." >&2
    exit 69
  fi
fi

validate_release_metadata

run() {
  echo "+ $*"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  "$@"
}

run_generate_appcast() {
  echo "+ $*"
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi

  local log_file
  log_file="$(mktemp "${TMPDIR:-/tmp}/caverno-generate-appcast.XXXXXX")"
  if ! "$@" 2>&1 | tee "${log_file}"; then
    rm -f "${log_file}"
    exit 1
  fi
  if grep -E 'SUPublicEDKey.*does not match|lack of private EdDSA key|Private key.*not found' "${log_file}" >/dev/null; then
    echo "Sparkle appcast generation reported signing key problems." >&2
    echo "Verify SUPublicEDKey in the app and the private EdDSA key in the Keychain." >&2
    rm -f "${log_file}"
    exit 65
  fi
  rm -f "${log_file}"
}

STAGED_ARTIFACT="${UPDATES_DIR}/${ARTIFACT_NAME}"
APPCAST_PATH="${UPDATES_DIR}/${APPCAST_FILENAME}"
APPCAST_URL="${DOWNLOAD_URL_PREFIX%/}/${APPCAST_FILENAME}"
ARTIFACT_URL="${DOWNLOAD_URL_PREFIX%/}/${ARTIFACT_NAME}"

echo "Publishing macOS Sparkle release"
echo "  Artifact: ${ARTIFACT_PATH}"
echo "  Updates directory: ${UPDATES_DIR}"
echo "  Download URL prefix: ${DOWNLOAD_URL_PREFIX}"
echo "  Appcast: ${APPCAST_PATH}"
echo "  Public verification: $([[ "${SKIP_PUBLIC_VERIFY}" == "yes" ]] && echo skipped || echo enabled)"
echo "  S3 URI: ${S3_URI:-<skipped>}"
echo "  Dry run: ${DRY_RUN}"

run mkdir -p "${UPDATES_DIR}"
run cp "${ARTIFACT_PATH}" "${STAGED_ARTIFACT}"

if [[ -n "${RELEASE_NOTES_PATH}" ]]; then
  RELEASE_NOTES_EXT="${RELEASE_NOTES_PATH##*.}"
  RELEASE_NOTES_TARGET="${STAGED_ARTIFACT%.*}.${RELEASE_NOTES_EXT}"
  run cp "${RELEASE_NOTES_PATH}" "${RELEASE_NOTES_TARGET}"
fi

generate_args=("${GENERATE_APPCAST_BIN}")
if [[ -n "${SPARKLE_ED_KEY_FILE}" ]]; then
  generate_args+=("--ed-key-file" "${SPARKLE_ED_KEY_FILE}")
fi
generate_args+=(
  "--download-url-prefix"
  "${DOWNLOAD_URL_PREFIX%/}/"
  "--maximum-deltas"
  "${SPARKLE_MAXIMUM_DELTAS}"
)
if [[ -n "${SPARKLE_CHANNEL}" ]]; then
  generate_args+=("--channel" "${SPARKLE_CHANNEL}")
fi
generate_args+=("${UPDATES_DIR}")

run_generate_appcast "${generate_args[@]}"

if [[ "${SKIP_UPLOAD}" == "yes" ]]; then
  echo "S3 upload skipped."
  exit 0
fi

if [[ "${DRY_RUN}" != "yes" ]] && ! command -v "${AWS_BIN}" >/dev/null 2>&1; then
  echo "AWS CLI not found: ${AWS_BIN}" >&2
  exit 69
fi

run "${AWS_BIN}" s3 sync "${UPDATES_DIR}" "${S3_URI}" \
  --exclude "old_updates/*" \
  --cache-control "max-age=300,public"
run "${AWS_BIN}" s3 cp "${APPCAST_PATH}" "${S3_URI%/}/${APPCAST_FILENAME}" \
  --content-type "application/xml" \
  --cache-control "no-cache,max-age=0"

if [[ "${SKIP_PUBLIC_VERIFY}" != "yes" ]]; then
  artifact_length="1"
  if [[ "${DRY_RUN}" != "yes" ]]; then
    artifact_length="$(wc -c <"${ARTIFACT_PATH}" | tr -d '[:space:]')"
  fi
  verify_args=(
    bash
    "${PUBLIC_VERIFY_SCRIPT}"
    --appcast-url
    "${APPCAST_URL}"
    --expected-artifact-url
    "${ARTIFACT_URL}"
    --expected-min-length
    "${artifact_length}"
  )
  if [[ -n "${EXPECTED_VERSION}" ]]; then
    verify_args+=(--expected-version "${EXPECTED_VERSION}")
  fi
  if [[ -n "${EXPECTED_BUILD}" ]]; then
    verify_args+=(--expected-build "${EXPECTED_BUILD}")
  fi
  if [[ "${DRY_RUN}" == "yes" ]]; then
    verify_args+=(--dry-run)
  fi
  run "${verify_args[@]}"
fi

echo "Sparkle release published."

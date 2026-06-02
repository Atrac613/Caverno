#!/usr/bin/env bash

set -euo pipefail

DEFAULT_APPCAST_URL="https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/appcast.xml"

APPCAST_URL="${CAVERNO_SPARKLE_APPCAST_URL:-${DEFAULT_APPCAST_URL}}"
EXPECTED_ARTIFACT_URL="${CAVERNO_SPARKLE_EXPECTED_ARTIFACT_URL:-}"
EXPECTED_VERSION="${CAVERNO_SPARKLE_EXPECTED_VERSION:-}"
EXPECTED_BUILD="${CAVERNO_SPARKLE_EXPECTED_BUILD:-}"
EXPECTED_MIN_LENGTH="${CAVERNO_SPARKLE_EXPECTED_MIN_LENGTH:-1}"
CURL_BIN="${CURL_BIN:-curl}"
DRY_RUN="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/verify_macos_sparkle_public_release.sh [options]

Options:
  --appcast-url URL             Public HTTPS appcast URL.
  --expected-artifact-url URL   Optional expected appcast enclosure URL.
  --expected-version VERSION    Optional expected sparkle:shortVersionString.
  --expected-build BUILD        Optional expected sparkle:version.
  --expected-min-length BYTES   Minimum artifact Content-Length, default 1.
  --curl-bin PATH               curl executable, default curl.
  --dry-run                     Print verification commands without network I/O.
  --help                        Show this help.

This verifier checks the public Sparkle appcast after an S3 publish. It fetches
the appcast, verifies required Sparkle signature and release-note fields, then
checks public HTTP headers for the appcast, enclosure artifact, and release
notes.
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
    --appcast-url)
      require_value "$@"
      APPCAST_URL="$2"
      shift 2
      ;;
    --expected-artifact-url)
      require_value "$@"
      EXPECTED_ARTIFACT_URL="$2"
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
    --expected-min-length)
      require_value "$@"
      EXPECTED_MIN_LENGTH="$2"
      shift 2
      ;;
    --curl-bin)
      require_value "$@"
      CURL_BIN="$2"
      shift 2
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

if [[ "${APPCAST_URL}" != https://* ]]; then
  echo "--appcast-url must use HTTPS." >&2
  exit 64
fi

if [[ -n "${EXPECTED_ARTIFACT_URL}" && "${EXPECTED_ARTIFACT_URL}" != https://* ]]; then
  echo "--expected-artifact-url must use HTTPS." >&2
  exit 64
fi

if ! [[ "${EXPECTED_MIN_LENGTH}" =~ ^[0-9]+$ ]]; then
  echo "--expected-min-length must be a non-negative integer." >&2
  exit 64
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

run_head() {
  local url="$1"
  local output_path="$2"
  printf '+ '
  shell_join "${CURL_BIN}" -fsSI "${url}"
  printf '\n'
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  "${CURL_BIN}" -fsSI "${url}" >"${output_path}"
}

run_fetch() {
  local url="$1"
  local output_path="$2"
  printf '+ '
  shell_join "${CURL_BIN}" -fsSL "${url}" -o "${output_path}"
  printf '\n'
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  "${CURL_BIN}" -fsSL "${url}" -o "${output_path}"
}

header_value() {
  local header_name
  local header_file
  header_name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  header_file="$2"
  awk -F': ' -v key="${header_name}" '
    {
      name = tolower($1)
      if (name == key) {
        value = $0
        sub(/^[^:]*: /, "", value)
        sub(/\r$/, "", value)
        print value
        exit
      }
    }
  ' "${header_file}"
}

require_header_contains() {
  local header_file="$1"
  local header_name="$2"
  local expected="$3"
  local actual
  actual="$(header_value "${header_name}" "${header_file}")"
  if [[ -z "${actual}" || "${actual}" != *"${expected}"* ]]; then
    echo "${header_name} must contain ${expected}; actual: ${actual:-<missing>}." >&2
    exit 65
  fi
}

require_content_type_xml() {
  local header_file="$1"
  local content_type
  content_type="$(header_value "Content-Type" "${header_file}")"
  if [[ "${content_type}" != *"application/xml"* && "${content_type}" != *"application/rss+xml"* ]]; then
    echo "Content-Type must be application/xml or application/rss+xml; actual: ${content_type:-<missing>}." >&2
    exit 65
  fi
}

extract_xml_value() {
  local pattern="$1"
  local file="$2"
  sed -nE "${pattern}" "${file}" | head -n 1
}

if [[ "${DRY_RUN}" != "yes" ]] && ! command -v "${CURL_BIN}" >/dev/null 2>&1; then
  echo "curl not found: ${CURL_BIN}" >&2
  exit 69
fi

echo "Verifying macOS Sparkle public release"
echo "  Appcast URL: ${APPCAST_URL}"
echo "  Expected artifact URL: ${EXPECTED_ARTIFACT_URL:-<not checked>}"
echo "  Expected version: ${EXPECTED_VERSION:-<not checked>}"
echo "  Expected build: ${EXPECTED_BUILD:-<not checked>}"
echo "  Expected minimum artifact bytes: ${EXPECTED_MIN_LENGTH}"
echo "  Dry run: ${DRY_RUN}"

if [[ "${DRY_RUN}" == "yes" ]]; then
  run_head "${APPCAST_URL}" "/tmp/caverno-sparkle-appcast.headers"
  run_fetch "${APPCAST_URL}" "/tmp/caverno-sparkle-appcast.xml"
  echo "Sparkle public release verification dry run completed."
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/caverno-sparkle-public-release.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

APPCAST_HEADERS="${TMP_DIR}/appcast.headers"
APPCAST_BODY="${TMP_DIR}/appcast.xml"
ARTIFACT_HEADERS="${TMP_DIR}/artifact.headers"
RELEASE_NOTES_HEADERS="${TMP_DIR}/release-notes.headers"

run_head "${APPCAST_URL}" "${APPCAST_HEADERS}"
run_fetch "${APPCAST_URL}" "${APPCAST_BODY}"

require_content_type_xml "${APPCAST_HEADERS}"
require_header_contains "${APPCAST_HEADERS}" "Cache-Control" "no-cache,max-age=0"

if ! grep -q 'sparkle:edSignature="' "${APPCAST_BODY}"; then
  echo "Appcast is missing sparkle:edSignature." >&2
  exit 65
fi

ARTIFACT_URL="$(
  extract_xml_value 's/.*<enclosure[^>]* url="([^"]+)".*/\1/p' "${APPCAST_BODY}"
)"
RELEASE_NOTES_URL="$(
  extract_xml_value 's/.*<sparkle:releaseNotesLink>([^<]+)<\/sparkle:releaseNotesLink>.*/\1/p' "${APPCAST_BODY}"
)"
VERSION="$(
  extract_xml_value 's/.*<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>.*/\1/p' "${APPCAST_BODY}"
)"
BUILD="$(
  extract_xml_value 's/.*<sparkle:version>([^<]+)<\/sparkle:version>.*/\1/p' "${APPCAST_BODY}"
)"

if [[ -z "${ARTIFACT_URL}" ]]; then
  echo "Appcast is missing an enclosure URL." >&2
  exit 65
fi

if [[ -z "${RELEASE_NOTES_URL}" ]]; then
  echo "Appcast is missing sparkle:releaseNotesLink." >&2
  exit 65
fi

if [[ "${ARTIFACT_URL}" != https://* ]]; then
  echo "Artifact URL must use HTTPS: ${ARTIFACT_URL}" >&2
  exit 65
fi

if [[ "${RELEASE_NOTES_URL}" != https://* ]]; then
  echo "Release notes URL must use HTTPS: ${RELEASE_NOTES_URL}" >&2
  exit 65
fi

if [[ -n "${EXPECTED_ARTIFACT_URL}" && "${ARTIFACT_URL}" != "${EXPECTED_ARTIFACT_URL}" ]]; then
  echo "Artifact URL mismatch." >&2
  echo "  Expected: ${EXPECTED_ARTIFACT_URL}" >&2
  echo "  Actual:   ${ARTIFACT_URL}" >&2
  exit 65
fi

if [[ -n "${EXPECTED_VERSION}" && "${VERSION}" != "${EXPECTED_VERSION}" ]]; then
  echo "Version mismatch. Expected ${EXPECTED_VERSION}; actual ${VERSION:-<missing>}." >&2
  exit 65
fi

if [[ -n "${EXPECTED_BUILD}" && "${BUILD}" != "${EXPECTED_BUILD}" ]]; then
  echo "Build mismatch. Expected ${EXPECTED_BUILD}; actual ${BUILD:-<missing>}." >&2
  exit 65
fi

run_head "${ARTIFACT_URL}" "${ARTIFACT_HEADERS}"
run_head "${RELEASE_NOTES_URL}" "${RELEASE_NOTES_HEADERS}"

require_header_contains "${ARTIFACT_HEADERS}" "Cache-Control" "max-age=300,public"

ARTIFACT_LENGTH="$(header_value "Content-Length" "${ARTIFACT_HEADERS}")"
if ! [[ "${ARTIFACT_LENGTH}" =~ ^[0-9]+$ ]]; then
  echo "Artifact Content-Length must be present; actual: ${ARTIFACT_LENGTH:-<missing>}." >&2
  exit 65
fi

if (( ARTIFACT_LENGTH < EXPECTED_MIN_LENGTH )); then
  echo "Artifact Content-Length is below the expected minimum." >&2
  echo "  Expected minimum: ${EXPECTED_MIN_LENGTH}" >&2
  echo "  Actual:           ${ARTIFACT_LENGTH}" >&2
  exit 65
fi

echo "Sparkle public release verified."
echo "  Appcast: ${APPCAST_URL}"
echo "  Version: ${VERSION:-<missing>}"
echo "  Build: ${BUILD:-<missing>}"
echo "  Artifact: ${ARTIFACT_URL}"
echo "  Artifact bytes: ${ARTIFACT_LENGTH}"
echo "  Release notes: ${RELEASE_NOTES_URL}"

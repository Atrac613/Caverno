#!/usr/bin/env bash

set -euo pipefail

DEFAULT_DOWNLOAD_URL_PREFIX="https://caverno-macos-releases.s3.amazonaws.com/caverno/macos"
DEFAULT_S3_URI="s3://caverno-macos-releases/caverno/macos"

DOWNLOAD_URL_PREFIX="${CAVERNO_SPARKLE_DOWNLOAD_URL_PREFIX:-${DEFAULT_DOWNLOAD_URL_PREFIX}}"
S3_URI="${CAVERNO_SPARKLE_S3_URI:-${DEFAULT_S3_URI}}"
AWS_BIN="${AWS_BIN:-aws}"
APPCAST_FILENAME="${CAVERNO_SPARKLE_APPCAST_FILENAME:-appcast.xml}"
CHECK_STS="yes"
CHECK_BUCKET_POLICY="yes"
DRY_RUN="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_sparkle_s3_preflight.sh [options]

Options:
  --download-url-prefix URL  HTTPS URL prefix used in generated appcasts.
  --s3-uri URI               S3 destination such as s3://bucket/caverno/macos.
  --appcast-filename NAME    Appcast file name, default appcast.xml.
  --aws-bin PATH             AWS CLI executable, default aws.
  --skip-sts                 Skip aws sts get-caller-identity.
  --skip-bucket-policy       Skip optional bucket public-access policy probes.
  --dry-run                  Print commands without executing AWS CLI calls.
  --help                     Show this help.

This preflight validates the production Sparkle S3 coordinates before a real
publish. It checks AWS CLI availability, credentials, bucket reachability, and
the dry-run shape of the S3 copy used for appcast publishing. It does not upload
or delete objects.
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
    --appcast-filename)
      require_value "$@"
      APPCAST_FILENAME="$2"
      shift 2
      ;;
    --aws-bin)
      require_value "$@"
      AWS_BIN="$2"
      shift 2
      ;;
    --skip-sts)
      CHECK_STS="no"
      shift 1
      ;;
    --skip-bucket-policy)
      CHECK_BUCKET_POLICY="no"
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

if [[ "${DOWNLOAD_URL_PREFIX}" != https://* ]]; then
  echo "--download-url-prefix must use HTTPS." >&2
  exit 64
fi

if [[ "${S3_URI}" != s3://* ]]; then
  echo "--s3-uri must start with s3://." >&2
  exit 64
fi

S3_WITHOUT_SCHEME="${S3_URI#s3://}"
S3_BUCKET="${S3_WITHOUT_SCHEME%%/*}"
if [[ -z "${S3_BUCKET}" || "${S3_BUCKET}" == "${S3_WITHOUT_SCHEME}" ]]; then
  S3_PREFIX=""
else
  S3_PREFIX="${S3_WITHOUT_SCHEME#*/}"
fi
S3_URI_NORMALIZED="${S3_URI%/}"
PROBE_KEY="${S3_URI_NORMALIZED}/.sparkle-preflight-write-probe.txt"
APPCAST_URL="${DOWNLOAD_URL_PREFIX%/}/${APPCAST_FILENAME}"

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

run_optional() {
  printf '+ '
  shell_join "$@"
  printf '\n'
  if [[ "${DRY_RUN}" == "yes" ]]; then
    return 0
  fi
  if ! "$@"; then
    echo "Optional check failed: $(shell_join "$@")" >&2
  fi
}

if [[ "${DRY_RUN}" != "yes" ]] && ! command -v "${AWS_BIN}" >/dev/null 2>&1; then
  echo "AWS CLI not found: ${AWS_BIN}" >&2
  exit 69
fi

echo "Running macOS Sparkle S3 preflight"
echo "  Download URL prefix: ${DOWNLOAD_URL_PREFIX}"
echo "  Appcast URL: ${APPCAST_URL}"
echo "  S3 URI: ${S3_URI_NORMALIZED}"
echo "  S3 bucket: ${S3_BUCKET}"
echo "  S3 prefix: ${S3_PREFIX:-<bucket root>}"
echo "  Dry run: ${DRY_RUN}"

run "${AWS_BIN}" --version
if [[ "${CHECK_STS}" == "yes" ]]; then
  run "${AWS_BIN}" sts get-caller-identity
fi
run "${AWS_BIN}" s3 ls "${S3_URI_NORMALIZED}/"

if [[ "${CHECK_BUCKET_POLICY}" == "yes" ]]; then
  run_optional "${AWS_BIN}" s3api get-public-access-block --bucket "${S3_BUCKET}"
  run_optional "${AWS_BIN}" s3api get-bucket-policy-status --bucket "${S3_BUCKET}"
fi

PROBE_FILE=""
if [[ "${DRY_RUN}" == "yes" ]]; then
  PROBE_FILE="/tmp/caverno-sparkle-s3-preflight.txt"
else
  PROBE_FILE="$(mktemp "${TMPDIR:-/tmp}/caverno-sparkle-s3-preflight.XXXXXX")"
  trap 'rm -f "${PROBE_FILE}"' EXIT
  {
    echo "Caverno Sparkle S3 preflight"
    date -u +"%Y-%m-%dT%H:%M:%SZ"
  } >"${PROBE_FILE}"
fi

run "${AWS_BIN}" s3 cp "${PROBE_FILE}" "${PROBE_KEY}" \
  --dryrun \
  --content-type "text/plain" \
  --cache-control "no-cache,max-age=0"

echo "Sparkle S3 preflight completed."

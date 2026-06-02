#!/usr/bin/env bash

set -euo pipefail

DEFAULT_S3_URI="s3://caverno-macos-releases/caverno/macos"

S3_URI="${CAVERNO_SPARKLE_S3_URI:-${DEFAULT_S3_URI}}"
AWS_BIN="${AWS_BIN:-aws}"
APPLY="no"

usage() {
  cat <<'USAGE'
Usage: bash tool/configure_macos_sparkle_s3_public_read.sh [options]

Options:
  --s3-uri URI     S3 destination such as s3://bucket/caverno/macos.
  --aws-bin PATH   AWS CLI executable, default aws.
  --apply          Apply the bucket public-access and policy changes.
  --help           Show this help.

By default this script prints the direct-S3 public read configuration needed for
Sparkle appcast hosting. It only mutates AWS when --apply is provided.
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
    --s3-uri)
      require_value "$@"
      S3_URI="$2"
      shift 2
      ;;
    --aws-bin)
      require_value "$@"
      AWS_BIN="$2"
      shift 2
      ;;
    --apply)
      APPLY="yes"
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

if [[ -z "${S3_PREFIX}" ]]; then
  PUBLIC_RESOURCE="arn:aws:s3:::${S3_BUCKET}/*"
else
  PUBLIC_RESOURCE="arn:aws:s3:::${S3_BUCKET}/${S3_PREFIX%/}/*"
fi

POLICY_FILE="$(mktemp "${TMPDIR:-/tmp}/caverno-sparkle-s3-policy.XXXXXX")"
trap 'rm -f "${POLICY_FILE}"' EXIT

cat >"${POLICY_FILE}" <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadCavernoMacosUpdates",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "${PUBLIC_RESOURCE}"
    }
  ]
}
POLICY

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
  if [[ "${APPLY}" != "yes" ]]; then
    return 0
  fi
  "$@"
}

if [[ "${APPLY}" == "yes" ]] && ! command -v "${AWS_BIN}" >/dev/null 2>&1; then
  echo "AWS CLI not found: ${AWS_BIN}" >&2
  exit 69
fi

echo "Configuring macOS Sparkle S3 public read"
echo "  S3 URI: ${S3_URI%/}"
echo "  S3 bucket: ${S3_BUCKET}"
echo "  S3 prefix: ${S3_PREFIX:-<bucket root>}"
echo "  Public resource: ${PUBLIC_RESOURCE}"
echo "  Apply: ${APPLY}"
echo "  Policy:"
cat "${POLICY_FILE}"

run "${AWS_BIN}" s3api put-public-access-block \
  --bucket "${S3_BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
run "${AWS_BIN}" s3api put-bucket-policy \
  --bucket "${S3_BUCKET}" \
  --policy "file://${POLICY_FILE}"

if [[ "${APPLY}" == "yes" ]]; then
  echo "S3 public read policy applied."
else
  echo "Dry run only. Re-run with --apply to update AWS."
fi

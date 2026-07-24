#!/usr/bin/env bash

set -euo pipefail

DEFAULT_S3_URI="s3://caverno-macos-releases/caverno/macos"
DEFAULT_REGION="ap-northeast-1"
DEFAULT_OAC_NAME="CavernoMacosUpdatesOAC"
DEFAULT_CACHE_POLICY_NAME="CavernoMacosUpdatesOriginCacheControl"
DEFAULT_DISTRIBUTION_COMMENT="Caverno macOS Sparkle updates"
DEFAULT_PRICE_CLASS="PriceClass_200"

S3_URI="${CAVERNO_SPARKLE_S3_URI:-${DEFAULT_S3_URI}}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-${DEFAULT_REGION}}}"
OAC_NAME="${CAVERNO_SPARKLE_CLOUDFRONT_OAC_NAME:-${DEFAULT_OAC_NAME}}"
CACHE_POLICY_NAME="${CAVERNO_SPARKLE_CLOUDFRONT_CACHE_POLICY_NAME:-${DEFAULT_CACHE_POLICY_NAME}}"
DISTRIBUTION_COMMENT="${CAVERNO_SPARKLE_CLOUDFRONT_COMMENT:-${DEFAULT_DISTRIBUTION_COMMENT}}"
PRICE_CLASS="${CAVERNO_SPARKLE_CLOUDFRONT_PRICE_CLASS:-${DEFAULT_PRICE_CLASS}}"
AWS_BIN="${AWS_BIN:-aws}"
DISTRIBUTION_ID="${CAVERNO_SPARKLE_CLOUDFRONT_DISTRIBUTION_ID:-}"
APPLY="no"
RETAIN_LEGACY_PUBLIC_READ="yes"

usage() {
  cat <<'USAGE'
Usage: bash tool/configure_macos_sparkle_cloudfront.sh [options]

Options:
  --s3-uri URI                  S3 origin such as s3://bucket/caverno/macos.
  --region REGION               S3 region, default ap-northeast-1.
  --distribution-id ID          Reuse an existing CloudFront distribution.
  --price-class CLASS           CloudFront price class, default PriceClass_200.
  --retire-direct-s3-read       Remove the legacy public S3 read statement.
  --aws-bin PATH                AWS CLI executable, default aws.
  --apply                       Create or update AWS resources.
  --help                        Show this help.

The script provisions an origin access control, an origin-cache policy, and a
CloudFront distribution for the Sparkle S3 prefix. It also writes the exact S3
bucket policy required by the distribution.

Direct S3 read remains enabled by default so installed builds whose compiled
SUFeedURL still points to S3 can migrate through a CloudFront-backed appcast.
Use --retire-direct-s3-read only after those builds no longer need the bridge.
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
    --region)
      require_value "$@"
      AWS_REGION="$2"
      shift 2
      ;;
    --distribution-id)
      require_value "$@"
      DISTRIBUTION_ID="$2"
      shift 2
      ;;
    --price-class)
      require_value "$@"
      PRICE_CLASS="$2"
      shift 2
      ;;
    --retire-direct-s3-read)
      RETAIN_LEGACY_PUBLIC_READ="no"
      shift 1
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

case "${PRICE_CLASS}" in
  PriceClass_All|PriceClass_100|PriceClass_200)
    ;;
  *)
    echo "--price-class must be PriceClass_All, PriceClass_100, or PriceClass_200." >&2
    exit 64
    ;;
esac

S3_WITHOUT_SCHEME="${S3_URI#s3://}"
S3_BUCKET="${S3_WITHOUT_SCHEME%%/*}"
if [[ -z "${S3_BUCKET}" || "${S3_BUCKET}" == "${S3_WITHOUT_SCHEME}" ]]; then
  S3_PREFIX=""
else
  S3_PREFIX="${S3_WITHOUT_SCHEME#*/}"
fi
S3_PREFIX="${S3_PREFIX%/}"

if [[ -z "${S3_BUCKET}" ]]; then
  echo "The S3 bucket must not be empty." >&2
  exit 64
fi

if [[ -z "${S3_PREFIX}" ]]; then
  S3_RESOURCE="arn:aws:s3:::${S3_BUCKET}/*"
else
  S3_RESOURCE="arn:aws:s3:::${S3_BUCKET}/${S3_PREFIX}/*"
fi

ORIGIN_DOMAIN="${S3_BUCKET}.s3.${AWS_REGION}.amazonaws.com"
CALLER_REFERENCE="caverno-macos-updates-$(date -u +%Y%m%d%H%M%S)"

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

print_command() {
  printf '+ '
  shell_join "$@"
  printf '\n'
}

if [[ "${APPLY}" != "yes" ]]; then
  echo "Configuring CloudFront for macOS Sparkle updates"
  echo "  S3 URI: ${S3_URI%/}"
  echo "  Origin: ${ORIGIN_DOMAIN}"
  echo "  Origin access control: ${OAC_NAME}"
  echo "  Cache policy: ${CACHE_POLICY_NAME}"
  echo "  Distribution: ${DISTRIBUTION_ID:-<create or reuse by comment>}"
  echo "  Legacy direct S3 read: ${RETAIN_LEGACY_PUBLIC_READ}"
  echo "  Apply: no"
  print_command "${AWS_BIN}" cloudfront create-origin-access-control \
    --origin-access-control-config "<generated-config>"
  print_command "${AWS_BIN}" cloudfront create-cache-policy \
    --cache-policy-config "<generated-config>"
  print_command "${AWS_BIN}" cloudfront create-distribution \
    --distribution-config "<generated-config>"
  print_command "${AWS_BIN}" s3api put-public-access-block \
    --bucket "${S3_BUCKET}" \
    --public-access-block-configuration "<migration-safe-config>"
  print_command "${AWS_BIN}" s3api put-bucket-policy \
    --bucket "${S3_BUCKET}" \
    --policy "<generated-policy>"
  echo "Dry run only. Re-run with --apply to update AWS."
  exit 0
fi

if ! command -v "${AWS_BIN}" >/dev/null 2>&1; then
  echo "AWS CLI not found: ${AWS_BIN}" >&2
  exit 69
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/caverno-sparkle-cloudfront.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

ACCOUNT_ID="$("${AWS_BIN}" sts get-caller-identity --query Account --output text)"

OAC_ID="$(
  "${AWS_BIN}" cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='${OAC_NAME}'].Id | [0]" \
    --output text
)"
if [[ -z "${OAC_ID}" || "${OAC_ID}" == "None" ]]; then
  OAC_CONFIG="${TMP_DIR}/oac.json"
  cat >"${OAC_CONFIG}" <<JSON
{
  "Name": "${OAC_NAME}",
  "Description": "Private S3 access for Caverno macOS Sparkle updates",
  "SigningProtocol": "sigv4",
  "SigningBehavior": "always",
  "OriginAccessControlOriginType": "s3"
}
JSON
  OAC_ID="$(
    "${AWS_BIN}" cloudfront create-origin-access-control \
      --origin-access-control-config "file://${OAC_CONFIG}" \
      --query OriginAccessControl.Id \
      --output text
  )"
  echo "Created origin access control: ${OAC_ID}"
else
  echo "Reusing origin access control: ${OAC_ID}"
fi

CACHE_POLICY_ID="$(
  "${AWS_BIN}" cloudfront list-cache-policies \
    --type custom \
    --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='${CACHE_POLICY_NAME}'].CachePolicy.Id | [0]" \
    --output text
)"
if [[ -z "${CACHE_POLICY_ID}" || "${CACHE_POLICY_ID}" == "None" ]]; then
  CACHE_POLICY_CONFIG="${TMP_DIR}/cache-policy.json"
  cat >"${CACHE_POLICY_CONFIG}" <<JSON
{
  "Name": "${CACHE_POLICY_NAME}",
  "Comment": "Honor S3 Cache-Control for Caverno Sparkle appcasts and artifacts",
  "DefaultTTL": 300,
  "MaxTTL": 31536000,
  "MinTTL": 0,
  "ParametersInCacheKeyAndForwardedToOrigin": {
    "EnableAcceptEncodingGzip": true,
    "EnableAcceptEncodingBrotli": true,
    "HeadersConfig": {"HeaderBehavior": "none"},
    "CookiesConfig": {"CookieBehavior": "none"},
    "QueryStringsConfig": {"QueryStringBehavior": "none"}
  }
}
JSON
  CACHE_POLICY_ID="$(
    "${AWS_BIN}" cloudfront create-cache-policy \
      --cache-policy-config "file://${CACHE_POLICY_CONFIG}" \
      --query CachePolicy.Id \
      --output text
  )"
  echo "Created cache policy: ${CACHE_POLICY_ID}"
else
  echo "Reusing cache policy: ${CACHE_POLICY_ID}"
fi

if [[ -z "${DISTRIBUTION_ID}" ]]; then
  DISTRIBUTION_ID="$(
    "${AWS_BIN}" cloudfront list-distributions \
      --query "DistributionList.Items[?Comment=='${DISTRIBUTION_COMMENT}'].Id | [0]" \
      --output text
  )"
fi

if [[ -z "${DISTRIBUTION_ID}" || "${DISTRIBUTION_ID}" == "None" ]]; then
  DISTRIBUTION_CONFIG="${TMP_DIR}/distribution.json"
  cat >"${DISTRIBUTION_CONFIG}" <<JSON
{
  "CallerReference": "${CALLER_REFERENCE}",
  "Comment": "${DISTRIBUTION_COMMENT}",
  "Enabled": true,
  "IsIPV6Enabled": true,
  "HttpVersion": "http2and3",
  "PriceClass": "${PRICE_CLASS}",
  "Aliases": {"Quantity": 0},
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3-caverno-macos-releases",
      "DomainName": "${ORIGIN_DOMAIN}",
      "OriginPath": "",
      "CustomHeaders": {"Quantity": 0},
      "S3OriginConfig": {"OriginAccessIdentity": ""},
      "ConnectionAttempts": 3,
      "ConnectionTimeout": 10,
      "OriginAccessControlId": "${OAC_ID}"
    }]
  },
  "OriginGroups": {"Quantity": 0},
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-caverno-macos-releases",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {"Quantity": 2, "Items": ["HEAD", "GET"]}
    },
    "SmoothStreaming": false,
    "Compress": true,
    "LambdaFunctionAssociations": {"Quantity": 0},
    "FunctionAssociations": {"Quantity": 0},
    "FieldLevelEncryptionId": "",
    "CachePolicyId": "${CACHE_POLICY_ID}",
    "TrustedSigners": {"Enabled": false, "Quantity": 0},
    "TrustedKeyGroups": {"Enabled": false, "Quantity": 0}
  },
  "CacheBehaviors": {"Quantity": 0},
  "CustomErrorResponses": {"Quantity": 0},
  "DefaultRootObject": "",
  "Logging": {
    "Enabled": false,
    "IncludeCookies": false,
    "Bucket": "",
    "Prefix": ""
  },
  "ViewerCertificate": {
    "CloudFrontDefaultCertificate": true,
    "MinimumProtocolVersion": "TLSv1",
    "CertificateSource": "cloudfront"
  },
  "Restrictions": {
    "GeoRestriction": {"RestrictionType": "none", "Quantity": 0}
  },
  "WebACLId": "",
  "Staging": false
}
JSON
  DISTRIBUTION_RESULT="${TMP_DIR}/distribution-result.json"
  "${AWS_BIN}" cloudfront create-distribution \
    --distribution-config "file://${DISTRIBUTION_CONFIG}" \
    >"${DISTRIBUTION_RESULT}"
  DISTRIBUTION_ID="$(
    "${AWS_BIN}" cloudfront get-distribution \
      --id "$(
        python3 -c \
          'import json,sys; print(json.load(open(sys.argv[1]))["Distribution"]["Id"])' \
          "${DISTRIBUTION_RESULT}"
      )" \
      --query Distribution.Id \
      --output text
  )"
  echo "Created distribution: ${DISTRIBUTION_ID}"
else
  echo "Reusing distribution: ${DISTRIBUTION_ID}"
fi

DISTRIBUTION_DOMAIN="$(
  "${AWS_BIN}" cloudfront get-distribution \
    --id "${DISTRIBUTION_ID}" \
    --query Distribution.DomainName \
    --output text
)"
DISTRIBUTION_ARN="arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"

BUCKET_POLICY="${TMP_DIR}/bucket-policy.json"
if [[ "${RETAIN_LEGACY_PUBLIC_READ}" == "yes" ]]; then
  cat >"${BUCKET_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontReadCavernoMacosUpdates",
      "Effect": "Allow",
      "Principal": {"Service": "cloudfront.amazonaws.com"},
      "Action": "s3:GetObject",
      "Resource": "${S3_RESOURCE}",
      "Condition": {"StringEquals": {"AWS:SourceArn": "${DISTRIBUTION_ARN}"}}
    },
    {
      "Sid": "LegacyPublicReadCavernoMacosUpdates",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "${S3_RESOURCE}"
    }
  ]
}
JSON
  PUBLIC_ACCESS_BLOCK="BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
else
  cat >"${BUCKET_POLICY}" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontReadCavernoMacosUpdates",
    "Effect": "Allow",
    "Principal": {"Service": "cloudfront.amazonaws.com"},
    "Action": "s3:GetObject",
    "Resource": "${S3_RESOURCE}",
    "Condition": {"StringEquals": {"AWS:SourceArn": "${DISTRIBUTION_ARN}"}}
  }]
}
JSON
  PUBLIC_ACCESS_BLOCK="BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

"${AWS_BIN}" s3api put-public-access-block \
  --bucket "${S3_BUCKET}" \
  --public-access-block-configuration "${PUBLIC_ACCESS_BLOCK}"
"${AWS_BIN}" s3api put-bucket-policy \
  --bucket "${S3_BUCKET}" \
  --policy "file://${BUCKET_POLICY}"

echo "CloudFront configuration applied."
echo "  Distribution ID: ${DISTRIBUTION_ID}"
echo "  Distribution domain: ${DISTRIBUTION_DOMAIN}"
echo "  Download URL prefix: https://${DISTRIBUTION_DOMAIN}/${S3_PREFIX}"
echo "  Legacy direct S3 read: ${RETAIN_LEGACY_PUBLIC_READ}"

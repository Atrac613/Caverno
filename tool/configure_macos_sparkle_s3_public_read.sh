#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "configure_macos_sparkle_s3_public_read.sh is deprecated." >&2
echo "Using the CloudFront migration-safe configuration instead." >&2

exec bash "${ROOT_DIR}/tool/configure_macos_sparkle_cloudfront.sh" "$@"

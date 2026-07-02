#!/usr/bin/env bash
set -euo pipefail

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command aws
require_command python3
require_command zip

ALLOW_PUBLIC_FUNCTION_URL="${CAVERNO_FEEDBACK_ALLOW_PUBLIC_FUNCTION_URL:-0}"
ALLOWED_ORIGIN="${CAVERNO_FEEDBACK_ALLOWED_ORIGIN:-*}"

if [[ "$ALLOW_PUBLIC_FUNCTION_URL" != "1" ]]; then
  echo "Refusing to create a public feedback endpoint by default." >&2
  echo "Set CAVERNO_FEEDBACK_ALLOW_PUBLIC_FUNCTION_URL=1 after reviewing the" >&2
  echo "risk: the Lambda Function URL accepts unauthenticated POST requests." >&2
  exit 2
fi

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-northeast-1}}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
BUCKET="${CAVERNO_FEEDBACK_BUCKET:-caverno-feedback-${ACCOUNT_ID}-${REGION}}"
PREFIX="${CAVERNO_FEEDBACK_PREFIX:-feedback}"
FUNCTION_NAME="${CAVERNO_FEEDBACK_FUNCTION:-caverno-feedback-ingest}"
RATE_LIMIT_TABLE="${CAVERNO_FEEDBACK_RATE_LIMIT_TABLE:-${FUNCTION_NAME}-rate-limit}"
ROLE_NAME="${CAVERNO_FEEDBACK_ROLE:-caverno-feedback-ingest-role}"
RUNTIME="${CAVERNO_FEEDBACK_RUNTIME:-python3.12}"
MAX_COMPRESSED_BYTES="${CAVERNO_FEEDBACK_MAX_COMPRESSED_BYTES:-1048576}"
MAX_UNCOMPRESSED_BYTES="${CAVERNO_FEEDBACK_MAX_UNCOMPRESSED_BYTES:-8388608}"
RATE_LIMIT_WINDOW_SECONDS="${CAVERNO_FEEDBACK_RATE_LIMIT_WINDOW_SECONDS:-60}"
RATE_LIMIT_MAX_REQUESTS="${CAVERNO_FEEDBACK_RATE_LIMIT_MAX_REQUESTS:-3}"
RATE_LIMIT_TTL_SECONDS="${CAVERNO_FEEDBACK_RATE_LIMIT_TTL_SECONDS:-3600}"
MIN_SECONDS_BETWEEN_POSTS="${CAVERNO_FEEDBACK_MIN_SECONDS_BETWEEN_POSTS:-10}"
RESERVED_CONCURRENCY="${CAVERNO_FEEDBACK_RESERVED_CONCURRENCY:-5}"

PREFIX="${PREFIX#/}"
PREFIX="${PREFIX%/}"
if [[ -z "$PREFIX" ]]; then
  PREFIX="feedback"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

TRUST_POLICY="$TMP_DIR/trust-policy.json"
INLINE_POLICY="$TMP_DIR/s3-policy.json"
LAMBDA_SRC="$TMP_DIR/lambda_function.py"
ZIP_FILE="$TMP_DIR/function.zip"
CORS_CONFIG="$TMP_DIR/cors.json"

echo "Preparing Caverno feedback endpoint in account ${ACCOUNT_ID}, region ${REGION}"
echo "Bucket: ${BUCKET}"
echo "Prefix: ${PREFIX}"
echo "Lambda: ${FUNCTION_NAME}"
echo "Rate limit table: ${RATE_LIMIT_TABLE}"
echo "Rate limit: ${RATE_LIMIT_MAX_REQUESTS} POSTs per ${RATE_LIMIT_WINDOW_SECONDS}s, ${MIN_SECONDS_BETWEEN_POSTS}s minimum spacing"

bucket_created=0
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "S3 bucket already exists."
else
  echo "Creating S3 bucket."
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
  bucket_created=1
fi

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" >/dev/null

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null

if [[ "$bucket_created" == "1" ]]; then
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled >/dev/null
fi

if aws dynamodb describe-table \
  --table-name "$RATE_LIMIT_TABLE" \
  --region "$REGION" >/dev/null 2>&1; then
  echo "DynamoDB rate limit table already exists."
else
  echo "Creating DynamoDB rate limit table."
  aws dynamodb create-table \
    --table-name "$RATE_LIMIT_TABLE" \
    --region "$REGION" \
    --attribute-definitions AttributeName=rateKey,AttributeType=S \
    --key-schema AttributeName=rateKey,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists \
    --table-name "$RATE_LIMIT_TABLE" \
    --region "$REGION"
fi

TTL_STATUS="$(
  aws dynamodb describe-time-to-live \
    --table-name "$RATE_LIMIT_TABLE" \
    --region "$REGION" \
    --query 'TimeToLiveDescription.TimeToLiveStatus' \
    --output text 2>/dev/null || true
)"
if [[ "$TTL_STATUS" == "ENABLED" || "$TTL_STATUS" == "ENABLING" ]]; then
  echo "DynamoDB TTL already enabled."
else
  echo "Enabling DynamoDB TTL."
  aws dynamodb update-time-to-live \
    --table-name "$RATE_LIMIT_TABLE" \
    --region "$REGION" \
    --time-to-live-specification "Enabled=true,AttributeName=expiresAt" >/dev/null
fi

cat >"$TRUST_POLICY" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "IAM role already exists."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "file://${TRUST_POLICY}" >/dev/null
else
  echo "Creating IAM role."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${TRUST_POLICY}" >/dev/null
fi

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null

RATE_LIMIT_TABLE_ARN="arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${RATE_LIMIT_TABLE}"

cat >"$INLINE_POLICY" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/${PREFIX}/*"
    },
    {
      "Effect": "Allow",
      "Action": "dynamodb:UpdateItem",
      "Resource": "${RATE_LIMIT_TABLE_ARN}"
    }
  ]
}
JSON

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name CavernoFeedbackWriteObjects \
  --policy-document "file://${INLINE_POLICY}" >/dev/null

ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"

cat >"$LAMBDA_SRC" <<'PY'
import base64
import gzip
import hashlib
import io
import json
import os
import re
import time
import traceback
import uuid

import boto3


s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")


BUCKET = os.environ["BUCKET"]
PREFIX = os.environ.get("PREFIX", "feedback").strip("/")
RATE_LIMIT_TABLE = os.environ["RATE_LIMIT_TABLE"]
MAX_COMPRESSED_BYTES = int(os.environ.get("MAX_COMPRESSED_BYTES", "1048576"))
MAX_UNCOMPRESSED_BYTES = int(os.environ.get("MAX_UNCOMPRESSED_BYTES", "8388608"))
RATE_LIMIT_WINDOW_SECONDS = int(os.environ.get("RATE_LIMIT_WINDOW_SECONDS", "60"))
RATE_LIMIT_MAX_REQUESTS = int(os.environ.get("RATE_LIMIT_MAX_REQUESTS", "3"))
RATE_LIMIT_TTL_SECONDS = int(os.environ.get("RATE_LIMIT_TTL_SECONDS", "3600"))
MIN_SECONDS_BETWEEN_POSTS = int(os.environ.get("MIN_SECONDS_BETWEEN_POSTS", "10"))
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")


class PayloadTooLarge(Exception):
    pass


SENSITIVE_KEY_RE = re.compile(
    r"(?:^|[_-])(?:api[_-]?key|authorization|auth[_-]?token|access[_-]?token|"
    r"refresh[_-]?token|id[_-]?token|token|secret|password|passwd|private[_-]?key|"
    r"client[_-]?secret|session[_-]?token|cookie|set[_-]?cookie)(?:$|[_-])",
    re.IGNORECASE,
)
PRIVATE_KEY_RE = re.compile(
    r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
    re.IGNORECASE | re.DOTALL,
)
AUTH_HEADER_RE = re.compile(
    r"(?im)^(\s*(?:authorization|proxy-authorization)\s*:\s*)(.+)$"
)
BEARER_RE = re.compile(r"\b[Bb]earer\s+[A-Za-z0-9._~+/=-]{12,}")
OPENAI_KEY_RE = re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")
GITHUB_TOKEN_RE = re.compile(
    r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"
)
JWT_RE = re.compile(
    r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"
)
URL_CREDENTIAL_RE = re.compile(r"([a-z][a-z0-9+.-]*://)([^/@\s:]+):([^/@\s]+)@")
SENSITIVE_QUERY_RE = re.compile(
    r"(?i)([?&](?:api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token|"
    r"token|secret|password|client[_-]?secret)=)[^&#\s]+"
)
ENV_SECRET_RE = re.compile(
    r"(?im)^(\s*[A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY)"
    r"[A-Z0-9_]*\s*=\s*)(.+)$"
)


def _is_sensitive_key(key):
    return bool(SENSITIVE_KEY_RE.search(str(key or "")))


def _redact_text(value):
    if not value:
        return value
    text = str(value)
    text = PRIVATE_KEY_RE.sub("[REDACTED_PRIVATE_KEY]", text)
    text = AUTH_HEADER_RE.sub(r"\1[REDACTED_AUTHORIZATION]", text)
    text = BEARER_RE.sub("Bearer [REDACTED_TOKEN]", text)
    text = OPENAI_KEY_RE.sub("[REDACTED_OPENAI_API_KEY]", text)
    text = GITHUB_TOKEN_RE.sub("[REDACTED_GITHUB_TOKEN]", text)
    text = JWT_RE.sub("[REDACTED_JWT]", text)
    text = URL_CREDENTIAL_RE.sub(r"\1[REDACTED_USER]:[REDACTED_PASSWORD]@", text)
    text = SENSITIVE_QUERY_RE.sub(r"\1[REDACTED]", text)
    text = ENV_SECRET_RE.sub(r"\1[REDACTED]", text)
    return text


def _redact_value(value, key=None):
    if _is_sensitive_key(key):
        if value in (None, ""):
            return value
        return "[REDACTED]"
    if isinstance(value, dict):
        return {
            item_key: _redact_value(item_value, item_key)
            for item_key, item_value in value.items()
        }
    if isinstance(value, list):
        return [_redact_value(item) for item in value]
    if isinstance(value, str):
        return _redact_text(value)
    return value


def _headers():
    return {
        "content-type": "application/json",
        "access-control-allow-origin": ALLOWED_ORIGIN,
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": (
            "content-type, content-encoding, x-caverno-feedback-id, "
            "x-caverno-feedback-schema"
        ),
        "access-control-expose-headers": "retry-after",
    }


def _response(status_code, payload, extra_headers=None):
    headers = _headers()
    if extra_headers:
        headers.update(extra_headers)
    return {
        "statusCode": status_code,
        "headers": headers,
        "body": json.dumps(payload, separators=(",", ":")),
    }


def _safe_segment(value, fallback):
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", str(value or "").strip())
    normalized = re.sub(r"-+", "-", normalized)
    normalized = re.sub(r"^[-.]+|[-.]+$", "", normalized)
    return normalized or fallback


def _event_method(event):
    request_context = event.get("requestContext") or {}
    http_context = request_context.get("http") or {}
    return http_context.get("method") or event.get("httpMethod") or "POST"


def _event_headers(event):
    return {
        str(key).lower(): str(value)
        for key, value in (event.get("headers") or {}).items()
        if value is not None
    }


def _raw_body(event):
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return base64.b64decode(body)
    if isinstance(body, bytes):
        return body
    return str(body).encode("utf-8")


def _source_ip(event, headers):
    request_context = event.get("requestContext") or {}
    http_context = request_context.get("http") or {}
    source_ip = http_context.get("sourceIp")
    if source_ip:
        return source_ip

    forwarded_for = headers.get("x-forwarded-for", "")
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip() or "unknown"

    return "unknown"


def _decompress_gzip(body):
    with gzip.GzipFile(fileobj=io.BytesIO(body)) as gzip_file:
        decompressed = gzip_file.read(MAX_UNCOMPRESSED_BYTES + 1)
    if len(decompressed) > MAX_UNCOMPRESSED_BYTES:
        raise PayloadTooLarge()
    return decompressed


def _check_rate_limit(source_ip):
    if RATE_LIMIT_MAX_REQUESTS <= 0 or RATE_LIMIT_WINDOW_SECONDS <= 0:
        return None

    now_epoch = int(time.time())
    window_start = now_epoch - (now_epoch % RATE_LIMIT_WINDOW_SECONDS)
    window_end = window_start + RATE_LIMIT_WINDOW_SECONDS
    source_digest = hashlib.sha256(source_ip.encode("utf-8")).hexdigest()[:32]
    rate_key = f"ip#{source_digest}#{window_start}"
    min_last_request_at = now_epoch - max(MIN_SECONDS_BETWEEN_POSTS, 0)
    expires_at = now_epoch + max(RATE_LIMIT_TTL_SECONDS, RATE_LIMIT_WINDOW_SECONDS)

    try:
        dynamodb.update_item(
            TableName=RATE_LIMIT_TABLE,
            Key={"rateKey": {"S": rate_key}},
            UpdateExpression=(
                "SET #requestCount = if_not_exists(#requestCount, :zero) + :one, "
                "#lastRequestAt = :now, #expiresAt = :expiresAt"
            ),
            ConditionExpression=(
                "attribute_not_exists(#requestCount) OR "
                "(#requestCount < :maxRequests AND "
                "(attribute_not_exists(#lastRequestAt) OR "
                "#lastRequestAt <= :minLastRequestAt))"
            ),
            ExpressionAttributeNames={
                "#requestCount": "requestCount",
                "#lastRequestAt": "lastRequestAt",
                "#expiresAt": "expiresAt",
            },
            ExpressionAttributeValues={
                ":zero": {"N": "0"},
                ":one": {"N": "1"},
                ":now": {"N": str(now_epoch)},
                ":expiresAt": {"N": str(expires_at)},
                ":maxRequests": {"N": str(RATE_LIMIT_MAX_REQUESTS)},
                ":minLastRequestAt": {"N": str(min_last_request_at)},
            },
        )
        return None
    except dynamodb.exceptions.ConditionalCheckFailedException:
        retry_after = max(1, window_end - now_epoch)
        return {
            "retryAfterSeconds": retry_after,
        }


def handler(event, context):
    method = _event_method(event).upper()
    if method == "OPTIONS":
        return _response(204, {})
    if method != "POST":
        return _response(405, {"ok": False, "error": "method_not_allowed"})

    try:
        headers = _event_headers(event)
        rate_limit = _check_rate_limit(_source_ip(event, headers))
        if rate_limit:
            retry_after = str(rate_limit["retryAfterSeconds"])
            return _response(
                429,
                {
                    "ok": False,
                    "error": "rate_limited",
                    "retryAfterSeconds": rate_limit["retryAfterSeconds"],
                },
                {"retry-after": retry_after},
            )

        if headers.get("x-caverno-feedback-schema") != "caverno_feedback_submission":
            return _response(400, {"ok": False, "error": "invalid_schema_header"})

        body = _raw_body(event)
        if len(body) > MAX_COMPRESSED_BYTES:
            return _response(413, {"ok": False, "error": "payload_too_large"})

        if "gzip" in headers.get("content-encoding", "").lower():
            try:
                body = _decompress_gzip(body)
            except PayloadTooLarge:
                return _response(413, {"ok": False, "error": "payload_too_large"})
            except (EOFError, OSError):
                return _response(400, {"ok": False, "error": "invalid_gzip"})
        elif len(body) > MAX_UNCOMPRESSED_BYTES:
            return _response(413, {"ok": False, "error": "payload_too_large"})

        try:
            payload = json.loads(body.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return _response(400, {"ok": False, "error": "invalid_json"})

        if payload.get("schemaName") != "caverno_feedback_submission":
            return _response(400, {"ok": False, "error": "invalid_schema"})

        redacted_payload = _redact_value(payload)
        body = json.dumps(
            redacted_payload,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
        if len(body) > MAX_UNCOMPRESSED_BYTES:
            return _response(413, {"ok": False, "error": "payload_too_large"})

        submission_id = _safe_segment(
            _redact_text(payload.get("submissionId") or uuid.uuid4()),
            "feedback",
        )
        now = time.gmtime()
        date_path = time.strftime("%Y/%m/%d", now)
        timestamp = time.strftime("%Y%m%dT%H%M%SZ", now)
        key = f"{PREFIX}/{date_path}/{timestamp}_{submission_id}.json"

        s3.put_object(
            Bucket=BUCKET,
            Key=key,
            Body=body,
            ContentType="application/json",
            ServerSideEncryption="AES256",
            Metadata={
                "schema": "caverno_feedback_submission",
                "submission-id": submission_id[:128],
            },
        )
        return _response(200, {"ok": True, "objectKey": key})
    except Exception:
        print(traceback.format_exc())
        return _response(500, {"ok": False, "error": "internal_error"})
PY

(
  cd "$TMP_DIR"
  zip -q function.zip lambda_function.py
)

ENVIRONMENT="Variables={BUCKET=${BUCKET},PREFIX=${PREFIX},RATE_LIMIT_TABLE=${RATE_LIMIT_TABLE},MAX_COMPRESSED_BYTES=${MAX_COMPRESSED_BYTES},MAX_UNCOMPRESSED_BYTES=${MAX_UNCOMPRESSED_BYTES},RATE_LIMIT_WINDOW_SECONDS=${RATE_LIMIT_WINDOW_SECONDS},RATE_LIMIT_MAX_REQUESTS=${RATE_LIMIT_MAX_REQUESTS},RATE_LIMIT_TTL_SECONDS=${RATE_LIMIT_TTL_SECONDS},MIN_SECONDS_BETWEEN_POSTS=${MIN_SECONDS_BETWEEN_POSTS},ALLOWED_ORIGIN=${ALLOWED_ORIGIN}}"

if aws lambda get-function \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" >/dev/null 2>&1; then
  echo "Updating Lambda function."
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --role "$ROLE_ARN" \
    --runtime "$RUNTIME" \
    --handler lambda_function.handler \
    --timeout 10 \
    --memory-size 256 \
    --environment "$ENVIRONMENT" >/dev/null
  aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION"
  aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --zip-file "fileb://${ZIP_FILE}" >/dev/null
  aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION"
else
  echo "Creating Lambda function."
  sleep 10
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --runtime "$RUNTIME" \
    --role "$ROLE_ARN" \
    --handler lambda_function.handler \
    --timeout 10 \
    --memory-size 256 \
    --zip-file "fileb://${ZIP_FILE}" \
    --environment "$ENVIRONMENT" >/dev/null
  aws lambda wait function-active-v2 \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION"
fi

aws lambda put-function-concurrency \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --reserved-concurrent-executions "$RESERVED_CONCURRENCY" >/dev/null

python3 - "$ALLOWED_ORIGIN" >"$CORS_CONFIG" <<'PY'
import json
import sys

print(
    json.dumps(
        {
            "AllowOrigins": [sys.argv[1]],
            "AllowMethods": ["POST"],
            "AllowHeaders": [
                "content-type",
                "content-encoding",
                "x-caverno-feedback-id",
                "x-caverno-feedback-schema",
            ],
            "MaxAge": 86400,
        }
    )
)
PY

if aws lambda get-function-url-config \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" >/dev/null 2>&1; then
  aws lambda update-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --auth-type NONE \
    --cors "file://${CORS_CONFIG}" >/dev/null
else
  aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --auth-type NONE \
    --cors "file://${CORS_CONFIG}" >/dev/null
fi

permission_output="$(
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --statement-id FunctionUrlAllowPublicInvoke \
    --action lambda:InvokeFunctionUrl \
    --principal '*' \
    --function-url-auth-type NONE 2>&1 >/dev/null || true
)"
if [[ -n "$permission_output" && "$permission_output" != *"ResourceConflictException"* ]]; then
  echo "$permission_output" >&2
  exit 1
fi

python3 - "$FUNCTION_NAME" "$REGION" <<'PY'
import datetime
import hashlib
import hmac
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


function_name = sys.argv[1]
region = sys.argv[2]
statement_id = "FunctionUrlAllowPublicInvokeFunction"
service = "lambda"
host = f"lambda.{region}.amazonaws.com"
function_path = urllib.parse.quote(function_name, safe="")
path = f"/2015-03-31/functions/{function_path}/policy"
body = json.dumps(
    {
        "StatementId": statement_id,
        "Action": "lambda:InvokeFunction",
        "Principal": "*",
        "InvokedViaFunctionUrl": True,
    },
    separators=(",", ":"),
).encode("utf-8")


def _sign(key, value):
    return hmac.new(key, value.encode("utf-8"), hashlib.sha256).digest()


def _signature_key(secret_key, date_stamp):
    date_key = _sign(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    region_key = _sign(date_key, region)
    service_key = _sign(region_key, service)
    return _sign(service_key, "aws4_request")


credentials = json.loads(
    subprocess.check_output(
        ["aws", "configure", "export-credentials", "--format", "process"],
        text=True,
    )
)
access_key = credentials["AccessKeyId"]
secret_key = credentials["SecretAccessKey"]
session_token = credentials.get("SessionToken")

now = datetime.datetime.now(datetime.UTC)
amz_date = now.strftime("%Y%m%dT%H%M%SZ")
date_stamp = now.strftime("%Y%m%d")
payload_hash = hashlib.sha256(body).hexdigest()
headers = {
    "content-type": "application/json",
    "host": host,
    "x-amz-date": amz_date,
}
if session_token:
    headers["x-amz-security-token"] = session_token

signed_header_names = sorted(headers)
canonical_headers = "".join(
    f"{name}:{headers[name].strip()}\n" for name in signed_header_names
)
signed_headers = ";".join(signed_header_names)
canonical_request = "\n".join(
    [
        "POST",
        path,
        "",
        canonical_headers,
        signed_headers,
        payload_hash,
    ]
)
credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
string_to_sign = "\n".join(
    [
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ]
)
signature = hmac.new(
    _signature_key(secret_key, date_stamp),
    string_to_sign.encode("utf-8"),
    hashlib.sha256,
).hexdigest()
headers["authorization"] = (
    "AWS4-HMAC-SHA256 "
    f"Credential={access_key}/{credential_scope}, "
    f"SignedHeaders={signed_headers}, "
    f"Signature={signature}"
)

request = urllib.request.Request(
    f"https://{host}{path}",
    data=body,
    headers=headers,
    method="POST",
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()
except urllib.error.HTTPError as error:
    error_body = error.read().decode("utf-8", errors="replace")
    if error.code == 409 and "ResourceConflictException" in error_body:
        sys.exit(0)
    print(error_body, file=sys.stderr)
    sys.exit(1)
PY

FUNCTION_URL="$(
  aws lambda get-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query FunctionUrl \
    --output text
)"

echo
echo "Feedback endpoint ready."
echo "Endpoint URL: ${FUNCTION_URL}"
echo "S3 destination: s3://${BUCKET}/${PREFIX}/"
echo "Configure Caverno Debug settings with the endpoint URL above."

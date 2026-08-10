import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

export const SCHEMA_VERSION = 2;
export const APP_CHECK_HEADER = "x-firebase-appcheck";
export const KEY_ID_HEADER = "x-caverno-relay-key-id";
export const TIMESTAMP_HEADER = "x-caverno-relay-timestamp";
export const NONCE_HEADER = "x-caverno-relay-nonce";
export const SIGNATURE_HEADER = "x-caverno-relay-signature";
export const MAX_SIGNED_CLOCK_SKEW_MS = 5 * 60 * 1000;
export const MAX_EVENT_AGE_MS = 15 * 60 * 1000;
export const MAX_EVENT_FUTURE_MS = 5 * 60 * 1000;
export const REPLAY_RETENTION_MS = 20 * 60 * 1000;

const identifierPattern = /^[A-Za-z0-9_-]{8,256}$/;
const secretPattern = /^[A-Za-z0-9_-]{43,128}$/;
const digestPattern = /^[a-f0-9]{64}$/;

export class RelayError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "RelayError";
    this.code = code;
    this.status = status;
  }
}

export function randomToken(byteLength = 32) {
  return randomBytes(byteLength).toString("base64url");
}

export function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function requireObject(value) {
  if (value === null || Array.isArray(value) || typeof value !== "object") {
    throw new RelayError("invalid_request");
  }
  return value;
}

export function requireExactKeys(value, keys) {
  const expected = new Set(keys);
  if (
    Object.keys(value).length !== expected.size ||
    Object.keys(value).some((key) => !expected.has(key))
  ) {
    throw new RelayError("invalid_request");
  }
}

export function requireSchema(value) {
  if (value.schemaVersion !== SCHEMA_VERSION) {
    throw new RelayError("unsupported_schema");
  }
}

export function requireString(value, field, { maxLength = 4096 } = {}) {
  const candidate = typeof value[field] === "string" ? value[field].trim() : "";
  if (!candidate || candidate.length > maxLength) {
    throw new RelayError("invalid_request");
  }
  return candidate;
}

export function requireIdentifier(value, field) {
  const candidate = requireString(value, field, { maxLength: 256 });
  if (!identifierPattern.test(candidate)) {
    throw new RelayError("invalid_request");
  }
  return candidate;
}

export function requireSecret(value, field) {
  const candidate = requireString(value, field, { maxLength: 128 });
  if (!secretPattern.test(candidate)) {
    throw new RelayError("invalid_request");
  }
  return candidate;
}

export function requireDigest(value, field) {
  const candidate = requireString(value, field, { maxLength: 64 }).toLowerCase();
  if (!digestPattern.test(candidate)) {
    throw new RelayError("invalid_request");
  }
  return candidate;
}

export function requireTimestamp(value, field) {
  const candidate = requireString(value, field, { maxLength: 64 });
  const timestamp = new Date(candidate);
  if (!Number.isFinite(timestamp.getTime())) {
    throw new RelayError("invalid_request");
  }
  return timestamp;
}

export function requireFreshTimestamp(timestamp, now, pastMs, futureMs = pastMs) {
  const delta = timestamp.getTime() - now.getTime();
  if (delta < -pastMs || delta > futureMs) {
    throw new RelayError("stale_request", 409);
  }
}

export function canonicalRequest({
  method,
  path,
  body,
  keyId,
  timestampSeconds,
  nonce,
}) {
  return [
    "caverno-relay-v1",
    method.trim().toUpperCase(),
    path.trim(),
    keyId.trim(),
    String(timestampSeconds),
    nonce.trim(),
    sha256(body),
  ].join("\n");
}

export function expectedSignature({ secret, ...request }) {
  return createHmac("sha256", secret)
    .update(canonicalRequest(request), "utf8")
    .digest("base64url");
}

export function constantTimeEqual(left, right) {
  const leftBytes = Buffer.from(left, "utf8");
  const rightBytes = Buffer.from(right, "utf8");
  if (leftBytes.length !== rightBytes.length) {
    return false;
  }
  return timingSafeEqual(leftBytes, rightBytes);
}

export function headerValue(headers, name) {
  const value = headers[name] ?? headers[name.toLowerCase()];
  if (Array.isArray(value)) {
    return value[0]?.trim() ?? "";
  }
  return typeof value === "string" ? value.trim() : "";
}

export function parseSignedHeaders(headers) {
  const keyId = headerValue(headers, KEY_ID_HEADER);
  const timestampSeconds = Number.parseInt(
    headerValue(headers, TIMESTAMP_HEADER),
    10,
  );
  const nonce = headerValue(headers, NONCE_HEADER);
  const signature = headerValue(headers, SIGNATURE_HEADER);
  if (
    !identifierPattern.test(keyId) ||
    !Number.isSafeInteger(timestampSeconds) ||
    !identifierPattern.test(nonce) ||
    !secretPattern.test(signature)
  ) {
    throw new RelayError("unauthorized", 401);
  }
  return { keyId, timestampSeconds, nonce, signature };
}

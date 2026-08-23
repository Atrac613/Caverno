# SEC4.6c1 Encrypted Settings Export Codec

Status: completed on 2026-08-23.

## Task

- Goal: define and implement the authenticated-encryption envelope that the
  explicit include-secrets settings export flow will use.
- User-visible behavior: none in this slice; it establishes the independently
  testable cryptographic boundary for the next UI and file integration slice.
- Non-goals: exposing an include-secrets action, changing default exports,
  importing encrypted files, or adding encrypted QR payloads.

## Context

- Affected components: settings data services and focused codec tests.
- Related finding: SA-11 in `docs/security_audit_2026-08-14.md`.
- Reference guidance: NIST SP 800-132 requires a random salt of at least 128
  bits and a user-acceptable work factor. OWASP recommends 600,000 iterations
  for PBKDF2-HMAC-SHA256 and AES with an authenticated mode for stored data.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Use AES-256-GCM with a fresh 96-bit nonce and a 128-bit authentication tag.
- Derive the key with PBKDF2-HMAC-SHA256, 600,000 iterations, and a fresh
  128-bit salt.
- Bind the schema, version, KDF, work factor, and cipher to the authentication
  tag as associated data.
- Bound passphrase, plaintext, envelope, ciphertext, and imported KDF cost to
  avoid resource-exhaustion inputs.
- Collapse malformed data, wrong passphrases, and authentication failures into
  one import error.
- Clear mutable plaintext, passphrase, and derived-key byte buffers after use.
- No generated files or new dependencies are required.
- Rollback unit: the codec, its tests, and this task document.

## Similar-Pattern Search

- Search terms: `encrypt`, `decrypt`, `AEADParameters`, `GCMBlockCipher`,
  `PBKDF2KeyDerivator`, `SettingsFileService`, and `exportSettings`.
- Files inspected: settings file and QR services, settings notifier and actions
  menu, Remote Coding security helpers, dependency declarations, and
  PointyCastle's installed GCM/PBKDF2 APIs and tests.
- Follow-up tasks found: SEC4.6c2 added the explicit warning, passphrase and
  confirmation UI, encrypted file export/import, quarantine on import, and
  localization. Encrypted QR remains out of scope because secret-bearing QR
  payloads create unnecessary visual and capture exposure.

## Acceptance Criteria

- The encrypted envelope contains no plaintext credential value.
- Identical inputs produce different salt, nonce, and ciphertext values.
- Correct passphrases round-trip byte-exact JSON.
- Wrong passphrases and modified ciphertext fail authentication.
- Unsupported versions, weak or excessive KDF work factors, malformed base64,
  and oversized inputs fail before settings parsing.
- Existing default exports remain secret-free and unchanged.

## Verification

```bash
fvm flutter test --no-pub \
  test/features/settings/data/encrypted_settings_export_codec_test.dart \
  test/features/settings/data/settings_file_service_test.dart \
  test/features/settings/data/settings_qr_service_test.dart
fvm flutter analyze --no-pub
```

## Handoff Notes

- Summary: a versioned, resource-bounded AES-256-GCM settings export envelope
  now exists behind a focused codec.
- Tests run: 36 codec and existing file/QR export tests passed, and
  `fvm flutter analyze --no-pub` reported no issues.
- Risks or follow-ups: pure-Dart PBKDF2 work must be measured on the supported
  mobile and desktop platform range. The local test run took about four seconds
  for an encrypt/decrypt round trip, so SEC4.6c2 must perform KDF work outside
  the main isolate and show progress-safe UI.

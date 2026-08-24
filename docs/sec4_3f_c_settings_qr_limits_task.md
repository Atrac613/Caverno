# SEC4.3f-C Settings QR Limits

Status: completed 2026-08-24.

## Task

- Goal: reject oversized or high-expansion settings QR payloads before Base64,
  gzip, UTF-8, or JSON processing can consume unbounded memory.
- User-visible behavior: normal secret-free settings QR round trips remain
  compatible; oversized payloads fail with a specific bounded-input error.
- Non-goals: changing settings schema validation, adding secret-bearing QR
  export, changing executable-import quarantine, or redesigning QR transport.

## Context

- Affected component: `SettingsQrService` and its focused tests.
- Related finding: SA-21 in
  `docs/security_followup_review_2026-08-24.md`.
- Release role: final independently reviewable sub-slice of SEC4.3f.

## Limit Contract

- Compressed gzip input: 256 KiB by default.
- Base64 text: derived from the compressed limit and rejected before decoding.
- Decompressed settings JSON: 1 MiB by default.
- Generation uses the same contract and refuses to create a QR string that the
  parser would reject.
- Limits remain constructor-configurable for exact-boundary tests.

## Implementation Notes

- Check the raw QR string length before `trim` or `base64Decode` creates another
  representation.
- Check decoded compressed bytes before starting gzip decompression.
- Drive `GZipCodec.decoder.startChunkedConversion` into a fixed-limit byte sink
  that rejects the crossing chunk before appending it.
- Decode UTF-8 and JSON only after the decompressed byte ceiling succeeds.
- Preserve `FormatException` for malformed input while exposing a distinct
  `SettingsQrLimitException` for resource-limit failures.

## Similar-Pattern Search

- Search terms: `GZipCodec`, `base64Decode`, `startChunkedConversion`,
  `parseQrString`, and `generateQrString`.
- Files inspected: settings QR service/tests, settings notifier import flow,
  executable-import quarantine tests, and Dart's gzip decoder implementation.
- Follow-up found: none for SA-21; successful completion closes SEC4.3f.

## Acceptance Criteria

- Base64 text that cannot fit the compressed-byte budget is rejected before
  decoding.
- Decoded compressed input over the configured ceiling is rejected before gzip
  decompression.
- A small gzip payload expanding past the configured output ceiling is rejected
  during chunked decompression.
- Compressed and decompressed payloads exactly at their ceilings remain
  accepted when the contained settings JSON is valid.
- Generation refuses output outside the same import contract.
- Existing secret-free QR round-trip and invalid-input behavior remain green.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/settings/data/settings_qr_service_test.dart
```

## Handoff Notes

- Summary: settings QR import now rejects Base64 text beyond the derived
  compressed budget before decoding, rejects compressed bytes over 256 KiB,
  and streams gzip output into a sink capped at 1 MiB before UTF-8 or JSON
  decoding. Generation enforces the same limits and limit failures remain
  distinct from malformed-input `FormatException`s.
- Tests run: all 8 focused settings QR tests pass; `flutter analyze --no-pub`
  reports no issues.
- Coverage or low-coverage notes: `settings_qr_service.dart` has 56/62 covered
  lines (90.3%) in the focused coverage run. Uncovered lines are defensive sink
  lifecycle errors and the decoder cleanup fallback.
- Risks or follow-ups: SA-21 and SEC4.3f are complete. The next security slice
  is SEC4.6k sensitive diagnostic storage.

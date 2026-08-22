# SEC4.6a Secret-Free Settings Export

Status: completed on 2026-08-22.

## Task

- Goal: prevent default settings file and QR exports from disclosing stored
  credentials.
- User-visible behavior: exported settings remain import-compatible, but API
  keys, webhook credentials, auth tokens, and executable-environment values
  must be re-entered after import.
- Non-goals: moving persisted credentials into platform secure storage or
  adding an encrypted include-secrets export flow.

## Context

- Affected components: `SettingsFileService`, `SettingsQrService`, and
  settings export tests.
- Related finding: SA-11 in `docs/security_audit_2026-08-14.md`.
- Reference pattern: `CavernoCliRedactor` recursively removes credential values
  before terminal output crosses a trust boundary.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Build one shared export payload for file and QR paths.
- Replace dedicated credential fields with empty strings so the payload remains
  compatible with `AppSettings.fromJson`.
- Remove all MCP server and external hook environment values because arbitrary
  environment keys can carry credentials.
- Preserve runtime settings and normal persistence behavior in this slice.
- No generated files are required.

## Similar-Pattern Search

- Search terms: `settings.toJson`, `generateQrString`, `exportSettings`,
  `apiKey`, `WebhookUrl`, `AuthToken`, and `env`.
- Files inspected: settings file export, QR export, settings repository,
  external settings sync, `AppSettings`, and the CLI redactor.
- Follow-up tasks found: secure-storage migration, encrypted include-secrets
  export, and external settings sync hardening remain in SEC4.6.

## Acceptance Criteria

- File and QR exports contain no primary or saved-endpoint API keys.
- Google Chat webhook URLs and feedback auth tokens are empty in exports.
- MCP server and external hook environment maps are empty in exports.
- Non-secret settings survive export and import.
- Exporting does not mutate the live `AppSettings` instance.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/settings/data/settings_file_service_test.dart \
  --test test/features/settings/data/settings_qr_service_test.dart
```

## Handoff Notes

- Summary: file and QR exports now share one import-compatible sanitized
  payload that clears dedicated credentials and executable environment values.
- Tests run: the repository-standard verification entrypoint passed with 29
  focused Flutter tests and 10 notification-relay tests.
- Risks or follow-ups: this slice reduces export exposure but does not close
  SA-11 until normal persistence uses platform secure storage and an explicit
  encrypted include-secrets flow exists.

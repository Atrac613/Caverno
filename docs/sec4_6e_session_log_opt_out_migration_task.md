# SEC4.6e Session Log Opt-Out Migration

Status: completed on 2026-08-23.

## Task

- Goal: prevent the session-log default migration from reversing an explicit
  user opt-out.
- User-visible behavior: users who disabled LLM session logging remain opted
  out after upgrade, even when the historical migration marker is absent.
- Non-goals: changing the default for new installs, log retention, filesystem
  permissions, or the session-log UI.

## Context

- Affected components: `SettingsRepository` migration detection and focused
  repository tests.
- Related finding: SA-14 in `docs/security_audit_2026-08-14.md`.
- Reference behavior: generated `AppSettings.fromJson` already defaults a
  missing `enableLlmSessionLogs` field to `true`.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Treat field presence as the authority for whether a user choice exists.
- Run and persist the default-on migration only when the saved JSON omits
  `enableLlmSessionLogs` and the historical marker is absent.
- Preserve explicit `false` and `true` values without interpreting the missing
  marker as consent to overwrite either value.
- Keep the marker for compatibility with already-migrated installations.
- No generated files or new dependencies are required.

## Similar-Pattern Search

- Search terms: `enableLlmSessionLogs`,
  `migration.enable_llm_session_logs_default_on.v1`, `loadReadOnly`, and
  `AppSettings.fromJson`.
- Files inspected: settings repository, generated settings JSON defaults,
  settings entity tests, roadmap, and security audit.
- Follow-up tasks found: SA-15 stale Hive resurrection is the next SEC4.6
  lifecycle slice.

## Acceptance Criteria

- Missing legacy fields migrate to the enabled default and persist the field
  and marker on a normal load.
- An explicit `false` remains false when the marker is absent.
- Read-only loading returns the effective default without writing a field or
  marker.
- Normal settings saves continue to mark the migration complete.
- Existing credential storage and migration tests remain green.

## Verification

```bash
fvm flutter test --no-pub \
  test/features/settings/data/settings_repository_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen --test \
  test/features/settings/data/settings_repository_test.dart
```

## Handoff Notes

- Summary: session-log default migration now distinguishes a missing legacy
  field from an explicit opt-out.
- Tests run: focused repository tests and the repository verification gate.
- Risks or follow-ups: SA-15 should make drift authoritative after verified
  Hive migration so deleted records cannot be resurrected.

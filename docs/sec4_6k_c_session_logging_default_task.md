# SEC4.6k-C Session Logging Default

Status: completed 2026-08-24.

## Task

- Goal: stop collecting sensitive LLM session content by default on new
  installations.
- User-visible behavior: a new installation starts with session logging off;
  existing installations retain their previous enabled or disabled behavior.
- Non-goals: deleting existing logs, changing the environment override, or
  changing the owner-only storage and diagnostic-redaction controls completed
  in SEC4.6k-A/B.

## Context

- Affected components: `AppSettings`, generated Freezed/JSON entities, and
  settings repository migration tests.
- Related finding: SA-22 in
  `docs/security_followup_review_2026-08-24.md`.
- Compatibility rule: legacy saved settings that predate the field continue to
  migrate to enabled, preserving the behavior users had before this change.

## Migration Contract

- No stored settings means session logging is disabled.
- A stored explicit `true` or `false` remains unchanged.
- A legacy stored payload without `enableLlmSessionLogs` retains the existing
  default-on migration and persists `true` on a normal load.
- Directly parsed file or QR imports without the field use the privacy-safe
  default off because they carry no explicit saved choice.
- Read-only loads apply the same effective legacy value without writing a
  payload or migration marker.
- `CAVERNO_SESSION_LOG_ENABLED` remains the explicit runtime override.

## Similar-Pattern Search

- Search terms: `enableLlmSessionLogs`, `DefaultOnMigration`,
  `writesEnabledFor`, and `CAVERNO_SESSION_LOG_ENABLED`.
- Files inspected: settings entity/repository, debug settings UI, chat/routine
  consumers, session log store, and focused settings tests.
- Follow-up found: none; this slice completes SA-22 and SEC4.6k.

## Acceptance Criteria

- Fresh settings default session logging to disabled.
- Explicit saved opt-in and opt-out values survive normal loads.
- Legacy missing-field payloads remain enabled and migrate durably.
- Missing-field imports outside the stored-settings migration default off.
- Read-only migration behavior and environment overrides remain unchanged.
- Generated entity files match the source annotation.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/settings/domain/entities/app_settings_test.dart \
  --test test/features/settings/data/settings_repository_test.dart \
  --test test/features/chat/data/datasources/llm_session_log_store_write_gate_test.dart
```

## Handoff Notes

- Summary: fresh settings now start with session logging disabled. Explicit
  stored opt-in/opt-out values and the legacy missing-field default-on migration
  retain their previous behavior.
- Tests run: all 67 focused entity, repository, and write-gate tests pass;
  `flutter analyze --no-pub` reports no issues.
- Coverage or low-coverage notes: the focused verification reports 31.41% line
  coverage across the selected root and workspace-package surface; the changed
  defaults and migration branches are directly asserted.
- Risks or follow-ups: legacy imports without an explicit field now choose the
  privacy-safe default off; runtime environment overrides are unchanged.
  SEC4.6k and SA-22 are complete; SEC4.5g/RC1 is the next follow-up queue item.

# SEC4.6b Secure Settings Credentials

Status: completed on 2026-08-22.

## Task

- Goal: remove settings credentials from normal preferences and migrate them to
  platform secure storage.
- User-visible behavior: existing credentials continue to load after upgrade,
  while normal settings persistence contains only opaque references.
- Non-goals: adding an encrypted include-secrets export flow or changing the
  default secret-free file and QR export behavior.

## Context

- Affected components: `SettingsRepository`, application and CLI bootstrap,
  and settings repository tests.
- Related finding: SA-11 in `docs/security_audit_2026-08-14.md`.
- Reference pattern: existing SSH and Remote Coding credential stores use
  `flutter_secure_storage` behind independently testable interfaces.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Store primary and saved-endpoint API keys, Google Chat webhook URLs,
  feedback auth tokens, MCP environment values, and external hook environment
  values in one versioned secure-storage payload.
- Persist opaque, generation-scoped references in SharedPreferences and hydrate
  them only in memory.
- Stage new secure values before switching the normal settings references, then
  remove superseded and orphaned values after the switch or next startup.
- Migrate legacy cleartext settings during application or CLI bootstrap and
  fail startup without rewriting normal settings if secure storage is
  unavailable.
- No generated files are required.
- Rollback unit: repository extraction, bootstrap initialization, migration
  tests, and this task documentation form one focused slice.

## Similar-Pattern Search

- Search terms: `SettingsRepository(`, `SettingsRepository.create`, `apiKey`,
  `WebhookUrl`, `AuthToken`, `mcpServers`, `externalToolHooks`, and `env`.
- Files inspected: application bootstrap, CLI bootstrap and read-only commands,
  settings providers, settings import/export services, and existing platform
  credential stores.
- Follow-up tasks found: an explicit encrypted include-secrets export remains
  in SEC4.6; external settings sync needs its own lifecycle review.

## Acceptance Criteria

- Normal preferences contain no supported settings credential values.
- Application and CLI startup migrate legacy cleartext credentials before use.
- Missing secure references hydrate to empty values rather than cleartext or a
  different credential.
- Interrupted saves cannot bind new settings to old credentials, and orphaned
  secure values are removed on the next startup.
- Reset clears both normal and secure settings.
- Secure-storage failures do not rewrite legacy cleartext settings.

## Verification

```bash
tool/codex_verify.sh --no-codegen
```

Focused verification:

```bash
fvm flutter test --no-pub \
  test/features/settings/data/settings_repository_test.dart \
  test/features/settings/data/settings_file_service_test.dart \
  test/features/settings/data/settings_qr_service_test.dart \
  test/features/settings/presentation/providers/settings_notifier_test.dart
fvm flutter analyze --no-pub
```

## Handoff Notes

- Summary: settings credentials now use platform secure storage with opaque
  normal-preference references, startup migration, safe save ordering, orphan
  cleanup, and reset coverage.
- Tests run: focused settings tests and static analysis passed. The full
  repository gate reached unrelated existing failures in the ChatNotifier file
  size ratchet, detached-turn tests using a configured live endpoint, and chat
  page scroll-follow tests.
- Risks or follow-ups: secure storage availability is now a startup dependency
  when credentials must be migrated. The encrypted include-secrets export is a
  separate SEC4.6 slice.

# SEC4.6f Drift Migration Authority

Status: completed on 2026-08-23.

## Task

- Goal: prevent deleted conversations or chat memory from reappearing through
  a stale Hive fallback after drift becomes authoritative.
- User-visible behavior: a pre-migration drift failure may still use Hive and
  retry later; a post-migration drift failure stops startup instead of exposing
  or mutating stale legacy data.
- Non-goals: deleting legacy Hive boxes, adding a recovery UI, changing the
  drift schema, or altering migration contents.

## Context

- Affected components: shared persistence bootstrap, GUI startup fallback, and
  persistence bootstrap tests.
- Related finding: SA-15 in `docs/security_audit_2026-08-14.md`.
- Reference behavior: the CLI already fails closed when shared persistence
  bootstrap fails.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Track authority across the whole bootstrap, including database opening,
  both migration markers, repository hydration, and cleanup.
- Once either migration was already complete or completes during the current
  bootstrap, wrap later failures in a typed authoritative-persistence error.
- Preserve the original cause, stack trace, and `StateError` compatibility for
  existing CLI diagnostics.
- Allow raw pre-migration failures to reach the GUI fallback so an interrupted
  first import can retry from the still-authoritative Hive source.
- Make GUI startup rethrow authoritative failures instead of installing mutable
  Hive-backed providers.
- No generated files or new dependencies are required.

## Similar-Pattern Search

- Search terms: `CavernoPersistenceBootstrap`, `falling back to Hive`,
  `f4_conversations_migrated_v1`, `f4_chat_memory_migrated_v1`, and
  `completed migrations do not require legacy Hive boxes`.
- Files inspected: GUI startup, shared bootstrap, CLI persistence adapter,
  conversation and chat-memory migration services, and focused tests.
- Follow-up tasks found: SA-17 Android backup exclusion is the next incomplete
  SEC4.6 slice. Legacy Hive deletion remains part of the wider SA-18 lifecycle
  cleanup rather than a prerequisite for fail-closed authority.

## Acceptance Criteria

- A failure before either migration completes remains eligible for legacy
  fallback and retry.
- A database-open failure with an existing marker is authoritative.
- A failure after only the first migration completes is authoritative.
- GUI startup never falls back to Hive for an authoritative failure.
- The database closes after post-open failures.
- CLI missing-box diagnostics retain their existing `StateError` contract.
- Successful migrations and isolated CLI data roots remain green.

## Verification

```bash
fvm flutter test --no-pub \
  test/features/chat/application/persistence/caverno_persistence_bootstrap_test.dart \
  test/features/terminal/application/caverno_cli_persistence_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen --test \
  test/features/chat/application/persistence/caverno_persistence_bootstrap_test.dart \
  --test test/features/terminal/application/caverno_cli_persistence_test.dart
```

## Handoff Notes

- Summary: drift migration authority now survives every later bootstrap
  failure, and GUI startup refuses stale Hive fallback once authority exists.
- Tests run: focused bootstrap and CLI persistence tests plus the repository
  verification gate.
- Risks or follow-ups: a post-migration database failure currently fails startup
  without a dedicated recovery screen. SA-17 should next exclude local stores,
  logs, and settings from Android cloud and device-transfer backup.

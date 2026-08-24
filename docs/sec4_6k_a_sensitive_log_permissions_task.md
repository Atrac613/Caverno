# SEC4.6k-A Sensitive Log Permissions

Status: completed 2026-08-24.

## Task

- Goal: prevent other local users from reading Caverno session and app logs.
- User-visible behavior: logging behavior and retention remain unchanged.
- Non-goals: structured MCP diagnostic redaction and the new-install session
  logging default, which remain separate SEC4.6k slices.

## Context

- Affected components: `AppLogFile`, `LlmSessionLogStore`, and the shared
  sensitive-file permission helper.
- Related finding: SA-22 in
  `docs/security_followup_review_2026-08-24.md`.
- Reference pattern: `ToolApprovalAuditLog` owner-only permission migration.

## Permission Contract

- The default `.caverno` root and each sensitive log directory use mode `0700`
  on POSIX platforms.
- New log files are created empty, changed to mode `0600`, and only then receive
  content.
- Existing current and rotated log files are migrated to mode `0600` before a
  new entry is appended.
- Explicit custom roots are hardened without changing their parent directory.
- Permission failures preserve the existing non-throwing log-sink behavior and
  do not fall back to an insecure write.

## Similar-Pattern Search

- Search terms: `SensitiveFilePermissions`, `writeAsString`, `FileMode.append`,
  `session_logs`, `app_logs`, and `approval_audit`.
- Files inspected: the two affected log writers, approval audit writer, shared
  permission helper, and focused writer tests.
- Follow-up found: structured MCP diagnostics and the session logging default
  remain in later SEC4.6k slices.

## Acceptance Criteria

- New app and session log files use mode `0600`.
- Existing current and rotated logs are migrated to mode `0600`.
- App, session workspace, and default Caverno root directories use mode `0700`.
- Content is appended only after the file permission change succeeds.
- An unusable or unsecurable destination does not make application logging
  throw and does not receive an insecure fallback write.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/core/utils/app_log_file_test.dart \
  --test test/features/chat/data/datasources/session_logging_chat_datasource_test.dart
```

## Handoff Notes

- Summary: app and session log writers now harden their sensitive directories,
  migrate existing current and rotated logs, and secure a newly created empty
  file before appending content.
- Tests run: all 31 focused tests pass; `flutter analyze --no-pub` reports no
  issues.
- Risks or follow-ups: POSIX permission enforcement uses the existing shared
  `chmod` helper. SEC4.6k-B must replace string-concatenated MCP diagnostics,
  redact session identifiers, and omit full response bodies by default.

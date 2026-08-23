# SEC4.6h Debug Log Redaction

Status: completed on 2026-08-23.

## Task

- Goal: prevent common credentials and private keys from crossing Caverno's
  debug console and app-log file boundaries.
- User-visible behavior: debug diagnostics remain available, but recognized
  secrets are replaced with stable redaction markers.
- Non-goals: suppressing all prompt or tool content, changing log retention,
  platform privacy declarations, or attachment deletion.

## Context

- Affected components: the shared debug logger, its direct console callers,
  its file sink, and focused regression tests.
- Related finding: SA-18 in `docs/security_audit_2026-08-14.md`.
- Reference pattern: `SensitiveDataRedactor` is the shared credential and
  private-key redaction boundary introduced for security diagnostics.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Redact before `debugPrint` so console and platform debug output are safe.
- Route direct application `debugPrint` call sites through the console-only
  redacting wrapper without adding file persistence to those messages.
- Redact again inside `AppLogFile.write` so direct sink callers cannot bypass
  the boundary.
- Preserve synchronous, flush-on-write diagnostics and existing retention.
- No generated files, migrations, or new dependencies are required.

## Similar-Pattern Search

- Search terms: `appLog`, `debugPrint`, `AppLogFile`, `writeAsStringSync`, and
  `SensitiveDataRedactor`.
- Files inspected: shared logger and file sink, every application `debugPrint`
  call site, session-log and approval-audit redaction, media-host logging tests,
  and the SA-18 audit finding.
- Follow-up tasks found: conversation-owned attachment deletion is the next
  bounded SA-18 lifecycle slice; platform privacy declarations remain open.

## Acceptance Criteria

- Debug console output redacts authorization values and API keys.
- Application debug console call sites use the redacting wrapper.
- App-log files redact authorization values, API keys, and private keys.
- Direct `AppLogFile` callers receive the same protection as `appLog` callers.
- Existing timestamp, durability, failure isolation, and retention behavior
  remains covered.

## Verification

```bash
fvm flutter test --no-pub test/core/utils/app_log_file_test.dart \
  test/core/utils/logger_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen --test test/core/utils/app_log_file_test.dart \
  --test test/core/utils/logger_test.dart
```

## Handoff Notes

- Summary: common credentials and private keys are redacted at both debug-log
  output boundaries, including direct file-sink writes.
- Tests run: focused logger/file-sink regressions, static analysis, and the
  repository verification gate.
- Risks or follow-ups: arbitrary prompt and tool content is intentionally not
  classified as a secret by this slice. Continue SA-18 with conversation-owned
  attachment deletion, then reconcile platform privacy declarations.

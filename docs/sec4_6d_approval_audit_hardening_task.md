# SEC4.6d Approval Audit Hardening

Status: completed on 2026-08-23.

## Task

- Goal: prevent nested tool arguments and permissive filesystem modes from
  exposing secrets through the always-on approval audit trail.
- User-visible behavior: none; automated approval evidence remains available
  with secrets removed recursively.
- Non-goals: changing audit retention, recording manual approvals, or hardening
  session-log and app-log leaf paths tracked by SA-18.

## Context

- Affected components: shared structured-data redaction and the approval audit
  log writer.
- Related finding: SA-13 in `docs/security_audit_2026-08-14.md`.
- Reference implementation: the recursive redaction previously embedded in
  `LlmSessionLogStore`.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Extract recursive key and string redaction into a core security utility so
  session logs and approval audits use one implementation.
- Preserve approval-audit-specific bulk argument keys as additional sensitive
  keys at every map depth.
- Redact recognized credentials and PEM private keys embedded in otherwise
  non-sensitive strings.
- Before appending, harden the Caverno root and approval-audit directory to
  `0700`, migrate existing day files to `0600`, and create each new day file
  before writing so its mode is corrected while empty.
- Apply explicit POSIX modes on macOS, Linux, and Android. Other platforms keep
  their native app-container or ACL protections.
- No generated files or new dependencies are required.

## Similar-Pattern Search

- Search terms: `redactSensitiveValue`, `redactJson`, `chmod`, `FileStat`, and
  `approval_audit`.
- Files inspected: LLM session logging, terminal output redaction, Remote Coding
  relay redaction, approval-audit storage, and their focused tests.
- Follow-up tasks found: SA-14 is the next SEC4.6 slice. SA-18 retains the wider
  session-log, app-log, attachment, and privacy-declaration lifecycle review.

## Acceptance Criteria

- Sensitive keys are redacted inside nested maps and lists.
- PEM private keys and recognized credential patterns are redacted even under
  non-sensitive keys.
- Non-sensitive approval metadata remains available.
- Existing and new approval-audit day files use `0600` and their parent paths
  use `0700` on supported POSIX targets.
- A permission-hardening failure prevents the audit entry from being appended
  and is reported through the existing application log boundary.
- Existing session-log redaction behavior remains covered by regression tests.

## Verification

```bash
fvm flutter test --no-pub \
  test/core/services/tool_approval_audit_log_test.dart \
  test/features/chat/data/datasources/session_logging_chat_datasource_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen --test \
  test/core/services/tool_approval_audit_log_test.dart
```

## Handoff Notes

- Summary: approval arguments now use the shared recursive redactor, and the
  audit writer migrates and enforces owner-only POSIX modes before content is
  appended.
- Tests run: focused audit and session-log regressions plus the repository
  verification gate.
- Risks or follow-ups: SA-14 must preserve an explicit session-log opt-out
  during settings migration. SA-18 owns direct mode hardening for other
  sensitive log directories and files.

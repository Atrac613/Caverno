# SEC4.5a SSH Known-Host Verification Task

Status: complete.

## Task

- Goal: verify SSH host identity before any credential is sent. Persist
  known-host records by host and port, confirm a SHA-256 fingerprint on first
  use, fail closed on mismatch, and replace a stored key only through an
  explicit rotation confirmation.
- User-visible behavior: a previously trusted host reconnects without an extra
  prompt. An unknown host shows its fingerprint and waits for Trust. A changed
  host key shows the stored and presented fingerprints and waits for Replace.
  Cancel leaves the stored identity unchanged and does not authenticate.
- Non-goals: Remote Coding plaintext containment (SEC4.5b), pinned WSS
  (SEC4.5c), short-lived session tokens (SEC4.5d), importing `~/.ssh/known_hosts`,
  and changing the existing SSH session-ownership fingerprint
  (`ssh-session:N`), which is a generation label rather than a host key.

## Context

- Affected components:
  - `SshClientConnector` handshake;
  - `SshService` production wiring;
  - SSH connect tool dispatch after credential approval;
  - a first-use / rotation confirmation sheet.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-05 and P0-5;
  - `docs/local_llm_agent_roadmap.md` SEC4.5a.
- Release gate: P0. SA-05 remains open until mismatch fails before
  authentication and the confirmation flow is covered by tests.

## Implementation Slices

1. Add a host:port known-host store and a pure verifier that can only match,
   report unknown, or report mismatch.
2. Require `onVerifyHostKey` on every production `SSHClient`. Map a rejected
   handshake to a typed unknown or mismatch exception. Never auto-accept.
3. After credential approval, intercept those exceptions, prompt the user,
   persist only after Trust/Replace, and retry the handshake once.
4. Keep the session-ownership fingerprint distinct from the host-key
   fingerprint.

## Implementation Notes

- Preferred approach: dartssh2 already hashes the host key as OpenSSH-style
  `SHA256:...` before authentication. Verify that value, then persist it.
- Constraints:
  - Fail closed when the verifier or store is missing.
  - Do not send a password or private-key proof until the callback returns true.
  - Do not reuse `SshSessionInfo.fingerprint` for known-host identity.
  - Full-access / cached SSH connect approval does not skip host-key prompts.
- Generated files needed: None.
- Migration: existing users have no stored host keys; the first reconnect after
  this slice is a first-use confirmation.

## Similar-Pattern Search

- Search terms: `onVerifyHostKey`, `SSHClient(`, `SshClientConnector.connect`,
  `ssh-session:`, `fingerprint`, `FlutterSecureStorage`.
- Files or modules inspected:
  - `ssh_client_connector.dart`
  - `ssh_service.dart`
  - `ssh_credentials_manager.dart`
  - `ssh_tool_handler.dart`
  - `chat_ssh_tool_runtime.dart`
- Follow-up tasks found: SEC4.5b must prove a release build cannot bind a
  plaintext non-loopback Remote Coding listener.

## Acceptance Criteria

- Required behavior:
  - A stored host:port identity that matches type and fingerprint connects.
  - An unknown host is rejected until the user confirms the SHA-256 fingerprint.
  - A mismatched host is rejected until the user explicitly replaces the record.
- Edge cases:
  - Empty key type or fingerprint is rejected.
  - IPv6 hosts compare without wrapping brackets.
  - A second concurrent connect to the same owner still uses session ownership
    rules; host-key identity stays on host:port.
- Failure paths:
  - User cancel does not persist and does not authenticate.
  - A rejected host key never reaches `SSHClient` password or identity auth.
- Platform expectations: confirmation copy matches the existing SSH sheets
  (English UI strings).

## Verification

```bash
fvm flutter test test/core/services/ssh_host_key_verifier_test.dart
fvm flutter test test/core/services/ssh_known_hosts_store_test.dart
fvm flutter test test/core/services/ssh_client_connector_test.dart
fvm flutter test test/core/services/ssh_service_test.dart
fvm flutter test test/features/chat/presentation/providers/ssh_host_key_prompting_transport_test.dart
fvm flutter test test/features/chat/presentation/widgets/approval/ssh_host_key_approval_sheet_test.dart
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: Production SSH handshakes now require host-key verification. Unknown
  hosts prompt for Trust with the SHA-256 fingerprint; mismatches prompt for
  Replace. Credentials are not sent until the callback accepts, and the stored
  identity is host:port rather than the session-ownership label.
- Focused verification passed:
  - `ssh_host_key_verifier_test.dart`
  - `ssh_known_hosts_store_test.dart`
  - `ssh_client_connector_test.dart`
  - `ssh_service_test.dart`
  - `ssh_host_key_prompting_transport_test.dart`
  - `chat_ssh_tool_runtime_test.dart`
  - `ssh_host_key_approval_sheet_test.dart`
  - `file_size_ratchet_test.dart`
- Risks or follow-ups: SEC4.5b must prove a release build cannot bind a
  plaintext non-loopback Remote Coding listener. Host-key prompts are not
  stashed in thread-scoped ChatState; switching threads during the prompt can
  drop the sheet while the connect call still waits.

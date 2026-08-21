# SEC4.5c Pinned Remote Coding WSS Transport Task

Status: complete.

## Task

- Goal: give Remote Coding pinned confidential transport and reject plaintext
  downgrade before a pairing secret or device token is sent. A release build
  may bind a non-loopback listener only when that listener is TLS.
- User-visible behavior: pairing QR codes carry a `wss` endpoint and a
  certificate pin. The mobile client connects with `wss://` and sends
  credentials only after the pin matches. A `ws://` URL or missing pin fails
  before `auth`. Debug and release hosts both speak WSS.
- Non-goals: short-lived channel-bound session tokens (SEC4.5d);
  connection/frame/rate limits (SEC4.5e); HTTPS for LLM endpoints (SEC4.5f);
  changing the notification relay HTTPS contract.

## Context

- Affected components:
  - pairing payload and saved host records;
  - Remote Coding listen policy;
  - desktop `HttpServer.bindSecure` start;
  - mobile WebSocket connect/auth.
- Related docs:
  - `docs/sec4_5b_remote_coding_plaintext_containment_task.md`;
  - `docs/remote_coding_p0_release_gate.md`;
  - `docs/remote_coding_p1_release_gate.md`;
  - `docs/security_audit_2026-08-14.md` SA-06.
- Release gate: P1. Required before enabling Remote Coding on a non-loopback
  interface in a release artifact.

## Implementation Slices

1. Add a transport policy that builds `wss://` URLs, matches a SHA-256
   certificate pin, and throws on plaintext downgrade.
2. Generate a self-signed host identity, persist it, and bind through
   `HttpServer.bindSecure`. Allow LAN binds in release only when confidential.
3. Put the pin on new pairing QR codes and saved hosts. The client refuses
   `ws://` and pin-less reconnects before sending `auth`.

## Implementation Notes

- Preferred approach: pin the self-signed certificate presented by
  `bindSecure`. Do not add a public CA. `badCertificateCallback` may accept
  the cert only when the pin matches.
- Constraints:
  - Do not grow `remote_coding_server_notifier.dart` or
    `remote_coding_client_notifier.dart` more than a thin call-site.
  - Keep SEC4.5b: plaintext `HttpServer.bind` of a non-loopback address still
    throws in a product isolate.
  - Do not default a missing pin to `ws://` for sending secrets or tokens.
- Generated files needed: None.
- Migration: previously paired phones must scan a fresh QR so the saved host
  carries a pin.

## Similar-Pattern Search

- Search terms: `ws://`, `WebSocket.connect`, `HttpServer.bind`,
  `RemoteCodingListenPolicy`, `websocketUrl`.
- Files or modules inspected:
  - `remote_coding_listen_policy.dart`
  - `remote_coding_models.dart`
  - `remote_coding_server_notifier.dart`
  - `remote_coding_client_notifier.dart`
- Follow-up tasks found: SEC4.5d short-lived session authorization; SEC4.5e
  connection/frame/rate limits.

## Acceptance Criteria

- Required behavior:
  - New pairing payloads encode `transport=wss` and `certificatePin`.
  - A matching pin connects; credentials are sent only on `wss://`.
- Edge cases:
  - Missing pin, `ws://` URL, and pin mismatch fail before `auth`.
  - Release plaintext LAN bind still throws.
  - Release confidential LAN bind is allowed.
- Failure paths:
  - Zero pairing secrets or bearer tokens written to a `ws://` socket.

## Verification

```bash
fvm flutter test test/features/remote_coding/domain/remote_coding_transport_policy_test.dart
fvm flutter test test/features/remote_coding/domain/remote_coding_listen_policy_test.dart
fvm flutter test test/features/remote_coding/data/remote_coding_tls_identity_test.dart
fvm flutter test test/features/remote_coding/domain/remote_coding_models_test.dart
fvm flutter test test/features/remote_coding/presentation/remote_coding_client_state_test.dart
fvm flutter test test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
fvm dart run --define=dart.vm.product=true tool/remote_coding_plaintext_lan_smoke.dart
```

## Handoff Notes

- Summary: Remote Coding hosts bind WSS with a persisted self-signed identity.
  Pairing QR codes carry `transport=wss` and `certificatePin`. The client
  connects through a pin-matching `badCertificateCallback` and refuses `ws://`
  or a missing pin before `auth`. Release plaintext LAN binds still throw;
  confidential LAN binds are allowed.
- Focused verification passed:
  - `remote_coding_transport_policy_test.dart`
  - `remote_coding_listen_policy_test.dart`
  - `remote_coding_tls_identity_test.dart`
  - `remote_coding_models_test.dart`
  - `remote_coding_client_state_test.dart`
  - `remote_coding_server_notifier_test.dart`
  - product-isolate plaintext LAN smoke
- Full suite: 8082 passed.
- Risks or follow-ups: previously paired phones must scan a fresh QR.
  SEC4.5d short-lived session authorization; SEC4.5e connection/frame/rate
  limits.

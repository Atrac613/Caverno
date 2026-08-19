# SEC4.5b Remote Coding Plaintext Containment Task

Status: complete.

## Task

- Goal: prove that a release build cannot start a plaintext non-loopback
  Remote Coding listener. Bind through one policy that fails closed in product
  mode, extend the P0 gate with a required `transportContainment` result, and
  run a product-isolate smoke that attempts the bind.
- User-visible behavior: debug and profile desktop hosts can still listen on
  all IPv4 interfaces for LAN pairing. A release build refuses to start the
  host and records that a plaintext LAN listener is forbidden. Loopback
  plaintext remains allowed if an explicit loopback address is requested.
- Non-goals: pinned WSS and downgrade rejection (SEC4.5c), short-lived session
  tokens (SEC4.5d), connection/frame/rate limits (SEC4.5e), HTTPS for LLM
  endpoints (SEC4.5f), and treating a default-off UI setting as evidence.

## Context

- Affected components:
  - Remote Coding server bind in `RemoteCodingServerNotifier`;
  - P0 release gate schema and static checks;
  - a product-isolate bind smoke.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-06 and P0-5;
  - `docs/remote_coding_p0_release_gate.md`;
  - `docs/local_llm_agent_roadmap.md` SEC4.5b.
- Release gate: P0. Documentation or a default-off control is not evidence.

## Implementation Slices

1. Add a pure listen policy that throws before bind when the current build is
   a product isolate and the requested address is not loopback.
2. Make the production server bind only through that policy.
3. Add a required `transportContainment` result to the P0 gate schema.
4. Run a `dart.vm.product=true` smoke that proves `HttpServer.bind` is never
   reached for `InternetAddress.anyIPv4`.

## Implementation Notes

- Preferred approach: `bool.fromEnvironment('dart.vm.product')` is the same
  flag Flutter uses for `kReleaseMode`, so a Dart product isolate is valid
  release-mode evidence without a signed app artifact.
- Constraints:
  - Fail closed in product mode; do not bind and then filter clients.
  - Keep debug LAN pairing on `anyIPv4`.
  - Do not silently disable stored `enabled` settings; report the error.
- Generated files needed: None.
- Migration: users who enabled Remote Coding in debug will see a start error
  in a release build until SEC4.5c lands.

## Similar-Pattern Search

- Search terms: `HttpServer.bind`, `InternetAddress.anyIPv4`, `ws://`,
  `kReleaseMode`, `dart.vm.product`, `transportContainment`.
- Files or modules inspected:
  - `remote_coding_server_notifier.dart`
  - `remote_coding_models.dart`
  - `remote_coding_p0_release_gate.dart`
  - `html_preview_static_server.dart`
- Follow-up tasks found: SEC4.5c must add pinned confidential transport before
  Remote Coding can be enabled in a release artifact.

## Acceptance Criteria

- Required behavior:
  - Debug policy allows `InternetAddress.anyIPv4`.
  - Product policy throws before bind for any non-loopback address.
  - Production `_startServer` has no direct `HttpServer.bind(InternetAddress.anyIPv4`.
  - The P0 gate JSON includes `transportContainment` and blocks when the
    production bind path is missing.
- Edge cases:
  - Explicit loopback bind is allowed in product mode.
  - Running the smoke without `dart.vm.product=true` is not containment
    evidence and must exit non-zero.
- Failure paths:
  - A refused start leaves `isRunning` false and does not listen on LAN.
- Platform expectations: error copy is English.

## Verification

```bash
fvm flutter test test/features/remote_coding/domain/remote_coding_listen_policy_test.dart
fvm flutter test test/integration_support/remote_coding_p0_release_gate_test.dart
fvm dart run --define=dart.vm.product=true tool/remote_coding_plaintext_lan_smoke.dart
fvm flutter test test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
```

## Handoff Notes

- Summary: Production Remote Coding start binds only through
  `RemoteCodingListenPolicy.current()`. Product/release builds throw before
  `HttpServer.bind` for any non-loopback address. The P0 gate schema v2 requires
  `transportContainment`, and the product-isolate smoke prints
  `plaintext_non_loopback_listener_can_start=false`.
- Focused verification passed:
  - `remote_coding_listen_policy_test.dart`
  - `remote_coding_p0_release_gate_test.dart` (including product-isolate smoke)
  - `remote_coding_server_notifier_test.dart`
- Risks or follow-ups: SEC4.5c remains required before enabling Remote Coding
  on a non-loopback interface in a release build.

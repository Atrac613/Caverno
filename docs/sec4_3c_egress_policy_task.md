# SEC4.3c Egress Destination Policy Task

Status: completed on 2026-08-14.

## Task

- Goal: enforce one fail-closed destination, DNS, peer, redirect, and
  credential policy for every model-triggered built-in HTTP request and browser
  navigation.
- User-visible behavior: public HTTP(S) destinations remain available through
  the built-in HTTP tools, while unsafe schemes, local or reserved
  destinations, unsafe DNS answers, peer mismatches, and unsafe redirects fail
  before protected data can be reached. External WebView navigation remains
  disabled until its connection peer can be enforced.
- Non-goals: response byte and total-time ceilings (SEC4.3d), user-configurable
  private-network grants, remote MCP transport, and general LLM endpoint
  validation.

## Context

- Affected components:
  - `NetworkHttpTools` and its injected `HttpClient` boundary;
  - the browser session service and WebView navigation delegate;
  - a shared egress destination policy under `lib/core/security/`.
- Related finding: `docs/security_audit_2026-08-14.md` SA-03.
- Related roadmap slice: SEC4.3c.
- Release gate: SEC4.3c is P0 and remains release-blocking until both HTTP and
  browser traffic fail closed at the connection boundary.

## Pre-Implementation Boundary Inventory

- `NetworkHttpTools` passes the model-supplied URI directly to `HttpClient` and
  enables automatic redirects. It does not inspect DNS answers or the connected
  peer before sending headers or a body.
- The built-in browser passes URLs directly to `flutter_inappwebview`. Navigation
  callbacks can reject a URL, but the native WebView API does not expose a
  portable connection peer or a way to pin the approved DNS answer.
- A browser-only DNS preflight would remain vulnerable to DNS rebinding because
  the WebView resolves the hostname again after the check. Browser navigation
  must therefore remain fail closed until Caverno mediates it through a transport
  that pins or verifies the peer.
- `about:blank` is used only to initialize the embedded WebView. It is not a
  model-authorized destination and must not broaden the HTTP(S)-only policy.

## Implementation Tasks

1. **SEC4.3c-1 — Pure destination policy.** Parse and normalize HTTP(S) URIs,
   reject embedded credentials and unsafe host forms, classify IPv4 and IPv6
   addresses, require every DNS answer to be safe, and compare the approved
   address with the actual peer.
2. **SEC4.3c-2 — Pinned HTTP transport.** Resolve once, reject mixed safe/unsafe
   answer sets, pin an approved address through `HttpClient.connectionFactory`,
   preserve hostname-based TLS verification, and fail before request headers or
   bodies are written when validation fails.
3. **SEC4.3c-3 — Manual redirects.** Disable automatic redirects, validate and
   pin every hop, enforce the configured redirect limit, apply standard method
   rewriting, and strip authorization, cookies, and proxy credentials whenever
   the origin changes.
4. **SEC4.3c-4 — Browser containment.** Route every main-frame model navigation
   through the shared URI policy and keep external browser navigation disabled
   unless a mediated connection can prove the peer. Reject link, script, form,
   history, reload, and redirect navigation through the same boundary.

## Implementation Notes

- Treat DNS as an all-answer decision: one private, loopback, link-local,
  multicast, unspecified, documentation, benchmarking, reserved, or metadata
  answer rejects the destination.
- Treat IPv4-mapped IPv6 addresses according to their embedded IPv4 address.
- Do not rely on host-name deny lists as the primary control. Resolve the host,
  validate all answers, and pin the chosen address to the connection.
- Preserve the original hostname in the URI so TLS certificate and HTTP host
  checks remain bound to the requested origin.
- Redirect handling must occur before headers or a body are sent to the next
  hop. Sensitive headers are never forwarded across origins.
- Keep browser initialization internal. A WebView callback alone is not peer
  verification and must not be described as closing the release gate.
- Generated files needed: none.

## Similar-Pattern Search

- Search terms: `HttpClient`, `connectionFactory`, `followRedirects`,
  `InternetAddress.lookup`, `loadUrl`, `shouldOverrideUrlLoading`, `WebUri`,
  `URLRequest`, and `currentUrl`.
- Files or modules inspected: network HTTP/DNS/route tools, browser session and
  widget callbacks, routine computer-use URL checks, remote MCP connections,
  feedback submission, and local-stack endpoint validation.
- Follow-up tasks found: SEC4.3d must replace complete response buffering with
  bounded streaming and a total deadline. Other application-owned HTTP clients
  need separate threat-model review before this policy is broadened beyond
  model-triggered built-in HTTP/browser tools.

## Acceptance Criteria

- Only absolute HTTP(S) URIs with a non-empty host and no embedded credentials
  can reach destination resolution.
- Literal and resolved IPv4/IPv6 tests cover loopback, private/ULA, link-local,
  multicast, unspecified, mapped IPv4, metadata, documentation, benchmarking,
  reserved, public, mixed-answer, and empty-answer cases.
- A DNS peer mismatch fails before request data is sent. Tests prove the
  connection is made to the pinned address while TLS and the Host header retain
  the original hostname.
- Every redirect repeats URI, DNS-answer, and connection enforcement. Redirects
  to unsafe destinations fail before the next connection.
- Authorization, cookie, and proxy-authorization headers are stripped on
  cross-origin redirects and preserved only for the same origin.
- Every model-triggered browser navigation remains blocked unless the same peer
  invariant can be enforced. Unsafe schemes cannot be loaded by the WebView.
- Existing HTTP result envelopes and approved mutation behavior remain
  compatible for successful requests.

## Verification

```bash
fvm flutter test test/core/security/egress_destination_policy_test.dart
fvm flutter test test/features/chat/data/datasources/network_http_tools_test.dart
fvm flutter test test/core/services/browser_session_service_test.dart
fvm flutter test test/features/chat/data/datasources/built_in_browser_tool_handler_test.dart
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "browser"
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Do not mark SA-03 closed after SEC4.3c. SEC4.3d remains required to bound
  response bytes and total request time.
- Do not re-enable external WebView navigation based only on a DNS preflight.
  The release gate requires connection pinning or observed-peer verification.
- Verification passed:
  - 22 combined destination-policy and pinned-HTTP tests;
  - 17 combined browser-session and browser-handler tests;
  - 6 ChatNotifier browser-path tests;
  - the built-in network-handler regression suite;
  - full `fvm flutter analyze`;
  - `tool/codex_verify.sh --no-codegen`, including all workspace package and
    Flutter test suites.

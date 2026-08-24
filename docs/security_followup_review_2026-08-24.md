# Caverno Security Follow-Up Review (2026-08-24)

Status: High severity remediation complete; defense-in-depth queue open.

Reviewed revision: `a3d35fc9e592`.

## Decision

SA-19 and SA-20 were remediated on 2026-08-24. SA-21 through SA-23 remain
independent defense-in-depth slices and must not be folded into either High
severity fix.

This review extends the point-in-time audit in
`docs/security_audit_2026-08-14.md`. It does not renumber or rewrite that
audit's original findings.

## Scope And Method

The review traced injection, authentication and authorization, deserialization,
and sensitive-data paths through:

- local foreground and background command execution;
- HTML Preview file serving and WebView navigation;
- HTTP and stdio MCP response parsing plus settings QR import;
- LLM session logs and debug app logs; and
- authenticated Remote Coding approval and question resolution.

The source review was followed by 49 focused Flutter tests covering the current
local-command guard, HTML Preview server, browser navigation, MCP client, and
Remote Coding server. Those tests passed, but none exercised the adversarial
cases listed below. No destructive exploit or real credential capture was
performed.

## Findings Summary

| ID | Severity | Evidence | Finding | Roadmap slice |
|---|---|---|---|---|
| SA-19 | High | Confirmed source path; activation depends on Full Access or approval | Opaque native-shell commands can compute an out-of-project write target after the lexical fence | SEC4.4g |
| SA-20 | High | Confirmed source path | Active HTML Preview content can read served project files and use unrestricted subresource egress | SEC4.3e |
| SA-21 | Medium | Confirmed source path | MCP HTTP, MCP stdio, and compressed QR inputs lack complete pre-parse resource limits | SEC4.3f |
| SA-22 | Medium | Confirmed source path and local permission inspection | Sensitive session and debug logs are created without owner-only modes, while string logging can bypass structured redaction | SEC4.6k |
| SA-23 | Low | Confirmed authorization check gap; identifier disclosure was not found | Remote Coding resolves pending interactions by ID without rechecking origin or device ownership | SEC4.5g / RC1 |

No unsafe object-instantiation primitive was found. The deserialization risk in
SA-21 is resource exhaustion rather than arbitrary code execution.

## SA-19: Opaque Shell Project-Containment Bypass

Preconditions:

- a coding project is selected;
- the model or an authenticated Remote Coding client supplies a native-shell
  command; and
- Full Access, auto-review, or an explicit approval permits execution.

Evidence:

- `lib/features/chat/data/datasources/local_command_mutation_guard.dart:45-110`
  authorizes only candidates that
  `lib/features/chat/data/datasources/local_command_mutation_guard.dart:251-267`
  can recognize as `~`, `..`, or absolute paths;
- `lib/features/chat/data/datasources/local_shell_tools.dart:192-208` forwards
  every non-internal command unchanged to `sh -c` or `cmd /C`; and
- `lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart:373-383`
  marks execution as Full Access eligible while requiring a special manual
  decision only for paths the lexical scan found.

An interpreter, environment expansion, or command substitution can construct an
external target without placing that target in the scanned command text. This
breaks the selected-project boundary independently of the earlier standalone
shell-separator fix.

Minimal production patch:

1. Classify every native-shell command as either structurally modeled or opaque.
2. When a project root exists, route opaque commands through a distinct
   host-write capability that requires fresh, non-cacheable manual approval.
3. Evaluate that requirement before saved approvals, auto-review, and Full
   Access.
4. Apply the same boundary to foreground execution and `process_start`.
5. Keep OS-level filesystem sandboxing as the path to enforce containment after
   approval; do not claim opaque commands are project-contained without it.

Exit evidence:

- computed interpreter paths, environment expansion, command substitution, and
  runtime-created symlink escapes cannot use Full Access or cached approval;
- denial causes zero target process starts; and
- in-project structured commands retain their existing behavior.

## SA-20: HTML Preview Active-Content Exfiltration

Preconditions:

- the user opens an HTML Preview for a project containing malicious or
  model-generated active content.

Evidence:

- `lib/features/chat/domain/services/html_preview_static_server.dart:63-91`
  serves files below the project root while
  `lib/features/chat/domain/services/html_preview_static_server.dart:113-153`
  excludes only selected path and key patterns, not all non-preview files;
- `lib/features/chat/presentation/pages/chat_page_browser_builders.dart:405-430`
  enables JavaScript and installs a navigation callback; and
- `lib/core/services/browser_session_service.dart:270-309` controls navigation
  destinations but does not constrain fetch, WebSocket, image, form, script, or
  other subresource egress.

Same-origin JavaScript can read a predictable project file through the loopback
server and send the content to an external destination.

Minimal production patch:

1. Serve only an explicit preview entry directory and declared web assets.
2. Add a response Content Security Policy with `connect-src 'none'`, external
   images/scripts/fonts disabled, `form-action 'none'`, `frame-src 'none'`,
   `object-src 'none'`, and `base-uri 'none'`.
3. Add `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, and
   `Cache-Control: no-store`.
4. Keep top-level navigation rejection and add platform-supported subresource
   request interception as defense in depth.

Exit evidence:

- malicious fetch, beacon, form, WebSocket, iframe, and external-resource cases
  cannot cross the preview origin;
- ordinary same-origin preview assets still load; and
- source, credential, and configuration files outside the declared preview
  surface return `404`.

## SA-21: Unbounded MCP And QR Deserialization

Evidence:

- `lib/features/chat/data/datasources/mcp_client.dart:249-269` uses `http.post`,
  buffers `bodyBytes`, and only then decodes the response, while
  `lib/features/chat/data/datasources/mcp_client.dart:279-306` scans and decodes
  every extracted JSON document;
- `lib/features/chat/data/datasources/mcp_stdio_client.dart:66-78` places an
  unbounded byte stream through `LineSplitter` before
  `lib/features/chat/data/datasources/mcp_stdio_client.dart:161-177` calls
  `jsonDecode`; and
- `lib/features/settings/data/settings_qr_service.dart:25-31` expands gzip input
  before enforcing a decoded-size limit.

A malicious or compromised configured endpoint can exhaust memory with a large
or never-terminated response. A compressed settings payload can consume
disproportionate memory before schema validation.

Minimal production patch:

1. Reuse the SEC4.3d streaming pattern with a 1 MiB MCP wire-byte ceiling,
   content-length precheck, total deadline, and idle timeout.
2. Terminate a stdio MCP server when one response line exceeds the configured
   limit; bound stderr diagnostics as well.
3. Bound the number of extracted JSON documents and aggregate tool-content
   length.
4. Enforce compressed-input and decompressed-output limits during QR decoding,
   before JSON parsing.

Exit evidence must cover declared-length, chunked, never-newline, excessive
JSON-document, and compression-expansion cases.

Remediation status (partially completed 2026-08-24): SEC4.3f-A replaces
body-buffering MCP HTTP requests with bounded stream consumption. It rejects a
declared or actual response over 1 MiB and enforces total and between-chunk idle
deadlines before UTF-8 or JSON decoding. Declared-length, chunked, stalled-body,
and existing transport compatibility tests pass. SEC4.3f-B adds a 1 MiB
pre-newline stdout/stderr ceiling that terminates the child on violation, caps
HTTP/SSE responses at 32 JSON documents, and caps returned tool text at 524,288
characters across HTTP and stdio. Never-newline, stderr, plain/SSE
document-count, exact-boundary, and aggregate-content tests pass. SA-21 remains
open only for SEC4.3f-C settings QR compressed-input and expansion limits.

## SA-22: Sensitive Diagnostic Storage

Evidence:

- `lib/features/settings/domain/entities/app_settings.dart:982` defaults LLM
  session logging to enabled, while
  `lib/features/chat/data/datasources/llm_session_log_store.dart:687-717` and
  `lib/features/chat/data/datasources/llm_session_log_store.dart:758-809`
  persist message content, tool arguments, and tool results;
- `lib/features/chat/data/datasources/llm_session_log_store.dart:666-682` and
  `lib/core/utils/app_log_file.dart:55-80` create directories and append files
  without applying `SensitiveFilePermissions`;
- a local inspection found 877 session-log files and eight app-log files at
  mode `0644`, with their log directories at `0755`; and
- `lib/features/chat/data/datasources/mcp_client.dart:79-92`,
  `lib/features/chat/data/datasources/mcp_client.dart:193-214`, and
  `lib/features/chat/data/datasources/mcp_client.dart:304-306` interpolate header
  maps, session identifiers, arguments, and response bodies into strings before
  the structured redactor can inspect keys.

Minimal production patch:

1. Harden the Caverno root and both log directories to `0700` before file
   creation.
2. Create empty current files, migrate current and rotated files to `0600`, and
   only then append content.
3. Replace string-concatenated structured diagnostics with a helper that parses
   and recursively redacts structured values.
4. Treat MCP session identifiers as sensitive and omit full response bodies by
   default.
5. Default session logging off for new installations while preserving an
   explicit existing user choice.

Exit evidence must cover new files, migrated files, rotation, permission
failure, nested secrets, MCP headers, and JSON embedded in diagnostic strings.

## SA-23: Remote Interaction Resolution Ownership

Evidence:

- `lib/features/remote_coding/presentation/remote_coding_server_notifier.dart:1121-1188`
  publishes only remote-origin pending approvals and questions; but
- `lib/features/remote_coding/presentation/remote_coding_server_notifier.dart:966-1025`
  accepts an authenticated client's identifier and resolves the matching
  pending object without rechecking its origin or initiating device.

UUID identifiers and the absence of a normal desktop-origin disclosure path
reduce exploitability. Authorization must nevertheless be enforced at the
mutation boundary rather than relying on identifier secrecy.

Minimal production patch:

1. Reject resolution unless the current pending object has remote origin.
2. If paired devices are separate principals, persist the initiating
   `deviceId` with the pending interaction and require an exact match.
3. Return the existing generic not-found error for authorization failures.

Exit evidence must cover desktop-origin rejection, stale identifiers, revoked
devices, reconnects, and the documented same-device or cross-device policy.

## Roadmap Order

| Order | Slice | Status | Release role |
|---|---|---|---|
| 1 | SEC4.4g opaque local-command authority | done 2026-08-24 | Closed SA-19 for unrestricted local commands |
| 2 | SEC4.3e HTML Preview active-content containment | done 2026-08-24 | Closed SA-20 for HTML Preview |
| 3 | SEC4.3f application-owned deserialization limits | current; MCP HTTP/stdio and JSON/content limits done 2026-08-24 | Next: settings QR compressed-input and expansion bounds |
| 4 | SEC4.6k sensitive diagnostic storage | later | Local data protection |
| 5 | SEC4.5g / RC1 remote interaction ownership | later | Authorization defense in depth |

Create one task document from `docs/codex_task_template.md` per slice. Do not
combine the two High severity fixes or mix any of these slices with remaining
SEC4.7 supply-chain work.

SEC4.4g remediation requires every native-shell foreground command,
`background:true` command, and `process_start` to obtain fresh, non-cacheable
`opaque_host_write` approval when a project is selected. Literal outside paths
retain their more specific decision. Bounded internal argv reads retain their
fast path. This closes SA-19.

SEC4.3e remediation binds each preview to its selected entry directory and
browser-consumable asset types after canonical symlink resolution. Restrictive
CSP and response headers disable connect, form, frame, object, worker, manifest,
referrer, cache, and DNS-prefetch channels; platform-reported WebView requests
outside the active preview origin are rejected as defense in depth. This closes
SA-20.

## Verification Baseline

The follow-up review ran:

```bash
fvm flutter test --no-pub \
  test/features/chat/data/datasources/local_command_mutation_guard_test.dart \
  test/features/chat/domain/services/html_preview_static_server_test.dart \
  test/core/services/browser_session_service_test.dart \
  test/features/chat/data/datasources/mcp_client_test.dart \
  test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
```

Result: 49 tests passed. Add the adversarial regressions above before using that
suite as closure evidence.

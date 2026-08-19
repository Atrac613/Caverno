# Caverno Security Audit (2026-08-14)

## Status

- Decision: **No-Go for a release that exposes the affected execution paths**.
- Audited revision: `50c3fdd330cb3b0609fcbfe0d635e9a5d01aba96`.
- Audit date: 2026-08-14.
- Finding state: all findings below are `open` unless explicitly marked
  otherwise.
- Roadmap owner: `SEC4`, with classifier corrections in `SEC1`, mandatory taint
  enforcement in `SEC2`, and authenticated Remote Coding transport in `RC1`.

This is a point-in-time source and configuration audit. Keep finding IDs stable
when findings are fixed, accepted, or invalidated; append closure evidence
instead of renumbering or deleting history.

## Executive Decision

The audit confirmed one critical approval-boundary bypass, six high-severity
security gaps, and several medium-severity data-protection, availability, and
release-pipeline risks. The critical path allows a model-supplied command that
is labelled read-only to execute arbitrary local code without the approval
surface that is intended to protect shell execution.

The immediate release blockers are:

1. approval-free commands can reach a native shell (`sh -c`, `cmd /C`, or a
   background-process equivalent) through semantic behavior in allowlisted
   programs;
2. imported settings can install executable hooks and trusted stdio MCP
   configuration without dedicated executable review;
3. mutating HTTP tools bypass the approval classifier and allow SSRF;
4. project-scoped reads accept arbitrary host paths;
5. SSH host keys are accepted without known-host verification;
6. Remote Coding credentials and control traffic use plaintext WebSockets when
   the feature is enabled; and
7. taint policy is advisory and is evaluated too late to constrain cached or
   full-access execution.

Release candidates may proceed only after the P0 exit criteria in this document
are met, or after an explicit, scoped, time-bounded risk acceptance disables the
affected feature in the released build.

## Audited Revision And Scope

The audit traced untrusted input through classification, approval, dispatch,
and side-effect boundaries across:

- built-in tools, local shell, background processes, Plan Mode, and routines;
- MCP configuration, stdio process startup, hooks, and settings import/export;
- HTTP, SSH, Remote Coding, and OpenAI-compatible endpoint transport;
- project filesystem reads and writes;
- SharedPreferences, Hive, drift, logs, backups, and attachment retention;
- Android, iOS/macOS, GitHub Actions, Gradle, Pub, and npm dependencies.

The audit used source inspection, focused Flutter tests, repository verification,
dependency advisory queries, and harmless local probes. It did not perform a
destructive exploit, capture real credentials, conduct an active LAN
man-in-the-middle attack, or exercise production signing and deployment.

## Trust Boundaries

The following boundaries must be treated as security boundaries rather than UX
conventions:

- model output and tool arguments versus local process execution;
- remote web, MCP, imported settings, and files versus user instructions;
- selected project roots versus the rest of the host filesystem;
- approval receipts versus the exact command, server identity, destination, and
  current turn that they authorize;
- local/LAN transport versus authenticated and confidential transport;
- app settings and logs versus OS-protected secret storage;
- a release workflow dependency versus code with repository-write credentials.

## Findings Summary

| ID | Severity | Finding | Primary roadmap owner |
|----|----------|---------|-----------------------|
| SA-01 | Critical | Read-only shell classification permits arbitrary execution without approval | SEC4.1 |
| SA-02 | High | Imported executable settings and pending MCP review can start processes before dedicated consent (fixed 2026-08-14) | SEC4.2 |
| SA-03 | High | Built-in HTTP and browser tools bypass a complete egress/SSRF boundary (destination boundary fixed 2026-08-14; resource limits pending) | SEC1, SEC4.3 |
| SA-04 | High | Project-scoped reads accept arbitrary absolute and home paths (fixed 2026-08-14) | SEC1, SEC4.4 |
| SA-05 | High | SSH host keys are accepted without known-host verification (fixed 2026-08-19) | SEC4.5 |
| SA-06 | High | Remote Coding credentials and control traffic use plaintext WebSockets (release non-loopback bind contained 2026-08-19; confidential transport pending) | RC1, SEC4.5 |
| SA-07 | High | Taint policy is advisory before cache and full-access decisions (fixed 2026-08-14) | SEC2.3b |
| SA-08 | Medium | File mutations can escape project scope through missing or lexical-only containment | SEC4.4 |
| SA-09 | Medium | Routines treat every external MCP tool as read-only | SEC4.4 |
| SA-10 | Medium | HTTP bodies and unauthenticated Remote Coding sockets/frames are unbounded | SEC4.3, RC1 |
| SA-11 | Medium | Settings secrets are persisted and exported in cleartext | SEC4.6 |
| SA-12 | Medium | Non-loopback plaintext LLM endpoints can receive bearer credentials and private content | SEC4.5 |
| SA-13 | Medium | Approval-audit redaction does not recurse into nested arguments | SEC4.6 |
| SA-14 | Medium | Session-log migration can reverse an explicit opt-out | SEC4.6 |
| SA-15 | Medium | Drift failure can resurrect stale deleted Hive conversations or memory | SEC4.6 |
| SA-16 | Medium | CI, dependency update, Gradle, and Android signing controls are not fail-closed | SEC4.7 |
| SA-17 | Medium | Android backup policy does not exclude settings, logs, and conversation stores | SEC4.6 |
| SA-18 | Low | Privacy declarations, debug-log handling, and attachment deletion need lifecycle review | SEC4.6 |

## Critical And High Findings

### SA-01: Approval-Free Semantic Shell Execution

Severity: `Critical`

Preconditions:

- a desktop coding project is selected;
- the local command tool is available; and
- a model or authenticated Remote Coding client supplies the command.

Evidence:

- `lib/features/chat/data/datasources/local_shell_tools.dart:67-90` labels
  `awk` read-only and conditionally labels `sed` read-only;
- `lib/features/chat/data/datasources/local_shell_tools.dart:139-146` executes
  non-internal commands through `sh -c` or Windows `cmd /C`;
- `lib/features/chat/data/datasources/local_shell_tools.dart:436-459` does not
  provide an internal `awk` or `sed` implementation;
- `lib/features/chat/data/datasources/local_shell_tools.dart:1008-1015` rejects
  `sed -i` but does not reject the `w` command;
- `lib/features/settings/domain/services/local_command_permission_service.dart:122-239`
  does not recognize these semantic execution forms;
- the read-only shortcut is consumed by
  `lib/features/chat/domain/services/local_command_tool_handler.dart:75-90`,
  `lib/features/chat/domain/services/background_process_tool_handler.dart:103-116`,
  and `lib/features/chat/domain/services/planning_tool_policy.dart:79-88`.

A harmless probe confirmed that `awk` can call `system()` and that `sed -n`
with `w` can create a file while both calls satisfy the current read-only
classifier. Existing tests cover shell separators, pipes, substitutions, and
`sed -i`, but not these semantic forms
(`test/features/chat/data/datasources/local_shell_tools_test.dart:94-125`).

Impact: arbitrary process execution or file mutation as the desktop user,
without the intended manual, auto-review, remote-origin, or Plan Mode gate.

Required remediation:

- enforce the invariant that an approval-free command is executed only by a
  bounded internal argv implementation and never by a native shell;
- remove interpreter-like and option-extensible programs from the read-only
  shortcut;
- apply the same decision to foreground, background, `process_start`, remote
  origin, saved permissions, and Plan Mode; and
- add combined regressions for semantic executable behavior, option-bearing
  internal commands, Windows `cmd /C`, and Plan Mode `background:true`.
  Preserve the standalone-`&` assertions under a newly named historical
  lexical-separator group as a distinct fixed bug.

Remediation status (2026-08-14): `Fixed` by `da2e6b84`, `e17d8eec`, and
`1415da6f`. The read-only classifier now admits only commands supported by the
bounded internal executor. Foreground, background, active `process_start`,
remote-origin, remembered-rule, Windows-shell, and Plan Mode regressions cover
the shared boundary. Explicitly approved native-shell execution remains
available by design.

### SA-02: Imported Executable Configuration

Severity: `High`

Precondition: a user imports or synchronizes an attacker-controlled settings
file/QR code, or reviews an attacker-controlled pending stdio server.

Evidence:

- `lib/features/settings/data/settings_file_service.dart:18-55` and
  `lib/features/settings/data/settings_qr_service.dart:24-35` deserialize the
  settings aggregate;
- `lib/features/settings/presentation/providers/settings_notifier.dart:1083-1100`
  persists the imported object;
- validation at `lib/features/settings/data/settings_file_service.dart:74-120`
  does not quarantine hooks, commands, environments, full-access settings, or
  trusted MCP state;
- `lib/features/settings/domain/entities/app_settings.dart:153-171` defaults
  imported MCP configuration toward enabled/trusted behavior;
- `lib/features/settings/domain/services/external_tool_hook_service.dart:22-65`
  starts configured commands;
- `lib/features/chat/data/datasources/mcp_stdio_client.dart:39-55` starts stdio
  MCP commands; and
- `lib/features/chat/data/datasources/remote_mcp_connection_manager.dart:263-285`
  can connect a pending server to enumerate it before the later trust decision.

Impact: arbitrary code execution as the user, or prompt/result exfiltration
through imported hooks.

Required remediation:

- use one import sanitizer for JSON, QR, onboarding, and external config;
- force imported executable entries to disabled/pending regardless of payload
  trust claims;
- clear imported full-access and cached permission state;
- show a redacted executable-configuration diff; and
- require an exact, expiring, non-cacheable review before starting a process or
  connecting a pending server.

Acceptance must inspect persisted state and delayed behavior, not only the
import call: provider rebuild, next turn, app restart, and manual resync must
remain inert. Any change to command, argv, environment-key set, URL, schema, or
normalized trust identity invalidates the prior review.

### SA-03: Unapproved HTTP/Browser Egress, Mutation, And SSRF

Severity: `High`

Precondition: a tool-capable model invokes a built-in HTTP or browser tool in
general or coding mode. Untrusted web, MCP, or file content can supply the
target.

Evidence:

- `lib/features/chat/data/datasources/built_in_network_tool_handler.dart:16-38`
  exposes POST, PUT, PATCH, and DELETE;
- `lib/features/chat/data/datasources/network_http_tools.dart:184-227` accepts
  arbitrary URLs, DNS results, headers, bodies, and redirects;
- `lib/features/chat/domain/services/chat_tool_dispatcher.dart:54-80` falls
  through to direct execution for tools outside the registered gated set;
- `packages/caverno_tool_contracts/lib/src/tool_capability_classifier.dart:386-478`
  recognizes GET/HEAD but lets mutation verbs fall back to low-risk `other`;
  and
- `lib/features/chat/data/datasources/mcp_tool_service.dart:629-632` performs the
  request on the fallback path;
- `lib/core/services/browser_tool_policy.dart:3-54` treats browser navigation,
  snapshot, and content reads as automatic;
- `lib/core/services/browser_session_service.dart:239-286` opens a model-supplied
  URL and returns page content; and
- `lib/core/services/browser_session_service.dart:624-633` accepts already
  schemed URLs plus `about:` and `data:` without a shared destination policy;
  and
- `lib/core/security/data_source_classifier.dart:67-116` does not identify the
  mutating HTTP names as remote results, while unknown `other` provenance maps
  to project-trusted at `lib/core/security/data_source_classifier.dart:145-152`.

Impact: unauthorised state changes or data access against local files/schemes,
loopback, LAN, link-local, cloud metadata, and authenticated internal services.

Required remediation:

- classify every verb as network access, mutation verbs as high risk, and every
  HTTP/browser result as remote/untrusted provenance;
- route every HTTP request and model-triggered browser navigation through one
  central destination and approval policy;
- allow only HTTP(S), reject every unsafe A/AAAA answer, and bind the approved
  address to the connection or verify the actual peer address so DNS rebinding
  cannot race the policy check;
- reject private/loopback/link-local/metadata destinations by default and
  repeat scheme, address, and peer validation after every redirect;
- remove sensitive headers on cross-origin redirects; and
- stream responses through byte and total-time limits rather than buffering the
  complete body.

Remediation status (2026-08-14): SEC4.3a through SEC4.3c are complete. HTTP reads
are classified as network fetches, HTTP mutations as high-risk remote side
effects, all HTTP/browser results use remote untrusted provenance, and every
interactive HTTP mutation passes through the owner-scoped approval boundary.
Tainted high-risk mutation blocks before cache/full access; other tainted
network access requires a fresh approval. HTTP destinations now reject unsafe
schemes and any unsafe DNS answer, connect directly to a pinned approved
address, verify the peer, revalidate every manual redirect, and strip sensitive
cross-origin headers. External WebView navigation fails closed because the
native WebView cannot enforce the peer invariant. SA-03 remains open for
SEC4.3d, which must bound response bytes and total time.

### SA-04: Host-Wide Reads Through Project-Scoped Tools

Severity: `High`

Precondition: a model can invoke the filesystem or local read-only command
tools for a selected project.

Evidence:

- `lib/features/chat/data/datasources/filesystem_path_resolver.dart:24-77`
  expands `~/` and accepts absolute paths;
- `lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart:25-97`
  supplies a default root but does not enforce containment;
- `lib/features/chat/domain/services/project_scoped_read_tool_handler.dart:29-69`
  performs the read without a project-root authorization check; and
- internal read-only shell paths at
  `lib/features/chat/data/datasources/local_shell_tools.dart:785-843` have the
  same host-wide reach.

Impact: readable SSH keys, `.env` files, cloud credentials, browser/app data,
or private documents can enter model requests, tool results, and session logs.

Required remediation: apply one canonical, symlink-aware project path fence to
all approval-free filesystem and internal shell reads. Host-wide reads must be
a separate disabled-by-default capability with a fresh, non-cacheable approval.

Remediation status (2026-08-14): SEC4.4a is complete. One canonical asynchronous
fence now covers interactive, Plan Mode, participant, Pro Reasoning, Personal
Eval, routine, and worktree-agent reads plus approval-free internal shell reads.
Missing authority, home paths, traversal, sibling and prefix collisions, and
direct or intermediate symlink escapes fail before the filesystem or process
effect. A complete current-main versus feature failure-set comparison recorded
15 shared pre-existing failures and zero feature-only failures.

### SA-05: Missing SSH Host-Key Verification

Severity: `High`

Precondition: an attacker can influence LAN/WAN routing, DNS, or the target SSH
endpoint.

Evidence:

- `lib/core/services/ssh_service.dart:289-301` constructs `SSHClient` without
  an `onVerifyHostKey` callback;
- `lib/core/services/ssh_service.dart:105-136` exposes a session sequence label,
  not a cryptographic host-key fingerprint; and
- the locked `dartssh2` version accepts host keys when the callback is absent.

Impact: server impersonation, password or session theft, command interception,
and spoofed results.

Required remediation: persist known-host identities by host and port, show a
SHA-256 fingerprint for first-use confirmation, fail closed on mismatch, and
provide an explicit rotation/recovery flow.

Remediation status (2026-08-19): SEC4.5a is complete. Production `SSHClient`
construction always installs `onVerifyHostKey`. Unknown hosts require a Trust
confirmation that shows the SHA-256 fingerprint; mismatches require an explicit
Replace confirmation. Neither path authenticates before the callback returns
true, and the session-ownership `ssh-session:N` label remains a generation
token rather than a host key. SA-06 / SEC4.5b is release-contained.

### SA-06: Plaintext Remote Coding Control Channel

Severity: `High`

Precondition: Remote Coding is enabled and a malicious LAN peer, access point,
router, or active MITM can observe or modify traffic.

Evidence:

- `lib/features/remote_coding/domain/remote_coding_models.dart:204-264` creates
  `ws://` endpoints;
- `lib/features/remote_coding/presentation/remote_coding_server_notifier.dart`
  still requests `InternetAddress.anyIPv4`, and debug/profile builds bind it;
- `lib/features/remote_coding/presentation/remote_coding_client_notifier.dart:435-466`
  sends pairing secrets or bearer tokens on that channel;
- `lib/features/remote_coding/presentation/remote_coding_server_notifier.dart:548-646`
  accepts credentials and returns a reusable token; and
- `docs/remote_coding_notification_relay_contract.md:7-15` already records that
  authenticated `ws://` is not confidential.

Impact: token replay, conversation and project disclosure, message injection,
and remote approval resolution.

Existing controls reduce but do not remove the risk: the feature defaults off,
source addresses are LAN-filtered, pairing secrets are random and short-lived,
tokens are hashed at rest, and devices can be revoked.

Required remediation: prevent non-loopback plaintext binding in release builds,
then introduce pinned authenticated WSS or equivalent application-layer
authenticated encryption, reject downgrade, and replace reusable transport
tokens with short-lived channel-bound session authorization.

Remediation status (2026-08-19): SEC4.5b is complete. Production start goes
through `RemoteCodingListenPolicy.current()`. A product isolate throws
`RemoteCodingPlaintextLanForbiddenException` before `HttpServer.bind` for any
non-loopback address. The P0 gate requires a `transportContainment` result, and
`tool/remote_coding_plaintext_lan_smoke.dart` compiled with
`dart.vm.product=true` prints `plaintext_non_loopback_listener_can_start=false`.
Debug LAN pairing is unchanged. Confidential transport remains SEC4.5c.

### SA-07: Advisory Taint Policy Before Trusted Execution

Severity: `High`

Precondition: untrusted evidence influences a turn while a cached approval or
full-access mode is available.

Evidence:

- `lib/core/security/taint_policy.dart:4-12` explicitly documents advisory-only
  policy;
- `lib/features/chat/domain/services/tool_approval_auto_review_service.dart:109-152`
  resolves cache/full-access paths before taint can impose a hard decision; and
- `lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart:233-267`
  supplies the influence flag, but it cannot constrain the earlier paths.

Impact: prompt-injected content can drive privileged shell, file, network, SSH,
browser, or Computer Use actions through a path the policy intended to
escalate.

Required remediation: complete `SEC2.3b` by evaluating `TaintDecision` at the
central execution boundary before cache/full-access resolution. Tainted
high-risk mutation must block or require fresh non-cacheable approval; the
decision and influence sources must be recorded recursively and survive turn
handoff.

Remediation status (2026-08-14): fixed by SEC2.3b/SEC4.3b. The shared approval
service evaluates `TaintDecision` before cached approval, auto-review, and full
access. High-risk tainted mutation is denied, other tainted network/state
actions require fresh manual approval, and the audit records `taint_policy`
with the untrusted-influence flag. Production ChatNotifier regressions prove an
HTTP fetch followed by POST cannot use full access and causes zero mutation
execution.

## Medium And Low Findings

### SA-08: Project Mutation Containment

`lib/features/chat/domain/services/file_mutation_tool_handler.dart:209-249`
does not authorize write/edit targets against the canonical project root, while
delete relies on lexical prefix checks in
`lib/features/chat/domain/services/dart_project_tooling.dart:239-265`.
Canonicalize the target or nearest existing parent immediately before every
effect and defend against intermediate symlinks and path races.

### SA-09: External MCP Tools In Routines

`lib/features/routines/domain/services/routine_tool_policy.dart:105-149` treats
every externally marked MCP tool as read-only, and
`lib/features/routines/data/routine_execution_service.dart:705-802` executes an
allowed name directly. Deny external MCP tools in unattended routines by
default; any future grant must bind server identity, tool name, schema digest,
and reviewed read-only intent.

### SA-10: Resource Exhaustion

`lib/features/chat/data/datasources/network_http_tools.dart:225-279` buffers a
complete response before truncating it. Remote Coding retains unauthenticated
sockets without connection, authentication, or frame limits at
`lib/features/remote_coding/presentation/remote_coding_server_notifier.dart:357-407`
and decodes unbounded JSON at
`lib/features/remote_coding/data/remote_coding_protocol.dart:16-41`. Add
streaming byte ceilings, total and idle deadlines, socket/per-IP caps,
authentication deadlines, frame limits, and rate limiting.

### SA-11: Cleartext Settings Secrets And Exports

`lib/features/settings/data/settings_repository.dart:22-50` stores the complete
settings JSON, while `lib/features/settings/data/settings_file_service.dart:59-69`
and `lib/features/settings/data/settings_qr_service.dart:13-21` export the same
object. Move credentials to platform secure storage, store references in normal
settings, redact normal exports, and require an explicit encrypted
include-secrets flow.

### SA-12: Plaintext Non-Loopback LLM Endpoints

`lib/features/settings/presentation/pages/general_settings_page.dart:1456-1463`
accepts HTTP outside loopback, and client construction in
`lib/features/chat/data/datasources/chat_remote_datasource.dart:37-59` can send
API keys and private prompts to that endpoint. Require HTTPS outside loopback;
keep any LAN exception narrow, explicit, visible, and credential-aware.

### SA-13: Nested Approval-Audit Secrets

`lib/core/services/tool_approval_audit_log.dart:251-272` redacts only top-level
keys, while participant arguments are nested under `toolArguments` in
`lib/features/chat/domain/services/participant_tool_executor.dart:290-318`.
Use the recursive shared redactor, test nested maps/lists and private keys, and
create audit directories/files with owner-only permissions. Creation at
`lib/core/services/tool_approval_audit_log.dart:171-184` does not explicitly
harden modes. On the audited macOS host, `stat -f '%Lp %N'` reported `0755` for
`~/.caverno`, `session_logs`, `app_logs`, and `approval_audit`; files sampled
with `find <those-directories> -type f -exec stat -f '%Lp %N' {} \;` were
`0644`. The target is `0700` directories and `0600` sensitive files, including
migration of existing paths.

### SA-14: Session-Log Opt-Out Reversal

`lib/features/settings/data/settings_repository.dart:22-39` and `:56-67`
change a persisted `enableLlmSessionLogs: false` value to true when the migration
marker is absent; `test/features/settings/data/settings_repository_test.dart:13-30`
asserts that behavior. Migrate only a missing field and never reinterpret an
explicit false value.

### SA-15: Stale Hive Data Resurrection

Legacy boxes remain after the drift migration
(`lib/features/chat/data/repositories/conversation_migration_service.dart:30-53`
and
`lib/features/chat/data/repositories/chat_memory_migration_service.dart:29-50`).
A later drift bootstrap failure falls back to Hive through
`lib/main.dart:94-155`, so data deleted from the authoritative store can
reappear. Clear legacy data after verified migration or fail closed/read-only
when migration state says drift is authoritative.

### SA-16: Supply-Chain And Release Controls

GitHub Actions use mutable tags in `.github/workflows/flutter_ci.yml:24-50` and
`.github/workflows/flutter_sdk_update.yml:16-115`; the write-capable update job
installs unversioned FVM. Dependabot omits the npm relay, the Gradle wrapper has
no distribution checksum, and `android/app/build.gradle.kts:55-61` falls back
to debug signing for release. Pin actions to commit SHAs, use least-privilege
jobs, pin build tools, add npm monitoring and the Gradle checksum, and fail
release builds when release signing is absent.

### SA-17: Android Backup Boundary

`android/app/src/main/AndroidManifest.xml:20-23` has no explicit backup or data
extraction policy while credentials, logs, and conversations live in app-private
storage. Disable backup or add modern and legacy exclusion rules for secrets,
logs, attachments, and conversation stores.

### SA-18: Privacy And Retention Review

Debug logs can contain prompt and tool content, `ios/Runner/PrivacyInfo.xcprivacy`
declares no collected-data categories, and attachments are swept by age rather
than conversation deletion (`lib/core/services/attachment_storage_service.dart:20-81`).
Review platform disclosures against the final data flows, use the shared
redactor for debug logs, and delete conversation-owned attachments with the
conversation.

## Dependency And Supply-Chain Review

- `cd services/notification_relay && npm audit --omit=dev --json` reported zero
  known production vulnerabilities at the audited lockfile. `npm ci` still
  emitted deprecation warnings for
  `glob@10.5.0` and `node-domexception@1.0.0`; treat them as dependency-hygiene
  work under SA-16 rather than as a confirmed audit advisory.
- `curl -sS 'https://api.github.com/advisories?ecosystem=pub&per_page=100'`
  returned 13 reviewed Pub advisories on 2026-08-14. None matched the lockfile.
  Direct record checks included `GHSA-vm9r-h74p-hg97` (`archive`),
  `GHSA-3hpf-ff72-j67p` (`shared_preferences_android`), and
  `GHSA-9v85-q87q-g4vg` (`http`); the installed versions are outside the
  affected ranges.
- An OSV querybatch over all 270 locked Pub packages returned no affected pair.
  This was a secondary aggregation cross-check and its response was not
  persisted, so it is not standalone release evidence.
- `sqlite3_flutter_libs 0.6.0+eol` is an end-of-life maintenance dependency, not
  a confirmed advisory in this audit.

These are point-in-time advisory results, not proof that the dependency graph is
safe. Re-run the queries for each release and when lockfiles change.

## Rejected Or Already-Mitigated Suspicions

- The notification relay uses cryptographic randomness, constant-time HMAC
  checks, transactional replay protection, and a bounded request body; no
  concrete relay authentication bypass was found.
- Remote Coding token generation, hashing, comparison, revocation, and mobile
  secure storage are sound at rest. SA-06 concerns transport confidentiality.
- Raw Markdown HTML is escaped before rendering; no browser-DOM XSS was
  substantiated.
- Network diagnostic targets are passed as argv to `Process.run`; no shell
  injection was substantiated there.
- The permissive certificate callback belongs to a certificate-inspection tool,
  not application authentication transport.
- The prior standalone-`&` shell separator bypass is fixed. Its stable history
  ID is `SEC-SHELL-LEX-2026-07`, fixed by `fd059e7e` and included in tags
  `v1.3.14+26` and `v1.3.15+27`; current assertions live in the generic shell
  safety tests near
  `test/features/chat/data/datasources/local_shell_tools_test.dart:107`.
  SEC4.1 must give those assertions a named lexical-separator group. SA-01 is
  `SEC-SHELL-SEM-2026-08`, a distinct semantic execution bug in allowlisted
  programs with its own regression group.
- No production private key, OpenAI key, GitHub token, service-account file, or
  keystore was found in tracked files. Matches were test fixtures for redaction.

## Test Gaps

Add negative coverage for:

- `awk system()`, `sed w`, option-bearing `find`/`rg`, Windows `cmd /C`, Plan
  Mode with `background:true`, and every command that can leave the internal
  argv executor;
- imported enabled hooks, trusted stdio servers, full access, saved permissions,
  onboarding import, persisted sanitized state, provider rebuild, next turn,
  restart, resync, and review-identity invalidation;
- pending MCP review before process/client creation;
- every HTTP verb and browser navigation/read tool, remote/untrusted result
  provenance, unsafe URL schemes, private/IPv6/mixed-DNS destinations,
  DNS-rebinding/peer mismatch, metadata addresses, redirect revalidation, and
  sensitive-header stripping;
- taint enforcement before cache and full access;
- canonical project containment, symlink escape, and prefix collision;
- SSH first-use, mismatch, and rotation;
- Remote Coding downgrade, wrong pin/MITM, authentication timeout, frame limits,
  and connection caps;
- nested audit redaction, secret-free exports, opt-out migration, stale Hive
  failure, and Android backup exclusions.

## Remediation Map

| Order | Slice | Findings | Exit evidence |
|-------|-------|----------|---------------|
| P0-1 | SEC4.1 approval-free execution boundary (completed 2026-08-14) | SA-01 | No command reaching a native shell can take a read-only shortcut; foreground, background, process, Windows, remote, and Plan Mode tests pass. |
| P0-2 | SEC4.2 executable configuration quarantine (completed 2026-08-14) | SA-02 | File, QR, onboarding, and external-config fixtures persist sanitized state and cause zero process/client starts across import, rebuild, next turn, restart, and resync before exact expiring review. |
| P0-3 | SEC1 + SEC2.3b + SEC4.3a-SEC4.3c network authority (completed 2026-08-14) | SA-03, SA-07 | Every HTTP/browser request uses one classifier, remote provenance, approval, destination, DNS/peer, and redirect policy; unverifiable external WebView navigation is absent; taint precedes cache/full access. |
| P0-4 | SEC4.4a project read containment (completed 2026-08-14) | SA-04 | Every approval-free read is fenced to the canonical selected-project root; host-wide reads require a separate fresh approval. |
| P0-5 | SEC4.5a-SEC4.5b authenticated transport containment (completed 2026-08-19) | SA-05, SA-06 | SSH known-host mismatch fails before authentication. A release build cannot start a plaintext non-loopback Remote Coding listener. |
| P1-1 | SEC4.4b mutation and autonomous containment | SA-08, SA-09 | Symlink-aware write fences and routine MCP deny-by-default tests pass. |
| P1-2 | SEC4.3d/SEC4.5e/SEC4.5f resource and credential transport | SA-10, SA-12 | HTTP and Remote Coding limits pass; credential-bearing non-loopback LLM endpoints require HTTPS. |
| P1-3 | SEC4.6 data protection and lifecycle | SA-11, SA-13, SA-14, SA-15, SA-17, SA-18 | Secret-free storage/export, recursive redaction, opt-out, migration, backup, and deletion tests pass. |
| P1-4 | SEC4.7 release supply-chain hardening | SA-16 | Immutable actions, pinned toolchain, checksum, dependency monitoring, and fail-closed release signing are enforced. |

Do not combine these slices into one implementation PR. Create a focused task
from `docs/codex_task_template.md` when each slice starts, including its exact
tests, rollback unit, and similar-pattern search.

## P0 Release Exit Criteria

- SA-01 through SA-07 are fixed or the affected feature is absent from the
  release artifact under a documented, expiring risk acceptance.
- The approval-free path has no native-shell fallback on any supported
  platform or foreground/background mode.
- Imported executable configuration persists only sanitized state and cannot
  establish trust or start a process across rebuild/restart/resync before
  dedicated consent bound to the unchanged identity.
- All HTTP verbs and browser navigation/read tools pass one authorization,
  destination, DNS/peer, redirect, and remote-result-provenance policy.
- Host-wide reads are not approval-free.
- SSH verifies host identity.
- Remote Coding either uses pinned confidential transport or cannot bind a
  plaintext non-loopback release server.
- Taint decisions run before cached/full-access authorization.
- The updated Remote Coding P0 gate plus a release artifact/runtime smoke test
  mechanically proves plaintext non-loopback startup is impossible; a UI
  default or documentation warning is insufficient.
- Focused regression tests and `tool/codex_verify.sh --coverage` pass.

## Verification Log

Completed on the audited revision:

- `tool/codex_verify.sh --no-codegen --no-tests`: passed, including workspace
  analysis plus notification-relay install and source checks;
- 174 focused Flutter tests covering dispatcher, HTTP, settings, shell,
  filesystem, classifier, and Remote Coding paths: passed;
- `cd services/notification_relay && npm audit --omit=dev --json`: zero known
  production vulnerabilities;
- the GitHub reviewed Pub advisory feed was queried with
  `https://api.github.com/advisories?ecosystem=pub&per_page=100`; none of its 13
  records matched the locked package/version pairs. Directly checked records
  included `GHSA-vm9r-h74p-hg97`, `GHSA-3hpf-ff72-j67p`, and
  `GHSA-9v85-q87q-g4vg` against the installed `archive`,
  `shared_preferences_android`, and `http` versions;
- an OSV Pub querybatch over all 270 locked packages was used only as a
  secondary aggregation cross-check and returned no affected pair. The response
  was not persisted, so this result is not standalone release evidence;
- harmless local semantic-command probes: SA-01 reproduced; and
- `git status --short --branch`: clean detached HEAD.

Passing tests do not mitigate the findings above; they identify adversarial
cases that the current suites do not cover.

### SA-01 Remediation Verification

- Focused shell classifier, command handler, background process, Plan Mode,
  permission service, active ChatNotifier, mutation guard, and handler
  file-size-ratchet tests pass.
- `tool/codex_verify.sh --no-codegen --no-tests` passes root and package analysis
  plus notification-relay checks.
- A full root test run completed after the implementation with four unrelated
  baseline failures remaining: three existing size-ratchet failures in
  `mcp_tool_service.dart` / `chat_remote_datasource.dart`, plus the existing
  model capability count expectation (`29` versus `32`). The SEC4.1-related
  mutation-guard and handler-ratchet failures were corrected and pass in
  isolation.

## Risk Acceptance And Update Policy

Any accepted risk must record:

- finding ID and affected versions/features;
- owner and approver;
- justification and compensating controls;
- whether the affected feature is removed or mechanically hard-disabled in the
  release artifact; a UI default alone is not a compensating control;
- expiry date and linked follow-up issue; and
- revalidation evidence.

Critical arbitrary execution must not be accepted for a general release merely
because it requires a tool-capable model. Remote Coding's default-off state is a
temporary compensating control, not closure of SA-06.

When a finding is closed, append the fix commit, focused regression-test names,
verified release version, and residual risk to this document. Do not replace the
audited revision or rewrite the original evidence.

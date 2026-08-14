# SEC4.3b Network Mutation Approval Task

Status: completed on 2026-08-14.

## Task

- Goal: route every model-triggered built-in HTTP mutation through the shared
  owner-scoped approval boundary and enforce the SEC2 taint decision before
  cached approval, auto-review, or full-access authorization can run it.
- User-visible behavior: POST, PUT, PATCH, and DELETE require the configured
  approval flow. A mutation influenced by untrusted content is denied before
  execution and cannot be revived by a cached grant or full-access mode.
- Non-goals: destination, DNS, peer, scheme, redirect, or credential policy
  (SEC4.3c), and response byte/time limits (SEC4.3d).

## Context

- Affected components:
  - `ChatToolDispatcher` and the owner-scoped handler registry;
  - `ToolApprovalAutoReviewService` and `TurnToolApprovalCoordinator`;
  - ChatNotifier approval UI/audit adapters;
  - built-in HTTP POST, PUT, PATCH, and DELETE operations.
- Related findings: `docs/security_audit_2026-08-14.md` SA-03 and SA-07.
- Related roadmap slices: SEC2.3b and SEC4.3b.
- Release gate: both slices are P0 and must close before an affected release.

## Dispatch Inventory

- Interactive native and content-tag tool calls converge on
  `ChatNotifier._dispatchToolCall` and `ChatToolDispatcher`.
- Before this slice, built-in HTTP mutations miss every registered handler and
  execute through the generic `McpToolService.executeTool` fallback.
- Plan Mode already rejects all four HTTP mutations.
- Routine tool definitions expose only HTTP status, GET, and HEAD; HTTP
  mutations are not eligible for autonomous routine execution.
- Personal-eval and diagnostic callers are explicit application-owned harnesses,
  not model-authorized interactive mutation paths. They remain outside the
  ChatNotifier approval UI and are not broadened by this slice.

## Implementation Tasks

1. **SEC4.3b-1 — Central dispatch.** Identify network mutations from the shared
   capability classifier before the handler registry and fallback, then require
   an owner-scoped mutation handler.
2. **SEC4.3b-2 — Exact approval.** Present method, destination, bounded body
   metadata, reason, and redacted header names through the existing approval
   surface. Execute the captured immutable arguments only after approval.
3. **SEC4.3b-3 — Taint before authorization.** Evaluate `TaintPolicy` inside
   the shared approval service before cached approval or full access. Block
   high-risk tainted mutations and force fresh manual approval for other
   tainted network/state actions.
4. **SEC4.3b-4 — Audit and lifetime.** Record taint decisions, preserve the
   untrusted-influence flag, reject expired owners, and prove denial causes zero
   network execution.

## Implementation Notes

- Keep the network-mutation name set owned by `ToolCapabilityClassifier`; do
  not duplicate a second authorization allowlist in the dispatcher.
- Approval is non-cacheable for HTTP mutations. Untainted auto-review or full
  access may authorize the exact turn request; tainted high-risk mutation is a
  hard denial under the existing `TaintPolicy` contract.
- Do not add a second execution path. The approval handler invokes the same
  `McpToolService.executeTool` operation only after the gate succeeds.
- Redact header values and avoid copying raw request bodies into auto-review or
  audit summaries. Recursive persisted-log redaction remains SA-13/SEC4.6.
- Generated files needed: none unless a new pending-approval state type becomes
  necessary. Prefer the existing generic action presentation for this slice.

## Acceptance Criteria

- POST, PUT, PATCH, and DELETE cannot reach generic fallback execution.
- Default mode waits for a manual owner-scoped decision and denial executes
  nothing.
- Auto-review denial executes nothing; an allowed untainted request executes
  exactly once.
- Full access executes an untainted request exactly once.
- Cached approval and full access cannot bypass a taint `block` or
  `requireApproval` decision.
- A tainted high-risk HTTP mutation is denied before review or execution and
  records `taint_policy` as the audit decision source.
- Owner expiry before or after approval executes nothing.
- Untainted HTTP status, GET, and HEAD remain read-only network fetches and
  continue through the normal fallback path. Tainted network reads require a
  fresh owner-scoped approval before that path can continue.

## Verification

```bash
fvm flutter test test/features/chat/domain/services/chat_tool_dispatcher_test.dart
fvm flutter test test/features/chat/domain/services/tool_approval_auto_review_service_test.dart
fvm flutter test test/features/chat/domain/services/turn_tool_approval_coordinator_test.dart
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "HTTP mutation"
tool/codex_verify.sh --no-codegen --no-tests
```

## Handoff Notes

- Verification passed:
  - 54 focused dispatcher, approval-service, and coordinator tests;
  - 3 production ChatNotifier-path HTTP mutation tests covering manual denial,
    untainted full access, and tainted full-access blocking;
  - `fvm flutter analyze`;
  - `tool/codex_verify.sh --no-codegen --no-tests`.
- Do not mark SA-03 or SEC4.3 complete: SEC4.3c remains a P0 release blocker and
  SEC4.3d remains a P1 resource-boundary task.
- Next task: SEC4.3c must enforce one HTTP/browser destination, DNS, peer, and
  redirect policy before any approved request can connect.

# Workflow Stage Confirmation Adapter Ownership Audit

## Task

- Goal: Specify the owner-scoped presentation adapter and stale-request
  lifecycle for workflow-stage confirmation before any UI is implemented.
- User-visible behavior: None. This is a read-only architecture audit.
- Non-goals: Implementing an adapter or dialog, persisting confirmation state,
  transforming conversations, selecting live authority, or removing the
  workflow editor.

## Context

- Affected files or components: ChatPage approval listeners and sheets,
  ChatNotifier approval routing and terminalization, thread-scoped chat state,
  owner registries, and the workflow-stage confirmation contract.
- Related docs:
  `docs/chat_notifier_workflow_stage_confirmation_contract_codex_task.md` and
  `docs/chat_notifier_workflow_stage_decision_rehearsal_codex_task.md`.
- Reference implementation or pattern: Owner-tagged pending tool approval
  registry plus thread-scoped UI projection and current-owner revalidation.
- Known quirks, compatibility rules, or release gates: Thread switching must
  preserve a pending request, while owner retirement, replacement, clearing,
  and notifier disposal must settle it safely. Widget unmount alone must not
  become confirmation authority.

## Implementation Notes

- Preferred approach: Trace request registration, projection, presentation,
  result intake, terminalization, thread switching, and disposal. Produce an
  ownership matrix and one bounded adapter design with explicit stop gates.
- Constraints: Keep the domain request content-free. Keep `ChatState` as a UI
  projection rather than the authoritative pending-request store. Do not reuse
  a planning-decision path unless its owner and stale-result guarantees match.
- Generated files needed: None.
- Migration or data compatibility concerns: None; this audit authorizes no
  persisted schema or conversation write.

## Similar-Pattern Search

- Search terms: `PendingToolApprovalRegistry`, `PendingWorkflowDecision`,
  `_routeApproval`, `_terminalizeRuntimeTurn`, `ThreadScopedChatState`,
  `_showApprovalDialogOnce`, `ChatTurnOwner`, and `ref.onDispose`.
- Files or modules inspected: Pending approval values and registries, approval
  listeners, workflow decision sheet, thread routing, runtime terminalization,
  detached-turn tests, and the new domain confirmation contract.
- Follow-up tasks found: Implement the owner-scoped operation registry and
  adapter without UI first. Add state projection and a sheet only after owner
  settlement tests pass.

## Current-State Findings

1. `PendingToolApprovalRegistry` is the strongest existing ownership pattern.
   It indexes each request by `ChatTurnOwner` and request ID, rejects stale
   registration and result intake, completes a safe cancellation value exactly
   once, and supports owner-specific and global settlement.
2. ChatNotifier runtime terminalization calls owner-specific tool-approval
   cancellation before releasing the active response. Clear and notifier
   disposal use global cancellation. The authoritative registry is therefore
   retired with the same generation that owns execution.
3. `ThreadScopedChatState` correctly treats approval fields as per-thread UI
   projections. A background thread keeps its pending projection in the stash,
   appears as awaiting approval, and restores the prompt when selected.
4. ChatPage listeners deduplicate modal presentation by request ID and defer it
   until after the frame. `_activeApprovalDialogIds` is intentionally local UI
   state; it neither validates ownership nor settles a request.
5. `PendingWorkflowDecision` is not an adequate owner pattern for the new
   confirmation. It carries only an ID, decision, and completer; it is absent
   from `PendingToolApprovalRegistry`, result intake checks only visible state
   and ID, and several paths clear its projection directly. Notifier disposal
   and runtime terminalization settle tool approvals but do not independently
   own this completer.
6. The detached-thread workflow-decision test proves thread stash restoration,
   but not generation replacement, owner retirement, notifier disposal, stale
   result rejection, or current conversation-context revalidation.

## Ownership Decision

- Bind one `ConversationWorkflowStageConfirmationPort` adapter instance to one
  exact `ChatTurnOwner`. Do not recover the owner later from the visible thread
  or mutable notifier state.
- Define a presentation-layer operation identity containing the owner, request
  ID, and context digest. Keep it outside the content-free domain request.
- Make a dedicated pending-operation registry authoritative. It owns the
  completer, indexes by owner and request ID, rejects duplicates, and exposes
  `registerCurrent`, `takeCurrent`, `cancelOwner`, and `cancelAll` behavior
  equivalent to the tool-approval registry.
- Store only an immutable presentation projection in `ChatState` and
  `ThreadScopedChatState`. The projection may contain the operation identity and
  domain request, but never becomes proof that the operation is current.
- On UI result intake, take the operation from the registry only if the exact
  owner remains current, clear the matching projection by identity, and settle
  once. Duplicate, cross-owner, and late results are no-ops.
- After the port future resolves, rebuild the authority-free preservation
  result from the current conversation and call
  `ConversationWorkflowStageConfirmationContract.resolve`. This second gate is
  what rejects workflow, Plan, provenance, or progress drift while the sheet
  was open.

## Lifecycle Matrix

| Event | Registry | Thread projection | Port future / result |
| --- | --- | --- | --- |
| Register for current owner | Insert exact operation | Route to the owner's visible state or thread stash | Remains pending |
| Owner thread becomes background | Keep operation | Stash under the owner conversation and mark awaiting approval | Remains pending |
| Owner thread becomes visible | Keep operation | Restore and present once by operation ID | Remains pending |
| Duplicate listener frame | No change | Modal dedup suppresses another presentation | Remains pending |
| User confirms or declines | `takeCurrent` removes exact operation | Clear only the identical projection | Complete exactly once |
| Conversation context changes while open | Keep until result intake | May remain visible | Domain resolver rejects after current-context rebuild; emit no decision |
| New generation replaces owner | `cancelOwner` before owner release | Clear matching owner projection | Complete with an adapter-created declined result |
| Runtime terminalizes or user cancels turn | `cancelOwner` | Clear matching owner projection | Complete with declined result |
| Messages/conversations are globally cleared | `cancelAll` | Clear all confirmation projections and stashes | Complete every pending operation with decline |
| Notifier disposes | `cancelAll` before registries are released | State is no longer authoritative | Complete every pending operation with decline |
| ChatPage or modal unmounts | No change | Preserve or restore projection on the next mounted page | Do not infer decline from widget lifecycle |
| Late or duplicate modal result | `takeCurrent` returns no operation | No change | Ignore; never complete another owner |

Cancellation needs an injected UTC clock so the adapter can construct a valid
declined result without importing UI time into the domain contract. Correctness
must not depend on closing a stale modal immediately; the registry rejects its
late result. A later UI slice should still dismiss or disable a sheet when its
projection disappears so the user is not left looking at an inert choice.

## Bounded Implementation Sequence

1. Add the presentation operation identity, registry, and owner-bound port
   adapter with tests for registration, take, owner replacement, decline,
   global disposal, duplicate result, and cross-thread isolation. Add no UI.
2. Add a thread-scoped immutable projection and wire owner/global settlement to
   the existing runtime terminalization, clear, and notifier-disposal paths.
3. Add a localized accessible sheet and listener only after the first two
   slices prove that unmount and late results cannot strand or confirm a turn.
4. Keep receipt persistence and conversation transformation as separate gates;
   this adapter sequence does not authorize either.

## Acceptance Criteria

- Required behavior: Identify one owner for authoritative pending operations,
  one projection owner, exact result validation, and deterministic settlement
  for thread switch, owner retirement, replacement, clear, and disposal.
- Edge cases: Background threads, repeated listener frames, dialog unmount,
  stale context while a sheet is open, duplicate result delivery, and a newer
  generation replacing the owner.
- Failure paths: The design must not strand a completer, let `ChatState` become
  authority, accept a result for a retired owner, or infer confirmation from
  dialog visibility or dismissal.
- Accessibility, localization, or platform expectations: Future UI copy and
  semantics remain outside this audit but must be adapter-owned, not domain
  fields.

## Verification

```bash
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: The authoritative owner must be a dedicated registry keyed by an
  exact `ChatTurnOwner`, request ID, and context digest. ChatState remains a
  thread-scoped projection, ChatPage remains presentation-only, and current
  conversation state is rebuilt after the port result before a decision can be
  emitted.
- Tests run: `git diff --check` passes. `tool/codex_verify.sh` completes
  generation, all analyzers, and package tests; the Flutter suite passes 6,538
  tests. Its only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper. Existing owner-registry and
  detached-thread tests were inspected read-only; no production or test code
  changed in this audit.
- Coverage or low-coverage notes: The matrix covers registration, background
  routing, presentation dedup, explicit result, context drift, replacement,
  terminalization, global clear, notifier disposal, widget unmount, and late or
  duplicate results.
- Risks or follow-ups: Existing `PendingWorkflowDecision` still has weaker
  lifecycle guarantees, but generalizing or repairing that planning path would
  broaden this migration slice. Implement a dedicated stage-confirmation
  registry and owner-bound adapter first, with no UI or persistence.

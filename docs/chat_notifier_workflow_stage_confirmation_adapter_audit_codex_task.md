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
- Follow-up tasks found: Pending audit.

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

- Summary: Pending.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: Pending.

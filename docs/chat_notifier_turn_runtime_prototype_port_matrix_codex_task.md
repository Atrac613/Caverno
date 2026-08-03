# ChatNotifier TurnRuntime Prototype Port Matrix: Codex Task

## Task

- Goal: Classify the selected part's external notifier dependencies and define
  the smallest honest boundary for the bounded `TurnRuntime` prototype.
- User-visible behavior: None. This task records an implementation contract
  before production Dart changes begin.
- Non-goals: Creating `TurnRuntime`, moving production symbols, completing the
  full I2 catalogue matrix, wiring `ChatToolHandlerCatalog`, changing behavior,
  or rerunning the live canary.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix_codex_task.md`
- Related docs:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_turn_runtime_preprototype_decision.md`
  - `docs/chat_notifier_turn_runtime_phase_1_5_decision_codex_task.md`
  - `docs/chat_notifier_turn_runtime_prototype_verification_codex_task.md`
- Reference implementation or pattern:
  - `tool/chat_notifier_turn_scope_baseline.json`
  - `tool/chat_notifier_decomposition_manifest.json`
  - `tool/chat_notifier_turn_runtime_prototype_verification.json`
  - `tool/measure_chat_notifier_turn_runtime_prototype.py`
- Known quirks, compatibility rules, or release gates:
  - Clean selection at source revision
    `06903a3b38aed7af3b6425f8efc3b3337e5c20d6` chose
    `chat_notifier_goal_auto_continue.dart` with 13 explicit identity
    entrypoints, zero turn-reachable ambient reads, and 804 production lines.
  - The verification manifest reserves only
    `_maybeAutoContinueCurrentGoal` and
    `_recordGoalAutoContinueSessionLog` for the prototype.
  - The complete selected part references 26 private notifier members defined
    elsewhere. The reserved prototype path reaches 10 of them, plus `ref`,
    `state`, and `sendHiddenPrompt`.
  - A callback or adapter that retains `ChatNotifier` fails the structural
    gate even if its public type looks narrow.

## Implementation Notes

- Preferred approach:
  1. Bind the audit to the clean selection revision and verification manifest.
  2. Inventory all external private notifier members in the selected part.
  3. Trace the two reserved symbols through same-part helpers and identify the
     smaller prototype dependency set.
  4. Group raw dependencies by ownership and capability rather than creating
     one port per member.
  5. Separate immutable turn inputs, runtime-owned state, narrow read/write
     ports, and effects returned to the `ChatNotifier` wrapper.
  6. Leave adjacent tool-loop, terminal-success, and content-dedupe methods in
     the extension during this prototype.
- Constraints:
  - Do not move conversation-spanning goal trackers into `TurnRuntime`.
  - Do not move thread queues, pending approvals, settings, conversation
    persistence, or session-log storage into `TurnRuntime`.
  - Do not pass `ChatNotifier`, a notifier method tear-off, or an adapter that
    retains the notifier into `TurnRuntime`.
  - Preserve explicit `ChatTurnOwner` identity at every boundary.
  - Treat aggregate line delta as a reported cost signal, not a hard gate.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_maybeAutoContinueCurrentGoal`,
  `_recordGoalAutoContinueSessionLog`, `_goalAutoContinueTrackerRegistry`,
  `_queuedChatMessages`, `_threadStates`, `_settings`, `sendHiddenPrompt`,
  `state`, `ref`.
- Files or modules inspected:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - `tool/chat_notifier_turn_runtime_prototype_verification.json`
- Follow-up tasks found:
  - Define the prototype value types and narrow interfaces from the approved
    capability matrix.
  - Move only the two reserved symbols and their pure helpers behind the
    wrapper.
  - Add comparison-mode measurement and run the focused behavior gates.

## Acceptance Criteria

- Required behavior:
  - The audit distinguishes the selected part's 26-member inventory from the
    reserved prototype path's 10-member inventory.
  - Every full-part private member has an ownership classification and an
    explicit prototype treatment.
  - The prototype path is expressed as capability boundaries, not ten
    one-member ports.
  - Conversation-, thread-, UI-, settings-, and persistence-scoped state stays
    outside `TurnRuntime`.
  - The proposed boundary introduces no callback or adapter that retains
    `ChatNotifier`.
  - Adjacent selected-part behavior is explicitly excluded from this first
    production slice.
- Edge cases:
  - Owner-current checks remain explicit before and after asynchronous work.
  - Hidden continuation and completion-elicitation dispatch remain observable
    effects rather than notifier callbacks captured by the runtime.
  - Reentrancy state is turn-runtime-owned, while the goal tracker remains
    conversation-scoped.
- Failure paths: Any unclassified dependency, implicit notifier capture, or
  scope transfer blocks production editing.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
rg -n "26|10|ChatNotifier|ChatTurnOwner|GoalContinuation|prototype treatment|outside" \
  docs/chat_notifier_turn_runtime_prototype_port_matrix.md \
  docs/chat_notifier_turn_runtime_prototype_port_matrix_codex_task.md
git diff --check
```

## Handoff Notes

- Summary: Audited the complete selected part and the smaller manifest-reserved
  call path, then defined five narrow collaborators and two returned effect
  boundaries without transferring longer-lived state into `TurnRuntime`.
- Tests run:
  - Full-part 26-member inventory search: passed.
  - Reserved-symbol manifest inspection: passed.
  - Decision-language search across the matrix and task: passed.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: Documentation-only boundary audit; no
  production coverage changes.
- Risks or follow-ups: The next production task must define typed contracts and
  focused tests without widening the slice to adjacent methods.

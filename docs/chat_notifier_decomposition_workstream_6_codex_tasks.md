# ChatNotifier Decomposition Workstream 6 Task Catalog

Status: deferred to the architecture-renewal plan. WS6-1 through WS6-5,
WS6-10, WS6-12, and WS6-13 completed focused acceptance and the merged-tree
verification gate. WS6-6 through WS6-9, WS6-11a, WS6-11b, and WS6-14 through
WS6-19 remain unimplemented while the renewal replaces their target
composition boundary. Resume them only after that plan establishes a stable
turn-runtime and composition-root API. WS6-19 retains its stricter registry-last
gate; the existence of its catalog implementation does not satisfy that gate.

This catalog decomposes the tool-handler workstream from
`docs/chat_notifier_decomposition_codex_task.md`. Each approved section is one
implementation slice and one focused review. Execute sections in order. Do not
combine sections, and do not move the handler registry before WS6-19.
Splitting the former combined device slice into WS6-11a and WS6-11b makes this
catalog 20 approved handler slices. The mandatory owner-keying repairs below
are additional prerequisite reviews and are not included in that count.

## Catalog-Wide Execution Contract

- The reviewed post-Slice 2b7 starting point is 9,364 physical lines in
  `chat_notifier.dart`, 42 declared parts totaling 13,523 lines, and a 22,887
  line same-library aggregate. The active ceilings are 9,380 primary lines and
  22,900 aggregate lines. These are starting evidence, not permission to skip
  the per-slice remeasurement.
- Remeasure every named source part, `chat_notifier.dart`, declared part count,
  and the same-library aggregate before editing.
- Confirm Slices 2a1-2a3 and 2b1-2b7 are green, including the exact-model
  canary. Stop if any prerequisite gate is missing or red.
- Resolve a typed `ChatTurnOwner` at the notifier boundary. It must carry the
  owning `conversationId`, `interactionGeneration`, and only the project or
  worktree paths required by the handler. Never let a collaborator read the
  visible thread, a provider, or a Zone.
- Side effects cross narrow owner-aware ports. A port method must take
  `ChatTurnOwner` plus immutable operation inputs. Do not pass `ChatNotifier`,
  `ChatState`, `Ref`, `ProviderContainer`, or a notifier-capturing callback.
- Keep public UI request and resolution methods in the notifier unless a task
  explicitly moves a pure presentation policy. Collaborators may request
  approval through typed ports; they must not own dialogs, completers, widget
  state, or visible-thread selection.
- Use the Slice 2a1 manifest and preserve every historical part record. A
  partial extraction changes `remaining` to `partial`; a whole-part extraction
  changes it to `extracted` and removes the old part.
- Use the manifest's canonical hyphenated historical IDs, such as
  `approval-handlers`, `local-file-handlers`, `computer-use-handlers`, and
  `tool-handler-registry`. Underscored Dart file stems are not manifest IDs.
- Append the exact collaborator record and discovery marker named by each task:
  `// ChatNotifier decomposition collaborator: <collaborator-id>`.
- Add each production file to the shrink-only size budget at its achieved
  physical line count. Every extracted collaborator in this catalog must stay
  below 500 physical lines.
- Calculate the achieved same-library aggregate as:

  ```text
  previous aggregate
  - physical lines removed from declared parts
  + ChatNotifier primary-file delta
  ```

  Independently imported collaborator lines are not part of that aggregate.
  Never raise a primary, aggregate, or collaborator budget. Lower every
  boundary that actually shrinks.
- Update `docs/large_file_refactor_plan.md` with achieved counts, manifest
  status, direct coverage, and any deferral.
- Update `tool/chat_notifier_decomposition_manifest.json`,
  `test/quality/chat_notifier_collaborator_boundary_test.dart`, and
  `test/quality/file_size_ratchet_test.dart` in every extraction. The
  structural test freezes the complete marker set and current declared-part
  count, so merely adding a manifest record cannot make the gate pass.
- Review and lower the checked-in turn-scope baseline whenever an extraction
  removes or reclassifies a reviewed read. The ratchet intentionally fails on
  both growth and unreviewed shrink:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

  Inspect the generated diff before accepting it. Never add a new ambient read
  merely to keep the old baseline numerically unchanged.
- Run `tool/codex_verify.sh --coverage` and `git diff --check` for every task.
- Run the corrected four-scenario live canary for every task. Record the
  reachable base URL, exact model, and exactly one `turn_exit` per expected
  conversation and interaction generation:

  ```bash
  reachable_base_url='<reachable-base-url>'
  curl -fsS "$reachable_base_url/models"
  CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
  CAVERNO_LLM_BASE_URL="$reachable_base_url" \
  CAVERNO_LLM_API_KEY=no-key \
  CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
  fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
    -d flutter-tester
  ```

  `<reachable-base-url>` includes `/v1`. Verify that the exact model is listed
  and warmed before running; a similarly named or larger model is not a
  substitute.

- Assert target-file coverage from `coverage/lcov.info` after the focused test:

  ```bash
  target='<target-production-file>'
  minimum='<minimum-percent>'
  awk -v target="$target" -v minimum="$minimum" '
    /^SF:/ {
      current = substr($0, 4)
      in_target = current == target
    }
    in_target && /^LF:/ { found = substr($0, 4) + 0 }
    in_target && /^LH:/ { hit = substr($0, 4) + 0 }
    in_target && /^end_of_record/ {
      rate = found == 0 ? 0 : (100.0 * hit / found)
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      checked = 1
      if (rate + 0.0001 < minimum) exit 1
      exit 0
    }
    END { if (!checked) exit 1 }
  ' coverage/lcov.info
  ```

## Mandatory Owner-Keying Prerequisites

The following repairs are dependency slices, not work that may be hidden
behind a typed-looking port. Specify, implement, and verify each repair before
the named extraction:

- P1a defines `ChatTurnOwner`. P1b adopts the corresponding owner snapshot and
  precedes WS6-2, WS6-7, WS6-10, and WS6-18.
- Before WS6-1, complete P5a, P5b, P5c, and P11. The current flat approval
  cache, pending approvals, and taint value cannot satisfy the poison tests.
- P5b precedes WS6-3 through WS6-10, WS6-12, and WS6-13.
- P5c precedes WS6-11a, WS6-11b, WS6-14, and WS6-16.
- Before WS6-4, complete P6 (`Key FileRollbackCheckpointStore by Owner`). A
  single process-wide rollback stack is forbidden.
- Before WS6-6, complete P7 (`Key Background Processes and Monitoring by
  Owner`) so `BackgroundProcessTools` jobs and
  `BackgroundProcessMonitorService` lookups are keyed by owner plus process ID.
  WS6-18 relies on the same repair for `process_status`, `process_tail`, and
  `process_wait`.
- Before WS6-9, complete P8 (`Key SSH Sessions by Owner`).
- Before WS6-17, complete P9 (`Key In-Memory Subagent Tasks by Owner`).
- In every slice that presents UI, reuse the P5b or P5c owner-keyed pending
  request and reject stale completion before resolving its port. Thread-scoped
  storage alone does not reject an older generation in the same conversation.

## WS6-1: Extract TurnToolApprovalCoordinator

### Task

- Goal: move approval-result reuse, denial caching, auto-review request
  construction, and approval-gate resolution behind an owner-aware
  coordinator.
- User-visible behavior: none; approval precedence, warning text, audit
  records, and denial payloads remain compatible.
- Non-goals: moving approval dialogs, changing approval policy, or changing the
  audit schema.

### Context

- Source: `chat_notifier_approval_handlers.dart` methods
  `_lookupToolApprovalResult`, `_rememberToolApprovalResult`,
  `_rememberToolApprovalDenial`, `_resolveToolApprovalGate`,
  `_recordApprovalAudit`, `_buildAutoReviewRequest`,
  `_runApprovalAutoReview`, `_domainEscalatesDeniedActionToManual`,
  `_escalatedApprovalWarningTitle`, `_escalatedApprovalWarningMessage`, and
  `_autoReviewDeniedResult`.
- Destination:
  `lib/features/chat/domain/services/turn_tool_approval_coordinator.dart`.
- Direct tests:
  `test/features/chat/domain/services/turn_tool_approval_coordinator_test.dart`.
- Required poison coverage: Slice 2b2 cross-thread and cross-generation
  approval isolation.

### Implementation Notes

- Reuse `ChatTurnOwner` from P1a. Define immutable `ToolApprovalRequest` and
  `ToolApprovalOutcome` values or reuse equally narrow independent types.
- Define owner-aware `ManualToolApprovalPort`, `ToolApprovalAutoReviewPort`, and
  `ToolApprovalAuditPort`. The notifier adapters may call existing UI and
  persistence services after validating the owner generation.
- Key reusable decisions by conversation, generation, and deterministic tool
  execution identity. No flat cache or visible-thread fallback is allowed.
- The coordinator owns precedence and result construction; the notifier owns
  UI presentation and application lifecycle.
- Manifest transition: `approval-handlers` from `remaining` to `extracted` only
  if the old part becomes empty; otherwise to `partial`.
- Append collaborator:
  - `id`: `turn-tool-approval-coordinator`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/turn_tool_approval_coordinator.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: turn-tool-approval-coordinator`.

### Similar-Pattern Search

- Search `_resolveToolApprovalGate`, `_toolApprovalCache`,
  `_recordApprovalAudit`, `ToolApprovalAutoReviewRequest`, and
  `requestToolApproval`.
- Inspect browser, Computer Use, Git, local-file, SSH, device, skill, and routine
  callers. Migrate only approval-gate ownership in this slice.

### Acceptance Criteria

1. Every cached lookup and write includes conversation and interaction
   generation.
2. The collaborator receives no notifier, state, provider, Zone, completer, or
   UI callback.
3. Direct tests cover remembered allow/deny, manual escalation, auto-review
   allow/deny/error, audit success/failure, warning variants, and stale-owner
   rejection.
4. Poison tests prove an earlier thread or generation cannot authorize the
   current owner.
5. Target-file line coverage is at least 95%.
6. Stop if any approval decision still depends on whichever conversation is
   visible when an asynchronous result completes.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/turn_tool_approval_coordinator.dart \
  lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart \
  test/features/chat/domain/services/turn_tool_approval_coordinator_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/turn_tool_approval_coordinator_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the owner key, port signatures, migrated callers, manifest transition,
  old/new counts, coverage, and Slice 2b2 poison cases.
- Completed on 2026-07-31 with exact `ChatTurnOwner` cache keys and a
  deterministic normalized tool/cache/state identity. The 489-line coordinator
  receives immutable request values and owner-aware manual, auto-review, audit,
  and liveness ports; the 70-line runtime adapter keeps notifier and provider
  callbacks outside the collaborator. Thirty-two focused tests cover 163/167
  executable lines (97.60%), including remembered allow/deny, escalation
  warnings,
  review and audit failures, exact-owner retirement, peer-thread isolation, and
  successor-generation isolation. The manifest moved `approval-handlers` to
  `partial`; its remaining UI adapters migrate with the typed handler slices.

## WS6-2: Extract LspGoToDefinitionToolHandler

### Task

- Goal: move LSP definition lookup argument validation and result mapping into
  an independent handler.
- User-visible behavior: none; validation errors, locations, paths, ranges, and
  JSON output remain compatible.
- Non-goals: changing the LSP protocol client or adding LSP operations.

### Context

- Source: `chat_notifier_local_file_handlers.dart` methods
  `_handleLspGoToDefinition`, `_oneBasedPositionValue`,
  `_lspDefinitionToJson`, and `_pathFromLspUri`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:60-71`.
- Destination:
  `lib/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/lsp_go_to_definition_tool_handler_test.dart`.

### Implementation Notes

- Define `LspDefinitionPort.goToDefinition(ChatTurnOwner owner, ...)`.
- Pass resolved project root and worktree path through `ChatTurnOwner`; the
  handler must not derive them from visible state.
- Preserve one-based input handling, URI conversion, multiple definition
  ordering, absent-location behavior, and current error payloads.
- Replace the registry binding directly. Leave unrelated local-file handlers in
  their current part.
- Manifest transition: `local-file-handlers` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `lsp-go-to-definition-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: lsp-go-to-definition-tool-handler`.

### Similar-Pattern Search

- Search `_handleLspGoToDefinition`, `lsp_go_to_definition`,
  `_pathFromLspUri`, `ProjectScopedToolArgumentResolver`, and
  `LanguageDiagnosticsBridge`.
- Do not move diagnostics feedback or unrelated project-scoped read tools.

### Acceptance Criteria

1. The four named methods live only in the collaborator.
2. Owner paths are explicit, immutable inputs and no callback captures the
   notifier.
3. Direct tests cover invalid path/line/column, zero and negative positions,
   file URI decoding, single/multiple/empty definitions, port errors, and exact
   result payloads.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact size budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if the current LSP service cannot be adapted without exposing a
   provider or mutable notifier state.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/lsp_go_to_definition_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/lsp_go_to_definition_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the port adapter, argument and URI branch matrix, registry binding,
  measured shrink, coverage, and canary identities.
- Completed on 2026-07-31 with an exact-owner `LspDefinitionPort` and lifecycle
  acknowledgement. The runtime adapter distinguishes unavailable, reused,
  started, compensated, and uncertain session effects and closes only the
  exact session started by an expired operation. Twenty-six focused tests
  cover 93/94 handler lines (98.94%), including invalid/missing/zero positions,
  file and non-file URIs, single/multiple/empty definitions, port errors,
  owner-generation poison, and settlement failures. The registry binding is
  owner-bound; the local-file part falls from 1,191 to 1,041 lines, declared
  parts fall to 11,123 lines, and the same-library aggregate falls to 20,035.

## WS6-3: Extract FileMutationToolHandler

### Task

- Goal: move write, edit, and delete execution plus approval-time file-change
  validation into one sub-500-line owner-aware handler.
- User-visible behavior: none; approval details, conflict detection, rollback
  capture, and tool result payloads remain compatible.
- Non-goals: moving rollback execution, changing filesystem semantics, or
  changing the mutation approval UI.

### Context

- Source: `chat_notifier_local_file_handlers.dart` methods
  `_handleWriteFile`, `_handleEditFile`, `_handleDeleteFile`,
  `_fileChangedSinceApprovalResult`,
  `_executeFileMutationToolAndCapture`, and
  `_isSuccessfulFileMutationResult`.
- Current registry bindings:
  `chat_notifier_tool_handler_registry.dart:84-91`.
- Destination:
  `lib/features/chat/domain/services/file_mutation_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/file_mutation_tool_handler_test.dart`.
- Existing execution dependency:
  `built_in_filesystem_tool_handler.dart`.

### Implementation Notes

- Define owner-aware `FileMutationExecutionPort`,
  `FileMutationApprovalPort`, and `FileMutationRollbackCapturePort`.
- Represent write, edit, and delete requests as a sealed or enumerated immutable
  operation model. Keep all three paths in one collaborator only while its
  achieved size remains below 500 lines.
- Resolve project/worktree roots in the notifier before dispatch. If
  `ProjectScopedToolArgumentResolver` is reused, call it with a closure over a
  plain resolved root, never over notifier state.
- Preserve approval-time fingerprint checks, successful-result detection,
  capture timing, error mapping, and exact tool names.
- Manifest transition: `local-file-handlers` remains `partial`.
- Append collaborator:
  - `id`: `file-mutation-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/file_mutation_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: file-mutation-tool-handler`.

### Similar-Pattern Search

- Search `_handleWriteFile`, `_handleEditFile`, `_handleDeleteFile`,
  `_executeFileMutationToolAndCapture`, `_fileChangedSinceApprovalResult`,
  `captureFileMutation`, and `requestFileChangeApproval`.
- Keep `_handleRollbackLastFileChange` for WS6-4.

### Acceptance Criteria

1. All six named methods move, and the registry maps all three tool names to the
   independent handler.
2. Every approval and filesystem effect carries the owning conversation and
   generation.
3. Direct tests cover create/overwrite, single/all edit replacement, delete,
   missing and invalid arguments, stale-file rejection, approval deny,
   execution errors, success detection, and rollback capture ordering.
4. Poison tests make a different visible thread expose conflicting roots and
   approvals without affecting the owner.
5. Target-file line coverage is at least 95% and physical size is below 500.
6. Stop if the combined handler exceeds 500 lines; split write from edit/delete
   rather than raising the budget.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/file_mutation_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/file_mutation_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/file_mutation_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the sealed request model, all port signatures, three registry
  bindings, poison cases, achieved file size, aggregate shrink, and coverage.

### Completion Evidence (2026-07-31)

WS6-3 is implemented. `FileMutationToolHandler` owns write, edit, and delete
validation, approval, conflict detection, effect dispatch, result
classification, and rollback recording through immutable exact-owner requests.
The production adapter binds the captured project root, messages, taint,
approval cache, filesystem fingerprint, and receipt-backed mutation boundary
to the request owner. All three registry names now dispatch through the shared
handler, and exact-owner terminalization retires pending mutation authority.

The 434-line handler reached 105/105 executable lines across 15 direct tests.
The 108-test focused handler, runtime, effect-boundary, transaction-fence,
filesystem, and rollback-store suite passed, as did four ChatNotifier
integration cases covering stale approval, path containment, cached command
approval coexistence, and post-mutation analyzer feedback. The notifier is
9,073 primary lines with 12,964 lines across 38 declared parts and a
22,037-line same-library aggregate. The historical `local-file-handlers`
record is `partial` with `file-mutation-tool-handler` as its collaborator.

## WS6-4: Extract FileRollbackToolHandler

### Task

- Goal: move `rollback_last_file_change` lookup, validation, approval, and
  execution into an owner-aware handler.
- User-visible behavior: none; rollback selection, approval details, and result
  payloads remain compatible.
- Non-goals: changing mutation capture history or combining rollback with new
  mutations.

### Context

- Source: `chat_notifier_local_file_handlers.dart` method
  `_handleRollbackLastFileChange`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:84-91`.
- Destination:
  `lib/features/chat/domain/services/file_rollback_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/file_rollback_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `FileRollbackHistoryPort`, `FileRollbackApprovalPort`, and
  `FileRollbackExecutionPort`.
- The history port must query only the owning conversation and interaction
  generation. Do not use a process-wide last mutation.
- Preserve no-history, stale-file, approval-denied, execution-failure, and
  success result shapes.
- Manifest transition: `local-file-handlers` remains `partial`.
- Append collaborator:
  - `id`: `file-rollback-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/file_rollback_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: file-rollback-tool-handler`.

### Similar-Pattern Search

- Search `_handleRollbackLastFileChange`, `rollback_last_file_change`,
  `_lastFileMutation`, `captureFileMutation`, and
  `requestFileChangeApproval`.
- Inspect Workstream 4 turn rollback but do not merge conversation rollback
  with file rollback.

### Acceptance Criteria

1. The handler has no access to a flat last-mutation field or visible thread.
2. Direct tests cover empty history, owner mismatch, changed file, allow/deny,
   successful rollback, execution error, and exact JSON payloads.
3. Poison tests prove another conversation's newer mutation is never selected.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if existing rollback history is not owner-keyed; repair that storage in
   a prerequisite slice rather than hiding a flat read in the port adapter.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/file_rollback_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/file_rollback_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/file_rollback_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the history key and adapter, branch cases, registry change, measured
  shrink, coverage, and canary identities.

### Completion Evidence (2026-07-31)

WS6-4 is implemented. The 225-line `FileRollbackToolHandler` selects only the
exact owner's checkpoint, binds approval to an immutable checkpoint token,
and treats mismatched or uncertain post-effect acknowledgements
conservatively. Its 225-line production adapter delegates to the owner-keyed
checkpoint store and rechecks owner liveness before and after restoration.
The existing registry name now reaches the handler through a 37-line MCP
service capability facade.

Thirty-three direct tests reached 85/86 executable handler lines (98.84%).
The 33-test runtime, conditional-store, and transaction-fence suite also
passed. The historical `local-file-handlers` record remains `partial` with
`file-rollback-tool-handler` appended. The notifier is 9,074 primary lines
with 12,942 lines across 38 declared parts and a 22,016-line same-library
aggregate.

## WS6-5: Extract LocalCommandToolHandler

### Task

- Goal: move synchronous local command validation, approval, execution, and
  result mapping into an independent owner-aware handler.
- User-visible behavior: none; working-directory resolution, timeout behavior,
  command permission handling, and output remain compatible.
- Non-goals: moving background process start/cancel or command guardrails.

### Context

- Source: `chat_notifier_local_file_handlers.dart` method
  `_handleLocalExecuteCommand`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:84-91`.
- Destination:
  `lib/features/chat/domain/services/local_command_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/local_command_tool_handler_test.dart`.
- Existing execution dependency:
  `built_in_local_command_tool_handler.dart`.

### Implementation Notes

- Define owner-aware `LocalCommandExecutionPort`,
  `LocalCommandApprovalPort`, and `CommandPermissionRuleStorePort`.
- Resolve project/worktree path before calling the handler. Carry the allowed
  working-directory boundary explicitly and preserve path escape rejection.
- The command approval port may present UI through a notifier adapter, but the
  handler must not receive completers or read the current conversation.
- Leave pre-execution command guardrails in Workstream 7; accept their approved
  result as an explicit input if required.
- Manifest transition: `local-file-handlers` remains `partial`.
- Append collaborator:
  - `id`: `local-command-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/local_command_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: local-command-tool-handler`.

### Similar-Pattern Search

- Search `_handleLocalExecuteCommand`, `local_execute_command`,
  `requestLocalCommandApproval`, `CommandPermissionRule`, `working_directory`,
  and `_guardCodingCommandBeforeExecution`.
- Do not move guardrail decisions or `process_start`.

### Acceptance Criteria

1. Synchronous local command execution uses only immutable owner and request
   inputs plus narrow ports.
2. Direct tests cover missing command, root/default/explicit working directory,
   path escape, timeout, approval allow/deny, remembered rule, execution error,
   exit code, stdout/stderr, and exact payloads.
3. Poison tests prove a visible thread's project root and permission rule do not
   affect the owner.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact size budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if command guardrail state or permission rules remain flat and cannot
   be supplied for the owner explicitly.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/local_command_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/local_command_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/local_command_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the working-directory contract, permission port, guardrail boundary,
  poison cases, measured counts, coverage, and canary identities.

### Completion Evidence (2026-07-31)

WS6-5 is implemented. The 404-line `LocalCommandToolHandler` owns immutable
command and working-directory validation, saved permission decisions, approval
outcomes, execution settlement, and compatible result mapping. Its exact-owner
contracts bind each launch to the owner, tool call, tool name, and canonical
argument digest. The 653-line runtime adapter freezes the permission snapshot,
compensates a remembered rule if its owner expires, serializes actual process
effects, and retains ambiguous post-dispatch effects for reconciliation.

Forty-one handler tests cover 161/169 executable lines (95.27%). Nineteen
runtime and permission-adapter tests plus the handler suite pass as a 60-test
focused set. The stale-owner persistence test and the approval grant/denial
replay integrations also pass. The historical `local-file-handlers` record
remains `partial` with `local-command-tool-handler` appended. The primary file
remains 8,912 lines, the local-file part falls from 1,041 to 1,029 lines, and
the same-library aggregate falls from 20,035 to 20,029 lines. The corrected
live canary remains deferred to the integrated tranche closure.

## WS6-6: Extract BackgroundProcessToolHandler

### Task

- Goal: move `process_start` and `process_cancel` request handling into one
  owner-aware background-process collaborator.
- User-visible behavior: none; command validation, approval, process identity,
  cancellation, and result payloads remain compatible.
- Non-goals: changing process storage, follow-up policy, or terminal UI.

### Context

- Source: `chat_notifier_local_file_handlers.dart` methods
  `_handleProcessStart` and `_handleProcessCancel`.
- Current registry bindings:
  `chat_notifier_tool_handler_registry.dart:84-91`.
- Destination:
  `lib/features/chat/domain/services/background_process_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/background_process_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `BackgroundProcessExecutionPort`,
  `BackgroundProcessLookupPort`, `LocalCommandApprovalPort`, and
  `CommandPermissionRuleStorePort`.
- Make the externally visible process ID distinct from any unscoped backend
  identity, or require the lookup port to validate owner plus process ID.
- Preserve process-start result policy from Workstream 5 as a direct
  dependency; do not copy its mapping logic.
- Preserve working-directory boundaries, environment handling, cancellation
  semantics, and current error codes.
- Manifest transition: `local-file-handlers` remains `partial`.
- Append collaborator:
  - `id`: `background-process-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/background_process_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: background-process-tool-handler`.

### Similar-Pattern Search

- Search `_handleProcessStart`, `_handleProcessCancel`, `process_start`,
  `process_cancel`, `BackgroundProcessFollowUpPolicy`, and process registries.
- Inspect terminal process controls but do not move presentation code.

### Acceptance Criteria

1. Start and cancel share an explicit owner-aware process contract.
2. Direct tests cover missing command/ID, working directories, approval
   allow/deny, start success/failure, cancellation success/not-found/already
   exited, owner mismatch, and exact result payloads.
3. Poison tests prove one conversation cannot cancel or inspect another
   conversation's process.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if the process registry cannot enforce ownership; fix that registry in
   a prerequisite slice instead of relying on obscured IDs.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/background_process_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/background_process_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/background_process_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record process ownership semantics, port adapters, registry bindings, poison
  cases, achieved size, coverage, and canary identities.

## WS6-7: Extract RunTestsToolHandler

### Task

- Goal: move test-runner inference, command construction, validation, approval,
  and execution into an independent owner-aware handler.
- User-visible behavior: none; inferred runners, quoting, normalized paths,
  command text, and result payloads remain compatible.
- Non-goals: changing supported runners, test diagnostics interpretation, or
  saved validation state.

### Context

- Source: `chat_notifier_local_file_handlers.dart` methods
  `_handleRunTests`, `_buildRunTestsError`, `_normalizeRunTestsRunner`,
  `_buildRunTestsCommand`, `_inferRunTestsRunner`,
  `_normalizeRunTestsPathForWorkingDirectory`,
  `_shellQuoteRunTestsArgument`, and `_normalizeRunTestsAbsolutePath`.
- Destination:
  `lib/features/chat/domain/services/run_tests_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/run_tests_tool_handler_test.dart`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:84-91`.

### Implementation Notes

- Define owner-aware `TestCommandExecutionPort` and reuse the narrow command
  approval and permission-rule ports from WS6-5.
- Keep pure runner inference and command construction private to the handler or
  an internal value helper; do not expose notifier test seams.
- Resolve the owner root before dispatch. Normalize all requested test paths
  against that root and preserve the current shell quoting exactly.
- Saved validation ownership remains a Workstream 7 concern. Emit execution
  evidence through an explicit owner-aware result port if current behavior
  requires it.
- Manifest transition: `local-file-handlers` remains `partial`.
- Append collaborator:
  - `id`: `run-tests-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/run_tests_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: run-tests-tool-handler`.

### Similar-Pattern Search

- Search `_handleRunTests`, `_buildRunTestsCommand`, `_inferRunTestsRunner`,
  `_shellQuoteRunTestsArgument`, `run_tests`, and saved validation writes.
- Compare existing `DartProjectTooling` behavior but do not change its API
  unless a narrow independent reuse is necessary.

### Acceptance Criteria

1. All eight named methods move and the registry uses the handler directly.
2. Direct tests cover explicit and inferred runners, root and nested working
   directories, absolute/relative paths, spaces and shell metacharacters,
   empty targets, invalid runner, approval outcomes, exit states, and exact
   commands and payloads.
3. Poison tests prove project root, task target, and validation evidence remain
   attached to the owning turn.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if command construction cannot be tested without real process
   execution or a notifier-bound callback.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/run_tests_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/run_tests_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/run_tests_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the runner/quoting matrix, execution and evidence ports, poison
  assertions, measured shrink, coverage, and canary identities.

## WS6-8: Extract GitToolHandler

### Task

- Goal: move Git command execution, worktree-session finishing, and Git
  lifecycle result interpretation into one sub-500-line owner-aware handler.
- User-visible behavior: none; approval behavior, worktree paths, completion
  detection, and final response text remain compatible.
- Non-goals: changing Git guardrails, branch policy, repository discovery, or
  Git UI.

### Context

- Source: `chat_notifier_git_handlers.dart` methods
  `_handleGitExecuteCommand`, `_handleGitFinishWorktreeSession`,
  `_boolArgument`, `_toolResultsSatisfyCurrentGoalGitLifecycle`,
  `_buildGitLifecycleCompletionResponse`, `_normalizedGitSubcommand`,
  `_gitStatusResultIsClean`, and `_firstCodingGoalMarker`.
- Public UI bridge methods at the end of that part remain in the notifier.
- Current registry bindings:
  `chat_notifier_tool_handler_registry.dart:129-130`.
- Destination:
  `lib/features/chat/domain/services/git_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/git_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `GitExecutionPort`, `GitWorktreeSessionPort`, and
  `GitApprovalPort`.
- Pass resolved repository and worktree paths through `ChatTurnOwner`.
- Preserve command subcommand normalization, clean-status inference, lifecycle
  marker selection, finish options, response wording, and result ordering.
- Keep Git tag and write-confirmation guardrails in Workstream 7; accept their
  decision as explicit input or invoke an independent policy directly.
- Manifest transition: `git-handlers` from `remaining` to `partial` because the
  public UI bridge remains.
- Append collaborator:
  - `id`: `git-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/git_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: git-tool-handler`.

### Similar-Pattern Search

- Search `_handleGitExecuteCommand`, `_handleGitFinishWorktreeSession`,
  `_toolResultsSatisfyCurrentGoalGitLifecycle`, `git_execute_command`,
  `git_finish_worktree_session`, and `requestGitCommandApproval`.
- Inspect Git write confirmation and tag-format guardrails without moving them.

### Acceptance Criteria

1. The eight named methods live only in the collaborator; UI request/resolve
   methods remain thin notifier adapters.
2. Direct tests cover invalid commands, allow/deny, execution failures, finish
   options, clean/dirty status, lifecycle marker permutations, and exact
   completion response text.
3. Poison tests prove repository, worktree, approval, and lifecycle evidence
   come from the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if execution and lifecycle interpretation exceed 500 lines together;
   split a pure `GitLifecycleCompletionPolicy` first.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/git_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_git_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/git_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/git_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the owner-aware Git ports, UI boundary, lifecycle branch matrix,
  measured size and shrink, coverage, and canary identities.

## WS6-9: Extract SshToolHandler

### Task

- Goal: move SSH connect and command execution into an independent owner-aware
  handler while leaving credential and approval UI in notifier adapters.
- User-visible behavior: none; host-key, credential, approval, connection, and
  command result behavior remain compatible.
- Non-goals: changing SSH transport policy, credential persistence, or dialogs.

### Context

- Source: `chat_notifier_ssh_handlers.dart` methods `_handleSshConnect` and
  `_handleSshExecuteCommand`.
- Public SSH request/resolve methods later in the part remain notifier UI
  bridges.
- Current registry bindings:
  `chat_notifier_tool_handler_registry.dart:115-116`.
- Destination:
  `lib/features/chat/domain/services/ssh_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/ssh_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `SshCredentialPort`, `SshConnectionPort`,
  `SshCommandExecutionPort`, and `SshCommandApprovalPort`.
- Pass host, port, username, owner, and connection identity explicitly. A
  connection lookup must validate ownership.
- Preserve password/key selection, cancellation, host-key errors, timeouts,
  command approval, stdout/stderr, exit code, and exact error payloads.
- Manifest transition: `ssh-handlers` from `remaining` to `partial` because UI
  bridges remain.
- Append collaborator:
  - `id`: `ssh-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/ssh_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: ssh-tool-handler`.

### Similar-Pattern Search

- Search `_handleSshConnect`, `_handleSshExecuteCommand`, `ssh_connect`,
  `ssh_execute_command`, SSH pending completers, and stored connections.
- Inspect the built-in SSH data-source handler, but keep transport mechanics in
  that lower-level dependency.

### Acceptance Criteria

1. Connect and command flows use owner-aware ports and no UI or provider type
   crosses the collaborator boundary.
2. Direct tests cover argument validation, credential cancellation, password
   and key paths, connection errors, approval allow/deny, timeouts,
   owner-mismatched connection, exit variants, and exact payloads.
3. Poison tests prove another conversation cannot reuse a connection,
   credential response, or command approval.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if connection storage is flat or credential completion cannot validate
   the owning conversation and generation.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/ssh_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_ssh_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/ssh_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ssh_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record connection ownership, credential and approval adapters, branch matrix,
  part shrink, coverage, and canary identities.

## WS6-10: Extract PythonScriptToolHandler

### Task

- Goal: move Python-script request validation, input attachment selection, and
  execution routing into an owner-aware handler.
- User-visible behavior: none; script inputs, staged attachments, result
  payloads, and errors remain compatible.
- Non-goals: changing Python attachment repair or the Python runtime service.

### Context

- Source: `chat_notifier_python_handlers.dart` methods
  `_handlePythonScript` and `_latestPythonInputMessage`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:103`.
- Destination:
  `lib/features/chat/domain/services/python_script_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/python_script_tool_handler_test.dart`.

### Implementation Notes

- Define `PythonScriptExecutionPort.execute(ChatTurnOwner owner, ...)`.
- Resolve the owning turn's latest eligible input message before dispatch, or
  pass the owner's immutable message list to a pure selector. Never read
  `state.messages` inside the collaborator.
- Preserve script, timeout, attachment metadata, path staging, disabled-runtime
  behavior, and exact result/error mapping.
- Reuse the Workstream 4 attachment-repair policy only after execution; do not
  copy it into this handler.
- Manifest transition: `python-handlers` from `remaining` to `extracted`;
  remove the part if no code remains.
- Append collaborator:
  - `id`: `python-script-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/python_script_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: python-script-tool-handler`.

### Similar-Pattern Search

- Search `_handlePythonScript`, `_latestPythonInputMessage`,
  `run_python_script`, `caverno.inputs`, and Python attachment staging.
- Inspect Python attachment repair callers but keep them in Workstream 4.

### Acceptance Criteria

1. The owning input message is selected without visible-thread state.
2. Direct tests cover missing/empty script, timeout values, no input,
   attachment and non-attachment messages, multiple inputs, disabled runtime,
   execution success/failure, and exact payloads.
3. Poison tests prove a newer visible conversation's attachment is never sent
   to the owner's Python execution.
4. Target-file line coverage is at least 95%.
5. The old part is removed, declared part count falls by one, and manifest,
   marker, budgets, structural gates, and live canary pass.
6. Stop if attachment staging cannot accept an explicit owner or immutable
   message input.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/python_script_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/python_script_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/python_script_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record owner-message selection, execution port, migrated binding, removed
  part count, poison cases, coverage, and canary identities.

## WS6-11a: Extract BleConnectionToolHandler

### Task

- Goal: move BLE connect execution into an owner-aware handler while leaving
  manual-approval UI in notifier adapters.
- User-visible behavior: none; argument validation, approval, connection
  results, and errors remain compatible.
- Non-goals: adding BLE operations, changing the BLE transport, or moving the
  connection dialog.

### Context

- Source: `chat_notifier_ble_handlers.dart` method `_handleBleConnect`.
- Public `requestBleConnect` and `resolveBleConnect` methods remain notifier UI
  bridges.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:143`.
- Destination:
  `lib/features/chat/domain/services/ble_connection_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/ble_connection_tool_handler_test.dart`.

### Implementation Notes

- Reuse `ChatTurnOwner`, WS6-1's approval coordinator, and P5c's owner-keyed
  manual approval request. Define only the owner-aware `BleConnectionPort`.
- Use typed BLE request and result values. The request carries the explicit
  `device_id`; scan results may supply only the display name.
- Validate conversation and generation again when asynchronous manual approval
  completes. There is no device-selection step in the current flow.
- Manifest transition: `ble-handlers` from `remaining` to `partial` because
  public UI bridges remain.
- Append collaborator:
  - `id`: `ble-connection-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/ble_connection_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: ble-connection-tool-handler`.

### Similar-Pattern Search

- Search `_handleBleConnect`, `ble_connect`, `requestBleConnect`,
  `resolveBleConnect`, approval completers, and BLE connection registries.
- Inspect the built-in BLE data-source handler without moving transport code.

### Acceptance Criteria

1. BLE execution uses an explicit owner-aware connection port and the shared
   approval coordinator; UI methods remain thin owner-validating adapters.
2. Direct tests cover a missing `device_id`, known and unknown display names,
   cached/bypassed/manual approval, denial, success/error paths, port failures,
   stale approval completion, and exact payloads.
3. Poison tests prove another conversation's approval or connection result
   cannot satisfy the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. The `ble-handlers` manifest record, marker, exact budget, aggregate ratchet,
   structural gates, thread-scope ratchet, and live canary pass.
6. Stop if BLE connection lookup cannot validate conversation and generation.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/ble_connection_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_ble_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/ble_connection_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ble_connection_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the BLE connection and shared approval ports, stale-approval tests,
  the `ble-handlers` transition, achieved file size, coverage, and canary
  identities.

## WS6-11b: Extract SerialConnectionToolHandler

### Task

- Goal: move serial-open execution and result-error parsing into an owner-aware
  handler while leaving manual-approval UI in notifier adapters.
- User-visible behavior: none; port validation, baud-rate handling, approval,
  result parsing, and errors remain compatible.
- Non-goals: adding serial operations, changing the serial transport, or moving
  the connection dialog.

### Context

- Source: `chat_notifier_serial_handlers.dart` methods `_handleSerialOpen` and
  `_serialResultIsError`.
- Public `requestSerialOpen` and `resolveSerialOpen` methods remain notifier UI
  bridges.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:144`.
- Destination:
  `lib/features/chat/domain/services/serial_connection_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/serial_connection_tool_handler_test.dart`.
- Prerequisite: WS6-11a.

### Implementation Notes

- Reuse `ChatTurnOwner`, WS6-1's approval coordinator, and P5c's owner-keyed
  manual approval request. Define only the owner-aware
  `SerialConnectionPort`.
- Use typed serial request and result values, preserve the current JSON error
  detector exactly, and forward the explicit `port` and serial options.
- Validate conversation and generation again when asynchronous manual approval
  completes. There is no port-selection step in the current flow.
- Manifest transition: `serial-handlers` from `remaining` to `partial` because
  public UI bridges remain.
- Append collaborator:
  - `id`: `serial-connection-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/serial_connection_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: serial-connection-tool-handler`.

### Similar-Pattern Search

- Search `_handleSerialOpen`, `_serialResultIsError`, `serial_open`,
  `requestSerialOpen`, `resolveSerialOpen`, approval completers, and serial
  connection registries.
- Inspect the built-in serial data-source handler without moving transport
  code.

### Acceptance Criteria

1. Serial execution uses an explicit owner-aware connection port and the
   shared approval coordinator; UI methods remain thin owner-validating
   adapters.
2. Direct tests cover a missing port, option defaults and forwarding,
   cached/bypassed/manual approval, denial, success, malformed and structured
   error results, port failures, stale approval completion, and exact payloads.
3. Poison tests prove another conversation's approval or connection result
   cannot satisfy the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. The `serial-handlers` manifest record, marker, exact budget, aggregate
   ratchet, structural gates, thread-scope ratchet, and live canary pass.
6. Stop if serial connection lookup cannot validate conversation and
   generation.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/serial_connection_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_serial_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/serial_connection_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/serial_connection_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the serial connection and shared approval ports, result-parsing
  fixtures, stale-approval tests, the `serial-handlers` transition, achieved
  file size, coverage, and canary identities.

## WS6-12: Extract SaveSkillToolHandler

### Task

- Goal: move `save_skill` parsing, duplicate lookup, approval, persistence, and
  result mapping into an owner-aware handler.
- User-visible behavior: none; validation, preview, duplicate behavior, saved
  content, and result payloads remain compatible.
- Non-goals: changing skill Markdown format, similarity policy, or settings UI.

### Context

- Source: entire `chat_notifier_skill_handlers.dart`, including
  `_handleSaveSkill` and `_findSkillByName`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:156`.
- Destination:
  `lib/features/chat/domain/services/save_skill_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/save_skill_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `SkillStorePort` and `SkillSaveApprovalPort`.
- Pass an immutable owner-scoped skill snapshot for duplicate checks, or expose
  an owner-aware lookup through the store port.
- Reuse `SkillMarkdownParser` and `SkillSimilarityService` directly where their
  APIs are already independent.
- Preserve validation ordering, replacement behavior, approval preview, saved
  entity fields, and exact success/error payloads.
- Manifest transition: `skill-handlers` from `remaining` to `extracted`;
  remove the old part.
- Append collaborator:
  - `id`: `save-skill-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/save_skill_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: save-skill-tool-handler`.

### Similar-Pattern Search

- Search `_handleSaveSkill`, `_findSkillByName`, `save_skill`,
  `SkillMarkdownParser`, `SkillSimilarityService`, and skill store writes.
- Do not change skill import/export or UI editing flows.

### Acceptance Criteria

1. The old part is absent and the registry uses the collaborator directly.
2. Direct tests cover missing fields, invalid Markdown, new/duplicate/replaced
   skill, approval allow/deny, persistence errors, similarity warnings, and
   exact payloads.
3. Poison tests prove a different conversation's pending approval or transient
   state cannot complete the owner operation.
4. Target-file line coverage is at least 95%.
5. Declared part count, manifest, marker, exact budget, aggregate ratchet,
   structural gate, thread-scope ratchet, and live canary pass.
6. Stop if the store or approval response cannot validate owner identity.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/save_skill_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/save_skill_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/save_skill_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record store and approval ports, parsing and duplicate branch matrix, part
  removal, measured counts, coverage, and canary identities.

## WS6-13: Extract CreateRoutineToolHandler

### Task

- Goal: move `create_routine` parsing, preview construction, duplicate lookup,
  approval, persistence, and result mapping into an owner-aware handler.
- User-visible behavior: none; schedule parsing, preview wording, defaults,
  saved routine fields, and result payloads remain compatible.
- Non-goals: changing routine execution, scheduler behavior, or routine UI.

### Context

- Source: entire `chat_notifier_routine_handlers.dart`, including
  `_handleCreateRoutine`, `_findNewestRoutineNamed`,
  `_routineScheduleSummary`, `_buildRoutinePreview`,
  `_parseRoutineScheduleMode`, `_parseRoutineIntervalUnit`,
  `_parseRoutineCompletionAction`, `_parseRoutineGoogleChatRule`, and
  `_parseRoutineTimeOfDayMinutes`.
- Current registry binding:
  `chat_notifier_tool_handler_registry.dart:167`.
- Destination:
  `lib/features/chat/domain/services/create_routine_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/create_routine_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `RoutineStorePort` and `RoutineCreationApprovalPort`.
- Keep schedule parsers and preview construction pure and private to the
  collaborator.
- Use an owner-scoped routine snapshot or owner-aware lookup port for duplicate
  selection. Preserve newest-match semantics.
- Preserve all default enum values, time normalization, completion actions,
  Google Chat rules, preview formatting, and exact errors.
- Manifest transition: `routine-handlers` from `remaining` to `extracted`;
  remove the old part.
- Append collaborator:
  - `id`: `create-routine-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/create_routine_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: create-routine-tool-handler`.

### Similar-Pattern Search

- Search `_handleCreateRoutine`, `_buildRoutinePreview`,
  `_parseRoutineScheduleMode`, `create_routine`, and routine notifier writes.
- Inspect routine task execution but do not move it into this slice.

### Acceptance Criteria

1. All nine named methods move and the old part is removed.
2. Direct tests cover every enum/default, interval and time boundaries,
   missing/invalid fields, newest duplicate selection, preview text, approval
   allow/deny, persistence errors, and exact payloads.
3. Poison tests prove another conversation's pending approval or routine
   snapshot cannot satisfy the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Declared part count, manifest, marker, exact budget, aggregate ratchet,
   structural gate, thread-scope ratchet, and live canary pass.
6. Stop if routine persistence cannot be adapted through a narrow owner-aware
   port.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/create_routine_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/create_routine_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/create_routine_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record all parsing/default branches, port contracts, part removal, achieved
  size and aggregate, coverage, and canary identities.

## WS6-14: Extract BrowserToolHandler

### Task

- Goal: move browser action classification, approval routing, execution, and
  presentation details into an owner-aware handler while leaving approval UI
  in notifier adapters.
- User-visible behavior: none; sensitive-action detection, review arguments,
  descriptions, targets, approval decisions, and results remain compatible.
- Non-goals: changing Browser APIs, adding actions, or moving dialogs.

### Context

- Source: `chat_notifier_browser_handlers.dart` methods
  `_handleBrowserAction`, `_handleBrowserActionWithoutApproval`,
  `_browserReviewArguments`, `_browserAutoReviewDeniedResult`,
  `_describeBrowserAction`, `_browserTargetLabel`,
  `_browserActionDetails`, `_browserActionTargetSummary`,
  `_browserSensitiveValuePreview`, and `_browserLooksLikeSecret`.
- Public browser approval request/resolve methods at lines 125-169 remain
  notifier UI bridges.
- Dispatcher call site:
  `chat_notifier.dart:7776-7777`.
- Destination:
  `lib/features/chat/domain/services/browser_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/browser_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `BrowserExecutionPort`, `BrowserApprovalPort`, and a narrow
  `BrowserObservationPort` only if action details require current page data.
- Keep description and secret-detection logic in the handler as pure helpers.
- Preserve approval bypass rules, auto-review denial mapping, target summaries,
  redaction previews, and result/error forwarding.
- Manifest transition: `browser-handlers` from `remaining` to `partial` because
  public UI bridges remain.
- Append collaborator:
  - `id`: `browser-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/browser_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: browser-tool-handler`.

### Similar-Pattern Search

- Search `_handleBrowserAction`, `_describeBrowserAction`,
  `_browserLooksLikeSecret`, `browser_action`, `requestBrowserApproval`, and
  direct dispatcher branches.
- Inspect Computer Use action descriptions for parity, but do not merge the two
  handlers.

### Acceptance Criteria

1. All ten named methods move; notifier UI methods remain thin owner-validating
   adapters.
2. Direct tests cover every browser action kind, safe and sensitive values,
   target summaries, no-approval and approval routes, allow/deny/error,
   observation failures, and exact descriptions and payloads.
3. Poison tests prove another conversation's browser approval or page metadata
   cannot satisfy the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, dispatcher tests, and live canary pass.
6. Stop if action-detail construction requires a broad Browser controller;
   introduce a read-only typed observation port instead.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/browser_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_browser_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/browser_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/browser_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record action/approval matrices, typed browser ports, UI boundary, direct
  dispatcher replacement, measured counts, coverage, and canary identities.

## WS6-15: Extract ComputerUseActionPolicy

### Task

- Goal: move Computer Use approval presentation, target extraction,
  post-action observation composition, result redaction, and blocked-result
  formatting into a pure policy below 500 lines.
- User-visible behavior: none; approval descriptions, detail text, redaction,
  vision arguments, and blocked messages remain compatible.
- Non-goals: moving action execution, approval UI, or Computer Use runtime
  access.

### Context

- Source: `chat_notifier_computer_use_handlers.dart` methods
  `_computerUseResultWithPostActionObservation`,
  `_redactComputerUseActionResult`,
  `_computerUsePostActionVisionArguments`,
  `_computerUseBlockedResult`, `_computerUseBlockedErrorMessage`,
  `_computerUseMetadataString`, `_computerUseVisionObservationContext`,
  `_computerUseActionTarget`, `_computerUseExactText`,
  `_describeComputerUseAction`, `_computerUseActionDetails`,
  `_summarizeComputerUseText`, `_formatComputerUseKey`, and
  `_formatComputerUseSpaceDirection`.
- Destination:
  `lib/features/chat/domain/services/computer_use_action_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/computer_use_action_policy_test.dart`.

### Implementation Notes

- Expose immutable input and output values for approval presentation,
  post-action observation arguments, composed results, and blocked results.
- Replace runtime reads with explicit action arguments, action result,
  observation result, and immutable metadata inputs.
- Preserve exact key formatting, text truncation, action-specific details,
  target fields, redaction keys, and blocked error codes/messages.
- Leave `_runComputerUsePostActionObservation` in the notifier part until
  WS6-16 supplies a typed observation port.
- Manifest transition:
  `computer-use-handlers` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `computer-use-action-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/computer_use_action_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: computer-use-action-policy`.

### Similar-Pattern Search

- Search `_describeComputerUseAction`, `_computerUseActionDetails`,
  `_computerUseBlockedResult`, `_redactComputerUseActionResult`,
  `computer_use_action`, and post-action vision metadata.
- Compare browser presentation behavior but keep protocols separate.

### Acceptance Criteria

1. All fourteen named pure methods move and accept only explicit immutable
   inputs.
2. Direct tests cover every supported action, targets and absent targets,
   keyboard modifiers, space directions, exact/long/secret text, observation
   present/absent/error, redaction, every blocked code, and exact strings/maps.
3. No side-effect or UI type appears in the policy.
4. Target-file line coverage is 100% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
6. Stop if the policy exceeds 500 lines; split result composition from approval
   presentation into two consecutive pure-policy slices.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/computer_use_action_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_computer_use_handlers.dart \
  test/features/chat/domain/services/computer_use_action_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/computer_use_action_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=100`,
then run the corrected live canary.

### Handoff Notes

- Record the explicit policy inputs, full action/redaction branch matrix,
  achieved file size, aggregate shrink, coverage, and canary identities.

## WS6-16: Extract ComputerUseToolHandler

### Task

- Goal: move Computer Use approval routing, action execution, and post-action
  observation orchestration into an owner-aware handler below 500 lines.
- User-visible behavior: none; approval timing, action order, observation
  behavior, result composition, and errors remain compatible.
- Non-goals: moving approval UI, changing action policy, or changing the
  Computer Use transport.

### Context

- Source: `chat_notifier_computer_use_handlers.dart` methods
  `_handleComputerUseAction`, `_handleComputerUseActionWithoutApproval`, and
  `_runComputerUsePostActionObservation`.
- Policy dependency: WS6-15 `ComputerUseActionPolicy`.
- Public approval request/resolve methods at lines 349-522 remain notifier UI
  bridges.
- Dispatcher call site:
  `chat_notifier.dart:7774-7775`.
- Destination:
  `lib/features/chat/domain/services/computer_use_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/computer_use_tool_handler_test.dart`.

### Implementation Notes

- Define owner-aware `ComputerUseExecutionPort`,
  `ComputerUseApprovalPort`, and `ComputerUseObservationPort`.
- The observation port must accept the same owner and immutable action result;
  reject stale generation before taking a screenshot or vision observation.
- Use `ComputerUseActionPolicy` for review presentation, blocked outcomes,
  redaction, observation arguments, and final result composition.
- Preserve the approval/no-approval split, action-before-observation ordering,
  observation fallback, transport errors, and exact result payloads.
- Manifest transition: `computer-use-handlers` remains `partial` because public
  UI bridges remain. Remove the part only if a later measured cleanup leaves no
  notifier-owned code.
- Append collaborator:
  - `id`: `computer-use-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/computer_use_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: computer-use-tool-handler`.

### Similar-Pattern Search

- Search `_handleComputerUseAction`,
  `_runComputerUsePostActionObservation`, `computer_use_action`,
  `requestComputerUseApproval`, and the direct dispatcher branch.
- Inspect browser approval routing for consistent owner checks without sharing
  protocol-specific types.

### Acceptance Criteria

1. All three execution methods move and the direct dispatcher uses the handler.
2. Public UI bridges validate owner and generation before completing the typed
   approval port.
3. Direct tests cover approval-required and bypass routes, allow/deny,
   auto-review result, action success/error, observation success/empty/error,
   stale owner, and exact ordering and payloads.
4. Poison tests prove another conversation's approval, action metadata, or
   observation cannot complete the owner turn.
5. Target-file line coverage is at least 95% and physical size is below 500.
6. Stop if the Computer Use runtime or vision request must be passed as a broad
   service locator.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/computer_use_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_computer_use_handlers.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/computer_use_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/computer_use_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the three ports, owner-validation boundary, execution/observation call
  order, poison cases, measured counts, coverage, and canary identities.

## WS6-17: Extract SubagentToolHandler

### Task

- Goal: move subagent spawn, background execution, child-tool dispatch,
  completion notification, and result lookup into an owner-aware handler.
- User-visible behavior: none; task states, background behavior, child tool
  results, notifications, and returned payloads remain compatible.
- Non-goals: changing subagent prompts, concurrency limits, or participant
  turns.

### Context

- Source: entire `chat_notifier_subagent_handlers.dart`, including
  `_handleSpawnSubagent`, `_startBackgroundSubagent`,
  `_runBackgroundSubagent`, `_runSubagent`, `_dispatchChildToolCall`,
  `_notifySubagentDone`, and `_handleGetSubagentResult`.
- Current registry bindings:
  `chat_notifier_tool_handler_registry.dart:183-195`.
- Destination:
  `lib/features/chat/domain/services/subagent_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/subagent_tool_handler_test.dart`.
- Existing independent references:
  `SubagentExecutionService` and `SubagentToolPolicy`.

### Implementation Notes

- Define owner-aware `SubagentTaskStorePort`, `SubagentExecutionPort`,
  `ChildToolExecutionPort`, and `SubagentNotificationPort`.
- Make task identity owner-scoped. Result lookup must validate conversation and
  interaction generation, including background completions after a thread
  switch.
- Reuse existing independent subagent policies rather than duplicating them.
- Child tool dispatch receives an immutable allowlist and the parent owner; it
  must not call back into the whole notifier.
- Manifest transition: `subagent-handlers` from `remaining` to `extracted`;
  remove the old part.
- Append collaborator:
  - `id`: `subagent-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/subagent_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: subagent-tool-handler`.

### Similar-Pattern Search

- Search `_handleSpawnSubagent`, `_dispatchChildToolCall`,
  `_handleGetSubagentResult`, `SubagentTask`, `spawn_subagent`,
  `get_subagent_result`, and background notifications.
- Inspect participant turns but keep their lifecycle in Workstream 8.

### Acceptance Criteria

1. All seven named methods move and task/result lookup is owner-scoped.
2. Direct tests cover foreground/background spawn, invalid requests, execution
   success/failure, child allow/deny/error, notification success/failure,
   pending/completed/missing result, cancellation if supported, and exact
   payloads.
3. Poison tests prove queued or completed work from another conversation cannot
   block or satisfy the owner.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Old part removal, part count, manifest, marker, exact budget, aggregate
   ratchet, structural gates, and live canary pass.
6. Stop if child dispatch requires a callback to generic notifier tool
   execution; introduce a narrow `ChildToolExecutionPort` with an explicit
   allowlist instead.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/subagent_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/subagent_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/subagent_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record owner-scoped task keys, all four ports, child allowlist behavior, part
  removal, poison cases, coverage, and canary identities.

## WS6-18: Extract ProjectScopedReadToolHandler

### Task

- Goal: replace the notifier-bound generic project-tool dispatch callback with
  an independently importable owner-aware handler.
- User-visible behavior: none; allowed definitions, project argument
  resolution, MCP execution, and result payloads remain compatible.
- Non-goals: moving specialized handlers, changing tool definitions, or
  changing MCP transport.

### Context

- Source:
  - `_ProjectScopedToolHandlerModule` in
    `chat_notifier_tool_handler_registry.dart:52-74`;
  - notifier `_dispatchToolCall` and `_handleProjectScopedTool` paths in
    `chat_notifier.dart:7762-7801`;
  - `_toolDefinitionsAllowedBy` and `_logAllowedToolDefinitions` remain
    notifier setup until WS6-19.
- Existing independent resolver:
  `ProjectScopedToolArgumentResolver`.
- Destination:
  `lib/features/chat/domain/services/project_scoped_read_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/project_scoped_read_tool_handler_test.dart`.

### Implementation Notes

- Define `McpToolExecutionPort.execute(ChatTurnOwner owner, String name,
  Map<String, dynamic> arguments)`.
- Accept an immutable set of supported tool names and an explicit owner root.
  Resolve arguments through `ProjectScopedToolArgumentResolver` using a closure
  over that plain root only.
- Preserve missing-root, unsupported-tool, argument-resolution, execution
  failure, and result forwarding behavior.
- Do not accept `_handleProjectScopedTool`, `_mcpToolService!.executeTool`,
  `_turnProjectRootFor`, or any notifier member as a callback.
- Manifest transition: `tool-handler-registry` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `project-scoped-read-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/project_scoped_read_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: project-scoped-read-tool-handler`.

### Similar-Pattern Search

- Search `_ProjectScopedToolHandlerModule`,
  `_handleProjectScopedTool`, `ProjectScopedToolArgumentResolver`,
  `_mcpToolService!.executeTool`, and `_turnProjectRootFor`.
- Verify specialized LSP, local-file, Git, SSH, and Python bindings are not
  accidentally routed through this generic handler.

### Acceptance Criteria

1. Generic project-scoped read dispatch has no notifier-capturing callback.
2. Direct tests cover supported/unsupported tools, absent root, explicit root,
   resolved and unchanged arguments, resolver errors, MCP errors, and exact
   result forwarding.
3. Poison tests prove a different visible project cannot alter the owner root
   or arguments.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gate,
   thread-scope ratchet, registry tests, and live canary pass.
6. Stop if any supported tool requires mutable chat state; give that tool a
   dedicated handler slice instead of widening this port.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/project_scoped_read_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/project_scoped_read_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/project_scoped_read_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=95`,
then run the corrected live canary.

### Handoff Notes

- Record the supported tool set, explicit resolver inputs, MCP port, poison
  cases, registry-part shrink, coverage, and canary identities.

## WS6-19: Extract ChatToolHandlerCatalog

### Task

- Goal: move final tool-name-to-handler catalog construction out of the
  notifier library after every preceding WS6 handler is independent.
- User-visible behavior: none; allowed definitions, handler precedence,
  fallbacks, and dispatch results remain compatible.
- Non-goals: adding or removing tools, changing tool availability policy, or
  redesigning `ChatToolHandlerRegistry`.

### Context

- Source: entire remaining
  `chat_notifier_tool_handler_registry.dart`, including
  `_toolDefinitionsAllowedBy`, `_logAllowedToolDefinitions`,
  `_buildToolHandlerRegistry`, and all remaining
  `_...ToolHandlerModule` classes.
- Dispatcher call sites:
  `chat_notifier.dart:7762-7785`.
- Destination:
  `lib/features/chat/domain/services/chat_tool_handler_catalog.dart`.
- Direct tests:
  `test/features/chat/domain/services/chat_tool_handler_catalog_test.dart`.
- Prerequisites: WS6-1 through WS6-10, WS6-11a, WS6-11b, and WS6-12 through
  WS6-18 are complete. WS8-2 (`AskUserQuestionPolicy`) and WS8-7
  (`GoalUpdateToolHandler`) must also be merged and green.

### Implementation Notes

- Construct the catalog from typed handler interfaces or functions that accept
  `ChatTurnOwner` and `ToolCallInfo`. No catalog entry may capture a notifier.
- Keep allowed-definition filtering pure. Route diagnostic logging through an
  optional narrow `ToolDefinitionLogPort` or keep the log call in the notifier
  around the returned filtered list.
- Preserve exact module ordering and duplicate-name precedence. Keep browser
  and Computer Use direct branches only if protocol-specific dispatch requires
  them; otherwise register them without changing behavior.
- Preserve the generic MCP fallback as an explicit `McpToolExecutionPort`.
- Manifest transition: `tool-handler-registry` from `partial` to `extracted`;
  remove the part.
- Append collaborator:
  - `id`: `chat-tool-handler-catalog`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/chat_tool_handler_catalog.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: chat-tool-handler-catalog`.

### Similar-Pattern Search

- Search `_buildToolHandlerRegistry`, `_toolDefinitionsAllowedBy`,
  `ChatToolHandlerRegistry`, every `_...ToolHandlerModule`,
  `_dispatchToolCall`, and generic fallback execution.
- Enumerate every tool name before and after. Treat a missing, duplicated, or
  reordered binding as a blocker.

### Acceptance Criteria

1. The old registry part is removed and no catalog callback captures
   `ChatNotifier`.
2. A golden binding test proves the complete tool-name set, precedence, owner
   propagation, specialized routes, and generic fallback.
3. Direct tests cover allowlist filtering, empty/all definitions, duplicate
   names, module ordering, handler success/error, unsupported names, and
   fallback behavior.
4. Poison tests prove owner identity reaches every registered handler when the
   visible thread changes during dispatch.
5. Target-file line coverage is 100% and physical size is below 500.
6. Stop if any remaining module stores `ChatNotifier`; return to the owning
   handler's prior slice, including WS8-2 or WS8-7, instead of introducing an
   exception.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/chat_tool_handler_catalog.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/chat_tool_handler_catalog_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/chat_tool_handler_catalog_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=100`,
then run the corrected live canary.

### Handoff Notes

- Record the before/after binding inventory, handler interface, fallback port,
  old part removal, final Workstream 6 aggregate, coverage, and canary
  identities.

## Dependency-Ordered Execution Note

After the exact-model prerequisite gate is green, execute the catalog in this
order:

1. Complete upstream WS4-1 (`PythonAttachmentRepairPolicy`) and WS5-8
   (`ProcessStartResultPolicy`) before their WS6 consumers.
2. Complete P1a, then P5a, P5b, P5c, and P11 before WS6-1.
3. Complete P1b before WS6-2. Complete P5b before WS6-3.
4. Complete P6 before WS6-4; both WS6-4 and WS6-5 also require P5b.
5. Complete P7 before WS6-6; WS6-6 also requires P5b. Complete WS6-7 after
   P1b and P5b.
6. Complete WS6-8 after P5b, then P8 and WS6-9. Complete WS6-10 after P1b and
   P5b.
7. Complete WS6-11a and WS6-11b after P5c. Complete WS6-12 and WS6-13 after
   P5b, WS6-14 and WS6-16 after P5c, and WS6-15 in catalog order.
8. Complete P9 before WS6-17. Complete WS6-18 after P1b and P7.
9. Pause Workstream 6 and complete WS8-1 through WS8-7 in their own dependency
   order. WS8-2 and WS8-7 remove the last question and goal notifier-bound
   registry entries.
10. Return to Workstream 6 and complete WS6-19 last.

Every owner-keying prerequisite requires its own task specification, focused
tests, ratchets, repository gate, exact-model canary when production
turn-execution behavior changes, and focused commit. Do not fold one into the
following extraction merely to preserve catalog numbering.

## Deferred Workstream 6 Boundaries

The following are not approved implementation slices in this catalog:

- Public approval, credential, device-approval, and command-permission UI
  request/resolve methods. They remain notifier adapters until a separate UI
  coordinator plan defines ownership and cancellation semantics.
- Lower-level built-in browser, Computer Use, filesystem, local-command, SSH,
  BLE, and serial data-source handlers, except for the narrowly scoped
  owner-keying prerequisite repairs listed above. Those repairs change
  identity and storage contracts only; this workstream does not change
  transport behavior.
- Command guardrails, Git tag validation, Git write confirmation, production
  release approval, saved validation, and saved target scope. They belong to
  Workstream 7 after the poison-test prerequisites are green.
- Python attachment repair, process-start result interpretation, and final
  answer recovery. Their approved owners are Workstreams 4 and 5.
- Ask-user-question, participant-turn, and goal-continuation handlers. They
  belong to Workstream 8.
- Any flat mutable ledger, connection, process, approval, mutation, or task
  store discovered during extraction. Stop and create a prerequisite
  owner-keying task; do not conceal flat state behind a typed-looking port.

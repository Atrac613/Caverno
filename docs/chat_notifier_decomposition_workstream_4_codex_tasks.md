# ChatNotifier Decomposition Workstream 4 Task Catalog

Status: complete. WS4-1 through WS4-6 completed focused acceptance, and the
merged tree passed integrated verification and the corrected four-scenario
live canary against `qwen3.6-27b-vision` on 2026-08-01.

This catalog decomposes the low-state and prompt-context workstream from
`docs/chat_notifier_decomposition_codex_task.md`. Each approved section is one
implementation slice and one focused review. Do not combine sections.

## Current Preflight Baseline

The reviewed post-Slice-2b7 preflight baseline is:

- `chat_notifier.dart`: 9,364 physical lines;
- declared `part` directives: 42;
- declared-part same-library aggregate: 22,887 physical lines;
- decomposition manifest: 43 historical part records.

The 43 manifest records are intentionally historical and do not shrink when a
current `part` directive is removed. The 9,380 primary and 22,900 aggregate
ratchets are ceilings, not achieved counts. Remeasure all four values before
each slice and use the measured 9,364/42/22,887 state only while it still
matches the worktree.

## Catalog-Wide Execution Contract

- Remeasure the named source files, `chat_notifier.dart`, declared part count,
  and same-library aggregate before editing.
- Confirm Slices 2a1-2a3 are green and the exact-model corrected Slice 2b1
  canary has closed the Slices 2b1-2b7 program gate. Stop if the canary did not
  use `qwen3.6-27b-vision`, did not record the reachable base URL, or did not
  prove exactly one exit for every expected conversation/generation.
- Use the manifest created by Slice 2a1. Preserve every historical part record.
  A partial extraction changes `remaining` to `partial`; a whole-part
  extraction changes it to `extracted` and removes the old part.
- Append the exact collaborator record named by the task. Add the exact marker
  `// ChatNotifier decomposition collaborator: <collaborator-id>`.
- Add every new production file to the shrink-only line budget at its achieved
  physical line count.
- Calculate the achieved same-library aggregate as:

  ```text
  previous aggregate
  - physical lines removed from declared parts
  + ChatNotifier primary-file delta
  ```

  Independently imported collaborator lines are not part of that aggregate.
  Never raise the primary or aggregate budget. Lower every boundary that
  actually shrinks.
- Update `docs/large_file_refactor_plan.md` with achieved counts, manifest
  status, direct coverage, and any deferral.
- After an extraction intentionally removes or reclassifies audited notifier
  reads, review the delta, regenerate the canonical baseline, and verify it
  explicitly:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  git diff -- tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

  Never accept a new ambient read merely by regenerating the baseline.
- Run `tool/codex_verify.sh --coverage` and `git diff --check` for every task.
- Run the corrected four-scenario live canary for every task in this catalog.
  Record the reachable base URL, exact model, and one exit per expected
  conversation and interaction generation:

  ```bash
  # <reachable-base-url> is the verified OpenAI-compatible URL ending in /v1.
  reachable_base_url='<reachable-base-url>'
  curl -fsS "$reachable_base_url/models"
  CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
  CAVERNO_LLM_BASE_URL="$reachable_base_url" \
  CAVERNO_LLM_API_KEY=no-key \
  CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
  fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
    -d flutter-tester
  ```

- Check target-file line coverage from `coverage/lcov.info` with the task's
  named target and minimum:

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

## Corrective Prerequisite Mapping

- P1b (`Adopt Explicit Turn Owner Snapshots`) must complete before WS4-1, WS4-2,
  WS4-3, and WS4-5. Those slices require owner messages, attachment presence,
  project roots, or log context that current ambient helpers cannot supply
  safely.
- P6 (`Key FileRollbackCheckpointStore by Owner`) must complete before WS4-6.
- WS4-4 has no corrective-prerequisite dependency beyond the exact-model gate.
  Its typed-port stop conditions still apply.
- Execute WS4-3 before WS4-5 so the `prompt-context` manifest record is already
  `partial` when WS4-5 appends its second collaborator.

## WS4-1: Extract PythonAttachmentRepairPolicy

### Task

- Goal: move Python attachment repair detection and prompt construction into an
  independently importable policy.
- User-visible behavior: none; detection outcomes and repair prompt text remain
  byte-compatible for the same explicit inputs.
- Non-goals: moving LLM request orchestration, changing attachment staging, or
  changing tool availability.

### Context

- Source:
  `chat_notifier_python_attachment_repair.dart` methods
  `_shouldRepairSkippedPythonAttachmentAnalysis`,
  `_hasRunPythonScriptToolResult`,
  `_looksLikePythonAttachmentAnalysisRequest`,
  `_containsCjkAnalysisMarker`,
  `_buildSkippedPythonAttachmentAnalysisRepairPrompt`,
  `_shouldRepairPythonAttachmentPathFailure`,
  `_hasRunPythonScriptPathFailure`, and
  `_buildPythonAttachmentPathFailureRepairPrompt`.
- Current adapters:
  `_requestSkippedPythonAttachmentAnalysisRepair` and
  `_requestPythonAttachmentPathFailureRepair`.
- Current external test seams:
  `buildSkippedPythonAttachmentAnalysisRepairPromptForTest` and
  `buildPythonAttachmentPathFailureRepairPromptForTest`.
- Destination:
  `lib/features/chat/domain/services/python_attachment_repair_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/python_attachment_repair_policy_test.dart`.

### Implementation Notes

- Add `PythonAttachmentRepairPolicy` with explicit immutable input containing:
  candidate response, executed results, available tool names,
  `runPythonScriptDisabled`, `hasPythonAttachment`, and owning-turn latest user
  text.
- Before extraction, add an owner-aware attachment lookup over the messages
  registered for `interactionGeneration`. Do not pass
  `_latestPythonInputMessage()` through unchanged: it currently scans visible
  `state.messages` and can take thread B's attachment while thread A owns the
  repair.
- The notifier resolves settings, owner-scoped attachment presence, and
  owning-turn text before calling the policy.
- Keep both completion-request methods in the notifier as thin orchestration
  adapters.
- Do not accept `AppSettings`, `ChatNotifier`, `ChatState`, `Ref`, a provider
  container, a Zone accessor, or a notifier-capturing callback.
- Manifest transition:
  `python-attachment-repair` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `python-attachment-repair-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/python_attachment_repair_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: python-attachment-repair-policy`.
- Declared part count is unchanged. Record the measured removed-part lines,
  primary delta, achieved aggregate, and new exact file budget.

### Similar-Pattern Search

- Search:
  `_looksLikePythonAttachmentAnalysisRequest`,
  `run_python_script`, `caverno.inputs[0]`,
  `buildSkippedPythonAttachmentAnalysisRepairPromptForTest`, and
  `buildPythonAttachmentPathFailureRepairPromptForTest`.
- Migrate policy assertions from notifier tests to the direct policy test.
  Keep only adapter behavior in notifier tests.

### Acceptance Criteria

1. All named detection and prompt methods live only in the independent policy.
2. The two request adapters pass owning-turn values explicitly.
3. Direct tests cover empty content, disabled/unavailable tool, missing
   attachment, prior execution, path failures, English and CJK request markers,
   prompt text, and negative cases.
4. A notifier poison test gives visible thread B an attachment while the
   registered owner A has none, then reverses the values, and proves the repair
   decision always uses A.
5. Target-file line coverage is 100%.
6. The manifest, marker, exact size budget, aggregate ratchet, thread-scope
   ratchet, and corrected live canary pass.
7. Stop if the adapter cannot resolve both the attachment and latest user text
   without a visible-thread fallback, or if extraction requires a broad
   completion callback. A missing owner-aware attachment seam is a prerequisite
   behavior fix, not permission to preserve the ambient read.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/python_attachment_repair_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_python_attachment_repair.dart \
  test/features/chat/domain/services/python_attachment_repair_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/python_attachment_repair_policy_test.dart
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

- Record old/new part lines, primary lines, aggregate, budgets, and part count.
- Record direct hit/line counts and every migrated branch case.
- Record canary endpoint, model, completed turn identities, and exit counts.

## WS4-2: Extract DuplicateToolResultRecovery

### Task

- Goal: move duplicate-call result reuse and fallback-result reconciliation out
  of the notifier library.
- User-visible behavior: none; ordering, deduplication, and JSON payloads remain
  compatible.
- Non-goals: changing duplicate-call detection, retry policy, or tool execution.

### Context

- Source: entire
  `chat_notifier_duplicate_recovery.dart`, including
  `_buildDuplicateRecoveryToolResults` and
  `_buildDuplicateResultReusePayload`.
- Callers:
  `buildDuplicateRecoveryToolResultsForTest` and the duplicate-recovery branch
  in `_executeToolCalls`.
- Destination:
  `lib/features/chat/domain/services/duplicate_tool_result_recovery.dart`.
- Direct tests:
  `test/features/chat/domain/services/duplicate_tool_result_recovery_test.dart`.
- Reference dependency:
  the existing deterministic tool execution identity logic used by
  `_toolExecutionKey`.

### Implementation Notes

- Expose one operation that accepts current calls, immutable executed results,
  immutable fallback results, and the explicit owning project root used for
  path normalization.
- Move or reuse a narrow independent tool-execution identity policy. Do not
  accept `_toolExecutionKey`, `_tryDecodeMap`, or
  `_dedupeRecoveryToolResults` as notifier-capturing callbacks.
- Reuse `ToolCallExecutionPolicy` with a resolver derived from the explicit
  root. Calling it without that resolver is not behavior-compatible: the
  current `_toolExecutionKey` normalizes relative file paths through
  `_getActiveProjectRootPath`.
- Preserve reverse-most-recent matching, current call IDs, reuse metadata,
  fallback filtering, and final deduplication.
- Replace both call sites directly and remove the old part directive/file.
- Manifest transition:
  `duplicate-recovery` from `remaining` to `extracted`.
- Append collaborator:
  - `id`: `duplicate-tool-result-recovery`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/duplicate_tool_result_recovery.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: duplicate-tool-result-recovery`.
- Declared part count must fall by one. Measure rather than assume the
  primary/import delta and final aggregate.

### Similar-Pattern Search

- Search:
  `_buildDuplicateRecoveryToolResults`,
  `_buildDuplicateResultReusePayload`,
  `duplicate_tool_call_result_reused`,
  `_dedupeRecoveryToolResults`, and `_toolExecutionKey`.
- Inspect tool-loop exhaustion recovery but do not combine it with this task.

### Acceptance Criteria

1. The old part is absent and both callers use the collaborator directly.
2. Direct tests cover latest-match selection, no match, map/non-map prior
   results, fallback inclusion/exclusion, duplicate fallbacks, ordering, and
   empty inputs. Include relative/absolute paths under two different explicit
   project roots.
3. The collaborator has no notifier, state, provider, Zone, persistence, or
   file dependency.
4. Target-file line coverage is 100%.
5. Part count, manifest, marker, size budget, aggregate budget, structural
   boundary, thread-scope ratchet, and live canary pass.
6. Stop if the owning project root is unavailable or execution identity cannot
   move behind the existing narrow independent policy without changing
   comparison semantics.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/duplicate_tool_result_recovery.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/duplicate_tool_result_recovery_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/duplicate_tool_result_recovery_test.dart
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

- Record old/new primary, part, aggregate, budgets, and declared part count.
- Record direct hit/line counts and execution-identity dependency.
- Record canary endpoint/model and exact exit evidence.

## WS4-3: Extract ReferencedSpecificationLoader

### Task

- Goal: isolate bounded Markdown specification discovery and loading behind an
  explicit project-root API.
- User-visible behavior: none for callers with an explicit owning project.
- Non-goals: deciding which project owns a turn, changing the short-prompt
  contract, or preserving an ambient visible-project fallback.

### Context

- Source:
  `_loadReferencedSpecification` in
  `chat_notifier_prompt_context.dart`.
- Caller:
  `_ensureShortPromptExecutionContract`.
- Destination:
  `lib/features/chat/domain/services/referenced_specification_loader.dart`.
- Direct tests:
  `test/features/chat/domain/services/referenced_specification_loader_test.dart`.
- Related boundary:
  `ProjectScopedToolArgumentResolver` demonstrates explicit root resolution,
  but its lazy callback is not an API shape for this collaborator.

### Implementation Notes

- API:
  `SpecificationContractInput? load({required String projectRoot, required String request, int maxBytes = 262144})`.
- Prerequisite: repair `_ensureShortPromptExecutionContract` in a separate
  behavior-fix review so it resolves the coding project from its explicit
  `currentConversation`. The current loader calls
  `_getEffectiveCodingProject()` and therefore preserves a visible-project
  fallback that this extraction is not allowed to copy.
- After that prerequisite, the notifier passes the owning conversation's root
  directly to the loader.
- Keep URI normalization, inside-root enforcement, regular file checks, byte
  limit, and `FileSystemException` behavior compatible. Characterize the
  current distinction before moving it: a `readAsStringSync` failure returns
  null, while a `lengthSync` failure currently occurs before the catch.
- The collaborator may perform its narrow file read directly or use a typed
  `SpecificationFilePort`; it must not load a project from a provider or Zone.
- Manifest transition:
  `prompt-context` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `referenced-specification-loader`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/referenced_specification_loader.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: referenced-specification-loader`.
- Part count is unchanged. Record removed-part lines, primary delta, exact
  collaborator size, and achieved aggregate.

### Similar-Pattern Search

- Search:
  `_loadReferencedSpecification`, `SpecificationContractInput`,
  `ShortPromptContractBuilder`, `.md`, and `256 * 1024`.
- Inspect other bounded local document loaders for path validation only; do not
  widen the task.

### Acceptance Criteria

1. The loader receives a non-empty explicit root and never calls
   `_getEffectiveCodingProject` or reads visible state.
2. Direct tests cover relative Markdown paths, traversal, outside-root paths,
   missing files, directories, oversize files, malformed references, Unicode
   paths, and read failures.
3. The caller uses the owning turn's project.
4. Target-file line coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural gate, thread-scope
   ratchet, and live canary pass.
6. Stop until the separate owner-root behavior fix is complete. Do not combine
   that fix with the loader extraction or preserve the visible-project
   fallback inside the collaborator.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/referenced_specification_loader.dart \
  lib/features/chat/presentation/providers/chat_notifier_prompt_context.dart \
  test/features/chat/domain/services/referenced_specification_loader_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/referenced_specification_loader_test.dart
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

- Record the owning-root resolution used at the call site.
- Record physical counts, budgets, direct coverage, and path cases.
- Record canary endpoint/model and exit evidence.

### Completion Record (2026-07-31)

- The 75-line `ReferencedSpecificationLoader` now receives the owning project
  root already resolved by `_ensureShortPromptExecutionContract`; it never
  performs a visible-project or provider fallback.
- Twelve direct tests cover relative and Unicode Markdown paths, first-match
  selection, traversal and absolute-path rejection, missing files,
  directories, byte limits, malformed input, and compatible filesystem
  failure handling.
- The `prompt-context` record is `partial`. Its historical part shrinks from
  286 to 260 lines, while the primary remains 9,073 lines.
- The focused tree retains 38 declared parts with 12,914 part lines and lowers
  the same-library aggregate from 22,013 to 21,987 lines.

## WS4-4: Extract SecondaryCompletionRouter

### Task

- Goal: move mesh routing for secondary and planning completions into an
  independent router with an immutable route snapshot.
- User-visible behavior: none; endpoint selection, primary fallback, and model
  selection remain compatible.
- Non-goals: changing mesh health policy, model settings, planning prompts, or
  approval-review semantics.

### Context

- Source:
  `_runSecondaryCompletion` and `_runPlanningCompletion` in
  `chat_notifier_mesh_routing.dart`.
- Callers:
  `_requestWorkflowProposal`, `_requestTaskProposal`, `suggestCurrentGoal`,
  `_extractMemoryDraftWithLlm`, and `_runApprovalAutoReview`.
- Destination:
  `lib/features/chat/domain/services/secondary_completion_router.dart`.
- Direct tests:
  `test/features/chat/domain/services/secondary_completion_router_test.dart`.
- Reference:
  `MeshSecondaryCompletionRunner`.

### Implementation Notes

- Define the smallest immutable route snapshot containing provider, primary
  base URL/API key/model, enabled endpoints, selected endpoint, selected model,
  and fallback model.
- Inject `MeshSecondaryCompletionRunner<ChatDataSource>` and the primary
  `ChatDataSource` through a typed constructor or narrow route port. The route
  snapshot alone is insufficient to execute or resolve a route, and a combined
  notifier context object is forbidden.
- The API may accept the typed completion operation
  `Future<T> Function(ChatDataSource, String)` because it cannot expose notifier
  state; do not accept a broad notifier host callback.
- Planning logging crosses a narrow `SecondaryCompletionLogPort` or is
  returned as route metadata for the notifier to log.
- Update every caller to construct the route snapshot explicitly.
- Remove the old part when no caller uses its private methods.
- Manifest transition:
  `mesh-routing` from `remaining` to `extracted`.
- Append collaborator:
  - `id`: `secondary-completion-router`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/secondary_completion_router.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: secondary-completion-router`.
- Declared part count must fall by one. Measure the primary/import delta and
  aggregate.

### Similar-Pattern Search

- Search:
  `_runSecondaryCompletion`, `_runPlanningCompletion`, `_meshRunner.run`,
  `_meshRunner.resolve`, `planningEndpointId`, `approvalAutoReviewEndpointId`,
  and `subagentEndpointId`.
- Do not absorb subagent multi-turn routing; record it as a Workstream 6
  consumer.

### Acceptance Criteria

1. All five call-site groups use the independent router.
2. Tests cover OpenAI-compatible routing, non-compatible provider fallback,
   empty endpoint, assigned endpoint, unhealthy/missing endpoint fallback,
   primary model substitution, and planning route metadata.
3. No full `AppSettings`, notifier, state, provider, Zone, or persistence
   dependency crosses the boundary.
4. Target-file line coverage is at least 95%.
5. Old part removal, manifest, marker, exact budget, aggregate ratchet,
   structural gate, thread-scope ratchet, and live canary pass.
6. Stop if preserving routing requires passing `_settings`, `_meshRunner`, and
   `_dataSource` as one broad context object.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/secondary_completion_router.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart \
  test/features/chat/domain/services/secondary_completion_router_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/secondary_completion_router_test.dart
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

- Record each migrated caller and route snapshot fields.
- Record old/new counts, budgets, direct coverage, and final part count.
- Record the canary endpoint/model and exit evidence.

### Completion Record (2026-07-31)

- The 135-line `SecondaryCompletionRouter` now receives an immutable route
  snapshot plus the primary data source and routes workflow, task, goal,
  memory, and approval-review completions through the existing mesh runner.
- The Notifier resolves every provider, endpoint, model, and fallback field
  before crossing the collaborator boundary. Planning logging uses only the
  returned model, endpoint, and fallback metadata.
- Fifteen direct tests cover assigned, empty, missing, unhealthy, fallback,
  non-compatible, immutable, logging, and failure routes with 27/27 executable
  lines covered.
- The historical `mesh-routing` part is removed and marked `extracted`.
  The primary file shrinks to 8,935 lines, declared parts fall to 37 with
  12,111 lines, and the same-library aggregate falls to 21,046 lines.

## WS4-5: Extract ExecutionSnapshotObserver

### Task

- Goal: move execution-snapshot deduplication and shadow-log emission into an
  owner-aware observer.
- User-visible behavior: none; log enablement, deduplication, and payload fields
  remain compatible.
- Non-goals: changing snapshot projection, session-log schema, prompt building,
  or UI state.

### Context

- Source:
  `_observeExecutionSnapshot` in
  `chat_notifier_prompt_context.dart`.
- Caller:
  `_createSystemMessage`.
- Destination:
  `lib/features/chat/domain/services/execution_snapshot_observer.dart`.
- Direct tests:
  `test/features/chat/domain/services/execution_snapshot_observer_test.dart`.
- Side effect:
  `LlmSessionLogStore.recordExecutionShadow`.

### Implementation Notes

- API input includes conversation ID, workspace mode, `ExecutionSnapshot`,
  logging-enabled flag, immutable log context, and timestamp.
- Maintain the latest observation key inside the observer and include
  conversation ID in that key.
- Build the immutable log context for the supplied conversation ID. Do not use
  `_currentLlmSessionLogContext()` unchanged: it resolves the visible
  conversation and can attribute thread A's snapshot to visible thread B.
- Define `ExecutionShadowLogPort.record(owner, event)`; the collaborator must
  not read a provider, call `ref`, or derive the active conversation.
- Return or send only the existing bounded event fields.
- Manifest transition:
  `prompt-context` remains `partial`; append another collaborator.
- Append collaborator:
  - `id`: `execution-snapshot-observer`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/execution_snapshot_observer.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: execution-snapshot-observer`.
- Part count is unchanged. Measure removed-part lines and achieved aggregate.

### Similar-Pattern Search

- Search:
  `_latestExecutionSnapshotObservationKey`, `recordExecutionShadow`,
  `ExecutionShadow`, `_observeExecutionSnapshot`, and
  `toRedactedLogSummary`.
- Do not change the log schema or retention behavior.

### Acceptance Criteria

1. The observer never reads visible conversation state.
2. Direct tests cover non-coding workspaces, first observation, duplicate
   observation, changed snapshot, same snapshot in another conversation,
   logging disabled, and log-port failure behavior.
3. A notifier poison test builds A's system prompt while B is visible and
   proves the log event and `LlmSessionLogContext` retain A's conversation ID.
4. Existing redacted diagnostic logging remains compatible.
5. Target-file line coverage is at least 95%.
6. Manifest, marker, exact size budget, aggregate ratchet, structural gate,
   thread-scope ratchet, and live canary pass.
7. Stop if the proposed port exposes the whole log store or notifier instead of
   one execution-shadow operation, or if the adapter can only construct context
   from visible state.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/execution_snapshot_observer.dart \
  lib/features/chat/presentation/providers/chat_notifier_prompt_context.dart \
  test/features/chat/domain/services/execution_snapshot_observer_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/execution_snapshot_observer_test.dart
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

- Record event fields, deduplication key behavior, and port shape.
- Record counts, budgets, direct coverage, and canary evidence.
- Record any session-log follow-up without changing it in this task.

### Completion Record (2026-07-31)

- The 179-line `ExecutionSnapshotObserver` freezes snapshots, keys the latest
  observation by conversation and snapshot, preserves redacted diagnostics,
  and emits only the established bounded shadow fields through a narrow port.
- A 32-line data adapter maps those bounded events onto
  `LlmSessionLogStore.recordExecutionShadow`; the observer has no notifier,
  provider, visible-conversation, or log-store dependency.
- Twelve direct tests cover 63/63 executable lines, including workspace gates,
  deduplication, conversation switches, immutable collections, disabled logs,
  and contained diagnostic and persistence failures. The detached-plan poison
  test switches visibility to B before A's initial shadow and proves that entry
  remains in A's exact session context.
- `prompt-context` remains `partial` and shrinks from 260 to 254 lines. The
  primary remains 8,935 lines, 37 declared parts contain 12,105 lines, and the
  same-library aggregate falls to 21,040 lines.

## WS4-6: Extract FileTurnRollbackService

### Task

- Goal: move file-turn rollback preview and execution behind a narrow
  checkpoint service while preserving notifier public APIs.
- User-visible behavior: none; preview, success, and unavailable-service
  results remain compatible.
- Non-goals: changing checkpoint storage, rollback semantics, approval UI, or
  lifecycle ownership.

### Context

- Source:
  `previewLastFileTurnRollback` and `rollbackLastFileTurnChanges` in
  `chat_notifier_turn_rollback_handlers.dart`.
- External callers:
  `_confirmAndRollbackLastFileTurn` in
  `chat_page_turn_rollback_support.dart`.
- Existing characterization:
  `test/features/chat/presentation/providers/chat_notifier_turn_rollback_part.dart`.
- Destination:
  `lib/features/chat/domain/services/file_turn_rollback_service.dart`.
- Direct tests:
  `test/features/chat/domain/services/file_turn_rollback_service_test.dart`.

### Implementation Notes

- Define a narrow `FileCheckpointPort` exposing only turn-preview and
  turn-rollback operations.
- `FileTurnRollbackService.preview()` and `rollback()` must preserve the
  existing unavailable-service failure result.
- Keep notifier public methods as thin delegates because UI and terminal
  callers depend on them. Place delegates in the primary notifier only if the
  achieved primary count remains at or below the existing 9,380-line ceiling;
  never raise that budget.
- Prefer removing the old part after the delegate placement is measured.
- At the current 9,364-line primary baseline, up to 16 lines of existing
  ceiling margin are available. Whole-part removal is allowed when the
  measured delegate/import result remains within that ceiling and the
  same-library aggregate shrinks. Otherwise retain the old part as `partial`;
  do not invent unrelated removals merely to fit the ceiling.
- Manifest transition:
  `turn-rollback-handlers` to `extracted` when the old part is removed,
  otherwise `partial` with the reason recorded.
- Append collaborator:
  - `id`: `file-turn-rollback-service`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/file_turn_rollback_service.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: file-turn-rollback-service`.
- Record the achieved part count and aggregate; do not force whole-part removal
  by raising the primary budget.

### Similar-Pattern Search

- Search:
  `previewLastFileTurnRollback`,
  `rollbackLastFileTurnChanges`,
  `previewLastFileTurnCheckpoint`,
  `rollbackLastFileTurnCheckpoint`, and
  `rollback_last_turn_file_changes`.
- Keep the separate single-file rollback tool out of this task.

### Acceptance Criteria

1. UI callers continue to use the same notifier public API.
2. Direct tests cover absent port, absent preview, successful preview,
   successful rollback, failed rollback, and propagated tool result fields.
3. The collaborator exposes no general MCP execution capability.
4. Target-file line coverage is 100%.
5. Manifest status accurately matches whether the part remains. Use
   `extracted` only when the old part is removed within the existing primary
   ceiling; otherwise record `partial`. Marker, budget, aggregate ratchet,
   structural gate, thread-scope ratchet, and live canary pass.
6. Stop if thin delegates would exceed the current primary ceiling or if
   rollback lifecycle cleanup would move out of the notifier.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/file_turn_rollback_service.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_turn_rollback_handlers.dart \
  test/features/chat/domain/services/file_turn_rollback_service_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/file_turn_rollback_service_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_turn_rollback_part.dart \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the catalog coverage assertion with the destination path and `minimum=100`,
then run the corrected live canary.

### Handoff Notes

- Record whether the old part was removed and why.
- Record public delegate placement, counts, budgets, and direct coverage.
- Record canary endpoint/model and exact exit evidence.

### Completion Record (2026-07-31)

- The 111-line `FileTurnRollbackService` now owns absent-port compatibility,
  preview isolation, and exact owner/checkpoint rollback delegation through the
  narrow `FileCheckpointPort`.
- The historical part remains `partial`: its two public notifier APIs and a
  callback-only adapter occupy 22 lines. Moving them into the primary notifier
  would exceed the current exact 9,073-line primary ratchet.
- Nine direct tests cover absent ports and previews, immutable preview copies,
  successful and failed rollback, complete result propagation, cross-owner
  isolation, and both callback-factory paths.
- The focused tree retains 38 declared parts with 12,940 part lines. The
  primary shrinks to 9,073 lines and the same-library aggregate shrinks from
  22,016 to 22,013 lines.

## Deferred Boundaries

The following are not approved Workstream 4 slices:

- `_createSystemMessage`: mixes provider reads, prompt assembly, execution
  projection, Agents.md, repo map, memory, settings, and context-surgery
  observation.
- `_markPendingExecutionTaskStarted`: reads and mutates the visible
  conversation and emits runtime lifecycle events. It needs an owner-aware
  persistence port and a separate behavior-fix review.
- `_turnProjectRootFor`, `_codingProjectForTurn`, and
  `_getEffectiveCodingProject`: notifier-owned identity adapters. Do not move
  Zone reads into a collaborator.
- `_loadAgentsMd` and `_repoMap`: provider adapters whose small line count does
  not justify widening a collaborator.
- `_buildPlanningResearchContext`: currently passes notifier-capturing tool
  dispatch and proposal extraction callbacks. Revisit only after adding a
  typed `PlanningResearchToolPort.run(owner, toolCall)` and explicit proposal
  text extraction boundary.
- The two Python completion-request methods: retain them until a separate
  generation-scoped completion-request port is proven without a broad notifier
  callback.

Each deferral remains in its historical manifest record with a concise reason.
Do not label a deferred boundary as extracted merely because nearby pure logic
moved.

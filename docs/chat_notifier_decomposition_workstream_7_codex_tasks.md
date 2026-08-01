# ChatNotifier Decomposition Workstream 7 Task Catalog

Status: task catalog ready; WS7-4, WS7-5, and WS7-8 have completed focused
acceptance and remain in progress pending integrated verification. Slices
2a1-2a3 and 2b1-2b7 are complete. The exact-model corrected canary passed on
2026-07-28, so Workstream 7 is unblocked subject to each slice's corrective
prerequisites.

Current planning baseline after Slice 2b7: `chat_notifier.dart` is 9,364
physical lines, 42 declared parts total 13,523 lines, and the same-library
aggregate is 22,887 lines. The shrink-only ceilings remain 9,380 primary lines
and 22,900 aggregate lines. The canonical turn-scope baseline reports 133
ambient reads and 118 turn-reachable reads. Remeasure all values at the start
of every slice; these numbers are not permission to restore removed lines.

This catalog decomposes guardrails, context surgery, and telemetry from
`docs/chat_notifier_decomposition_codex_task.md`. Each approved section is one
implementation slice and one focused review. Execute sections in order and do
not combine them.

## Catalog-Wide Execution Contract

- Remeasure the named source part, `chat_notifier.dart`, declared part count,
  and same-library aggregate before editing.
- Confirm Slices 2a1-2a3 and 2b1-2b7 are green. In particular, do not start a
  production extraction while any Slice 2b row remains `In progress`. Stop if
  any prerequisite gate is missing or red.
- Re-inventory current source symbols and callers before editing. Line numbers
  and historical manifest entrypoints are discovery aids, not substitutes for
  the current source. Preserve historical entrypoint records even when a
  production method was renamed; change only manifest status and collaborator
  records required by the slice.
- Guard and policy inputs must be immutable snapshots owned by a specific
  conversation and interaction generation. Resolve conversation, workflow,
  messages, pending questions, project roots, and tool results at the notifier
  boundary. Never read the visible thread from a collaborator.
- Side effects cross narrow owner-aware ports. Do not pass `ChatNotifier`,
  `ChatState`, `Ref`, `ProviderContainer`, Zones, or notifier-capturing
  callbacks.
- Use the Slice 2a1 manifest and preserve historical part records. A partial
  extraction changes `remaining` to `partial`; a whole-part extraction changes
  it to `extracted` and removes the old part.
- Append the exact collaborator record and marker named by the task:
  `// ChatNotifier decomposition collaborator: <collaborator-id>`.
- Add new or newly governed production files to the shrink-only size budget at
  achieved physical lines. Keep every collaborator below 500 lines.
- Calculate the achieved same-library aggregate as:

  ```text
  previous aggregate
  - physical lines removed from declared parts
  + ChatNotifier primary-file delta
  ```

  Independently imported collaborator lines are excluded. Never raise a
  primary, aggregate, or collaborator budget.
- Update `docs/large_file_refactor_plan.md` with achieved counts, manifest
  status, direct coverage, and any deferral.
- Every task runs formatting, analyze, its focused test with coverage, the
  structural/file-size/thread-scope quality gates,
  `tool/codex_verify.sh --coverage`, and `git diff --check`.
- Run the canonical turn-scope check before editing. After an intended
  production or manifest change, regenerate the baseline explicitly, review
  every changed method/read record, and then rerun the check. Never regenerate
  solely to silence an unexplained failure:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

- Every task runs the corrected four-scenario live canary and records the
  reachable endpoint, exact model, and exactly one `turn_exit` per expected
  conversation and generation:

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

  `<reachable-base-url>` must be the verified OpenAI-compatible `/v1` base URL
  reachable from `flutter-tester`, using a loopback relay when direct LAN
  access is unavailable. Do not substitute another model or infer success from
  a `/models` response alone.

- Assert target-file coverage from `coverage/lcov.info`:

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

- WS8-1 must complete before WS7-7.
- P12 (`Split CodingCommandOutputGuardrailService Below 500 Lines`) must
  complete before WS7-8.
- P2 (`Key TurnToolResultLedger by Owner`) must complete before any WS7-6 or
  WS7-11 implementation that would otherwise consult the flat ledger.

## WS7-1: Extract GoalValidationProbeGuard

### Task

- Goal: move validation-only continuation command classification and blocked
  result construction into a pure guard.
- User-visible behavior: none; classification and exact result payload remain
  compatible.
- Non-goals: changing continuation selection, capability classification, or
  command execution.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildGoalValidationProbeCommandGuardResult` and
  `_isGoalValidationProbeCommandGuardResult`.
- Call sites:
  `chat_notifier_tool_loop_batch.dart:165` and related batch-result checks.
- Destination:
  `lib/features/chat/domain/services/goal_validation_probe_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_validation_probe_guard_test.dart`.

### Implementation Notes

- Expose a pure evaluation taking `ToolCallInfo` and
  `verifierOnlyContinuation`.
- Reuse `ToolCapabilityClassifier` directly. Preserve the exact code, error,
  attempted effect, required action, success flag, and detector behavior.
- Manifest transition:
  `command-guardrails` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `goal-validation-probe-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_validation_probe_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-validation-probe-guard`.

### Similar-Pattern Search

- Search `_buildGoalValidationProbeCommandGuardResult`,
  `_isGoalValidationProbeCommandGuardResult`,
  `goal_validation_probe_requires_verifier`, and
  `verifierOnlyContinuation`.
- Do not move goal continuation or tool-loop exhaustion.

### Acceptance Criteria

1. Both named methods move and all callers use the guard directly.
2. Direct tests cover false mode, every command-effect class, exact blocked
   payload, detector true/false, and malformed result JSON.
3. The guard has no state, provider, Zone, or side-effect dependency.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   corrected live canary pass.
6. Stop if classification requires mutable turn state beyond the explicit
   boolean.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_validation_probe_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/goal_validation_probe_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_validation_probe_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record migrated callers, effect branch matrix, measured shrink, coverage, and
  canary identities.

Focused implementation completed on 2026-07-31. The tool-loop evaluator and
mutation-result detector now call the stateless 53-line
`GoalValidationProbeGuard` directly. Four direct tests cover 13/13 executable
lines, including false-mode short-circuiting, all eleven command-effect
classes, the exact blocked payload, exact-code matching, non-object JSON, and
malformed JSON. The primary remains at 8,925 lines,
`command-guardrails` shrinks from 812 to 776 lines, 37 declared parts contain
11,879 lines, and the same-library aggregate falls to 20,804 lines.

## WS7-2: Extract MaterialContractAssumptionGuard

### Task

- Goal: move blocking material-assumption detection and clarification result
  construction into a pure guard with explicit workflow inputs.
- User-visible behavior: none; mutation classification, chosen question, and
  result payload remain compatible.
- Non-goals: changing workflow specifications or asking the question.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildMaterialContractAssumptionGuardResult` and
  `_isContractMutationToolCall`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:173`.
- Destination:
  `lib/features/chat/domain/services/material_contract_assumption_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/material_contract_assumption_guard_test.dart`.

### Implementation Notes

- Accept `ToolCallInfo`, owning `WorkspaceMode`, and an immutable ordered list
  of blocking assumptions.
- Reuse `ToolCapabilityClassifier`; preserve first-assumption selection,
  normalized clarification fallback, exact payload, and success/error flags.
- The notifier resolves the owning workflow specification before evaluation.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `material-contract-assumption-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/material_contract_assumption_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: material-contract-assumption-guard`.

### Similar-Pattern Search

- Search `_buildMaterialContractAssumptionGuardResult`,
  `_isContractMutationToolCall`, `blockingAssumptions`, and
  `material_contract_assumption_unconfirmed`.
- Inspect workflow clarification UI without moving it.

### Acceptance Criteria

1. No guard read uses `currentConversation`.
2. Direct tests cover non-coding mode, empty assumptions, every command-effect
   class, normalized/custom/fallback question, first-item ordering, and exact
   payload.
3. Poison tests supply a different visible workflow assumption and prove the
   owner snapshot wins.
4. Target-file line coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural gates, and live
   canary pass.
6. Stop if the owning workflow cannot be resolved without a visible-thread
   fallback.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/material_contract_assumption_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/material_contract_assumption_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/material_contract_assumption_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record explicit workflow inputs, poison case, branch matrix, achieved counts,
  coverage, and canary identities.

Focused implementation completed on 2026-07-31. The batch resolves the owning
conversation once, freezes its ordered blocking assumptions, and passes those
facts plus the owning workspace mode to the independent 64-line
`MaterialContractAssumptionGuard`; no guard path reads the visible
conversation. Eight direct tests cover 18/18 executable lines, all eleven
command-effect classes, inactive gates, normalized, fallback, and ordered
questions, exact result fields, and owner/visible workflow poisoning. The
primary remains at 8,925 lines, `command-guardrails` shrinks from 776 to 733
lines, `tool-loop-batch` grows from 710 to 727 lines for explicit owner inputs,
37 declared parts contain 11,853 lines, and the same-library aggregate falls
to 20,778 lines.

## WS7-3: Extract CommandDiagnosticVerifierReplayGuard

### Task

- Goal: move unchanged-verifier replay detection, pending-mutation analysis,
  logging data, and blocked result construction into an independent guard.
- User-visible behavior: none; diagnostic selection, retry identity, result
  payload, and log meaning remain compatible.
- Non-goals: changing diagnostic focus creation or verifier replay policy.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildUnchangedVerifierReplayBeforeRepairGuardResult` and
  `_isUnchangedVerifierReplayBeforeRepairGuardResult`.
- Existing collaborator:
  `CommandDiagnosticVerifierReplayPolicy`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:229`.
- Destination:
  `lib/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/command_diagnostic_verifier_replay_guard_test.dart`.

### Implementation Notes

- Accept explicit diagnostic focus, attempted command key, classified command
  effect, pending calls, and current call identity.
- Return a typed decision containing optional `McpToolResult` and structured log
  fields. Log through the notifier or a narrow `DiagnosticLogPort`.
- Reuse `CommandDiagnosticVerifierReplayPolicy` for the decision.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `command-diagnostic-verifier-replay-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: command-diagnostic-verifier-replay-guard`.

### Similar-Pattern Search

- Search `_buildUnchangedVerifierReplayBeforeRepairGuardResult`,
  `_isUnchangedVerifierReplayBeforeRepairGuardResult`,
  `CommandDiagnosticRepairFocus`, `_toolFailureKey`, and
  `unchanged_verifier_replay_before_repair_blocked`.
- Keep focus tracking in Workstream 8 unless separately approved.

### Acceptance Criteria

1. The guard receives no conversation provider or notifier callback.
2. Direct tests cover absent focus, non-verifier, changed key, preceding
   mutation before/after current call, blocked replay, exact payload, log data,
   detector true/false, and malformed JSON.
3. Poison tests prove diagnostic focus and pending calls come from the owning
   turn.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if command identity still depends on mutable retry state not included
   in the explicit input.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/command_diagnostic_verifier_replay_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/command_diagnostic_verifier_replay_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record focus and identity inputs, policy reuse, pending-call cases, measured
  shrink, coverage, and canary identities.

Focused implementation completed on 2026-07-31. The batch now passes the
owner's diagnostic focus, retry-qualified command identity, classified effect,
and frozen pending calls to the 142-line
`CommandDiagnosticVerifierReplayGuard`. The guard reuses the existing policy,
returns typed log fields, and the caller preserves the prior log message.
Thirteen direct tests cover 43/43 executable lines, including absent and
pathless focus, all command effects, changed identity, mutation ordering,
missing current calls, exact payload and log fields, nested immutability,
invalid JSON snapshots, owner/visible-turn poisoning, and malformed result
detection. The primary remains at 8,925 lines, `command-guardrails` shrinks
from 733 to 663 lines, `tool-loop-batch` grows from 727 to 741 lines, 37
declared parts contain 11,797 lines, and the same-library aggregate falls to
20,722 lines.

## WS7-4: Complete AnalysisOptionsLintEditGuard Adoption

### Task

- Goal: remove the notifier wrapper around the existing independent
  `AnalysisOptionsLintEditGuard` and make it return the final tool result
  through an independent adapter API.
- User-visible behavior: none; issue detection and exact payload remain
  compatible.
- Non-goals: changing lint policy or broadening guarded files.

### Context

- Source:
  `_buildAnalysisOptionsLintEditGuardResult` in
  `chat_notifier_command_guardrails.dart`.
- Existing destination:
  `lib/features/chat/domain/services/analysis_options_lint_edit_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/analysis_options_lint_edit_guard_test.dart`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:183`.

### Implementation Notes

- Add a narrow result-building API to the existing guard or an adjacent value
  adapter in the same file. Preserve `detectIssue` for existing callers.
- Accept only `ToolCallInfo` and immutable executed results.
- Preserve `issue.toJson()`, error, required action, success flag, and error
  message exactly.
- Manifest transition: `command-guardrails` remains `partial`.
- Register or update collaborator:
  - `id`: `analysis-options-lint-edit-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/analysis_options_lint_edit_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: analysis-options-lint-edit-guard`.

### Similar-Pattern Search

- Search `_buildAnalysisOptionsLintEditGuardResult`,
  `AnalysisOptionsLintEditGuard`, `analysis_options.yaml`, and
  `detectIssue`.
- Do not alter other lint-edit protection.

### Acceptance Criteria

1. The notifier wrapper is gone and the batch caller invokes the independent
   API.
2. Direct tests cover no issue, every issue variant, exact JSON/result fields,
   and existing detector behavior.
3. Target-file line coverage is 100%.
4. The existing file budget does not increase beyond achieved lines without a
   measured ratchet update.
5. Manifest, marker, aggregate ratchet, structural gates, and live canary pass.
6. Stop if adoption changes any existing public detector semantics.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/analysis_options_lint_edit_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/analysis_options_lint_edit_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/analysis_options_lint_edit_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the existing destination and `minimum=100`,
then the corrected live canary.

### Handoff Notes

- Record existing API compatibility, wrapper deletion, file budget, coverage,
  and canary identities.

### Completion Record (2026-07-31)

- `AnalysisOptionsLintEditGuard.buildResult` now owns the exact blocked
  `McpToolResult` payload while preserving the existing `detectIssue` API and
  detector semantics. The notifier wrapper is removed and the tool-loop batch
  calls the independent API directly.
- Seventeen direct tests cover 164/164 executable lines, including every
  existing issue route, exact result fields, quoted YAML comments, human and
  machine analyzer output, and owner-scoped process results.
- The destination is 380 lines. `command-guardrails` remains `partial` and
  shrinks from 1,027 to 1,001 lines. The primary remains 8,935 lines, 37
  declared parts contain 12,079 lines, and the same-library aggregate falls to
  21,014 lines.

## WS7-5: Extract GitTagFormatInspectionGuard

### Task

- Goal: move pre-tag inspection enforcement and Git command parsing into a pure
  guard.
- User-visible behavior: none; qualifying commands, prior-inspection detection,
  and blocked payload remain compatible.
- Non-goals: changing Git tag policy or executing Git commands.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildGitTagFormatInspectionGuardResult`, `_isGitTagCreationCommand`,
  `_isSuccessfulGitTagFormatInspection`, and
  `_isGitTagFormatInspectionCommand`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:190`.
- Destination:
  `lib/features/chat/domain/services/git_tag_format_inspection_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/git_tag_format_inspection_guard_test.dart`.

### Implementation Notes

- Accept the tool call, explicitly resolved project-scoped arguments, and
  immutable executed results. The notifier or WS6 handler resolves owner paths.
- Preserve shell-control bypass, normalized command parsing, working-directory
  matching, successful-result requirements, accepted inspection commands, and
  exact payload.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `git-tag-format-inspection-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/git_tag_format_inspection_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: git-tag-format-inspection-guard`.

### Similar-Pattern Search

- Search all four source methods, `git_tag_format_inspection_required`,
  `tag --list`, `for-each-ref refs/tags`, and Git tool argument resolution.
- Do not move Git command execution.

### Acceptance Criteria

1. The guard has no project resolver callback or mutable repository state.
2. Direct tests cover non-Git calls, tag create variants, shell controls,
   inspection variants, success/failure, matching/different directories,
   ordering, and exact result.
3. Poison tests prove another conversation's inspection result cannot satisfy
   the owner's repository and working directory.
4. Target-file line coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural gates, and live
   canary pass.
6. Stop if owner-resolved arguments cannot be supplied explicitly.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/git_tag_format_inspection_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/git_tag_format_inspection_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/git_tag_format_inspection_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the command/inspection matrix, owner directory poison case, measured
  shrink, coverage, and canary identities.

### Completion Record (2026-07-31)

- The 151-line `GitTagFormatInspectionGuard` receives frozen tool-call,
  owner-resolved argument, and executed-result snapshots. It preserves
  supported inspection commands, success and working-directory compatibility,
  exact blocked payloads, and bypasses every shell control including newlines.
- Fourteen direct tests cover 58/58 executable lines, including tag variants,
  quoted controls, malformed and failed inspection results, result ordering,
  immutable nested inputs, and an owner/visible-repository poison case.
- A three-line command-guardrail export facade keeps the primary shrink-only.
  `command-guardrails` remains `partial` and shrinks from 963 to 859 lines,
  while the explicit caller grows from 703 to 709 lines. The primary falls from
  8,935 to 8,934 lines, 37 declared parts contain 11,961 lines, and the
  same-library aggregate falls to 20,895 lines.

## WS7-6: Extract TimedOutCommandRetryGuard

### Task

- Goal: move same-command timeout replay detection and blocked result
  construction into a pure guard.
- User-visible behavior: none; command matching, prior result selection, and
  result payload remain compatible.
- Non-goals: changing timeout values or process-state inspection.

### Context

- Source:
  `_buildTimedOutCommandRetryGuardResult` in
  `chat_notifier_command_guardrails.dart`.
- Call sites:
  `chat_notifier_tool_loop_batch.dart:107` and `:197`.
- Destination:
  `lib/features/chat/domain/services/timed_out_command_retry_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/timed_out_command_retry_guard_test.dart`.

### Implementation Notes

- Accept the tool call and immutable owner-turn executed results.
- Reuse independent command classification, normalization, timeout, result
  error, and command-match helpers through narrow value APIs; do not pass those
  notifier methods as callbacks.
- Preserve reverse-most-recent selection and exact blocked payload.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `timed-out-command-retry-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/timed_out_command_retry_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: timed-out-command-retry-guard`.

### Similar-Pattern Search

- Search `_buildTimedOutCommandRetryGuardResult`,
  `command_retry_after_timeout_blocked`, `_toolResultTimedOut`,
  `_toolResultCommandMatches`, and both batch call sites.
- Do not move process cancellation.

### Acceptance Criteria

1. Both call sites use the pure guard with owner-turn results.
2. Direct tests cover non-command, read-only command, absent command, no prior
   timeout, normalized matches/mismatches, multiple results, prior error text,
   and exact payload.
3. Poison tests prove another turn's timeout does not block the owner.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if matching still depends on a flat result ledger.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/timed_out_command_retry_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/timed_out_command_retry_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/timed_out_command_retry_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record both migrated callers, normalization and recency cases, poison test,
  measured counts, coverage, and canary identities.

Focused implementation completed on 2026-07-31. Both tool-loop call sites now
pass immutable owner-turn tool-call and executed-result snapshots to the
96-line `TimedOutCommandRetryGuard`. The guard preserves normalized
cross-command matching, reverse-most-recent timeout selection, and the exact
blocked payload. Eighteen direct tests cover 30/30 executable lines, including
missing and read-only commands, timeout flag and error-text variants,
normalization and mismatches, recency, nested immutability, and an owner/visible
turn poison case. The primary shrinks from 8,934 to 8,925 lines,
`command-guardrails` shrinks from 859 to 812 lines, `tool-loop-batch` grows from
709 to 710 lines for explicit inputs, 37 declared parts contain 11,915 lines,
and the same-library aggregate falls to 20,840 lines.

## WS7-7: Extract ProductionReleaseApprovalPolicy

### Task

- Goal: move production-release command recognition and explicit-approval
  history evaluation into an owner-scoped policy.
- User-visible behavior: none; qualifying commands, accepted approvals, prompt
  matching, and blocked payload remain compatible.
- Non-goals: asking questions, executing releases, or changing release policy.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildProductionReleaseApprovalGuardResult`,
  `_isProductionReleaseCommandToolCall`,
  `_looksLikeProductionReleaseCommand`,
  `_captureProof`,
  `_releaseEvidenceFor`,
  `_answerApproves`,
  `_looksLikeExplicitProductionReleaseApproval`,
  `_looksLikeProductionReleaseApprovalPrompt`,
  `_mentionsProductionRelease`, and
  `_looksLikeAffirmativeReleaseApprovalAnswer`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:205`.
- Destination:
  `lib/features/chat/domain/services/production_release_approval_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/production_release_approval_policy_test.dart`.
- Required poison coverage: Slice 2b2.

### Implementation Notes

- Preserve the current capture-time proof contract. Build immutable proof from
  owner ID, owner generation, submitted user content, and the immediately
  preceding non-system owner message before the turn starts. Do not rescan
  generic message history when a release tool call is later evaluated.
- Accept `ToolCallInfo`, the captured owner proof, and owner-keyed
  ask-question results. Return typed approval evidence plus the optional
  `McpToolResult`.
- Preserve proof generation/owner validation, accepted direct and affirmative
  reply forms, question-result decoding, release mentions, assistant prompt
  recognition, intent clipping, and exact result fields.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `production-release-approval-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/production_release_approval_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: production-release-approval-policy`.

### Similar-Pattern Search

- Search every named method, `_ReleaseProof`, `_ReleaseApprovalEvidence`,
  `_releaseApprovalSnapshots`, `production_release_explicit_approval_required`,
  ask-user-question answers, and release command patterns.
- Inspect Git write confirmation but keep it in WS7-13.

### Acceptance Criteria

1. Approval evaluation uses only capture-time owner proof and owner-generation
   question results; it never rescans the visible or current conversation.
2. Direct tests cover every release command family, non-release commands,
   missing/stale/negative/affirmative answers, capture-time preceding prompt
   requirements, owner/generation mismatch, assistant intent clipping, and
   exact payload.
3. Slice 2b2 poison tests prove cross-thread and earlier-generation approvals
   cannot authorize a later owner.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if ask-question results are not keyed by conversation and generation;
   complete Workstream 8 question-cache ownership first.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/production_release_approval_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/production_release_approval_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/production_release_approval_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record accepted command and approval patterns, owner-history contract, Slice
  2b2 cases, measured shrink, coverage, and canary identities.

## WS7-8: Complete CodingCommandPreflightGuard Adoption

### Task

- Goal: remove the notifier wrapper around
  `CodingCommandOutputGuardrailService.detectPreflightIssue` by adding an
  independent final-result API.
- User-visible behavior: none; command normalization, detected issues, and
  payloads remain compatible.
- Non-goals: changing guarded command patterns or execution.

### Context

- Source:
  `_buildCodingCommandPreflightGuardResult` in
  `chat_notifier_command_guardrails.dart`.
- Existing destination:
  `lib/features/chat/domain/services/coding_command_output_guardrail_service.dart`.
- Direct tests:
  `test/features/chat/domain/services/coding_command_output_guardrail_service_test.dart`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:214`.
- Measured prerequisite: the existing destination is 715 physical lines. It
  cannot become a program collaborator while the catalog-wide 500-line limit
  applies.

### Implementation Notes

- Before this adoption slice, land a separately reviewed behavior-preserving
  split that leaves every resulting collaborator below 500 physical lines,
  with direct tests and shrink-only budgets. Do not hide the oversized file
  behind an exception, a `part` file, or a second broad service.
- Add a result-building API that accepts tool name plus explicitly resolved
  command and working directory. Preserve the existing detector API.
- Keep project argument resolution at the owner boundary.
- Preserve tool filtering, normalization, `issue.toJson()`, required action,
  success flag, and error message.
- Manifest transition: `command-guardrails` remains `partial`.
- Register or update collaborator:
  - `id`: `coding-command-output-guardrail-service`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/coding_command_output_guardrail_service.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: coding-command-output-guardrail-service`.

### Similar-Pattern Search

- Search `_buildCodingCommandPreflightGuardResult`,
  `detectPreflightIssue`, `local_execute_command`, `process_start`, and
  `_resolveProjectScopedArguments`.
- Do not change post-execution output guards.

### Acceptance Criteria

1. The prerequisite split is complete and every newly governed production file
   is below 500 physical lines.
2. The notifier wrapper is removed and the batch caller passes owner-resolved
   values directly.
3. Direct tests cover unsupported tools, empty and normalized commands,
   working-directory variants, every issue type, no issue, and exact result.
4. Poison tests prove another conversation's project root cannot change
   preflight evaluation.
5. Target-file line coverage is 100%.
6. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
7. Stop if project argument resolution must move into the service.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/coding_command_output_guardrail_service.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/coding_command_output_guardrail_service_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/coding_command_output_guardrail_service_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the existing destination and `minimum=100`,
then the corrected live canary.

### Handoff Notes

- Record resolved inputs, existing API compatibility, wrapper deletion,
  coverage, and canary identities.

### Completion Record (2026-07-31)

- `CodingCommandOutputGuardrailService.buildPreflightResult` now owns exact
  blocked-result construction while preserving all detector APIs. Project
  argument resolution remains at the owner-scoped caller before the service
  receives normalized command and working-directory values.
- The prerequisite split remains intact: the 161-line facade, 298-line output
  detector, and 356-line preflight detector are each below 500 physical lines.
  Eight direct tests cover 43/43 facade executable lines, including unsupported
  tools, empty input, every delegated detector route, null passthrough, and the
  exact result payload.
- `command-guardrails` remains `partial` and shrinks from 1,001 to 963 lines.
  The tool-loop batch grows from 685 to 703 lines for explicit owner-bound
  input assembly. The primary remains 8,935 lines, 37 declared parts contain
  12,059 lines, and the same-library aggregate falls to 20,994 lines.

## WS7-9: Extract SavedValidationCommandGuard

### Task

- Goal: move modified saved-validation command detection and result
  construction into a pure owner-input guard.
- User-visible behavior: none; equivalence, wrapper/operator detection, and
  blocked payload remain compatible.
- Non-goals: choosing or persisting the saved validation command.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildModifiedSavedValidationCommandGuardResult`,
  `_looksLikeModifiedSavedValidationCommand`,
  `_looksLikePathResolvedSavedValidationCommand`,
  `_simpleCommandSegmentArgs`, `_isShellControlArgument`, and
  `_savedValidationPathArgumentIndex`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:219`.
- Destination:
  `lib/features/chat/domain/services/saved_validation_command_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/saved_validation_command_guard_test.dart`.
- Required poison coverage: Slice 2b5.
- Owner lookup retained at the notifier boundary:
  `_savedValidationCommandForGeneration`.

### Implementation Notes

- Accept `ToolCallInfo` and the owning turn's saved validation command
  explicitly.
- Reuse independent command normalization and argument parsing through value
  APIs; do not pass notifier helpers as callbacks.
- Preserve exact-match acceptance, shell wrapper/operator rejection,
  path-resolved variants, tool filtering, and exact payload.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `saved-validation-command-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/saved_validation_command_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: saved-validation-command-guard`.

### Similar-Pattern Search

- Search all six named methods, `_savedValidationCommandForGeneration`,
  `saved_validation_command_modified`, and validation evidence writes.
- Keep saved-command selection at the owner boundary.

### Acceptance Criteria

1. The guard contains no workflow, conversation, or visible-state lookup.
2. Direct tests cover absent command, non-command tool, exact match,
   whitespace normalization, wrappers, operators, extra arguments,
   path-resolved commands, unrelated commands, and exact payload.
3. Slice 2b5 poison tests prove another conversation's saved command is ignored.
4. Target-file line coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural gates, and live
   canary pass.
6. Stop if the owner saved command cannot be supplied explicitly.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/saved_validation_command_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/saved_validation_command_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/saved_validation_command_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record command-equivalence cases, explicit owner value, Slice 2b5 poison
  test, measured shrink, coverage, and canary identities.

Focused implementation completed on 2026-07-31. The batch now passes the exact
turn owner, owner-saved validation command, and owner project root to the
independent 178-line `SavedValidationCommandGuard`. Fourteen direct tests cover
66/66 executable lines, including absent and non-command inputs, exact and
normalized equality, every shell operator, unrelated extensions, exact result
fields, relative/absolute `cat`, `ls`, `test`, and `grep` paths, shape and flag
mismatches, nested immutability, cross-conversation saved-command poisoning,
and owner-root poisoning. The primary remains at 8,925 lines,
`command-guardrails` shrinks from 663 to 529 lines, `tool-loop-batch` grows
from 741 to 747 lines, 37 declared parts contain 11,669 lines, and the
same-library aggregate falls to 20,594 lines.

## WS7-10: Extract SavedTaskTargetScopeGuard

### Task

- Goal: move saved-task target expansion, path normalization, scope checks, and
  blocked result construction into a pure guard.
- User-visible behavior: none; allowed paths, validation executable exceptions,
  normalization, and result payload remain compatible.
- Non-goals: selecting the active task or changing task target files.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_buildSavedTaskTargetScopeGuardResult`,
  `_allowedSavedTaskTargetFiles`, `_savedTaskForGeneration`,
  `_savedTaskTargetAllowsPath`, and `_normalizeSavedTaskScopePath`.
- External test seam:
  `allowedSavedTaskTargetFilesForTest`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:224`.
- Destination:
  `lib/features/chat/domain/services/saved_task_target_scope_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/saved_task_target_scope_guard_test.dart`.
- Required poison coverage: Slice 2b5.

### Implementation Notes

- Accept `ToolCallInfo` and the owning `ConversationWorkflowTask?`.
- Move target expansion and normalization; replace the notifier test seam with
  the collaborator API or direct tests.
- Preserve validation executable paths from
  `ConversationPlanExecutionGuardrails`, directory/relative matching, task
  metadata, and exact payload.
- Leave active-task selection in the notifier as an owner-aware lookup.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `saved-task-target-scope-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/saved_task_target_scope_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: saved-task-target-scope-guard`.

### Similar-Pattern Search

- Search all five source methods, the test seam,
  `saved_task_target_scope_violation`, `targetFiles`, and
  `_savedTaskForGeneration`.
- Do not move plan execution focus selection.

### Acceptance Criteria

1. The collaborator receives the owner task explicitly and has no conversation
   lookup.
2. Direct tests cover no task, empty targets, write/edit/other tools,
   exact/relative/nested/outside paths, normalization, validation executable
   paths, duplicate targets, and exact payload.
3. Slice 2b5 poison tests prove the visible thread's task and project root do
   not affect the owner.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if active-task lookup is not owner-keyed.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/saved_task_target_scope_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/saved_task_target_scope_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/saved_task_target_scope_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record task lookup boundary, path matrix, removed test seam, Slice 2b5 cases,
  measured counts, coverage, and canary identities.

Focused implementation completed on 2026-07-31. The notifier retains only the
owner-keyed active-task lookup and passes the captured task, project root, and
immutable tool call to the independent 135-line
`SavedTaskTargetScopeGuard`. Its public target-expansion API replaces the
notifier-only test seam, while owner-root normalization is also reused for
saved `cat` validation evidence. Eighteen direct tests cover 48/48 executable
lines across absent and empty tasks, write/edit applicability, exact,
relative, directory, nested, outside-root, case, slash, whitespace, and dot
segment paths, validation executables, duplicate targets, exact blocked
fields, nested immutability, visible-task poisoning, and visible-root
poisoning. The primary falls from 8,925 to 8,924 lines,
`command-guardrails` shrinks from 529 to 429 lines, `tool-loop-batch` grows
from 747 to 751 lines, 37 declared parts contain 11,573 lines, and the
same-library aggregate falls to 20,497 lines. Integrated verification and the
corrected live canary remain pending at this focused checkpoint.

## WS7-11: Extract UnexecutedFileMutationBeforeCommandGuard

### Task

- Goal: move claimed-but-unexecuted file mutation detection before commands
  into a pure guard.
- User-visible behavior: none; pending-call/result evidence, claim detection,
  and blocked payload remain compatible.
- Non-goals: changing claim detection policy or executing file mutations.

### Context

- Source:
  `_buildUnexecutedFileMutationBeforeCommandGuardResult` in
  `chat_notifier_command_guardrails.dart`.
- Call site:
  `chat_notifier_tool_loop_batch.dart:238`.
- Existing policy dependencies include successful file-side-effect and future
  file-action detection helpers.
- Destination:
  `lib/features/chat/domain/services/unexecuted_file_mutation_before_command_guard.dart`.
- Direct tests:
  `test/features/chat/domain/services/unexecuted_file_mutation_before_command_guard_test.dart`.

### Implementation Notes

- Accept the tool call, current owner assistant content, pending owner calls,
  and executed owner results.
- Reuse or move narrow independent claim/evidence policies; never pass notifier
  helpers as callbacks.
- Preserve read-only bypass, pending mutation behavior, successful side-effect
  evidence, diagnostic clipping, optional blocked command, and exact payload.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `unexecuted-file-mutation-before-command-guard`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/unexecuted_file_mutation_before_command_guard.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: unexecuted-file-mutation-before-command-guard`.

### Similar-Pattern Search

- Search the source method, `unexecuted_file_save`,
  `_looksLikeFutureFileSideEffectAction`,
  `_hasSuccessfulFileSideEffectResult`, and pending batch calls.
- Inspect final-answer claim guards without combining them.

### Acceptance Criteria

1. All evidence is an explicit owner-turn input.
2. Direct tests cover non-command/read-only, pending mutation before/after,
   successful and failed mutation results, claim/no claim, long content,
   command present/absent, and exact payload.
3. Poison tests prove another thread's mutation result or claim does not affect
   the owner.
4. Target-file line coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural gates, and live
   canary pass.
6. Stop if successful mutation evidence comes from a flat cross-turn ledger.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/unexecuted_file_mutation_before_command_guard.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  test/features/chat/domain/services/unexecuted_file_mutation_before_command_guard_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/unexecuted_file_mutation_before_command_guard_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record explicit evidence inputs, branch matrix, poison case, achieved counts,
  coverage, and canary identities.

Focused implementation completed on 2026-07-31. The tool-loop batch now passes
the owner identity, recursively frozen command, pending calls, executed
results, and current assistant content to the independent 115-line
`UnexecutedFileMutationBeforeCommandGuard`. Twelve direct tests cover 38/38
executable lines across non-command and read-only bypasses, pending mutations
before and after the command, same-ID behavior, successful and failed mutation
evidence, claim and no-claim text, diagnostic clipping, optional command
fields, non-JSON rejection, recursive immutability, cross-owner result
poisoning, and cross-owner claim poisoning. The primary falls to 8,923
lines, `command-guardrails` shrinks from 429 to 376 lines,
`tool-loop-batch` grows from 751 to 754 lines, 37 declared parts contain
11,523 lines, and the same-library aggregate falls to 20,446 lines. Integrated
verification and the corrected live canary remain pending at this focused
checkpoint.

## WS7-12: Extract ToolLoopExhaustionPolicy

### Task

- Goal: move the tool-loop exhaustion recovery predicate into a pure policy.
- User-visible behavior: none; recovery eligibility remains compatible.
- Non-goals: requesting the recovery completion or changing loop budgets.

### Context

- Source:
  `_shouldRequestToolLoopExhaustionRecovery` in
  `chat_notifier_command_guardrails.dart`.
- Caller:
  `chat_notifier.dart:5985`.
- Destination:
  `lib/features/chat/domain/services/tool_loop_exhaustion_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/tool_loop_exhaustion_policy_test.dart`.

### Implementation Notes

- Expose one pure decision with all current booleans, exit reason, completion
  state, and owner-turn evidence as named immutable inputs.
- Preserve every gating condition and short-circuit outcome.
- Replace the notifier call directly; do not move recovery orchestration.
- Manifest transition: `command-guardrails` remains `partial`.
- Append collaborator:
  - `id`: `tool-loop-exhaustion-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/tool_loop_exhaustion_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: tool-loop-exhaustion-policy`.

### Similar-Pattern Search

- Search `_shouldRequestToolLoopExhaustionRecovery`,
  `ToolLoopExitReason`, exhaustion recovery request methods, and loop budget
  extensions.
- Do not move `ToolLoopRecoveryPolicy`.

### Acceptance Criteria

1. The predicate is independent and all inputs are named.
2. Direct tests use a truth-table covering every blocking and allowing
   condition plus relevant combinations.
3. Target-file line coverage is 100%.
4. No state, provider, Zone, callback, or I/O dependency exists.
5. Manifest, marker, budget, aggregate ratchet, structural gates, and live
   canary pass.
6. Stop if a decision input cannot be expressed as an immutable value.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/tool_loop_exhaustion_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/tool_loop_exhaustion_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/tool_loop_exhaustion_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the complete decision table, migrated caller, measured shrink,
  coverage, and canary identities.

Focused implementation completed on 2026-07-31. The bounded-recovery caller
now derives all seven named immutable facts from its current loop and passes
them to the independent 55-line `ToolLoopExhaustionPolicy`; recovery
orchestration and budgets remain in the notifier. Six direct tests cover 10/10
executable lines, including the exact limit and beyond, zero-budget behavior,
each individual blocker, combined blockers, and the allowing read-only case.
The primary falls from 8,923 to 8,922 lines, `command-guardrails` shrinks from
376 to 365 lines, 37 declared parts contain 11,512 lines, and the same-library
aggregate falls to 20,434 lines. Integrated verification and the corrected
live canary remain pending at this focused checkpoint.

## WS7-13: Extract GitWriteConfirmationPolicy

### Task

- Goal: move Git write-command recognition and user-confirmation blocking into
  an owner-input policy.
- User-visible behavior: none; qualifying calls and confirmation-question
  recognition remain compatible.
- Non-goals: asking the user, executing Git, or changing write classification.

### Context

- Source: `chat_notifier_command_guardrails.dart` methods
  `_shouldBlockToolCallsForUserConfirmation`,
  `_isWriteGitCommandToolCall`, and
  `_looksLikeGitWriteConfirmationQuestion`.
- Caller:
  `chat_notifier.dart:5479`.
- Destination:
  `lib/features/chat/domain/services/git_write_confirmation_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/git_write_confirmation_policy_test.dart`.

### Implementation Notes

- Accept immutable owner-turn pending calls and current assistant content.
- Reuse `ToolCapabilityClassifier` or independent Git classification. Preserve
  question-pattern matching and batch-blocking semantics exactly.
- The notifier remains responsible for asking and waiting.
- Manifest transition: `command-guardrails` remains `partial`; if this is the
  final method moved from the part, change it to `extracted` and remove the
  part.
- Append collaborator:
  - `id`: `git-write-confirmation-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/git_write_confirmation_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: git-write-confirmation-policy`.

### Similar-Pattern Search

- Search all three methods, Git write capability classes, confirmation prompt
  strings, and tool-loop blocking.
- Inspect production-release approval but do not combine it.

### Acceptance Criteria

1. The caller supplies owner-turn content and calls explicitly.
2. Direct tests cover empty/mixed batches, read/write Git commands,
   non-Git mutations, recognized/unrecognized questions, whitespace/case
   variants, and exact decision behavior.
3. Poison tests prove another thread's question or pending Git call cannot
   block the owner.
4. Target-file line coverage is 100%.
5. Final manifest status, optional old-part removal, marker, exact budgets,
   structural gates, and live canary pass.
6. Stop if pending-call ownership is not explicit.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/git_write_confirmation_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/git_write_confirmation_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/git_write_confirmation_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record Git classification and question matrices, owner poison case, final
  command-guardrails part status, counts, coverage, and canary identities.

Focused implementation completed on 2026-07-31. Both the confirmation block
and tool-loop exhaustion callers now use the independent 93-line
`GitWriteConfirmationPolicy`; the notifier supplies the exact owner,
recursively frozen pending calls, and current assistant content and remains
responsible for asking and waiting. Thirteen direct tests cover 32/32
executable lines across always-read, always-write, and conditional Git
commands, missing commands, non-Git mutations, mixed and empty batches,
English and localized question families, whitespace and case variants,
oversized and declarative text, recursive immutability, non-JSON rejection,
cross-owner question poisoning, and cross-owner pending-call poisoning. The
primary remains at 8,922 lines, `command-guardrails` shrinks from 365 to 311
lines and remains `partial`, 37 declared parts contain 11,458 lines, and the
same-library aggregate falls to 20,380 lines. Integrated verification and the
corrected live canary remain pending at this focused checkpoint.

## WS7-14: Extract ModelSwitchSettingsPolicy

### Task

- Goal: move model-route comparison, previous-model preparation selection, and
  data-source rebuild decisions into a pure settings policy.
- User-visible behavior: none; route-change and rebuild decisions remain
  compatible.
- Non-goals: mutating settings, rebuilding the data source, or scheduling a
  handoff.

### Context

- Source: `chat_notifier_context_surgery.dart` methods
  `_previousPrimaryModelForPreparation`, `_modelSwitchRouteKey`, and
  `_shouldRebuildChatDataSource`, plus their decision use in
  `_updateConnectionSettings`.
- Destination:
  `lib/features/chat/domain/services/model_switch_settings_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/model_switch_settings_policy_test.dart`.

### Implementation Notes

- Expose one pure comparison result with route-changed, previous model for
  preparation, and should-rebuild-data-source fields.
- Accept previous and next `AppSettings`; do not perform provider reads or
  mutations.
- Preserve OpenAI-compatible/demo gates, trimmed credential and URL
  comparison, effective model route identity, and every rebuild field.
- Leave `_updateConnectionSettings` as a thin notifier orchestration shell.
- Manifest transition: `context-surgery` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `model-switch-settings-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/model_switch_settings_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: model-switch-settings-policy`.

### Similar-Pattern Search

- Search the three source methods, `_updateConnectionSettings`,
  `_primaryModelPreparationKey`, and data-source rebuild logic.
- Do not move settings persistence or remote data-source construction.

### Acceptance Criteria

1. The three decisions move and `_updateConnectionSettings` applies the typed
   result.
2. Direct tests cover provider changes, demo transitions, URL/API key changes
   and trimming, model changes, reasoning effort, log flag, unchanged values,
   and exact route IDs.
3. Target-file line coverage is 100%.
4. The policy has no provider, state, clock, or side effect.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if a decision mutates settings or depends on runtime provider state.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/model_switch_settings_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  test/features/chat/domain/services/model_switch_settings_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/model_switch_settings_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the comparison result type, full settings matrix, measured shrink,
  coverage, and canary identities.

Focused implementation completed on 2026-07-31. The context-surgery shell now
passes previous and next `AppSettings` to the independent 71-line
`ModelSwitchSettingsPolicy` and applies its typed route IDs, route-change,
previous-model preparation, and data-source rebuild result without moving any
side effect. Fourteen direct tests cover 30/30 executable lines across
OpenAI-compatible and Apple route IDs, provider and demo transitions, raw and
trimmed URL/API-key comparisons, model case and whitespace, empty models,
reasoning effort, session logs, unrelated settings, and every preparation
exclusion. The `context-surgery` manifest record becomes `partial`; the
primary remains at 8,922 lines, its historical part shrinks from 268 to 218
lines, 37 declared parts contain 11,408 lines, and the same-library aggregate
falls to 20,330 lines. Integrated verification and the corrected live canary
remain pending at this focused checkpoint.

## WS7-15: Extract ModelSwitchHandoffRegistry

### Task

- Goal: move model-switch handoff scheduling, owner-scoped consumption,
  clearing, prompt-compaction flag consumption, and prompt message creation
  into an independent registry.
- User-visible behavior: none; handoff briefs, single consumption, compaction,
  and inserted system messages remain compatible.
- Non-goals: changing brief generation or connection settings orchestration.

### Context

- Source: `chat_notifier_context_surgery.dart` methods
  `_scheduleModelSwitchHandoff`, `_takePendingModelSwitchHandoffBrief`,
  `_clearPendingModelSwitchHandoff`, `_consumeForcePromptCompactionFlag`, and
  `_addModelSwitchHandoffPromptMessage`.
- Existing brief builder:
  `ModelSwitchHandoffBriefService`.
- External test seam:
  `scheduleModelSwitchHandoffForTest`.
- Destination:
  `lib/features/chat/domain/services/model_switch_handoff_registry.dart`.
- Direct tests:
  `test/features/chat/domain/services/model_switch_handoff_registry_test.dart`.

### Implementation Notes

- Key pending handoffs by conversation. Include interaction generation if a
  handoff can coexist across generations.
- Accept explicit conversation, immutable messages, previous/next models, and
  injected clock for prompt message creation.
- Return updated prompt messages or a typed handoff message; do not mutate
  notifier collections.
- Replace the notifier test seam with direct registry tests.
- Manifest transition: `context-surgery` remains `partial`.
- Append collaborator:
  - `id`: `model-switch-handoff-registry`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/model_switch_handoff_registry.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: model-switch-handoff-registry`.

### Similar-Pattern Search

- Search all five source methods, `_modelSwitchHandoffBrief`,
  `_modelSwitchHandoffConversationId`, `_forcePromptCompactionForNextRequest`,
  and the external test seam.
- Do not move `ModelSwitchHandoffBriefService`.

### Acceptance Criteria

1. No flat single-conversation handoff field remains.
2. Direct tests cover no brief, schedule, same/different owner take, one-time
   consumption, clear one/all as supported, forced and handoff compaction,
   timestamp injection, and exact system message.
3. Poison tests prove switching the visible conversation cannot consume or
   clear another owner's brief.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if owner-keyed storage cannot replace the flat fields without changing
   lifecycle semantics.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/model_switch_handoff_registry.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  test/features/chat/domain/services/model_switch_handoff_registry_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/model_switch_handoff_registry_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. The notifier now owns one
independent 89-line `ModelSwitchHandoffRegistry`: pending briefs are keyed by
conversation, forced compaction requests by exact `ChatTurnOwner`, and prompt
message timestamps come from the injected clock. The flat brief,
conversation-ID, and generation-set fields and the notifier-only scheduling
test seam are removed; the existing integration test now uses the public
settings update path. Seventeen direct tests cover 26/26 executable lines
across absent context, schedule/replace/take-once, wrong-owner poisoning,
targeted and global clears, generation-scoped one-shot compaction, explicit
forcing, handoff forcing, exact messages, clock usage, and immutable message
snapshots. The one-shot notifier integration test also passes. The primary
falls from 8,922 to 8,921 lines, `context-surgery` shrinks from 218 to 160
lines, the notifier test root falls to 18,613 lines, 37 declared parts contain
11,350 lines, and the same-library aggregate falls to 20,271 lines. Integrated
verification and the corrected live canary remain pending at this focused
checkpoint.

## WS7-16: Extract ContextSurgeryProtectedPathPolicy

### Task

- Goal: move context-surgery protected-path derivation into a pure policy using
  the owning conversation.
- User-visible behavior: none; execution-focus selection and normalized
  protected paths remain compatible.
- Non-goals: changing compaction or task focus.

### Context

- Source:
  `_contextSurgeryProtectedPathsForGeneration` in
  `chat_notifier_context_surgery.dart`.
- Callers:
  `chat_notifier.dart` and `chat_notifier_final_answer_recovery.dart`.
- Destination:
  `lib/features/chat/domain/services/context_surgery_protected_path_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/context_surgery_protected_path_policy_test.dart`.
- Required poison coverage: Slice 2b6.

### Implementation Notes

- Accept `Conversation?` explicitly and reuse
  `ConversationPlanExecutionCoordinator.executionFocusTask`.
- Preserve null handling, target trimming, empty filtering, and set
  deduplication.
- Replace both notifier calls with the owner conversation resolved at the turn
  boundary.
- Manifest transition: `context-surgery` remains `partial`.
- Append collaborator:
  - `id`: `context-surgery-protected-path-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/context_surgery_protected_path_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: context-surgery-protected-path-policy`.

### Similar-Pattern Search

- Search `_contextSurgeryProtectedPathsForGeneration`, both call sites,
  `executionFocusTask`, `protectedPaths`, and compact-result generation.
- Do not move compaction itself.

### Acceptance Criteria

1. Neither call site reads `currentConversation`.
2. Direct tests cover null conversation, no focus, empty/whitespace/duplicate
   paths, multiple tasks, and exact selected set.
3. Slice 2b6 poison tests prove visible-thread paths never protect or expose
   the owner's compacted results.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the owner conversation is unavailable at either call site.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/context_surgery_protected_path_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_final_answer_recovery.dart \
  test/features/chat/domain/services/context_surgery_protected_path_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/context_surgery_protected_path_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. Both compact-result call sites
now resolve the registered interaction owner's conversation and pass it to the
independent 20-line `ContextSurgeryProtectedPathPolicy`; neither path consults
the visible conversation. The policy reuses the existing execution-focus
selection and returns a trimmed, filtered, deduplicated, immutable set. Ten
direct tests cover null and absent focus, active/blocked/pending precedence,
projected progress, whitespace, duplicates, immutability, and owner/visible
poisoning with 7/7 executable lines covered. Three existing Slice 2b6
integration tests also pass for non-streaming compact retry, retry eligibility,
and streamed plus concise recovery in both owner directions. The primary
remains at 8,921 lines, `context-surgery` shrinks from 160 to 147 lines,
`final-answer-recovery` shrinks by one line to 286, 37 declared parts contain
11,336 lines, and the same-library aggregate falls to 20,257 lines. Integrated
verification and the corrected live canary remain pending at this focused
checkpoint.

## WS7-17: Extract RequestToolObservationCollector

### Task

- Goal: move request tool-definition and external-MCP-name observation into an
  independent pure collector.
- User-visible behavior: none; observed definitions and names remain
  compatible and never alter the advertised tool list.
- Non-goals: choosing request tools or managing MCP connection state.

### Context

- Source: `chat_notifier_context_surgery.dart` methods
  `_collectRequestToolObservation` and `_externalMcpToolNames`.
- Caller:
  `chat_notifier_prompt_context.dart:21`.
- Destination:
  `lib/features/chat/domain/services/request_tool_observation_collector.dart`.
- Direct tests:
  `test/features/chat/domain/services/request_tool_observation_collector_test.dart`.

### Implementation Notes

- Accept immutable tool definitions, connection status, external tool
  descriptors, override presence, effective tool names, MCP-enabled state, and
  temporal-context presence.
- Do not accept `McpToolService`; the notifier takes its immutable snapshot
  first.
- Preserve disabled behavior, connected-only external names, plan-drafting
  observation semantics, override filtering, malformed definition handling,
  ordering, and non-mutation.
- Manifest transition: `context-surgery` remains `partial`.
- Append collaborator:
  - `id`: `request-tool-observation-collector`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/request_tool_observation_collector.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: request-tool-observation-collector`.

### Similar-Pattern Search

- Search both source methods, `_mcpToolService`,
  `getOpenAiToolDefinitions`, `toolNamesOverride`, and context-window tool
  rows.
- Verify the collector never writes to request tool names.

### Acceptance Criteria

1. The collector is pure and receives no service or provider.
2. Direct tests cover null/empty override, MCP disabled/enabled,
   temporal-context enablement, connected/disconnected status, malformed
   tools/definitions, subset filtering, ordering, and input non-mutation.
3. Target-file line coverage is 100%.
4. Prompt-context tests prove observed and actually sent definitions remain
   distinct.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if collection changes the advertised tool catalog.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/request_tool_observation_collector.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  test/features/chat/domain/services/request_tool_observation_collector_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/request_tool_observation_collector_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. Prompt construction now takes
an immutable snapshot of the MCP catalog and passes only definitions,
descriptors, connection state, override presence, effective names, MCP
enablement, and temporal-context presence to the independent 116-line
`RequestToolObservationCollector`. The collector never receives a service or
Provider and never writes to advertised tool names. Fifteen direct tests cover
37/37 executable lines across every activation source, null catalog, full
plan-drafting observation with an unchanged empty advertised list, empty and
subset overrides, malformed definitions and descriptors, exact ordering and
case, every connection state, sequential-owner poisoning, recursive snapshot
immutability, invalid JSON values, and unmodifiable output. The primary remains
at 8,921 lines, `context-surgery` shrinks from 147 to 87 lines,
`prompt-context` grows from 254 to 268 lines for explicit snapshot capture, 37
declared parts contain 11,290 lines, and the same-library aggregate falls to
20,211 lines. Integrated verification and the corrected live canary remain
pending at this focused checkpoint.

## WS7-18: Extract ContextSurgeryObservationAccumulator

### Task

- Goal: move partial observation accumulation and snapshot projection into an
  owner-scoped accumulator.
- User-visible behavior: none; retained fields, snapshot equality, and context
  surgery UI updates remain compatible.
- Non-goals: changing snapshot computation or storing UI state.

### Context

- Source:
  `_updateContextSurgeryObservation` in
  `chat_notifier_context_surgery.dart`.
- Callers:
  `chat_notifier_prompt_context.dart:70` and `chat_notifier.dart:4382`.
- Existing projector:
  `ContextSurgeryObservationService`.
- Destination:
  `lib/features/chat/domain/services/context_surgery_observation_accumulator.dart`.
- Direct tests:
  `test/features/chat/domain/services/context_surgery_observation_accumulator_test.dart`.

### Implementation Notes

- Key accumulated inputs by conversation and interaction generation. Define an
  immutable update with optional prompt, results, definitions, and MCP names.
- Return the new snapshot and a changed flag; the notifier checks mount and
  writes `ChatState`.
- Copy incoming collections into unmodifiable values and preserve omitted
  fields from the same owner only.
- Manifest transition: `context-surgery` becomes `extracted` only if
  `_updateConnectionSettings` and public adapters have moved elsewhere;
  otherwise remains `partial`.
- Append collaborator:
  - `id`: `context-surgery-observation-accumulator`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/context_surgery_observation_accumulator.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: context-surgery-observation-accumulator`.

### Similar-Pattern Search

- Search `_updateContextSurgeryObservation`,
  `_latestObservedSystemPrompt`, `_latestObservedToolResults`,
  `_latestObservedToolDefinitions`, `_latestObservedMcpToolNames`, and both
  callers.
- Do not move state assignment or widget presentation.

### Acceptance Criteria

1. No flat latest-observation fields remain across conversations.
2. Direct tests cover partial updates, preservation, collection copies,
   equal/changed snapshot, two owners, two generations, clear/dispose behavior,
   and exact projection.
3. Poison tests prove one thread's prompt, tools, or results never combine with
   another's snapshot.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the accumulator cannot be keyed by owner without lifecycle
   ambiguity.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/context_surgery_observation_accumulator.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  test/features/chat/domain/services/context_surgery_observation_accumulator_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/context_surgery_observation_accumulator_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. The four flat latest-observation
fields are replaced by the independent 130-line
`ContextSurgeryObservationAccumulator`, keyed by exact `ChatTurnOwner`.
Prompt observations use the captured turn owner, with conversation-scoped
generation zero reserved for proposal drafts; budgeted tool-result observations
use the registered interaction owner. Changed snapshots are routed into the
owning thread's `ChatState`, and owner completion, global response cleanup, and
notifier disposal release accumulator state. Thirteen direct tests cover 49/49
executable lines across partial preservation, explicit clears, equal and
changed projections, exact service projection, recursive copies and invalid
JSON, two conversations, two generations, owner removal, conversation removal,
and global clear. Three existing detached-owner integrations also pass across
non-streaming retry, retry eligibility, and streamed plus concise recovery.
The primary falls from 8,921 to 8,914 lines, `context-surgery` falls from 87 to
79 lines, `prompt-context` grows from 268 to 279 lines,
`final-answer-recovery` grows from 286 to 288 lines, 37 declared parts contain
11,295 lines, and the same-library aggregate falls to 20,209 lines. Integrated
verification and the corrected live canary remain pending at this focused
checkpoint.

## WS7-19: Extract ModelEditApplyTelemetryRecorder

### Task

- Goal: move model edit-apply telemetry classification, profile update, and
  failure feedback routing behind an owner-aware recorder.
- User-visible behavior: none; telemetry remains best-effort and never
  interrupts the tool loop.
- Non-goals: changing profile scoring, sampler feedback calculations, or
  settings persistence.

### Context

- Source:
  `_recordModelEditApplyTelemetry` in
  `chat_notifier_tool_result_telemetry.dart`.
- Callers:
  `chat_notifier_tool_loop_batch.dart:584` and
  `chat_notifier.dart:7664`.
- Existing policies:
  `ModelEditApplyTelemetryService` and
  `LlmSamplerRuntimeFeedbackService`.
- Destination:
  `lib/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart`.
- Direct tests:
  `test/features/chat/domain/services/model_edit_apply_telemetry_recorder_test.dart`.

### Implementation Notes

- Define owner-aware `ModelCapabilityProfileStorePort` and
  `RuntimeSamplerFeedbackPort`.
- Accept the owner, tool result, and explicit baseline profile. Construct the
  same normalized fallback profile at the notifier boundary or in a pure value
  helper.
- Preserve classification, null-update behavior, persist-before-feedback
  order, edit-failure signal, and exception swallowing.
- Do not mutate notifier `_settings`; return the persisted profile or a typed
  outcome so the notifier adapter can refresh owner-independent settings.
- Manifest transition:
  `tool-result-telemetry` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `model-edit-apply-telemetry-recorder`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: model-edit-apply-telemetry-recorder`.

### Similar-Pattern Search

- Search `_recordModelEditApplyTelemetry`, both call sites,
  `ModelEditApplyTelemetryService`, profile upserts, and edit failure signals.
- Do not move the pure telemetry classifier.

### Acceptance Criteria

1. Both callers pass owner and baseline profile explicitly.
2. Direct tests cover non-edit, edit success/failure, null update, fallback
   profile, persistence success/failure, feedback success/failure, call order,
   and never-throw behavior.
3. Poison tests prove delayed persistence cannot apply turn-specific feedback
   to another owner.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if profile persistence requires a provider to cross the collaborator
   boundary.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_result_telemetry.dart \
  test/features/chat/domain/services/model_edit_apply_telemetry_recorder_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/model_edit_apply_telemetry_recorder_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. Both persisted tool-loop results
and streamed content-tool results pass their exact `ChatTurnOwner`, tool result,
and an explicit normalized profile baseline to the independent 191-line
`ModelEditApplyTelemetryRecorder`. The recorder owns classification, null-update
handling, persist-before-feedback order, failure-signal routing, and exception
swallowing. An owner-validating 58-line store adapter checks the owner before
and after settings persistence; the 82-line presentation adapter is the only
boundary that holds `SettingsNotifier`. Thirteen recorder tests cover 28/28
executable lines (100%), four store tests cover stale, retired, replaced, and
cross-conversation owners, and three runtime tests cover fallback construction,
two-write failure ordering, and delayed-owner poisoning. The primary falls to
8,913 lines, `tool-result-telemetry` falls from 148 to 130 lines,
`tool-loop-batch` grows from 754 to 758 lines, 37 declared parts contain 11,281
lines, and the same-library aggregate falls from 20,209 to 20,194 lines.
Integrated verification and the corrected live canary remain pending at this
focused checkpoint.

## WS7-20: Extract RuntimeSamplerFeedbackRecorder

### Task

- Goal: move malformed-call, repetition, planning JSON repair, generic JSON
  repair, and sampler feedback recording behind a narrow best-effort recorder.
- User-visible behavior: none; signal types, request-class selection, profile
  updates, and failure swallowing remain compatible.
- Non-goals: changing sampler policy or settings UI.

### Context

- Source: `chat_notifier_tool_result_telemetry.dart` methods
  `_recordMalformedToolCallRuntimeFeedback`,
  `_recordToolLoopRepetitionRuntimeFeedback`,
  `_recordPlanningJsonRepairRuntimeFeedback`,
  `_recordJsonRepairRuntimeFeedback`, and
  `_recordRuntimeSamplerFeedback`.
- Callers include tool-call batch handling and JSON repair proposal parsers.
- Existing policy:
  `LlmSamplerRuntimeFeedbackService`.
- Destination:
  `lib/features/chat/domain/services/runtime_sampler_feedback_recorder.dart`.
- Direct tests:
  `test/features/chat/domain/services/runtime_sampler_feedback_recorder_test.dart`.

### Implementation Notes

- Define `ModelCapabilityProfileStorePort`; pass the owner, explicit baseline
  profile, settings-loaded flag, and assistant mode where relevant.
- Expose named operations for malformed call, repetition, planning repair, JSON
  repair, and generic signal, or one typed event API.
- Preserve malformed detection, assistant-mode request-class mapping, signal
  counts, null-update behavior, unawaited planning behavior at the caller, and
  never-throw semantics.
- Manifest transition: `tool-result-telemetry` remains `partial`.
- Append collaborator:
  - `id`: `runtime-sampler-feedback-recorder`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/runtime_sampler_feedback_recorder.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: runtime-sampler-feedback-recorder`.

### Similar-Pattern Search

- Search all five source methods, `LlmSamplerRuntimeFeedbackSignal`, JSON repair
  callbacks, malformed call handling, and profile upserts.
- Replace every caller; do not leave a notifier wrapper used only as a callback.

### Acceptance Criteria

1. All callers use typed recorder events and no callback captures the notifier.
2. Direct tests cover malformed match/no match, repetition, every assistant
   mode, settings not loaded, each JSON repair class, null update, persistence
   success/error, and never-throw behavior.
3. Poison tests preserve owner identity across delayed feedback writes.
4. Target-file line coverage is at least 95%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if a parser still requires a broad telemetry callback; replace it with
   a typed event sink.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/runtime_sampler_feedback_recorder.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_result_telemetry.dart \
  test/features/chat/domain/services/runtime_sampler_feedback_recorder_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/runtime_sampler_feedback_recorder_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. Malformed-call, repetition,
planning JSON repair, explicit JSON repair, and generic sampler signals now
flow through the independent 245-line `RuntimeSamplerFeedbackRecorder`.
Every event snapshots its exact owner and normalized profile baseline; planning
parsers receive a typed immutable event binding instead of capturing a notifier
callback, and the parser remains responsible for unawaited delivery. The
existing owner-validating profile store is shared with edit-apply telemetry,
including detached planning operations, and every policy or persistence failure
remains best effort. Nineteen direct tests cover malformed match/no-match,
repetition, all assistant modes, unloaded settings, all request classes, null
updates, signal snapshots, ordering, delayed-owner poisoning, and never-throw
paths. Target coverage is 49/49 executable lines (100%). The primary falls
from 8,913 to 8,912 lines, `tool-result-telemetry` falls from 130 to 76 lines,
`tool-loop-batch` grows from 758 to 767 lines, 37 declared parts contain 11,246
lines, and the same-library aggregate falls from 20,194 to 20,158 lines.
Integrated verification and the corrected live canary remain pending at this
focused checkpoint.

## WS7-21: Extract ContentToolFailureFormatter

### Task

- Goal: move content-tool failure code classification and JSON result
  construction into a pure formatter.
- User-visible behavior: none; default errors, code precedence, and JSON output
  remain byte-compatible.
- Non-goals: changing tool execution or result-ledger recording.

### Context

- Source: `chat_notifier_tool_result_telemetry.dart` methods
  `_buildContentToolFailureResult` and `_contentToolFailureCode`.
- Callers:
  `chat_notifier.dart:7633` and `:7681`.
- Destination:
  `lib/features/chat/domain/services/content_tool_failure_formatter.dart`.
- Direct tests:
  `test/features/chat/domain/services/content_tool_failure_formatter_test.dart`.

### Implementation Notes

- Expose one pure `format(toolName, errorMessage)` operation; keep code
  selection private.
- Preserve trimming, default error text, case-insensitive matching, match
  precedence, exact keys, and JSON encoding.
- Replace both callers directly.
- Manifest transition: `tool-result-telemetry` remains `partial` because flat
  content-result ledger writes are deferred. Do not remove the part.
- Append collaborator:
  - `id`: `content-tool-failure-formatter`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/content_tool_failure_formatter.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: content-tool-failure-formatter`.

### Similar-Pattern Search

- Search both source methods, both call sites, `tool_not_available`,
  `edit_mismatch`, `permission_denied`, `timeout`, and
  `tool_execution_failed`.
- Inspect Workstream 1 content-result formatting without combining protocols.

### Acceptance Criteria

1. Both methods move and both callers use the formatter directly.
2. Direct tests cover null/empty/whitespace error, every classified phrase,
   case variants, overlapping phrases and precedence, fallback, tool names, and
   exact decoded and encoded output.
3. Target-file line coverage is 100%.
4. No state, provider, Zone, port, or I/O dependency exists.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if output changes byte-for-byte for any current branch.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/content_tool_failure_formatter.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_result_telemetry.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/content_tool_failure_formatter_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/content_tool_failure_formatter_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

Focused implementation completed on 2026-07-31. Both streamed content-tool
failure branches now call the independent 32-line
`ContentToolFailureFormatter` directly. The formatter preserves null-only
defaulting, trimming, case-insensitive matching, exact precedence
(`tool_not_available`, `edit_mismatch`, `permission_denied`, `timeout`,
fallback), key order, and `jsonEncode` output. Eight direct tests cover exact
encoded and decoded payloads, empty and whitespace input, all phrases and case
variants, overlaps, near misses, tool-name preservation, and escaped control
and Unicode content; target coverage is 11/11 executable lines (100%). The
primary remains at 8,912 lines, `tool-result-telemetry` falls from 76 to 55
lines, 37 declared parts contain 11,225 lines, and the same-library aggregate
falls from 20,158 to 20,137 lines. Integrated verification and the corrected
live canary remain pending at this focused checkpoint.

## Deferred Workstream 7 Boundaries

The following are not approved implementation slices in this catalog:

- `_updateConnectionSettings` orchestration, remote data-source construction,
  settings provider reads, and final `ChatState` assignment. They remain thin
  notifier responsibilities after their decisions move.
- `_recordContentToolResult` and `_recordContentToolResultInfo`. They append to
  the flat `_turnToolResults` ledger and must not move until that ledger is
  keyed by conversation and interaction generation.
- Command diagnostic focus creation, retry-generation ownership, saved
  validation selection, and active saved-task selection. This catalog consumes
  explicit owner snapshots; it does not approve flat storage.
- Ask-user-question storage required by production-release approval. WS7-7 must
  wait for WS8-1 and its owner-keyed question cache. Do not implement WS7-7
  against the current generation-only cache.
- Tool execution, approval UI, command persistence, plan execution, compaction,
  and goal continuation. Their workstreams own those boundaries.

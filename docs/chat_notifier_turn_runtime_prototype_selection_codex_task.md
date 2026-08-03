# ChatNotifier TurnRuntime Prototype Selection: Codex Task

## Task

- Goal: Select the first `TurnRuntime` prototype part mechanically from the
  current ChatNotifier turn-scope audit and make the selection reproducible from
  a clean Git revision.
- User-visible behavior: None. This task adds development-time measurement
  tooling and tests only.
- Non-goals: Creating `TurnRuntime`, moving production behavior, wiring
  `ChatToolHandlerCatalog`, changing task-status ownership, adding a verification
  manifest, validating gates, comparing a prototype diff, or changing runtime
  telemetry.

## Context

- Affected files or components:
  - `tool/measure_chat_notifier_turn_runtime_prototype.py`
  - `test/python/measure_chat_notifier_turn_runtime_prototype_test.py`
  - `docs/chat_notifier_turn_runtime_prototype_selection_codex_task.md`
- Related docs:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_renewal_candidate_ranking.md`
- Reference implementation or pattern:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - `tool/chat_notifier_turn_scope_baseline.json`
  - `tool/chat_notifier_decomposition_manifest.json`
- Known quirks, compatibility rules, or release gates:
  - The decomposition manifest retains 43 historical part records, while the
    current audit declares 37 active part files. Only the audit's current
    `entrypoints` list is eligible for prototype selection.
  - A current part can retain historical manifest entrypoint names that no
    longer resolve in the AST audit. Selection records those names explicitly
    and ranks only resolved audited methods.
  - The checked-in audit is a working-tree baseline. Selection binds its bytes
    and the manifest bytes to the resolved source revision rather than claiming
    that the JSON embeds a build revision.
  - The architecture plan requires a clean source revision and forbids choosing
    an easier part manually.

## Implementation Notes

- Preferred approach:
  1. Add a `select` subcommand that reads the checked-in turn-scope audit and
     decomposition manifest.
  2. Resolve `--source-revision` to a full commit SHA with Git.
  3. When `--require-clean` is present, reject tracked or untracked worktree
     changes before producing a selection.
  4. Join every current audit part to its manifest entry and source file.
  5. Rank parts by the required keys, in order: descending count of
     turn-reachable entrypoints with explicit turn-identity parameters,
     descending turn-reachable ambient-read count, descending physical
     production line count, then ascending lexical part path.
  6. Emit the selected part and the full ranked candidate table as deterministic
     JSON, including source revision and SHA-256 input bindings.
- Constraints:
  - Do not modify Dart production files or checked-in audit baselines.
  - Do not add heuristic weighting or manual allow/deny lists.
  - Reject malformed or inconsistent schemas, duplicate part paths, missing
    manifest joins, missing source files, and entrypoints that join ambiguously
    to audited methods. Preserve unresolved historical entrypoint names in the
    output instead of treating them as current methods.
  - Keep errors concise, deterministic, and English-only.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The output is an ephemeral
  development artifact written outside the repository by the documented command.

## Similar-Pattern Search

- Search terms: `sourceRevision`, `rev-parse`, `require-clean`, `partPath`,
  `turnIdentityParameters`, `turnReachable`, `ambientReads`.
- Files or modules inspected:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - `tool/audit_chat_notifier_turn_scope.dart`
  - `tool/chat_notifier_turn_scope_baseline.json`
  - `tool/chat_notifier_decomposition_manifest.json`
- Follow-up tasks found:
  - Prepare a focused test and live canary for the selected part if either gate
    is missing.
  - Add and validate
    `tool/chat_notifier_turn_runtime_prototype_verification.json` in a separate
    preparatory slice.
  - Implement `compare` only when an isolated prototype is ready for measurement.

## Acceptance Criteria

- Required behavior:
  - The command selects from all and only current part paths declared in the
    audit.
  - Every eligible part joins to exactly one manifest record and an existing
    production source file.
  - Ranking follows the four architecture-plan keys exactly.
  - `HEAD` and other revision expressions are recorded as full Git SHAs.
  - Output is deterministic and contains SHA-256 bindings for both inputs.
- Edge cases:
  - Lexical path order resolves an otherwise exact tie.
  - A dirty worktree fails when `--require-clean` is set and is accepted when it
    is omitted.
  - Duplicate, missing, or inconsistent audit/manifest entries fail.
  - Ambiguous audited methods for a declared entrypoint fail; unresolved
    historical entrypoints remain visible but do not affect ranking.
- Failure paths: Invalid input or repository state exits with status 2 and a
  concise English error without writing a partial output file.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py
python3 tool/measure_chat_notifier_turn_runtime_prototype.py select \
  --audit tool/chat_notifier_turn_scope_baseline.json \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --source-revision HEAD \
  --require-clean \
  --output /tmp/chat_notifier_turn_runtime_candidate.json
git diff --check
```

## Handoff Notes

- Summary: Implemented the deterministic `select` command. From clean revision
  `519c2c9aeec37eb999e793309b3538c238584290`, it selected
  `chat_notifier_goal_auto_continue.dart`: 14 turn-reachable identity
  entrypoints, zero turn-reachable ambient reads, and 1,020 production lines.
  The output retains 22 resolved and 12 unresolved historical entrypoints.
- Tests run:
  - `python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py`:
    12 passed.
  - The documented clean-revision `select` command completed and wrote
    `/tmp/chat_notifier_turn_runtime_candidate.json`.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: Focused tests cover all four ranking keys,
  input hashing, full-SHA resolution, clean and dirty worktrees, stale
  revisions, malformed joins, unresolved historical entrypoints, and atomic
  CLI output. No production behavior changed.
- Risks or follow-ups:
  - The selected part reads `projectedExecutionTasks` and task status, so task
    state must not cross the runtime boundary before the M1 single-owner task
    view work establishes its contract.
  - The selected file also coordinates conversation-scoped goal trackers. A
    prototype must leave that state outside `TurnRuntime` behind an explicit
    port rather than moving the tracker into turn scope.
  - A goal auto-continue live canary already exists at
    `tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh`; the next
    preparatory slice must bind it and an exact focused test to the selected
    part in the verification manifest.
  - `validate-gates`, `compare`, and production extraction remain separate
    tasks.

## Selection Semantics Correction (2026-08-03)

The original selection consumed the broad audit's `turnIdentityParameters`
field without distinguishing `Conversation` context from explicit turn
identity. The architecture plan requires only `ChatTurnOwner`,
`interactionGeneration`, or `generation` parameters for its first ranking key.
The selector now applies that narrower contract while leaving the broad audit
and checked-in baseline unchanged. The clean-revision candidate must be
re-recorded before prototype implementation.

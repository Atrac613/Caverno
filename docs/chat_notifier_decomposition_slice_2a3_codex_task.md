# ChatNotifier Decomposition Slice 2a3: Thread-Scope Ratchet Repair

## Task

- Goal: make the existing thread-scope ratchet use complete signatures and
  per-read findings from the canonical Slice 2a1 audit.
- User-visible behavior: none.
- Non-goals:
  - fixing a pre-existing ambient production read;
  - changing the read or accessor vocabulary without updating the canonical
    audit;
  - extracting production code;
  - allowing baseline growth.

## Context

- Affected files:
  - `test/quality/thread_scoped_state_ratchet_test.dart`;
  - `tool/chat_notifier_turn_scope_baseline.json`;
  - the audit API introduced in Slice 2a1.
- Related docs:
  - `docs/chat_notifier_decomposition_codex_task.md`;
  - `docs/chat_notifier_decomposition_slice_2a1_codex_task.md`;
  - `docs/multi_thread_architecture_study.md`.
- Current defects:
  - only the first six signature lines are inspected;
  - finding any turn-scoped accessor skips the entire method;
  - multiple read occurrences collapse to one method/read-kind identity.

## Implementation Notes

- Remove the hand-written method splitter and signature window from the
  ratchet. Consume the syntax-aware audit result directly.
- Compare stable per-occurrence IDs, not source line numbers.
- Treat the reviewed Slice 2a1 baseline as a shrink-only set:
  - new production-read IDs fail;
  - missing IDs fail with instructions to regenerate and lower the baseline in
    the same extraction slice;
  - metadata drift for an existing ID fails rather than being ignored.
- Reconcile every newly surfaced pre-existing read exactly with the committed
  Slice 2a1 report. Label this commit as a baseline migration; do not describe
  it as new debt.
- Keep fixture coverage that proves:
  - a turn parameter below line six is recognized;
  - two same-kind reads in one method produce two IDs;
  - a method with a turn accessor still reports its ambient reads;
  - adding, removing, or reclassifying a baseline read fails.
- Do not modify production code, the decomposition manifest, or size budgets.

## Similar-Pattern Search

- Search terms:
  - `_methods`;
  - `_signature`;
  - `take(6)`;
  - `_asksWhichThread`;
  - `_knownAmbientReads`.
- Confirm no second quality test retains the old six-line or whole-method-skip
  implementation.

## Acceptance Criteria

1. The ratchet uses the Slice 2a1 AST audit and complete signatures.
2. Every ambient read occurrence remains visible even when the method consults
   a turn-scoped accessor.
3. The checked baseline exactly matches the reviewed Slice 2a1 audit.
4. New, removed, and metadata-changed reads all fail with actionable output.
5. Fixture tests cover multiline signatures, repeated reads, mixed accessors,
   baseline growth, and baseline shrink.
6. The production tree is unchanged and no allowlist growth is introduced
   after the baseline migration.

## Verification

```bash
fvm dart format \
  test/quality/thread_scoped_state_ratchet_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test test/quality/thread_scoped_state_ratchet_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh --coverage
git diff --check
```

The live multi-thread canary is not required because this slice changes only
static detection and its reviewed baseline.

## Handoff Notes

- Record old and new finding counts and the exact baseline-migration mapping.
- Record fixture cases proving complete-signature and per-read behavior.
- State explicitly that no production ambient read was added or fixed.
- Keep this slice in one focused Conventional Commit.

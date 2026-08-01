# ChatNotifier Decomposition Slice 2a2: Collaborator Boundary Gate

## Task

- Goal: enforce the decomposition manifest and strict independent-collaborator
  contract with a syntax-aware architecture test.
- User-visible behavior: none.
- Non-goals:
  - extracting another production collaborator;
  - changing manifest statuses except to correct a proven Slice 2a1 defect;
  - repairing thread-scope read detection from Slice 2a3;
  - accepting a new notifier part or an unmanifested marker.

## Context

- Affected files:
  - `test/quality/chat_notifier_collaborator_boundary_test.dart`;
  - the manifest reader introduced by Slice 2a1;
  - `tool/chat_notifier_decomposition_manifest.json`.
- Related docs:
  - `docs/chat_notifier_decomposition_codex_task.md`;
  - `docs/chat_notifier_decomposition_slice_2a1_codex_task.md`.
- Reference data:
  - the 43 historical `partPath` values recorded from `b0c19fdb`;
  - the current 42 declared parts;
  - the `content-tool-result-formatter` discovery marker and size budget.
- Known quirks:
  comment and string contents must not be treated as type references. Use
  analyzer nodes rather than raw substring bans.

## Implementation Notes

- Freeze all 43 historical part paths in the test independently of the
  manifest.
- Parse the current notifier part directives and require exact equality with
  manifest records whose status is `remaining`, `partial`, `keep`, or
  `deferred`.
- Enforce status lifecycle:
  - `extracted`: old part absent and at least one collaborator present;
  - `partial`: old part present and at least one collaborator present;
  - `remaining`, `keep`, or `deferred`: old part present;
  - only the five manifest status values are accepted.
- Require every collaborator path and `sizeBudgetKey` to exist. Verify the
  budget key is declared in `test/quality/file_size_ratchet_test.dart`.
- Independently scan all Dart files under `lib/features/chat` for the exact
  discovery marker format. Require a one-to-one match between marker ID,
  manifest collaborator ID, and file path.
- Parse every partial or extracted collaborator with analyzer ASTs and reject:
  - `part of`;
  - imports of notifier, chat-state, provider, or Riverpod libraries;
  - references to `ChatNotifier`, `ChatState`, `Ref`, `WidgetRef`, or
    `ProviderContainer`;
  - direct `TurnThread` or `TurnProjectRoot` reads;
  - those forbidden types in any public signature.
- Keep separate fixture tests for marker discovery, forbidden imports,
  forbidden type references, forbidden public signatures, and valid
  collaborators. A real-tree assertion alone is not enough to prove the gate.
- Do not change production files or budgets.

## Similar-Pattern Search

- Search terms:
  - `ChatNotifier decomposition collaborator:`;
  - `part of 'chat_notifier.dart'`;
  - `ChatNotifier`;
  - `ChatState`;
  - `WidgetRef`;
  - `ProviderContainer`;
  - `TurnThread`;
  - `TurnProjectRoot`.
- Inspect all marked files under `lib/features/chat`, including markers not
  listed by the manifest.

## Acceptance Criteria

1. The test freezes exactly the original 43 paths and rejects additions,
   removals, or duplicates.
2. Current declarations exactly match manifest status semantics.
3. Extracted and partial records enforce old-part presence and collaborator
   presence correctly.
4. Marker discovery is independent of manifest traversal and is one-to-one.
5. Every collaborator path and shrink-only budget key exists.
6. Syntax-aware checks reject every forbidden dependency and public-signature
   type without false positives from comments or strings.
7. Fixture tests prove each rejection path and the current formatter passes.
8. No production file, notifier declaration, or size budget changes.

## Verification

```bash
fvm dart format \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test test/quality/chat_notifier_collaborator_boundary_test.dart
fvm flutter test \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh --coverage
git diff --check
```

The live multi-thread canary is not required because this slice adds only a
static architecture gate.

## Handoff Notes

- Record frozen, declared, and status-selected part counts.
- Record discovered marker IDs and validated budget keys.
- Record every forbidden AST category covered by fixtures.
- Keep this slice in one focused Conventional Commit.

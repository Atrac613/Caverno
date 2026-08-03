# ChatNotifier TurnRuntime Prototype Compare: Codex Task

## Task

- Goal: Implement the required `compare` mode for the completed isolated
  `TurnRuntime` prototype.
- User-visible behavior: None. This task adds deterministic measurement and
  structural-gate reporting only.
- Non-goals: Changing production behavior, running the live canary, or making
  the Phase 1.5 closure decision.

## Context

- Affected components:
  - `tool/measure_chat_notifier_turn_runtime_prototype.py`
  - `test/python/measure_chat_notifier_turn_runtime_prototype_test.py`
- Comparison base: the clean production-edit branch point at `0bac2bc0`.
- Validated selection: the existing schema-v1 artifact whose source revision
  is an ancestor of the production comparison base.

## Implementation Notes

1. Require the comparison base to be an ancestor of current HEAD. Accept a
   squashed validated-selection revision only when the selected source is byte
   identical at the comparison base, and report that relation explicitly.
2. Report every touched non-generated `lib/` file with before and after lines.
3. Measure identity parameters on the manifest-reserved migrated symbols.
4. Report introduced port methods, callback surfaces, and public declarations.
5. Run the current turn-scope audit and compare it with the baseline stored at
   the before revision.
6. Detect newly added callback expressions that capture notifier surfaces.
7. Emit explicit machine-readable structural gate results.

## Acceptance Criteria

- Added, modified, deleted, and renamed production files are measured or fail
  clearly when unsupported.
- At least one migrated identity parameter can be proven removed.
- Ambient-read growth and notifier-capturing callbacks fail their gates.
- Selection drift, or non-ancestral source mismatch after a squash, fails
  before producing output.
- CLI output is atomic and deterministic.
- Existing `select` and `validate-gates` behavior remains green.

## Verification

```bash
python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py
python3 tool/measure_chat_notifier_turn_runtime_prototype.py compare --help
git diff --check
```

## Handoff Notes

- Summary: Added the schema-v1 `compare` command with atomic JSON output. It
  validates revision relationships, accepts a squashed selection only when the
  selected source is byte identical, measures every changed non-generated
  production file, compares migrated identity parameters, port methods,
  callback surfaces, public declarations, current ambient reads, and newly
  added notifier-capturing callback expressions, then emits explicit structural
  gates.
- Tests run:
  - 27 focused Python tests passed, including squashed-base equivalence,
    identity declaration disambiguation, callback capture, ambient growth, and
    atomic CLI output.
  - Actual comparison from `0bac2bc0` to the current worktree passed all three
    automated structural gates.
  - `git diff --check` passed.
- Actual comparison:
  - Production files touched: 15.
  - Production line delta: +708.
  - Migrated identity parameters removed: 1.
  - Turn-reachable ambient-read delta: -1.
  - Introduced port methods: 1.
  - Introduced callback surfaces: 2 clock surfaces.
  - New callback captures of `ChatNotifier`: 0.
  - Introduced public declarations: 19.
- Risks or follow-ups: Full coverage and post-prototype live evidence remain
  required before the Phase 1.5 closure decision.

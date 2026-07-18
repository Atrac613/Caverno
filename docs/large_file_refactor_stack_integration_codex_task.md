# Large-File Refactor Stack Integration

## Task

- Goal: squash-integrate the completed eight-slice large-file refactor stack
  into `main`, verify the integrated tree, and refresh the next-boundary
  ranking from current evidence.
- User-visible behavior: no product behavior changes beyond the already
  verified behavior-preserving extractions in the stack.
- Non-goals: starting another extraction, changing public APIs or result
  envelopes, deleting source branches or worktrees, pushing, or changing
  application behavior while refreshing the ranking.

## Context

- Affected files or components: the 37-file diff from `main` through
  `feature/workflow-task-run-lifecycle-policy-extraction`, this task document,
  `docs/large_file_refactor_plan.md`, and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Related docs: the eight slice-specific task documents and outcome sections in
  the boundary inventory.
- Reference implementation or pattern: use a clean canonical checkout, verify
  ancestry, apply `git merge --squash --no-commit`, inspect the staged scope,
  and create one Conventional Commit on `main`.
- Known quirks, compatibility rules, or release gates:
  - the audited branch relationship starts at zero `main`-only commits and 30
    stack-only commits before this task document;
  - all eight slices have already passed focused and full gates independently;
  - the integrated tree must pass `tool/codex_verify.sh --coverage --no-codegen`;
  - unrelated worktree branches and their dirty state remain out of scope.

## Implementation Notes

- Preferred approach:
  1. commit this integration contract on the stack tip;
  2. switch the canonical worktree to `main` and squash the completed stack;
  3. inspect the staged file list and diff checks before committing;
  4. run the full coverage gate on integrated `main`;
  5. refresh file sizes, coverage, ownership signals, completed phases, stale
     next-slice text, and the ranked candidate queue;
  6. commit the evidence-only documentation refresh separately.
- Constraints: preserve every verified extraction boundary and exact
  line-count ratchet; do not fold a ninth implementation slice into the
  integration commit.
- Generated files needed: none.
- Migration or data compatibility concerns: none; the stack contains
  behavior-preserving source moves and tests without persisted-schema changes.

## Similar-Pattern Search

- Search terms: `Next slice`, `Next application-boundary slice`, `re-rank`,
  `paused`, `deferred`, `main...HEAD`, and `worktree`.
- Files or modules inspected: the refactor plan, boundary inventory, current
  worktree list, branch ancestry, and the complete `main...HEAD` diff.
- Follow-up tasks found: the workflow recovery state machine still needs a
  route-and-evidence contract; other clear-ownership candidates require a
  refreshed comparison before selection.

## Acceptance Criteria

- Required behavior:
  - `main` contains the completed stack as one squash integration commit;
  - the staged integration scope contains only the audited stack and this task
    contract;
  - analysis, internal-package tests, root tests, and coverage reporting pass
    on integrated `main`;
  - the plan no longer points to already completed ChatPage work as a next
    slice;
  - the boundary inventory reports current line counts, coverage, ownership,
    and the next contract or extraction candidates;
  - the worktree is clean after the documentation outcome commit.
- Edge cases: stale prunable worktree entries and overlapping unrelated
  worktrees remain recorded but are not removed or modified.
- Failure paths: stop before committing if the squash produces conflicts,
  unexpected files, or a non-ancestral branch relationship; diagnose any full
  gate failure before updating outcomes.
- Accessibility, localization, or platform expectations: no UI, copy,
  localization, accessibility, or platform behavior changes.

## Verification

```bash
git diff --check
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: complete. The 31-commit feature stack was applied without conflicts
  and integrated into `main` as the single squash commit `f80132bf`. The staged
  scope contained the audited 37 files plus this integration contract.
- Tests run: `tool/codex_verify.sh --coverage --no-codegen` passed integrated
  main analysis, 13 internal-package tests, and 3,905 root tests.
- Coverage or low-coverage notes: integrated-main line coverage reached 74.98%
  (53,368/71,175). The refreshed candidate ranking uses the same LCOV artifact.
- Risks or follow-ups: define the workflow coordinator's route-and-evidence
  contract before another recovery extraction. Treat
  `chat_remote_datasource.dart` as the first implementation fallback if that
  contract is not ready; do not mix the two boundaries.

# LL37 Worktree-Agent Evidence Capture

## Task

- Goal: Persist bounded changed-file evidence for completed LL13 worktree-agent
  tasks so LL37 can later replay objective fidelity on a second unattended
  surface.
- User-visible behavior: None. Existing worktree-agent task status, verification,
  and review UI remain unchanged.
- Non-goals: Running the LL37 verifier, creating benchmark labels, changing
  worktree-agent approval policy, or treating verification success as objective
  success.

## Context

- Affected files or components: `WorktreeAgentTask`, the worktree-scoped tool
  dispatcher, task execution outcome persistence, and focused tests.
- Related docs: LL13, LL19, and LL37 in
  `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: LL34 producer-owned
  `ToolOutcome.fileMutations` and the existing LL13 verification summary.
- Known quirks, compatibility rules, or release gates: The current local LL13
  store is empty and no LL7 retry-until-green report is persisted. Existing
  worktree-agent task JSON must continue loading with an empty evidence list.

## Implementation Notes

- Preferred approach: Observe successful first-party mutation outcomes in the
  existing worktree-scoped dispatcher, deduplicate affected paths, and capture
  their final state immediately after the subagent settles and before
  verification runs.
- Constraints: Store only paths inside the assigned worktree, use relative
  paths, hash the full bytes, cap persisted content and file count, record
  deletions explicitly, and ignore typed no-op mutations.
- Generated files needed: Regenerate the Freezed and JSON serialization outputs
  for `WorktreeAgentTask`.
- Migration or data compatibility concerns: Additive fields use defaults so
  previously persisted tasks remain readable.

## Similar-Pattern Search

- Search terms: `WorktreeAgentTask`, `verifiedGreen`, `ToolFileMutation`,
  `changedFiles`, `RetryUntilGreenReport`.
- Files or modules inspected: LL13 task repository/entity/executor/registry,
  LL34 tool outcomes, stored SharedPreferences, session logs, and integration
  report artifacts.
- Follow-up tasks found: Generate one consented correct/broken LL13 pair after
  this capture surface lands, then pass it through the existing LL37 probe.

## Acceptance Criteria

- Required behavior: Completed worktree-agent tasks persist final evidence for
  each successful changed file with relative path, full-content hash, byte
  size, deletion state, truncation state, and bounded text content.
- Edge cases: Ignore failed and typed no-op mutations; deduplicate repeated
  writes; reject paths outside the worktree; preserve deletion evidence; cap
  file count and per-file content without weakening the full-file hash.
- Failure paths: Evidence capture failure must not convert an otherwise
  completed task into a failed task; omit unreadable evidence and preserve the
  existing verification result.
- Accessibility, localization, or platform expectations: Not applicable. All
  persisted schema fields and diagnostics are English-only.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/worktree_agent_execution_evidence_recorder_test.dart --test test/features/chat/presentation/providers/worktree_agent_task_executor_test.dart --test test/features/chat/presentation/providers/worktree_agent_task_registry_notifier_test.dart
```

## Handoff Notes

- Summary: Added typed changed-file evidence to persisted LL13 tasks. The
  worktree dispatcher records only successful `changed: true` mutation
  outcomes; the recorder deduplicates paths and captures final relative-path
  state before verification.
- Tests run: `tool/codex_verify.sh` with the recorder, executor, and registry
  test files completed successfully: generated files were unchanged, project
  and workspace-package analysis passed, package tests passed, and 22 focused
  tests passed.
- Coverage or low-coverage notes: Tests cover changed/no-op/failed/outside
  mutations, deletions, per-file and aggregate content caps, full-file hashes,
  dispatcher wiring, task persistence, and legacy defaults.
- Risks or follow-ups: This slice creates replayable evidence but does not add
  an eligible LL37 case by itself. Run a consented LL13 task pair after landing,
  then export it through the existing LL37 evidence schema.

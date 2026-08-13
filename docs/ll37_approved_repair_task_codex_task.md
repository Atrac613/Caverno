# LL37 Approved Repair Task Slice

## Task

- Goal: Let a user turn one reviewed LL37 repair packet into a new queued LL13
  task after an explicit confirmation.
- User-visible behavior: A converged refutation with an eligible completed LL13
  source task shows `Create repair task`. The confirmation previews the frozen
  objective, ordered acceptance criteria, concrete gap IDs, verification
  command, and the fact that the source task remains unchanged. Confirming
  queues one new task; cancelling or merely opening the verdict has no task,
  clipboard, model, worktree, or persistence side effect.
- Non-goals: Automatically running the task, resuming or mutating the completed
  source task, automatic repair/reverify loops, Routine or retry-until-green
  adapters, parallel verifier fan-out, strategist passes, or interactive chat
  verification.

## Context

- Affected components: LL37 continuation domain policy, an LL37-to-LL13 request
  adapter, the idle-maintenance verdict history, and the existing LL13 launcher.
- Related docs: `docs/ll37_reviewed_continuation_codex_task.md` and
  `docs/local_llm_agent_roadmap.md` LL37 idle-panel slice 6.
- Reference pattern: `/agent` queues a `WorktreeAgentTaskLaunchRequest` through
  `WorktreeAgentTaskLauncher`; this slice reuses that path instead of writing
  the task repository directly.
- Release gate: Interactive chat must remain unable to import LL37 verifier or
  continuation-policy code.

## Implementation Notes

- Build a pure immutable repair-task specification before touching providers.
- Require an exact `worktree-agent:<source task id>` candidate match, a completed
  mechanically-green source task, the same normalized objective and ordered
  acceptance criteria, a non-empty coding-project ID, source branch, and
  verification command.
- Use the completed source branch as the new task's base branch. Preserve the
  source verification command and frozen acceptance criteria.
- Derive a stable assignment ID from the candidate, frozen contract, and sorted
  gap IDs. An already-registered assignment suppresses duplicate queueing.
- Send the exact reviewed anti-ratchet packet as the new task prompt. Do not add
  changed-file contents, implementation-evidence bodies, raw prompts, or raw
  verifier responses.
- Queue only. Starting the task remains a separate existing LL13 action.

## Similar-Pattern Search

- Search terms: `WorktreeAgentTaskLaunchRequest`, `registerAssignment`,
  `showDialog<bool>`, `objectiveAcceptanceCriteria`, and `assignmentId`.
- Inspected modules: slash-command LL13 launcher, assignment planner, task
  registry/repository, LL37 candidate adapter, continuation policy, verdict
  history, and idle-maintenance widget tests.
- Follow-up found: Routine and retry-until-green production candidate adapters
  remain separate work because they do not have an LL13 source task or launcher
  contract.

## Acceptance Criteria

- Cancelling the confirmation queues nothing and leaves the source task equal
  to its pre-action value.
- Confirming once queues exactly one new LL13 task with a distinct stable ID,
  the source branch as base, exact reviewed packet, frozen ordered criteria, and
  source verification command.
- Repeated confirmation for the same packet does not queue a duplicate.
- A missing, non-terminal, non-green, candidate-mismatched, contract-drifted,
  projectless, branchless, or verification-less source fails closed and exposes
  no create action.
- The adapter performs no repository, worktree, model, or clipboard operation.
- The existing copy-only action and interactive-chat structural boundary remain
  covered.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_approved_repair_task_adapter_test.dart \
  test/features/maintenance/presentation/pages/idle_maintenance_debug_page_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  test/widget_test.dart
fvm flutter analyze
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Implemented frozen-contract validation, stable assignment IDs,
  duplicate suppression, a read-only source projection, explicit confirmation,
  and queue-only submission through the existing LL13 launcher.
- Focused tests: 31 passed across adapter/launcher mapping, approval UI,
  maintenance-stage isolation, translation parity, and the real LL13
  launcher/registry/repository path. `fvm flutter analyze` reported no issues.
- Full gate: `tool/codex_verify.sh` passed 7,352 Flutter tests and 10
  notification-relay tests, with analyzers and generated-file checks clean.
- Risks: The queued task can still fail during later worktree materialization or
  execution. This slice records queueing success only and does not claim repair
  completion.

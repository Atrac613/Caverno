# CLI3 GUI-To-Terminal Resume Smoke

## Task

- Goal: Prove that Coding and Plan Mode conversations written through the GUI
  provider composition can be resumed and extended through the terminal
  frontend without losing persisted context.
- User-visible behavior: A complete conversation ID created by the GUI remains
  resumable through `caverno conversations resume`, including its saved project,
  worktree, messages, workflow state, and contract provenance.
- Non-goals: Automating visible desktop controls, mutating an existing user
  conversation, live-model quality evaluation, global memory reconciliation,
  routine ownership, or standalone CLI packaging.

## Context

- Affected components:
  - `test/features/terminal/presentation/providers/`
  - `lib/features/chat/application/persistence/`
  - `lib/features/chat/presentation/providers/`
  - `lib/features/terminal/presentation/providers/`
- Related docs: `docs/caverno_cli_terminal_contract.md`, `docs/roadmap.md`, and
  `docs/cli3_conversation_resume_codex_task.md`.
- Reference pattern: GUI startup and terminal startup already use the same
  `CavernoPersistenceBootstrap`, drift conversation repository, coding-project
  repository, and runtime lease boundary. Existing resume tests seed an
  in-memory repository directly rather than writing through GUI notifiers.

## Implementation Notes

- Use a temporary file-backed production drift database and temporary project
  and worktree directories.
- Create the coding project through `CodingProjectsNotifier` and create each
  conversation through `ConversationsNotifier`, matching the GUI composition.
- Persist initial user and assistant messages, Plan Mode workflow tasks, source
  references, and item provenance before disposing the GUI container.
- Reopen the same drift database in a terminal container, prepare an exact-ID
  resume invocation, acquire the normal runtime lease, append a deterministic
  terminal user/assistant turn, and complete the runtime event sequence.
- Reopen storage again and assert that mode, project, worktree, messages,
  workflow, and provenance survived the frontend boundary.
- Cover Coding and Plan Mode independently. Keep the test deterministic and do
  not contact an LLM or mutate the user's application data.

## Similar-Pattern Search

- Search terms: `CavernoPersistenceBootstrap`, `CodingProjectsNotifier`,
  `ConversationsNotifier`, `conversationResume`, `startTurn`,
  `workflowSourceHash`, and `provenance`.
- Files inspected: GUI bootstrap in `main.dart`, terminal persistence and
  adapter composition, runtime lease lifecycle, notifier persistence methods,
  and existing terminal adapter tests.
- Follow-up found: A terminal-created Coding conversation uses a transient
  project record. Its stable-ID resume behavior should be measured separately
  from this GUI-to-terminal contract.

## Acceptance Criteria

- The seed path writes through GUI-facing notifiers and a production drift
  repository instead of injecting a prebuilt conversation into the terminal.
- Coding resume restores the exact project and worktree and retains existing
  messages before appending the terminal turn.
- Plan resume restores Plan Mode, workflow tasks, workflow source metadata, and
  contract provenance before appending the terminal turn.
- Both cases emit `run_started` and `run_completed` through the shared runtime,
  persist exactly one new user/assistant pair, and preserve the stable ID.
- The test uses only temporary data and never calls an LLM.

## Verification

```bash
(cd packages/caverno_execution_runtime && \
  fvm dart test test/caverno_execution_runtime_test.dart)
tool/codex_verify.sh \
  --test test/features/terminal/presentation/providers/caverno_gui_terminal_resume_test.dart \
  --test test/features/terminal/presentation/providers/caverno_terminal_runtime_adapter_test.dart
```

Then run `tool/codex_verify.sh` and update `docs/roadmap.md` with the verified
cross-frontend boundary and the next CLI3 risk.

## Handoff Notes

- Summary: Added a deterministic cross-frontend test that writes Coding and
  Plan Mode conversations through GUI-facing project and conversation
  notifiers, closes the production drift database, resumes each exact ID through
  the terminal adapter and runtime lease, and verifies the persisted result
  after another database reopen.
- Tests run: The focused CLI3 gate passed with no generated-file drift, no
  analyzer findings, and 22 passing tests. `tool/codex_verify.sh` passed with no
  generated-file drift, no analyzer findings, and 3,365 passing tests.
- Coverage or low-coverage notes: Both modes verify stable ID, saved project,
  worktree, initial and appended messages, execution mode, workflow stage and
  tasks, source hash and derived timestamp, source references, item provenance,
  runtime mode/workspace, and `run_started`/`run_completed`. The fixture uses a
  deterministic terminal responder and does not test live-model quality.
- Risks or follow-ups: Terminal-created Coding and Plan conversations currently
  bind to `useTransientProject`, which does not persist the generated project
  record. Add a restart/resume regression test and persist enough canonical
  project identity for stable-ID resume before starting global-memory or routine
  ownership work.

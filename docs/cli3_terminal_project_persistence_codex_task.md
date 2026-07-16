# CLI3 Terminal Project Persistence

## Task

- Goal: Keep terminal-created Coding and Plan Mode conversations resumable by
  stable ID after the creating terminal process exits.
- User-visible behavior: A project selected with `--project` is persisted before
  its first conversation is activated, so `caverno conversations resume` can
  restore the project and execution mode in a later process.
- Non-goals: Recovering conversations created before this fix with an unknown
  transient project ID, adding security-scoped bookmarks from the terminal,
  global memory or routine ownership, or standalone CLI packaging.

## Context

- Affected components:
  - `lib/features/chat/presentation/providers/coding_projects_notifier.dart`
  - `lib/features/terminal/application/`
  - `lib/features/terminal/presentation/`
  - `test/features/terminal/`
- Related docs: `docs/caverno_cli_terminal_contract.md`, `docs/roadmap.md`,
  `docs/cli3_conversation_resume_codex_task.md`, and
  `docs/cli3_gui_terminal_resume_smoke_codex_task.md`.
- Failure boundary: Conversation persistence stores a project ID, but
  `useTransientProject` creates that project only in the current provider
  container. A later process therefore rejects the otherwise valid conversation
  as `conversation_project_unavailable`.

## Persistence Contract

- With the application-default data root, use the existing shared-preferences
  project registry so terminal-created projects remain visible to the GUI.
- With an explicit `--data-dir` or `CAVERNO_HOME`, store the project registry in
  `coding_projects.json` inside that data root. Isolated runs must not add
  projects to the application-default shared preferences.
- Reuse an existing project ID when its normalized root path matches the
  requested project path.
- Persist a newly generated project before activating or creating a conversation
  that references its ID. Surface persistence failure instead of creating an
  unresumable conversation.
- Write the data-root-local registry through a temporary file and rename so an
  interrupted write does not expose a partial JSON document.
- Treat a missing or malformed data-root-local registry as empty, matching the
  existing shared-preferences repository behavior.

## Implementation Notes

- Replace the terminal-only transient notifier method with an asynchronous
  persistent method; leave GUI project creation and bookmark behavior unchanged.
- Select the project repository during CLI bootstrap from the resolved data-root
  scope and inject it through `codingProjectRepositoryProvider`.
- Keep the registry format equal to the existing `CodingProject` JSON list so
  ordering and entity validation remain consistent across storage backends.
- Add deterministic restart coverage for terminal-created Coding and Plan Mode
  conversations. Use temporary production persistence and do not contact an LLM
  or mutate user application data.

## Compatibility Risk

- Conversations created by older terminal builds may reference a transient
  project ID that was never persisted. The conversation record contains the ID
  and optional worktree path, but not enough canonical source-root information
  to reconstruct the missing project safely. Those records continue to fail
  with the existing actionable project-unavailable diagnostic.

## Similar-Pattern Search

- Search terms: `useTransientProject`, `codingProjectRepositoryProvider`,
  `resolvedDataDirectory`, `conversation_project_unavailable`, and
  `deferInitialConversationCreationProvider`.
- Files inspected: CLI process bootstrap, terminal runtime preparation, coding
  project notifier and repository, conversation resume tests, and the GUI-to-
  terminal persistence smoke.

## Acceptance Criteria

- A terminal-created Coding conversation resumes by exact stable ID in a new
  provider container and reopened production database.
- A terminal-created Plan Mode conversation resumes with planning mode restored
  under the same restart boundary.
- Both modes resolve the same persisted project ID and retain existing messages.
- Application-default project persistence remains GUI-compatible.
- An explicit data root writes only its local project registry and does not
  mutate the application-default shared-preferences registry.
- Focused tests and `tool/codex_verify.sh` pass without generated-file drift or
  analyzer findings.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/coding_projects_notifier_test.dart \
  --test test/features/terminal/application/caverno_cli_coding_project_repository_test.dart \
  --test test/features/terminal/presentation/providers/caverno_terminal_created_resume_test.dart \
  --test test/features/terminal/presentation/providers/caverno_terminal_runtime_adapter_test.dart
```

Then run `tool/codex_verify.sh` and update `docs/roadmap.md` with the verified
restart boundary and the next CLI3 risk.

## Handoff Notes

- Summary: Terminal project preparation now persists a generated project before
  activating its first conversation. Application-default runs share the GUI
  registry, while explicit data roots use an atomically replaced local JSON
  registry.
- Tests run: The focused CLI3 gate passed with no generated-file drift, no
  analyzer findings, and 21 passing tests. `tool/codex_verify.sh` passed with no
  generated-file drift, no analyzer findings, and 3,372 passing tests.
- Coverage notes: Unit coverage proves default-root compatibility, explicit-root
  isolation, registry replacement, malformed-registry fallback, same-root ID
  reuse, and persistence-failure rollback. Restart coverage creates, closes,
  resumes, appends to, and reopens both Coding and Plan Mode conversations using
  production drift persistence.
- Compatibility note: Pre-fix conversations whose project existed only in a
  discarded provider container remain unrecoverable from their persisted
  project ID alone and retain the existing project-unavailable diagnostic.
- Next risk: Define cross-frontend ownership and storage scope for global memory
  and routines without making an isolated terminal data root read or mutate the
  application-default registries.

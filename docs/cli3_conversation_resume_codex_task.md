# CLI3 Stable-ID Conversation Resume

## Task

- Goal: Resume an existing persisted conversation from the terminal by its
  complete stable identifier without bypassing the shared runtime ownership and
  authoritative refresh boundary.
- User-visible behavior: `caverno conversations resume <conversation-id>
  [input options] [prompt]` continues the selected conversation using its saved
  chat, coding, or planning context.
- Non-goals: Prefix or fuzzy ID matching, conversation mutation without a new
  prompt, project reassignment, conversation deletion, global chat-memory merge
  policy, routine ownership, and standalone Windows or Linux packaging.

## Context

- Affected components:
  - `lib/features/terminal/application/caverno_cli_arguments.dart`
  - `lib/features/terminal/application/caverno_cli_contract.dart`
  - `lib/features/terminal/presentation/caverno_cli_process.dart`
  - `lib/features/terminal/presentation/providers/caverno_terminal_runtime_adapter.dart`
  - Terminal parser, adapter, lifecycle, and packaged process tests.
- Related docs: `docs/caverno_cli_terminal_contract.md`, `docs/roadmap.md`,
  `docs/cli3_runtime_lease_integration_codex_task.md`.
- Reference pattern: Read-only `conversations show` already resolves a complete
  identifier from the production drift repository. Runtime turn preparation
  already acquires a conversation and effective workspace lease, then refreshes
  the selected conversation before publishing `run_started`.
- Compatibility rules:
  - Existing `chat`, `coding`, `plan`, `conversations list`, and
    `conversations show` syntax remains unchanged.
  - Resume accepts the normal prompt, endpoint, model, API key, data directory,
    and output options. It does not accept `--project` or `--limit`.
  - A saved planning conversation resumes in Plan Mode. A saved non-planning
    coding conversation resumes in Coding Mode. A saved chat conversation
    resumes in general chat mode.

## Implementation Notes

- Add `resume` as a conversation command and a runnable invocation action.
- Require one complete non-empty conversation identifier. Treat all remaining
  positional text as the prompt and apply the existing exclusive prompt-source
  rules.
- Select the persisted conversation before initializing `ChatNotifier` so its
  message state hydrates from the selected conversation.
- For coding conversations, require the saved project to exist in the coding
  project repository and require the effective project or worktree directory to
  exist. Do not silently fall back from a missing worktree to the source project.
- Select the saved coding project and restore its security-scoped access before
  starting the turn.
- Keep the runtime lease flow unchanged: acquire conversation and effective
  workspace ownership, refresh from drift, then publish `run_started` and append
  the new user message.
- No generated entities or data migrations are needed.

## Similar-Pattern Search

- Search terms: `conversationId`, `conversationShow`, `selectConversation`,
  `selectedProject`, `normalizedWorktreePath`, `run_started`, and
  `execution_lease_conflict`.
- Files inspected: CLI argument parsing and process routing, terminal runtime
  adapter, conversation and coding-project notifiers, ChatNotifier turn startup,
  runtime settings and repository ports, and execution lease normalization.
- Follow-up tasks found: Cross-frontend global chat-memory reconciliation and
  routine ownership remain separate CLI3 follow-ups.

## Acceptance Criteria

- `conversations resume` requires one exact identifier and one prompt source.
- Resume preserves existing messages, workflow state, goal, execution progress,
  plan artifact, provenance fields, saved workspace mode, saved project, and
  saved worktree.
- The selected conversation and project are active before the chat notifier
  initializes.
- No user message is appended and no `run_started` is published before all
  required ownership is acquired and the authoritative refresh succeeds.
- Missing conversations, projects, project directories, and worktrees fail with
  stable actionable codes and exit code `65`.
- Ownership contention remains retryable with `execution_lease_conflict`, exit
  code `75`, and no `run_started` event from the rejected process.
- Read-only list and show commands remain runtime-free.

## Verification

```bash
(cd packages/caverno_execution_runtime && \
  fvm dart test test/caverno_execution_runtime_test.dart)
tool/codex_verify.sh \
  --test test/features/terminal/application/caverno_cli_arguments_test.dart \
  --test test/features/terminal/presentation/providers/caverno_terminal_runtime_adapter_test.dart
```

Then run `tool/codex_verify.sh`, build the Debug macOS application, and execute
an isolated packaged smoke that seeds a persisted conversation, resumes it by
ID, and inspects the resulting conversation detail.

## Handoff Notes

- Summary: Added exact stable-ID resume syntax, restored saved Chat, Coding, or
  Plan Mode state before ChatNotifier initialization, reused the leased refresh
  boundary, and deferred unrelated empty-chat creation for headless resume.
- Tests run: The focused parser, notifier, terminal adapter, and execution
  runtime tests passed. `tool/codex_verify.sh` completed with no generated-file
  drift, no analyzer findings, and 3,363 passing tests. A Debug macOS build and
  packaged success, missing-ID, and live-contention smokes also passed.
- Coverage or low-coverage notes: Unit coverage includes exact-ID parsing,
  prompt-source conflicts, chat history hydration, planning project/worktree
  restoration, missing conversation/project/worktree failures, and deferred
  empty-chat startup. The packaged smoke proves chat resume and cross-process
  contention; a GUI-created Coding and Plan Mode fixture remains outstanding.
- Risks or follow-ups: Run GUI-to-terminal Coding and Plan Mode resume smokes
  with the shared production data root, then define cross-frontend global-memory
  reconciliation and routine ownership as separate CLI3 tasks.

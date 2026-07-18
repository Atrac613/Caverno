# ChatPage Slash Command Handler Extraction

Status: complete on `feature/chat-page-slash-command-handler`.

## Task

- Goal: complete ChatPage Tranche 4 by moving all slash-command-specific
  catalog, help presentation, dispatch, goal lifecycle, feedback submission,
  worktree-agent parsing, and prompt-template resolution out of the ChatPage
  library into independently tested boundaries.
- User-visible behavior: none. Every built-in and custom slash command keeps
  its current availability, side effects, input-clearing behavior, localized
  feedback, prompt expansion, and failure handling.
- Non-goals: the shared goal editor, goal status controls, the normal composer
  worktree launcher, MessageInput parsing and suggestion UI, slash-command
  persistence settings, or ChatPage scaffold/layout decomposition.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/pages/chat_page_goal_builders.dart`
  - `lib/features/chat/presentation/pages/chat_page_support.dart`
  - `lib/features/chat/presentation/slash_commands/`
  - standalone slash-command coordinators and help widget
  - direct unit, widget, product-path, and exact line-count tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 2, Tranche 4
  - `docs/chat_page_task_actions_codex_task.md`
  - `docs/roadmap.md` F5
- Reference implementation or pattern: follow the Tranche 3 coordinators by
  passing narrow callbacks for page-owned UI and provider composition. Keep
  Flutter, `BuildContext`, localization extensions, Riverpod reads, and modal
  launch out of coordinators.
- Known quirks, compatibility rules, or release gates:
  - commands other than help and cancel retain input while generation is active.
  - `/new` uses a coding draft for an active coding project and a normal new
    conversation elsewhere.
  - general or coding selection exits an active planning session and dismisses
    the plan proposal; plan selection only enters planning in a coding thread.
  - `/goal` may create the first coding conversation, open the shared editor,
    report status and budgets, manage pause/resume/clear/auto state, or save a
    normal objective. Only exact reserved arguments are subcommands.
  - the first `/goal <objective>` in an empty coding workspace sends the saved
    objective as the initial chat prompt without awaiting generation.
  - `/feedback` requires enabled upload, configured credentials, a conversation,
    enabled session logging, and an existing log before submission.
  - `/agent` recognizes boundary-delimited `--run` and `--verify`, validates a
    missing prompt or verification command, truncates the title to 80 characters,
    and starts queued work without awaiting execution when requested.
  - built-in prompt templates precede custom templates during ID resolution;
    custom commands retain their own names, aliases, descriptions, and templates.

## Implementation Notes

- Preferred approach:
  1. Add a pure slash-command catalog that builds built-in plus custom command
     definitions from a text resolver and resolves prompt templates.
  2. Move the help modal body into `SlashCommandHelpSheet` with a direct widget
     test; keep `showModalBottomSheet` in ChatPage.
  3. Add `GoalSlashCommandCoordinator` for exact goal subcommand parsing,
     persistence, status summaries, trailing auto state, and initial-prompt
     callbacks. Keep the reusable goal editor UI in its existing page part.
  4. Add `FeedbackSlashCommandCoordinator` for preconditions, log lookup,
     submission, and typed user feedback without Riverpod reads.
  5. Add `SlashCommandActionCoordinator` for loading policy and every top-level
     action, including mode selection, conversation actions, delegation, agent
     parsing/queueing, and prompt expansion.
  6. Replace ChatPage methods with thin composition delegates, remove obsolete
     slash support from part files, and lower all exact ratchets.
- Constraints:
  - Do not pass `BuildContext`, `WidgetRef`, `_ChatPageState`, localized strings,
    or provider containers into coordinators.
  - Preserve the existing asynchronous ordering and unawaited initial-goal and
    worktree-run behavior.
  - Do not change command names, aliases, argument requirements, descriptions,
    translation keys, feedback copy, prompt templates, or worktree naming.
  - Do not add another ChatPage `part` file; every extracted boundary must be
    independently imported so the aggregate library shrinks.
- Generated files needed: none.
- Migration or data compatibility concerns: none. Conversation, goal, custom
  command, worktree task, feedback, and settings schemas remain unchanged.

## Similar-Pattern Search

- Search terms: `_buildSlashCommands`, `_handleSlashCommand`,
  `_findPromptTemplateForInvocation`, `_showSlashCommandHelp`,
  `_handleGoalSlashCommand`, `_submitFeedbackCommand`,
  `_parseWorktreeAgentCommandArgs`, `_worktreeAgentTaskTitle`,
  `SlashCommandAction`, `onSlashCommand`, and `builtInSlashCommandPromptTemplates`.
- Files or modules inspected: ChatPage primary, support, and goal part files;
  MessageInput; slash command model/parser/templates; custom command provider;
  feedback service and log store; worktree launcher/run controller; page and
  parser tests; roadmap; and line-count ratchets.
- Follow-up tasks found: the shared goal editor remains a later goal-UI slice.
  ChatPage Tranche 5 remains `build()` scaffold and right-sidebar layout helper
  decomposition. MessageInput slash parsing is already independently tested and
  does not belong to Tranche 4.

## Acceptance Criteria

- Required behavior:
  - the catalog emits every current built-in definition in order, appends prompt
    templates and custom definitions, and preserves aliases and loading flags.
  - help renders the same title, command usage, descriptions, order, icons,
    padding, dividers, safe area, and drag-handle host behavior.
  - every `SlashCommandAction` has a directly tested coordinator outcome.
  - mode, conversation, clear, planning, cancellation, feedback, worktree,
    goal, and prompt-template side effects retain their current ordering.
  - all goal status, usage, auto state, exact subcommands, objective parsing,
    budgets, and first-session prompt behavior remain unchanged.
  - all feedback preconditions and exception classes preserve current results.
  - ChatPage retains provider composition, modal launch, language selection,
    dashboard state, shared goal editor, and normal composer worktree launch.
- Edge cases:
  - commands blocked during loading retain raw input and perform no side effect.
  - `/goal auto`, invalid two-token auto values, no-goal management commands,
    case-insensitive exact keywords, and keyword-prefixed objectives behave as
    before.
  - missing agent prompts, empty `--verify`, enqueue exceptions, long/multiline
    titles, and boundary-delimited markers behave as before.
  - missing prompt-template IDs retain input with the generic failure feedback.
  - missing logs and typed or unexpected feedback failures retain input.
- Failure paths: coordinator dependencies continue to throw unless the current
  handler already converts that path into user feedback. No new catches,
  retries, or fallback mutations are introduced.
- Accessibility, localization, or platform expectations: retain Material help
  semantics and all translation keys. Direct tests perform no real LLM,
  filesystem mutation, network upload, git, worktree, or platform action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/slash_commands/slash_command_catalog_test.dart \
  --test test/features/chat/presentation/coordinators/slash_command_action_coordinator_test.dart \
  --test test/features/chat/presentation/coordinators/goal_slash_command_coordinator_test.dart \
  --test test/features/chat/presentation/coordinators/feedback_slash_command_coordinator_test.dart \
  --test test/features/chat/presentation/widgets/slash_command_help_sheet_test.dart \
  --test test/features/chat/presentation/pages/chat_page_slash_commands_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: the catalog, help body, top-level action dispatch, goal lifecycle,
  feedback submission, worktree argument parsing and title generation, and
  prompt-template resolution now live in five independent boundaries. ChatPage
  retains provider composition, modal launch, localization, the shared goal
  editor, and the normal composer worktree launcher.
- Tests run: the focused repository gate passed 128 root tests plus all 13
  `caverno_execution_runtime` package tests. The broader coverage gate passed
  all 3,745 root tests plus the same 13 package tests with no analyzer findings.
- Coverage or low-coverage notes: repository line coverage is 74.11%
  (52,539/70,896). The catalog and feedback coordinator reached 100.00%, the
  action coordinator 99.31%, the goal coordinator 99.09%, and the help widget
  93.33%; the widget's only uncovered executable line is its const constructor.
- Risks or follow-ups: behavior remains pinned by both direct coordinator/widget
  tests and the existing ChatPage product-path suite. Tranche 5 should address
  only `build()` scaffold and right-sidebar layout ownership.

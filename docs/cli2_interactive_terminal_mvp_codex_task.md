# CLI2 Interactive Terminal MVP

## Task

- Goal: Ship a supported, one-shot `caverno` terminal frontend for chat,
  coding, and Plan Mode on top of the CLI1 execution runtime.
- User-visible behavior: A user can invoke `caverno chat`, `caverno coding`, or
  `caverno plan`, stream the result in a terminal, answer typed questions and
  approvals when a TTY is available, or consume versioned JSON Lines from
  automation.
- Non-goals: Conversation listing and resume, concurrent GUI/CLI ownership,
  daemon IPC, shell completion, signed standalone packaging, or Computer Use.
  Those remain CLI3 or CLI4 work.

## Context

- Affected files or components: Application bootstrap, CLI argument and input
  parsing, terminal presentation, CLI1 runtime events, `ChatNotifier` runtime
  adaptation, transient settings/project selection, and process lifecycle.
- Related docs: `docs/caverno_cli_terminal_contract.md`,
  `docs/cli1_shared_execution_runtime_codex_task.md`, and `docs/roadmap.md`.
- Reference implementation or pattern: `ChatNotifier` remains the production
  turn driver. The CLI0 headless Plan Mode lane demonstrates no-window provider
  composition, while CLI1 provides the typed event stream and terminal surface.
- Known quirks, compatibility rules, or release gates: `sendMessage` can return
  before a streamed turn is terminal. The CLI must wait for the runtime terminal
  event. macOS application launches can include a `-psn_` argument, which must
  not be interpreted as a CLI command.

## Implementation Notes

- Preferred approach: Route recognized command-line invocations through a
  no-window Flutter host. Build the same Riverpod production composition used by
  the GUI, select the terminal runtime surface, and adapt CLI1 runtime events to
  human or JSON output. Do not add a second LLM client, tool dispatcher, tool
  loop, Plan Mode state machine, or Goal Auto-Continue implementation.
- Constraints:
  - Keep argument parsing, input selection, redaction, event serialization, and
    terminal rendering independent of widgets so focused tests need no window.
  - Human assistant output goes to stdout. Diagnostics and interactions go to
    stderr. JSON mode writes only versioned events to stdout.
  - Force manual approval boundaries for terminal runs. When stdin is not a
    TTY, a pending mutation approval fails closed with exit code 77.
  - Disable every Computer Use tool before the model sees terminal tool
    definitions. A terminal approval must never arm or execute Computer Use.
  - CLI flags and environment variables are transient process overrides and
    must not overwrite persisted application settings.
  - A project root is required for coding and Plan Mode, must resolve to an
    existing directory, and remains the containment root for local tools.
- Generated files needed: None unless a persisted entity changes.
- Migration or data compatibility concerns: CLI2 may reuse current settings,
  conversations, and session logs, but cross-process resume and execution
  leases remain disabled until CLI3.

## Similar-Pattern Search

- Search terms: `ProviderContainer`, `sendMessage`, `cancelStreaming`,
  `pendingLocalCommand`, `pendingGitCommand`, `pendingFileOperation`,
  `pendingBrowserAction`, `pendingAskUserQuestion`,
  `CavernoRuntimeTerminalEvent`, and `ProcessSignal.sigint`.
- Files or modules inspected: `lib/main.dart`, `ChatNotifier`, CLI1 runtime
  files and provider composition, coding project/conversation notifiers, and
  the Plan Mode no-window harness.
- Follow-up tasks found: CLI3 must add durable resume and execution ownership.
  CLI4 must package the host as standalone signed/checksummed terminal
  artifacts and add `doctor`, version, and shell-completion UX.

## Acceptance Criteria

- Required behavior:
  - `caverno chat <prompt>` executes one chat turn through the shared runtime.
  - `caverno coding --project <path> <prompt>` executes against the explicit
    project through the production coding tool loop.
  - `caverno plan --project <path> <prompt>` enters the production Plan Mode
    path and exposes its workflow events and decisions to the terminal.
  - `--prompt`, `--prompt-file`, piped stdin, and an interactive prompt obey the
    single-input-source contract.
  - `--json` emits only `caverno_cli_event` schema version 1 JSON Lines with
    strictly increasing runtime sequence numbers.
  - Successful, blocked, usage, input, transport, persistence, approval, and
    cancellation outcomes use the documented stable exit codes.
  - SIGINT stops new model/tool work, terminates the runtime turn, flushes
    owned resources, and exits 130.
- Edge cases:
  - Conflicting or empty inputs fail before an LLM request.
  - Unknown commands/flags and missing project roots exit 64 or 65 as
    documented.
  - Non-TTY approvals and questions never default to consent.
  - Duplicate terminal events do not trigger duplicate prompts or decisions.
- Failure paths:
  - Transport/service failures exit 69 and emit a machine-readable
    `run_failed` event in JSON mode.
  - Approval denial or unavailability exits 77 after resolving the production
    pending action as denied.
  - Verification or workflow blocked states exit 2.
- Security and platform expectations:
  - Output redacts API keys, bearer credentials, sensitive flag/env values,
    approval payload secrets, and protected verifier content.
  - Computer Use is neither advertised nor executable from the terminal
    surface.
  - A CLI invocation does not open or foreground an application window.

## Verification

Use focused parser, presenter, runtime-adapter, and process-lifecycle tests
while implementing, then run the repository verification entrypoint:

```bash
tool/codex_verify.sh
```

Before marking CLI2 done, run a terminal process smoke for all three commands,
non-interactive approval denial, JSON schema/sequence validation, and SIGINT.
Then repeat the existing CLI0 headless Live LLM canary and one macOS app-path
comparison to confirm the terminal host did not change either baseline.

## Handoff Notes

- Summary: The production macOS host now routes recognized CLI invocations to
  a no-window terminal frontend for chat, coding, and Plan Mode. It reuses the
  shared runtime, applies transient configuration and project selection,
  renders human or JSON events, handles approvals and questions, redacts
  secrets, disables Computer Use, and maps terminal failures to stable exit
  codes.
- Tests run: Flutter analysis; 59 focused terminal/runtime/settings tests; 358
  combined `ChatNotifier`, terminal, runtime, roadmap, and file-size-ratchet
  tests; macOS debug and release builds; and serial `--help`, `--version`, and
  unknown-command process smoke checks. The repository-wide run reached 3,304
  tests with only three stale roadmap/ratchet failures, all of which were
  corrected and rerun. Follow-up hardening passed 325 affected `ChatNotifier`
  and domain tests.
- Live terminal evidence: Release-binary chat, coding, and Plan Mode commands
  completed through the shared runtime. Human output hid reasoning and tool
  markup; JSON mode preserved schema version 1, increasing sequence numbers,
  and redaction. Non-interactive approval denial exited 77 without mutation,
  and SIGINT exited 130 with a terminal cancelled event.
- CLI0 parity evidence: The post-fix comparison under
  `plan_mode_todo_app_cli0_comparison_1784160867` passed two headless runs with
  no drift or warnings before the third generated app omitted `help`. The
  bounded rerun under `plan_mode_todo_app_cli0_comparison_1784162209` passed its
  first headless run with five successful validations and no warnings, then a
  generated app exposed an unknown-id stack trace. The macOS app-path run under
  `cli2_live_verification_macos/plan_mode_todo_app_live_canary_1784163187`
  reached the production runtime and completed four of five saved tasks; its
  final model-authored validation attempted to execute a generated binary, so
  the harness correctly denied automatic approval and blocked the workflow.
- Coverage or low-coverage notes: Coverage was not collected for this slice.
- Risks or follow-ups: CLI2 remains `current` until a clean three-headless-plus-
  one-macOS CLI0 parity pass is recorded. The remaining failures are stochastic
  model artifact or plan-quality failures rather than terminal runtime
  regressions; the independent validator and harness safety boundary must stay
  strict. Packaging, durable resume, and cross-process ownership remain
  CLI3/CLI4 work.

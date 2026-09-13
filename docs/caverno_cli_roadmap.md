# Caverno CLI Roadmap

Scope, acceptance criteria, and dated evidence for this track.
[Cross-track priorities](roadmap.md#active-focus) remain in the main
roadmap; dated investigation notes below preserve the implementation history.

## Caverno CLI Track

The long-term goal is a supported `caverno` terminal client for chat, coding,
and Plan Mode. The product CLI must reuse Caverno's execution behavior rather
than wrapping a test command or maintaining a second tool loop.

The current repository provides two useful but incomplete starting points:

- Coding Live canaries run `ChatNotifier` inside a `ProviderContainer` through
  `flutter test` without launching a desktop application window. They already
  exercise live OpenAI-compatible requests, built-in coding tools, session
  logs, Goal Auto-Continue, and independent artifact verifiers.
- Production-path Plan Mode canaries run
  `integration_test/plan_mode_scenario_test.dart -d macos`. They exercise the
  app composition and Plan Mode workflow path but launch the macOS app and keep
  test-only approval bypasses in the integration harness.
- `lib/main.dart` currently owns Flutter binding, localization, Hive,
  SharedPreferences, drift migration, window restoration, and provider
  overrides in one GUI composition root. A supported Dart executable cannot
  depend on that bootstrap unchanged.
- Pending approvals are represented as state and completed by UI listeners.
  A terminal frontend therefore needs an explicit approval presenter rather
  than implicit approval when no dialog is available.

Target architecture:

```text
Flutter GUI ---------+
                     +--> Caverno execution runtime --> LLM and tool policies
Terminal CLI --------+             |
                                   +--> repositories, session logs, checkpoints
```

Architecture constraints:

- Keep one prompt builder, tool dispatcher, tool-loop policy, Plan Mode state
  machine, Goal Auto-Continue implementation, and evidence guardrail stack.
- Keep frontend rendering outside the execution runtime. Flutter sheets and
  terminal prompts adapt the same typed pending approval and question events.
- Start with an in-process runtime. Preserve interfaces that permit a local
  daemon later, but do not introduce IPC until concurrent GUI/CLI evidence
  justifies it.
- Reuse the existing Caverno data directory and redacted session-log schema.
  Define locking and ownership before the GUI and CLI can mutate the same
  conversation or coding project concurrently.
- Non-interactive execution fails closed when a tool requires approval. A
  machine-readable denial must include the pending capability and a stable exit
  code; absence of a GUI must never become approval.
- Computer Use remains unavailable from a headless CLI until a dedicated host,
  fresh arming flow, and observable approval boundary exist. Result replay or a
  remembered coding-command rule must not authorize a physical desktop action.
- Preserve project-root containment, verifier protection, high-risk approval
  review, checkpoint/rollback behavior, and sensitive-log redaction across
  both frontends.
- Treat SIGINT as cancellation: stop new LLM/tool work, terminate owned child
  processes through the existing process lifecycle, flush logs, and preserve a
  resumable conversation state.
- Support human-readable streaming by default and a versioned `--json` event
  stream for automation. Do not parse formatted terminal prose to recover
  tool, approval, token, or completion state.

Verification policy:

- Frequent weak-model and repeated Live LLM canaries use the headless lane and
  must not launch a desktop application window.
- The macOS application lane remains a separate release and UI-change gate for
  app bootstrap, localization, proposal presentation, and approval rendering.
- Both lanes reuse the same scenario contract, short prompt, saved workflow
  assertions, post-validator, session-log schema, and report vocabulary.
- A headless pass does not replace the app-path smoke, and an app-path pass does
  not replace terminal TTY, exit-code, signal, and non-interactive tests.

### CLI0: Headless Production-Path Baseline And Contract

Status: `done`

Scope:
- Extract a reusable no-window execution driver from the current Coding Live
  canary container and Plan Mode live harness.
- Run the exact short TODO prompt through chat, coding, and Plan Mode runtime
  entrypoints without `-d macos`, while retaining the independent TODO
  verifier and report bundle.
- Record a terminal contract for command names, stdin/prompt input, streaming
  output, JSON events, exit codes, cancellation, configuration precedence, and
  approval behavior.
- Keep the current macOS production-path canary unchanged as the comparison
  lane.

Acceptance criteria:
- A headless Plan Mode TODO canary completes from a shell without opening or
  foregrounding Caverno.app.
- The headless and macOS lanes consume the same fixture, exact prompt,
  scenario-level expectations, and post-validator.
- Three consecutive headless runs record pass/fail, duration, tool-loop count,
  recovery count, approval decisions, and session-log paths.
- One macOS comparison run demonstrates which coverage remains UI-specific.
- The CLI contract explicitly denies approval-required actions in non-TTY mode
  and reserves Computer Use for a later armed host design.

Current evidence:
- `docs/caverno_cli_terminal_contract.md`
- `docs/cli0_headless_app_parity_codex_task.md`
- `tool/run_plan_mode_todo_app_headless_live_canary.sh`
- `tool/canaries/plan_mode_headless_scenario_canary_test.dart`
- `tool/plan_mode_headless_canary_summary.dart`
- `tool/run_plan_mode_todo_app_cli0_comparison.sh`
- `tool/plan_mode_cli0_comparison_summary.dart`
- `tool/run_coding_todo_app_minimal_prompt_live_canary.sh`
- `tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart`
- `tool/run_plan_mode_todo_app_live_canary.sh`
- `integration_test/plan_mode_scenario_test.dart`
- `integration_test/test_support/plan_mode_live_harness_execution.dart`
- `docs/production_path_todo_live_canary_codex_task.md`
- `build/integration_test_reports/plan_mode_todo_app_cli0_comparison_1784130590/cli0_comparison_summary.json`

Next action:
- Start CLI1 with the smallest frontend-neutral seam: define typed runtime
  events and approval ports, then move one one-shot chat turn through the new
  facade while preserving the existing Flutter result.

### CLI1: Shared Application Execution Runtime

Status: `done`

Scope:
- Move runtime composition out of `lib/main.dart` and test-only canary builders
  into a reusable application layer with explicit settings, repository, LLM,
  tool, approval, logging, and lifecycle ports.
- Keep `ChatNotifier` and Flutter pages as GUI adapters while moving terminal-
  relevant orchestration behind a frontend-neutral facade.
- Remove `dart:ui`, widget, window-manager, notification, and platform-plugin
  requirements from the code imported by a Dart CLI executable.
- Preserve existing behavior before changing command UX or persistence.

Acceptance criteria:
- GUI and headless tests instantiate the same runtime composition API.
- The execution runtime exposes typed streams for assistant text, tool
  lifecycle, approval requests, questions, workflow transitions, usage, and
  terminal completion.
- The pure runtime test target runs under `dart test` or an equivalent
  no-window runner without Flutter widget bindings.
- Existing chat, coding, Plan Mode, routine-tool, approval, and session-log
  regression suites remain green.

Dependencies:
- CLI0 contract and headless baseline.
- Continue the F2/F5 large-file decomposition pattern instead of adding a new
  orchestration state machine beside `ChatNotifier`.

Evidence:
- `docs/cli1_shared_execution_runtime_codex_task.md`
- `packages/caverno_execution_runtime/lib/src/caverno_execution_runtime.dart`
- `packages/caverno_execution_runtime/lib/src/caverno_runtime_event.dart`
- `packages/caverno_execution_runtime/lib/src/caverno_runtime_ports.dart`
- `lib/features/chat/presentation/providers/caverno_execution_runtime_provider.dart`
- `packages/caverno_execution_runtime/test/caverno_execution_runtime_test.dart`
- `test/features/chat/presentation/providers/chat_notifier_execution_runtime_part.dart`
- `build/integration_test_reports/cli1_live/plan_mode_todo_app_cli0_comparison_1784149029/headless/`
- `build/integration_test_reports/cli1_macos_after_harness_fix/plan_mode_todo_app_live_canary_1784152249/plan_mode/plan_mode_live_suite_macos_report.json`
- Repository-standard verification passed Flutter analysis and 347 focused/full
  tests across the runtime, `ChatNotifier`, harness, and scenario configuration.

Next action:
- Start CLI2 with a one-shot `chat` command and a terminal presenter over the
  shared event stream. Keep coding and Plan Mode commands behind approval,
  cancellation, and exit-code tests.

### CLI2: Interactive Terminal MVP

Status: `done`

Scope:
- Add a supported `caverno` executable with `chat`, `coding`, and `plan`
  commands. Coding and Plan Mode require an explicit project root.
- Stream assistant output and concise tool lifecycle events to a TTY.
- Render typed approval, question, workflow-decision, and recovery events as
  terminal interactions using the same underlying policies as the GUI.
- Provide `--json` and stdin input for automation while keeping mutation
  approvals fail-closed when no TTY is attached.

Acceptance criteria:
- `caverno chat <prompt>`, `caverno coding --project <path> <prompt>`, and
  `caverno plan --project <path> <prompt>` use the shared runtime.
- Successful, blocked, denied, cancelled, transport-failed, and verification-
  failed outcomes have documented stable exit codes.
- Interactive local command, git, file, browser, and user-question boundaries
  are covered by terminal presenter tests.
- CLI output never leaks API keys, unredacted approval packets, or protected
  verifier content.
- The CLI does not advertise Computer Use support.

Dependencies:
- CLI1 shared runtime.

Evidence:
- `docs/cli2_interactive_terminal_mvp_codex_task.md`
- Terminal process smoke coverage passed for chat, coding, and Plan Mode,
  including human and JSON output, non-interactive approval denial, and SIGINT
  cancellation.
- `build/integration_test_reports/plan_mode_todo_app_cli0_comparison_1784165000/cli0_comparison_summary.json`
  recorded three consecutive passing headless runs and one passing macOS
  application-path run with Qwen3.6 27B Vision. All four runs had zero task
  drift and zero report-quality blockers under the strict comparison gate.

Next action:
- Preserve the terminal process and CLI0 parity gates as the CLI2 regression
  baseline. When CLI work resumes, start CLI3 with read-only `list` and `show`
  commands before adding cross-frontend resume or mutation.

### CLI3: Persistence, Resume, And Concurrent Ownership

Status: `done`

Scope:
- Reuse Caverno settings, drift conversations, memory, coding projects,
  checkpoints, routines, and session logs without test-only repositories.
- Add conversation listing and resume commands with stable identifiers.
- Define an execution lease for a conversation and coding project so GUI and
  CLI processes cannot perform conflicting mutations.
- Decide from measured contention whether direct storage locking is sufficient
  or a local Caverno daemon is justified.

Acceptance criteria:
- A conversation started in one frontend can be listed and resumed in the
  other without losing messages, workflow state, or provenance.
- Simultaneous execution against the same conversation/project is rejected or
  serialized with an actionable owner diagnostic.
- Storage migrations remain idempotent and recoverable when only the CLI is
  launched.
- Config precedence is deterministic: explicit CLI flags, environment,
  persisted Caverno settings, then built-in defaults.

Dependencies:
- CLI2 interactive MVP and F4 drift storage.

Evidence:
- `docs/cli3_shared_persistence_bootstrap_codex_task.md`
- `docs/cli3_read_only_conversation_commands_codex_task.md`
- `docs/cli3_execution_lease_foundation_codex_task.md`
- `docs/cli3_runtime_lease_integration_codex_task.md`
- `docs/cli3_conversation_resume_codex_task.md`
- `docs/cli3_gui_terminal_resume_smoke_codex_task.md`
- `lib/features/chat/application/persistence/caverno_persistence_bootstrap.dart`
  now owns the shared F4 migration, repository hydration, and database cleanup
  used by GUI and terminal frontends.
- `lib/features/terminal/application/caverno_cli_persistence.dart` routes the
  terminal runtime to the production drift repositories. Explicit data
  directories keep their SQLite database and migration markers in the same
  isolated root.
- Focused persistence and terminal-lifecycle tests passed, and a rebuilt macOS
  CLI process created the isolated drift store without starting MCP clients or
  producing a post-close persistence error on an early validation failure.
- `lib/features/terminal/application/caverno_conversation_query.dart` now emits
  redacted human output or schema-versioned `conversation_list` and
  `conversation_detail` events from exact drift repository reads.
- `lib/features/terminal/presentation/caverno_cli_process.dart` completes
  read-only queries before creating the Riverpod execution container, MCP
  clients, tools, or the LLM runtime. Completed migrations also avoid opening
  legacy conversation and chat-memory Hive boxes.
- Focused parser, query, and persistence tests cover bounded lists, exact-ID
  details, redaction, omitted attachment internals, missing IDs, and migration
  reader requirements.
- A rebuilt macOS executable emitted one empty `conversation_list` event from
  an isolated store on consecutive runs. The migrated second run still passed
  while both legacy data files were temporarily unreadable, confirming that
  the read-only path did not reopen those boxes.
- `CavernoExecutionLeaseService` now owns non-blocking OS file locks under each
  data root. Conversation and canonical workspace resources use hashed
  filenames, safe owner metadata, deterministic multi-resource ordering, and
  an in-process guard for POSIX process-scoped lock behavior.
- Separate-process tests cover contention, partial-acquisition rollback,
  independent resources and data roots, invalid diagnostics, and automatic
  recovery after abrupt owner exit.
- The macOS runner now bypasses duplicate-GUI activation only for CLI-shaped
  arguments. The full verification suite and a Debug macOS build passed, and
  the built executable returned its version through the terminal entry point.
- `CavernoExecutionRuntime` now acquires conversation and effective workspace
  leases before `run_started`, refreshes the authoritative conversation, and
  retains ownership until terminal persistence drains. Conflict, missing
  conversation, cancellation, preparation failure, completion, and shutdown
  paths have focused lifecycle coverage.
- GUI and terminal providers now resolve the same production data root for
  execution ownership. Explicit terminal data directories remain isolated,
  and Coding or Plan Mode leases the effective worktree instead of the source
  project when one is active.
- The migrated terminal path closes legacy conversation and chat-memory Hive
  boxes before execution and uses transient in-memory skill storage without
  exposing skill mutation tools. Packaged isolated and unreadable-legacy-file
  smokes reached runtime execution without Hive or provider errors.
- `tool/codex_verify.sh` passed with no generated-file drift, no analyzer
  findings, and 3,355 passing tests. A Debug macOS build passed, and two
  packaged Coding CLI processes using the same data root and workspace proved
  live contention: the second process emitted no `run_started`, returned
  `execution_lease_conflict`, and exited `75` while the first held ownership.
- `conversations resume` now resolves only a complete stable ID, selects the
  persisted conversation before ChatNotifier initialization, infers its saved
  Chat, Coding, or Plan Mode, and restores its saved project and worktree without
  accepting project reassignment.
- Headless resume startup defers unrelated empty-chat creation until the exact
  conversation is selected. This prevents a database-close race when a resume
  attempt loses its lease before normal chat initialization.
- Parser, notifier, terminal adapter, and runtime tests cover prompt-source
  conflicts, exact-ID enforcement, restored message history and planning
  workspace, missing project/worktree failures, refresh ordering, and live
  lease rejection. `tool/codex_verify.sh` passed with no generated-file drift,
  no analyzer findings, and 3,363 passing tests; a Debug macOS build also passed.
- A packaged isolated chat smoke against Qwen3.6 35B A3B Vision seeded a
  conversation, resumed its exact ID, and persisted the original and resumed
  user/assistant turns in order. Missing-ID resume returned
  `conversation_not_found` with exit `65`. A second packaged resume against a
  held conversation emitted only `execution_lease_conflict`, returned exit
  `75`, and produced neither `run_started` nor a post-close Drift exception.
- `caverno_gui_terminal_resume_test.dart` now writes separate Coding and Plan
  Mode conversations through the GUI-facing project and conversation notifiers
  into a temporary production drift database. It closes and reopens storage,
  resumes each exact ID through the terminal runtime lease, appends one
  deterministic terminal turn, and reopens storage again for final assertions.
- The cross-frontend smoke preserves the saved project, worktree, initial and
  appended messages, execution mode, workflow stage and tasks, source hash and
  timestamp, source references, and item provenance. Both cases emit
  `run_started` and `run_completed` with the saved worktree as the effective
  workspace. The focused gate passed 22 tests and the full gate passed 3,365
  tests with no generated-file drift or analyzer findings.
- `docs/cli3_terminal_project_persistence_codex_task.md`
- Terminal Coding and Plan Mode preparation now persists a generated canonical
  project record before activating a conversation. Application-default runs
  share the GUI shared-preferences registry, while an explicit data root owns
  an atomically replaced `coding_projects.json` registry and does not pollute
  application-default preferences.
- Deterministic restart tests create both execution modes in one terminal
  container, close and reopen the production drift database and project
  registry, resume each stable ID in a new container, append messages, and
  reopen storage again to verify mode, project ID, and message continuity. The
  focused gate passed 21 tests and the full gate passed 3,372 tests with no
  generated-file drift or analyzer findings.
- `docs/cli3_global_state_storage_scope_codex_task.md`
- Chat memory now has explicit storage-ownership evidence: sequential default
  frontend openings observe the same drift-backed profile, while separate
  explicit data roots cannot observe or overwrite each other's profile.
- Terminal routine composition now shares the GUI SharedPreferences registry
  only for the application-default root. Explicit data roots receive an
  atomically replaced local `routines.json` repository, so future provider
  initialization cannot cross into the default registry before routine commands
  are exposed. The focused gate passed 22 tests and the full gate passed 3,378
  tests with no generated-file drift or analyzer findings.
- `docs/cli3_chat_memory_atomic_merge_codex_task.md`
- Drift-backed chat-memory mutations now acquire a short global memory lease,
  refresh all six authoritative sections, and merge against that snapshot.
  Zone-scoped reentrancy keeps a composite session-memory update under one
  boundary without serializing the complete LLM turn.
- GUI and terminal bootstrap inject the same coordinator contract using their
  resolved data root. Conflicts retry for a bounded interval, stable timeouts
  identify unresolved contention, and every success or failure path releases
  ownership.
- A deterministic stale-cache regression opens two repositories before either
  writes, then proves distinct memories and conversation summaries from both
  frontend owners survive a database reopen. The focused gate passed 38 tests
  and the full gate passed 3,383 tests with no generated-file drift or analyzer
  findings.
- `docs/cli3_completion_audit_codex_task.md`
- Terminal LLM configuration now resolves through one tested flags,
  environment, persisted-settings, and built-in-default precedence helper.
  Blank higher-priority values fall through without exposing API-key values.
- Session-log composition keeps application-default runs on the GUI-compatible
  store. An explicit terminal data root owns `session_logs/` beneath that root,
  while `CAVERNO_SESSION_LOG_DIR` remains the dedicated highest-priority log
  override.
- Migration recovery now has an end-to-end retry regression: a failed first
  bootstrap closes its database and leaves the marker unset, then a second
  bootstrap migrates the legacy records and commits the marker without manual
  cleanup.
- `tool/cli3_contention_soak.dart` runs GUI-like and terminal-like workers as
  separate operating-system processes behind one start barrier. It exercises
  the same conversation, canonical workspace, and global chat-memory resources
  and emits redacted schema-versioned JSON and Markdown decision reports.
- Three consecutive two-worker, 100-iteration soaks completed all 200 runtime
  and 200 chat-memory operations per run with zero timeouts and zero invalid
  owner diagnostics. Runtime p95 was 5.454, 5.333, and 5.075 ms; chat-memory
  p95 was 6.317, 4.961, and 4.528 ms; throughput was 365.985, 362.857, and
  376.869 operations/s. All results stayed below the 250 ms p95 threshold, so
  the recorded decision is `direct_file_locking_sufficient`; a local daemon is
  not justified by current CLI3 contention evidence.
- A rebuilt Debug macOS application returned `Caverno 1.3.13` and a
  schema-versioned empty conversation list through the CLI entrypoint against
  an isolated data root, with both commands exiting successfully.
- The focused completion gate passed 14 tests. The final repository gate passed
  3,394 tests with no generated-file drift or analyzer findings.

Next action:
- Preserve the CLI3 runtime and doctor-foundation regression gates while CLI4
  packaging is paused. Keep terminal routine execution unavailable until its
  separate per-routine lease contract is defined.

### CLI4: Packaging, Automation, And Release Gate

Status: `later`

Scope:
- Package signed or checksummed executables for supported desktop platforms.
- Add shell completion, version/doctor output, signal handling, terminal
  capability detection, and upgrade guidance.
- Publish a CLI release gate combining pure runtime tests, TTY integration
  tests, non-interactive denial tests, headless Live LLM canaries, and one
  macOS app-path comparison smoke.
- Document unsupported tools and platform-specific degradation explicitly.

Acceptance criteria:
- Release artifacts run without a Flutter test runner or a visible Caverno app
  process.
- `caverno doctor` reports endpoint, model, configuration, storage, project,
  and tool-runtime readiness without exposing secrets.
- Automation consumes versioned JSON events and stable exit codes.
- The release gate proves approval, containment, cancellation, persistence,
  logging, and headless/app-path parity boundaries.

Dependencies:
- CLI3 persistence and ownership behavior.
- Completed: the F5 runtime package foundation is merged and the combined root
  and internal-package verification gate passes.

Current evidence:
- The doctor foundation has argument, configuration, bounded endpoint, model,
  storage, optional project, tool-policy, redaction, JSON, and exit-code tests.
  The focused repository gate passed 48 tests with no analyzer findings or
  generated-file drift.
- A fresh Debug macOS build is blocked at code signing because the timestamp
  service is unavailable. No packaged doctor evidence is claimed from the
  existing older app bundle.

Next action:
- Start from current `main` with architecture-stamped macOS archive tooling, a
  relative launcher, checksums, and packaged-process smokes. Restore signing
  timestamp connectivity before promotion, then rebuild the macOS app and run
  `doctor --json` through the packaged executable with an isolated data root.
  Treat that signed packaged doctor as a promotion and release gate, not as a
  prerequisite for starting CLI4 implementation.

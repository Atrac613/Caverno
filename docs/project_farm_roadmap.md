# Project Farm Roadmap

Date: 2026-09-26

Status: FARM0 `done` (2026-09-26); FARM1 `next`. Promoted from the
[Anabasis Project Vision](anabasis_project_vision.md) by user decision on
2026-09-26. [Roadmap](roadmap.md) owns cross-track selection; this document
owns FARM scope, acceptance criteria, and evidence.

## Purpose

For each coding project, Caverno should show where the project stands and what
its next step is. The in-app model should be able to operate projects and their
threads from chat. Eventually Caverno should advance each project's next step
on its own, within bounds the user sets. The user calls that last stage a
software farm.

The user's example: when this repository's roadmap recommends RC1 next, the
project's dashboard shows `Next task: RC1` with a **Start work** button.

Three consumers read the same project state and act through the same commands:

1. the project dashboard, through its buttons;
2. the in-app model, through built-in control-plane tools (the "internal MCP");
3. a future orchestrator that proposes, and later takes, the next step.

This track takes over two stages of the Anabasis Project Vision: the project
view, and bounded ongoing operation. ANA4 keeps its single-goal destination. A
started task runs through the existing Goal, Plan Mode, delegation, and
acceptance machinery, not a parallel one.

## Decisions

| Date | Decision |
| --- | --- |
| 2026-09-26 | The consumers are Caverno's own model, the dashboard, and the future orchestrator. Exposing the control plane to external agents over a real MCP transport is deferred. |
| 2026-09-26 | The control plane is a set of first-party built-in tools over a transport-neutral application service, not an in-process MCP server. SEC1 classifies MCP results as third-party provenance (`DataSourceClass.mcpResource`), and the mutating commands need the calling turn's owner, approval, and taint state, which only an owner-bound built-in handler has. |
| 2026-09-26 | The next task comes from LLM extraction over the project's roadmap document. The extraction is verified mechanically against the source text and cached by content hash, and the user can pin or override the result. |
| 2026-09-26 | Work starts now, ahead of RC1's signed-device evidence. |
| 2026-09-26 | The chat half of the dashboard starts as an ordinary chat-workspace thread. The 2026-09-14 decision against a fourth `WorkspaceMode` stands. A split-view console is added only if use shows the need. |
| 2026-09-26 | The model does not get a "switch the visible thread, then send" capability. Manual starts go through the dashboard, and automatic starts need background execution either way, so the intermediate design is not worth building. |

## Architecture

```text
Repository (roadmap, git, later pull requests)      <- source of truth
   | change detection (content hash, HEAD, runtime events)
   v
Project State (per-project projection with citations)
   +--> Dashboard            [Start work] --+
   +--> Built-in tools (the model)  --------+--> WorkspaceControlService
   +--> Orchestrator (FARM3+)  -------------+    (one policy, approval, audit)
                                                    |
        manual:    coding thread with the task as its goal (Goal / Plan Mode)
        automatic: substrate chosen by FARM0 spike B (first candidate: LL13)
                                                    |
        Anabasis acceptance -> branch ready for review (never auto-merged)
```

- **Project State** is a per-project projection, and every derived fact carries
  a citation. The repository is the source of truth. Caverno stores only what
  it derived, where it came from, and the content hash it was derived against.
  Inputs:
  - roadmap pointers, extracted and verified;
  - git state read by the app itself: branch, uncommitted changes,
    ahead/behind, latest commit;
  - thread and goal state from the conversation store and the runtime
    registries (`ActiveResponseRegistry`, `approvalRequiredConversationIds`,
    pending questions, the per-thread queue);
  - worktree-agent tasks;
  - pull requests, later.
- **Control plane.** `WorkspaceControlService` is an application-layer service
  with transport-neutral commands. The dashboard and the built-in tools are two
  front-ends over the same commands, so policy, approval, and audit live in one
  place. A real MCP transport can be added later as a third front-end.
- **Orchestrator** (FARM3 onward). It proposes a next step for each project from
  that project's Project State, and from FARM5 it takes the step within policy.
- **Execution.** A manual start opens a coding thread with the task as its goal.
  Automatic execution uses the substrate that FARM0 spike B selects.

## Constraints Found In The Code

Measured 2026-09-26 against main `a33200f14`.

- **A turn can only start on the visible thread.**
  `ThreadScopedMessageQueue.canStart` requires the message owner to equal the
  visible conversation, and so does `_canDrainQueuedMessagesForThread` in
  `chat_notifier.dart`. A message queued for another thread waits until the
  user opens that thread. Turns started while their thread was visible keep
  running in the background. The per-thread split that would remove this
  limit is stage 3 of `docs/multi_thread_architecture_study.md` and has not
  been started.
- **Creating and cancelling act on the visible thread.**
  `ConversationsNotifier.createNewConversation` and `ensureCurrentConversation`
  always make the new conversation current, and `_cancelStreaming` targets the
  visible thread.
- **Remote Coding also works on the visible thread.** It selects a thread and
  then sends to it, and it rejects a destination-bound command with
  `destination_changed` when the desktop has moved to another thread.
- **Nested turns inherit zone values.** A turn started from inside another
  turn's tool handler inherits that turn's `TurnThread`, `TurnProjectRoot`, and
  `ModelUsageRole` zone values unless it is started from the root zone.
- **LL13 worktree agents run headless.** They go through
  `SubagentExecutionService` with file tools only
  (`WorktreeAgentScopedToolDispatcher`). Their verification command runs
  through `Process.start` without an approval gate. Verified-green tasks end
  as a branch ready for review, and nothing merges automatically.
- **Who supplies the verification command.** The verification command comes
  from one of three places:
  - the user-typed `/agent` command;
  - an LL37 repair packet that needs explicit queue approval;
  - for an Anabasis worktree child, the saved plan task's `validationCommand`.

  The model drafts that last one. Before an orchestrator drafts plans with no
  human in the loop (FARM5), confirm whether plan approval shows the command
  to the user. Either way, such a command must not run unreviewed.
- **Shell commands always need a person.** SEC4.4g requires fresh human
  approval for every command that reaches `sh -c`, including under Full
  Access.
- **Tool policies differ in their defaults.**
  - `SubagentToolPolicy.blockedTools` is a blocklist, so a child inherits any
    new tool that is not added to it.
  - `RoutineToolPolicy` is an allowlist, so it excludes new tools by default.
  - The Anabasis parent guard refuses unknown tools, so it excludes them too.
- **Two files have no room to grow.** `conversations_notifier.dart` sits
  exactly at its size budget and `chat_notifier.dart` is close to its own, so
  new code goes into new files.
- **Strict structured output is available.** It goes through
  `StructuredOutputChatDataSource.createStructuredChatCompletion`, and
  `test/quality/structured_output_schema_test.dart` pins that every schema
  requires all of its properties.
- **Unattended scheduling is already gated.** The roadmap gates unattended
  agent-farm scheduling on OBS1 and SEC1: see the LL13 baseline row and the
  OBS1 row in `roadmap.md`.

## Invariants

Every milestone preserves these. A slice that would have to break one stops and
returns to a decision instead.

1. **No model or orchestrator gets around a human decision.** It never
   resolves an approval, question, or plan review, never caches around one,
   and never bypasses one. The farm advances work until a human decision is
   needed, then notifies the user: on the desktop, and on the phone through the
   existing approval push.
2. **Nothing a model writes runs without approval.** No model or orchestrator
   authors a command that runs without approval. Verification commands come
   from human-reviewed sources: project configuration, or a plan a human
   approved while seeing the command.
3. **The repository stays the source of truth.** Caverno persists only cited
   projections and the provenance of every start. It never keeps a parallel
   task store.
4. **Every automated start is traceable.** A start that comes from a model or
   the orchestrator records its origin, carries the originating turn's taint
   into the started work, and is audited.
5. **Delegation stops at one level.** Started turns, subagents, and worktree
   agents never receive control-plane mutation tools.
6. **The dashboard never waits on a model.** Rendering it requires no model
   call. Models run only when a source changes or the user asks.
7. **Concurrency has hard limits.** Inference capacity (LL20 slots, the LL8
   mesh) and workspace leases bound how much runs at once.
8. **Nothing merges automatically.**

## Next-Task Extraction Contract

FARM1 owns this contract. FARM0 spike A measures it first.

- **Source.** One roadmap document per project, chosen by the user.
  `docs/roadmap.md`, `ROADMAP.md`, and `roadmap.md` are offered as defaults.
- **Request.** Strict structured output at temperature 0 under a dedicated
  `ModelUsageRole`, so the cost is accounted for instead of landing in
  `unknown`.
- **Response.** A recommended next item, plus the current and blocked items.
  Each item carries `id`, `title`, `quote` (a verbatim span from the source),
  and `line`. Every schema property is required.
- **Verification.** An item is kept only when both hold:
  - its quote occurs in the source, after whitespace, the line-number gutter,
    and markdown emphasis are normalized away;
  - when the item has an id, the quote contains it.

  The verifier then records the occurrence nearest to the reported line as the
  item's line, so the citation comes from the source rather than from the
  model. Items that fail are dropped and counted. A recommended item that fails
  verification is shown as unverified, never as a guess.
- **Size.** A document over the direct budget is read outline-first. The model
  picks sections from the heading outline, the verifier confirms that each
  heading exists at its reported line, and only those sections are extracted.
- **Cache.** Keyed by the content SHA-256, the extractor prompt version, and
  the model. Extraction reruns only when that key changes or the user asks for
  a refresh.
- **Language.** No keyword or pattern heuristic decides what the next task is.
  The model interprets and the verifier checks, so roadmaps in any language
  are handled the same way.
- **Scope.** The extraction yields a pointer, not a task contract. Acceptance
  criteria and verification commands come from Plan Mode after the user starts
  the task.

## Milestones

### FARM0: Design And Feasibility Spikes

Status: `done`

Scope:
- This document and its roadmap rows.
- Spike A: next-task extraction accuracy.
- Spike B: the execution substrate for FARM4.

Spike A protocol:
- **Fixtures**, each labeled by hand from that revision's own text.
  - The six revisions of `docs/roadmap.md` since 2026-09-05 whose
    "Recommended Next Slice" section names a milestone: RC1, ANA4, ANA3 three
    times, and ANA2. Three of them are over 200 KB, which exceeds the model's
    64k-token context. They exercise an outline-first path: the model picks
    sections from the heading outline, and only those sections are extracted.
  - The 2026-09-26 revision, which selects FARM0 while still carrying
    "Previous recommendation: RC1".
  - One revision, from 2026-09-20, that recommends a work item with no
    milestone id. It is reported but not scored.
  - Three synthetic roadmaps: a README checklist, Japanese prose, and a
    milestone table that recommends nothing.

  Revisions before 2026-09-05 were checked and left out. They list many
  `current` and `next` rows without singling one out, so a hand label would
  encode the labeler's choice, not the document's.
- **Model.** `qwen3.8-27b-exl3` at temperature 0, following the
  [live LLM canary runbook](live_llm_canary_agent_runbook.md).
- **Thresholds, fixed before the run.**
  - The recommended id is correct on at least 6 of the 7 scored revisions.
  - All three synthetic fixtures are correct. For the table, correct means no
    recommended item at all.
  - The verifier rejects every fabricated quote in its unit tests, and the
    live run reports how many model quotes it had to drop.
- **Also recorded.** Latency and prompt size per extraction.
- **Instrument.** `tool/farm0_next_task_extraction_spike.dart`, with fixtures
  in `tool/fixtures/farm0_next_task/`.

Spike B protocol:
- Inventory the visible-thread reads on the turn-start path, from
  `_sendMessageNow` up to owner registration, using the classifier behind
  `test/quality/thread_scoped_state_ratchet_test.dart`.
- Classify recent roadmap items by whether an LL13 worktree agent could complete
  them with file tools and a human-declared verification command. RC1, which
  needs signed physical devices, is the reference example of an item that
  cannot be automated.
- Compare a per-thread runtime with headless CLI workers on four points:
  approval bridging, GUI state refresh, duplicated MCP clients, and inference
  capacity.
- Confirm whether plan approval shows each task's `validationCommand`
  (invariant 2).

Acceptance criteria:
- A spike A report that meets or misses each threshold, with its evidence
  directory recorded.
- A spike B memo that names the FARM4 substrate and lists what it cannot do.

Spike A findings, 2026-09-26. Model `qwen3.8-27b-exl3` at temperature 0, on
main `a33200f14` with the FARM0 changes uncommitted. Evidence is under
`build/integration_test_reports/farm0_spike_a/`.

1. **Run 1 was aborted as an instrument defect.** The prompt asked for "one
   sentence or table row" as each quote, so the model copied whole roadmap
   table rows, some of them hundreds of words long. Every direct-route caverno
   revision ran past the 2,000-token answer budget (`finish_reason: length`)
   and left unparseable JSON, even though the recommendation inside the cut-off
   answer was already correct. The fix:
   - The prompt now asks for the shortest verbatim span: at most 25 words, and
     for a table row only its leading cells.
   - The answer budget is 4,000 tokens.

   The thresholds did not change.
2. **Run 2 (`run2/`) met both thresholds.** Historical revisions scored 6 of 7
   and synthetic fixtures 3 of 3. Of 105 extracted items, 2 were dropped, and
   neither was fabricated. Both quotes exist in the source but do not carry the
   reported id (`idNotInQuote`). No quote was missing from its document.
3. **The one miss (`0084af193`) is the verifier doing its job.** That revision
   recommends ANA3 only implicitly ("Keep ANA3 `current` until that closure
   scope is resolved"). The model named ANA3 but quoted the neighboring
   sentence, which mentions ANA4. The dashboard would show the recommendation
   as unverified rather than cite a line that names a different milestone. The
   unscored `32ff587b4` revision recommends work with no milestone id and ended
   the same way: unverified, not wrong.
4. **Outline-first read all three revisions over 200 KB correctly.** In each,
   the model chose exactly Active Focus, Recommended Next Slice, In Progress,
   and Blocked, and every heading resolved at its reported line. The excerpts
   came to 55–63 KB.
5. **Latency:**
   - 3–4 s for the synthetic fixtures;
   - 20–28 s for revisions of 34–43 KB;
   - 33–38 s through the outline route.

   Extraction therefore has to be cached and run off the render path, as
   invariant 6 already requires.
6. **Run 3 (`run3/`) repeated run 2 exactly.** It produced the same verdict on
   every fixture: 6 of 7, 3 of 3, and 2 of 105 quotes dropped. At temperature 0
   the result is stable.

**Consequences for FARM1.**
- Keep the id-in-quote rule.
- Show an implicit recommendation as unverified, with a pin action.
- Run extraction in the background after a content-hash change.
- Promote the prompt, schema, verifier, and outline-first reader from the spike
  tool into `lib/` rather than rewriting them, since they are what was
  measured.

Spike B findings, 2026-09-26, against main `a33200f14`:

1. **Turn start reads the visible thread by construction.** From
   `_sendMessageNow`, `tool/audit_chat_notifier_turn_scope.dart` reaches 356
   methods. 53 of the library's 62 ambient visible-thread reads sit on that
   path. 34 of those are in methods with no turn identity in scope, including
   10 in `_sendMessageNow` itself (seven `state.messages`, three
   `currentConversation`). Starting a turn on a non-visible thread is
   therefore not a local change. It is stage 2 of
   `docs/multi_thread_architecture_study.md`: a turn object built from a
   conversation id, with those reads moved onto it.
2. **Plan approval shows validation commands.**
   - `ConversationPlanDocumentBuilder` writes `- Validation:` lines into the
     plan markdown that `PlanReviewSheet` renders.
   - `ConversationPlanProjectionService` parses the saved `validationCommand`
     back out of that same markdown.

   A plan a human approved therefore satisfies invariant 2. A plan approved by
   an orchestrator would not, so FARM5 needs either human plan approval or a
   project-declared allowlist of verification commands.
3. **LL13 worktree agents complete only one class of work:** pure edits that a
   single declared command verifies. They have file tools only, and no shell,
   network, or code generation. The 17 active roadmap rows on 2026-09-26 (In
   Progress plus Ready Candidates) were classified by hand from each row's next
   action:
   - **3 fit:** a single F5 extraction slice, SEC1 slice 7 classifier work,
     and TOOL0.
   - **4 fit in part:** SEC4, COMPAT1, ROUTINE3, and FARM2.
   - **10 do not fit.** RC1, WATCH5, WATCH14, and RC2 need devices; FARM0 and
     RAG3R need live models or network; HOOK1 and ANA4 wait on a decision;
     FORK1 and FARM1 need Freezed code generation.
4. **Substrates compared.**
   - **LL13 worktree agents** already exist. They are headless, isolated,
     verified, and end in branches ready for review, but they are limited to
     the class above.
   - **A per-thread runtime** gives full capability and a live UI, but first
     needs the 34 reads migrated and `ChatState` split per thread.
   - **Headless CLI workers** (CLI2 and CLI3) exist, with leases and resume,
     but they fall short in three ways:
     - Non-interactive approval fails closed, so a coding run stops at its
       first shell command (SEC4.4g).
     - The GUI sees the conversation only after the worker persists it.
     - Each worker starts its own MCP clients.

**Spike B decision.**
- FARM4 starts on LL13 worktree agents for the class that fits.
- Background execution of full threads becomes its own foundation milestone,
  multi-thread stage 2. It is promoted only if FARM3 shows that class is too
  narrow to be worth automating.
- CLI workers are not used.

The first product value is therefore suggest, start, and carry work to the next
human decision, not unattended completion.

Next action: start FARM1 by promoting the measured extractor into `lib/`.

### FARM1: Project State And Dashboard v1

Status: `next`

Scope:
- A Project State projection and its repository, built behind an interface
  like `CodingProjectRepositoryApi`. Per-project roadmap path configuration.
- A dashboard page opened from the coding drawer's project tile
  (`_ProjectTile` in `conversation_drawer.dart`) and pushed with `Navigator`.
- Summary sections:
  - the next task, with its source link and verification state;
  - current and blocked roadmap items;
  - threads by state (running, awaiting approval, awaiting an answer, queued)
    with their goals;
  - worktree agents;
  - git state.
- **Start work** runs `WorkspaceControlService.startProjectTask`. It creates a
  coding thread in the project, sets the task as the thread's goal together
  with its source citation, and opens the thread. The user reviews and sends,
  or enters Plan Mode. The start is user-initiated, so the visible-thread
  constraint does not apply.

Acceptance criteria:
- Rendering the dashboard makes no model call. A test with a datasource that
  fails on any request proves it.
- Extraction reruns only when the cache key changes.
- A fabricated quote from a fake model is never shown as verified.
- **Start work** creates exactly one thread, in the right project, with the goal
  and its citation. A poison test proves that a background thread's running
  turn is unaffected.
- Widget tests cover four states: no roadmap configured, extraction pending,
  unverified, and verified.
- The extraction schema is registered in `structured_output_schema_test.dart`.
  Size ratchets are respected.

Dependencies: FARM0 spike A meets its thresholds.

Progress:
- **Slice 1 (2026-09-26).** The measured contract moved into
  `lib/features/project_farm/domain/roadmap_next_task_contract.dart`.
- **Slice 2 (2026-09-26).** Added `RoadmapNextTaskExtractor`, which both the app
  and the FARM0 tool now drive, plus `RoadmapSnapshotService` with its
  repository and providers.
  - Snapshots are cached by content hash, extractor version, and model.
  - Extraction runs under the new `ModelUsageRole.projectState`.
  - Roadmap paths are confined to the project root.
  - Concurrent refreshes share one run.
  - A live smoke on three fixtures, covering both routes, matched the spike.
- **Slice 3 (2026-09-26).** Added `ProjectDashboardPage`, opened from the
  project tile's menu in the coding drawer.
  - It shows the next task with its verification label and citation, the
    roadmap items in progress and blocked, the project's threads with their
    run and goal state, worktree agents, and git state read by the app.
  - **Start work** runs `startProjectTask`, the command FARM2's tool will
    share. It creates a coding thread whose goal cites the source and sends
    nothing.
  - Rendering reads the cached snapshot and refreshes in the background.
  - The full suite passes apart from the six file-size ratchet failures
    already on main.
- **Next:** a visual check in the macOS app, then FARM2.

### FARM2: Control Plane And Built-in Tools

Status: `next`

Scope:
- **The service.** `WorkspaceControlService`, with commands for listing
  projects and threads, reading project state, reading a thread, and starting a
  project task.
- **The tools** (names are tentative): `list_coding_projects`,
  `list_coding_threads`, `get_project_state`, `read_coding_thread`, and
  `start_project_task`. `start_project_task` runs the same command as the
  **Start work** button.
- **Registration points:**
  - `McpToolService` reserved names;
  - a `BuiltInToolRegistry` category with localization, deferred behind
    `tool_search`;
  - the owner-bound handler catalog;
  - a SEC1 capability classification;
  - `SubagentToolPolicy.blockedTools` for the mutating tool.
- **Availability by mode:**
  - chat workspace: all tools;
  - coding workspace: read-only, own project only;
  - Plan Mode, the Anabasis parent, routines, and children: none.
- **Transcript reads** strip reasoning blocks, reduce each tool result to one
  line, and stay within a size bound.

Acceptance criteria:
- No tool changes the visible thread. Poison tests prove it.
- The initial `tool_search` selection is unchanged, measured.
- `start_project_task` and **Start work** produce identical threads.
- A live probe is graded on the tool names the model calls, not on its wording.

Dependencies: FARM1.

Progress:
- **Slice 1 (2026-09-26).** The four read-only tools are
  `WorkspaceControlTools`.
  - They reach the model through a new first-party seam,
    `BuiltInToolExtension` on `McpToolService`, so `chat` does not depend on
    `project_farm` and `chat_notifier` is untouched.
  - The caller's thread comes from the `TurnThread` zone. A coding thread sees
    only its own project, a chat thread sees every project, and a call with no
    identifiable thread is refused.
  - The tools are registered in `BuiltInToolRegistry` under a new `workspace`
    category, deferred behind `tool_search`, and classified by SEC1 like
    `search_past_conversations`: read-only inspection and project source.
  - To make room, `ConversationSearchTool.candidates` moved out of
    `mcp_tool_service.dart`, which brought that file back under its ratchet.
  - **Live probe (2026-09-26, `qwen3.8-27b-exl3`, one run at temperature 0).**
    `tool/canaries/farm2_tool_selection_live_canary_test.dart` offers the
    real built-in catalogue narrowed to the initial `tool_search` selection,
    so the workspace tools start deferred. It grades only on the tool names
    called. 3 of 3 prompts passed, two in English and one in Japanese. Each
    reached `list_coding_projects` through `tool_search`. The Japanese prompt
    first tried `list_directory`, and then searched.
  - **Next:** `start_project_task`. It mutates, so it needs the approval
    surface and taint check that live in the chat notifier library, which is
    over its size budget. Land the ratchet repair first.

### FARM3: Suggest Mode

Status: `later`

Scope:
- The orchestrator proposes the next step for each project, with a cited
  rationale.
- Proposals are recomputed on change events (a roadmap change, a thread
  finishing, and later a merged pull request). There is no periodic polling.
- A cross-project overview.
- A user approval starts the proposed step through the FARM2 command.
- Classify each item by whether it can be automated.

Acceptance criteria:
- Every proposal cites its sources.
- Items that need a human, such as physical devices, are labeled as such.

### FARM4: Background Execution

Status: `later`

Scope:
- Execution on the substrate that spike B selects.
- Concurrency limits derived from inference capacity, workspace leases, and
  budgets.
- Results end as branches ready for review.

Acceptance criteria:
- Two projects run at once with no crossed prompts or tool results. The
  multi-thread live canary is extended to prove it.
- Cancelling reaches only its own work.

Dependencies: FARM0 spike B, FARM2.

### FARM5: Bounded Autonomous Operation

Status: `later`

Scope:
- A per-project policy: the task classes allowed to run, a budget, and a time
  window.
- Runs are scheduled through the LL18 idle orchestrator.
- Work stops at human decisions and notifies the user.
- A morning report.

Dependencies: OBS1, SEC1, FARM3, FARM4.

### FARM6: Pull Requests

Status: `later`

Scope:
- Show pull request and CI status on the dashboard.
- Later, let the farm open pull requests. This mutates a remote service, so it
  is approval-gated.

Open: token storage and the egress review.

## Open Questions

- Where the per-project roadmap path and farm policy live: a new
  `CodingProject` field, which needs a Freezed regeneration, or a separate
  per-project settings record.
- Where automatability comes from: the Plan Mode task contract, an explicit
  project policy, or both (FARM3).
- Where the cross-project overview is placed (FARM3).

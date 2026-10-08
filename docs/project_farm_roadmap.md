# Project Farm Roadmap

Date: 2026-09-26

Status: FARM0–FARM5 `done` (2026-09-26); FARM6 `later`. Promoted from the
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
| 2026-09-29 | Dashboard Start work opens a task thread and runs implementation, dedicated read-only `/review`, and at most two repair rounds. An implementation turn without a captured file change gets one bounded retry before stopping, including when the response omits its ready marker. It stops at approval, a pending question, incomplete verification, missing captured patches, an unavailable review route, or a thread switch; it never commits or publishes. Model-created task threads do not auto-run. |
| 2026-10-01 | Supersedes "it never commits" in the row above, by user decision. After a clean review the workflow sends one commit turn: the model marks the cited roadmap item done by that document's own conventions and commits only the task's captured files plus the roadmap, never pushing, amending, or rewriting history. The commit is a model `git_execute_command` call, so it passes the normal approval gate (invariant 2). Success is read from git by the app, not from the response: HEAD must move and no captured task file may remain dirty; otherwise the workflow stops with a recorded reason. The implementation turn is told to leave the roadmap status alone, so the reviewed patch holds only the task's changes. Before this, a clean review ended with the work uncommitted and the dashboard offered the next roadmap task on top of it. Start work, on the dashboard and the projects overview, now reads git fresh and asks before starting over uncommitted changes; Cancel is the default, Start anyway proceeds, and a project git cannot read is not blocked. |
| 2026-10-01 | By user decision, a dashboard-started task is split into 1–6 ordered subtasks by a structured-output call under `ModelUsageRole.planning`, and the subtasks are saved as the thread's execution tasks without a plan review, so the Plan Mode progress rows and the prompt's execution snapshot show them. This narrows invariant 1 for this one path: the outline is saved unreviewed, but it carries no validation command (invariant 2 holds) and every shell command still needs fresh approval. Each subtask but the last runs as its own turn judged by a `PROJECT_TASK_SUBTASK_DONE` marker; the last keeps the ready marker and goal completion. A failed decomposition runs the task as one step. The companion sidebar shows the workflow stage (break down, implement k/n, review with repair round, commit) from an in-memory provider, since the workflow itself does not survive a restart. |
| 2026-10-01 | Conflict audit across Plan Mode, Anabasis, and the farm split (all three share `workflowSpec` tasks). Fixed: a subtask that coding verification left `blocked` or `failed` stops the workflow instead of being recorded done on the model's marker; the generated outline is saved under the revision label `Generated task outline (not reviewed)`, and the system prompt presents it as unreviewed rather than as an approved plan; a goal a non-final subtask turn completed early is reopened before the next subtask. Left as is: the workflow stage flips to `review` between subtasks while a plan document exists, and a user-started Plan Mode run or `@anabasis` turn stops the farm workflow (busy) without resuming it. |
| 2026-10-01 | A re-run of a roadmap task carries the earlier run's work forward. Session b2971ae0 re-ran `.gitignore` over changes thread 26d7db3e had made and left uncommitted; with no file change of its own, completion was refused, the a2baaff2b guidance sent it to `blocked_reason`, and the workflow stopped with the task done but unreviewed and uncommitted. At start the workflow now collects file-tool diffs that earlier threads with the identical goal objective captured and git still reports dirty, records their paths on the goal (`projectTaskInheritedPaths`), names them in the implementation prompt, and reviews and commits them as the task's own. With inherited paths the completion gate drops the file-change requirement but still demands a successful execution verification, and its guidance asks for that verification rather than a blocker. Index-only changes (for example `git rm --cached`) are not captured and are not carried. Session b58b0db0 (build 369d0e31d) showed the carry blind after a relaunch: threads not opened since launch are listing stubs with their turn diffs dropped, so the earlier run's diffs are now loaded with `refreshConversationForExecution` before they are read. |
| 2026-10-01 | Session 6f3ea3cf: the decomposer made the last subtask verify-only, the README edits were captured in the two subtask turns before it, and the per-turn file-change check refused completion; the gap guidance led to a blocker and the workflow stopped with every subtask done. Before each implementation turn the workflow now adds the files this thread already changed to `projectTaskInheritedPaths`, so earlier subtask turns count like an earlier run. A change is still required somewhere in the task, and a successful execution verification after it is still required. The sidebar's implement row now counts finished subtasks, and the plan card shows a generated outline as not reviewed. |

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

Measured 2026-09-26 against main `a33200f14`; execution-boundary notes updated
2026-10-01.

- **A turn can only start on the visible thread.**
  `ThreadScopedMessageQueue.canStart` requires the message owner to equal the
  visible conversation, and so does `_canDrainQueuedMessagesForThread` in
  `chat_notifier.dart`. A message queued for another thread waits until the
  user opens that thread. Turns started while their thread was visible keep
  running in the background. The per-thread split that would remove this
  limit is stage 3 of `docs/worklog/multi_thread_architecture_study.md` and has not
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
  through the shared workspace sandbox without a per-run approval gate.
  Unsupported runtimes stop verification. Verified-green tasks end as a branch
  ready for review, and nothing merges automatically.
- **Who supplies the verification command.** The verification command comes
  from one of three places:
  - the user-typed `/agent` command;
  - an LL37 repair packet that needs explicit queue approval;
  - for an Anabasis worktree child, the saved plan task's `validationCommand`.

  The model drafts that last one. Before an orchestrator drafts plans with no
  human in the loop (FARM5), confirm whether plan approval shows the command
  to the user. Either way, such a command must not run unreviewed.
- **Host commands need a person.** SEC4.4g requires fresh human approval for
  uncontained native commands in a coding project. Contained local commands
  can use the selected approval mode; see
  [Project Execution Boundaries](project_execution_boundary_design.md).
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
2. **Execution stays within authorized authority.** Farm verification commands
   come from human-reviewed sources: project configuration, or a plan a human
   approved while seeing the command. Generated code runs only inside the
   enforced workspace boundary. Foreground coding actions may be reviewed by
   the configured LLM; uncontained host commands retain fresh human approval.
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
- **Response.** A recommended next item, plus current, blocked, and prioritized
  upcoming items. Upcoming includes up to eight other unfinished tasks in
  priority order, excluding the recommendation and active or blocked work.
  An explicit next item takes precedence. Without one, the extractor suggests
  an unfinished item in the highest-priority group, preferring any items singled
  out within that group and using document order for ties. It records whether
  the recommendation was explicit or inferred from priorities. With no supported
  choice, it recommends nothing.
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
   `docs/worklog/multi_thread_architecture_study.md`: a turn object built from a
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

Closed 2026-09-26: FARM1 promoted the measured extractor into `lib/` unchanged.

### FARM1: Project State And Dashboard v1

Status: `done`

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
- **Still open:** a check in the real macOS app. Only widget tests cover the
  dashboard so far.
- **Pin and roadmap file (2026-09-26).** This delivers the 2026-09-26 decision
  that the user can pin or override the extracted next task.
  - The next-task menu can change the roadmap file (project-relative, refused
    outside the project), pin a verified item, or clear the pin.
  - `RoadmapSnapshotService` applies the pin whenever a snapshot is read, so
    the dashboard, overview, proposals, and tools all see the pinned task. The
    stored snapshot stays as extracted.
  - A pin naming an item the roadmap no longer has is ignored, never shown
    stale.
  - The chip row now wraps, instead of overflowing on narrow widths.

### FARM2: Control Plane And Built-in Tools

Status: `done`

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
  - The chat-notifier library's size budget blocked `start_project_task`
    until `fix/ratchet-overruns` (`a8286e942`) brought four chat files back
    under their ratchets. That branch is merged here.
- **Slice 2 (2026-09-26).** `start_project_task`.
  - It is offered only when a starter is wired, and runs only from a chat
    thread.
  - It starts only a verified roadmap item: the next task, or an in-progress
    item named by id. It never starts text the model composed.
  - It asks the user every time through the file-operation approval sheet,
    with the goal as its preview, and never caches the answer.
  - It adds the thread with `ConversationsNotifier.addBackgroundConversation`,
    so the manager thread keeps the screen and its running turn, and it sends
    nothing. The goal's auto-continue stays off.
  - **Start work** now goes through the same `startProjectTask` command, so
    both paths create identical threads. The dashboard then opens the thread
    by returning its id to the drawer.
  - Children cannot call it: it is in `SubagentToolPolicy.blockedTools`.
  - Making room in `conversations_notifier.dart` moved
    `retainTurnDiffsForMessages` into `domain/services`.
  - **Taint carry (invariant 4) is not implemented yet.** Nothing runs until
    the user sends, so the user's send is the start. Carry the originating
    turn's taint once FARM4 starts work without a send.


### FARM3: Suggest Mode

Status: `done`

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

Progress:
- **Slice 1 (2026-09-26).** Added `ProjectsOverviewPage`, opened from the
  projects header in the coding drawer.
  - Each row shows a project's cached next task, how many of its threads are
    running or need approval, and Start work for a verified task.
  - **Refresh all** re-reads roadmaps one project at a time, so the model never
    gets concurrent extractions.
  - There are no proposals yet. The next slice adds the orchestrator's cited
    rationale and the automatability label.

- **Slice 2 (2026-09-26).** Orchestrator proposals.
  - `ProjectProposalService` asks the model to choose the next step from the
    verified roadmap items plus a summary of each thread's state (no
    transcripts). It gives a two-sentence rationale and an automatability
    label: `unattended` or `needsHuman`.
  - `verifyNextStepProposal` drops any answer that names a task outside the
    candidate list, or uses an unknown label.
  - A proposal is cached against a hash of its input: items, thread states,
    contract version, and model. **Refresh all** recomputes proposals after
    each roadmap read, one project at a time.
  - The overview shows the proposal and its label. Start work begins the
    proposed item when it is a verified next or in-progress item, and never a
    blocked or unverified one.
  - **Live probe (`tool/canaries/farm3_proposal_live_canary_test.dart`,
    `qwen3.8-27b-exl3`, one run):** 3 of 3 proposals were grounded.
    - caverno: FARM0, `needsHuman`. Correct: it needs design work and live
      measurement.
    - Pantry tracker: PT-12, `needsHuman`. Conservative: the model cited
      product decisions.
    - Household ledger: M6, `unattended`. Plausible: a PDF export verified by
      tests.
  - **The label is the model's self-report.** It is advice only. FARM5 must
    not start unattended work on it alone: it needs a project-declared
    allowlist of task classes and verification commands (invariant 2).
  - **Not yet:** recomputing when a thread finishes. That needs a
    runtime-event listener and is left for a later slice.

### FARM4: Background Execution

Status: `done`. The design below was drafted 2026-09-26 and needs the user's
review before any code.

Scope: run a started task in the background on an LL13 worktree agent. The
result is a branch ready for review, and the user decides what happens to it.
The trigger is still a person: FARM4 changes **where** work runs, not **who**
decides to run it.

**Design.**

1. **A project policy, declared by the user.** Before anything runs, a
   per-project record sets:
   - which verification commands are allowed, as exact argv, for example
     `tool/flutter_test_quiet.sh` and `fvm flutter analyze`;
   - a concurrency limit of 1 by default;
   - which worktree root to use.

   Caverno stores the policy, the settings page edits it, and a model never
   writes it. With no policy, FARM4 is unavailable for that project
   (invariant 2).
2. **Run in background.** The action sits next to Start work and is offered
   only when all of these hold:
   - the proposal is labeled `unattended`;
   - the task is a verified next or in-progress item;
   - the project has a policy.

   It opens an approval sheet showing the task, the goal, the one
   verification command chosen from the policy, the worktree, and the branch
   name. Approving enqueues an LL13 task through `WorktreeAgentTaskLauncher`.
   Refusing leaves Start work as the manual path.
3. **Execution** reuses the existing LL13 route unchanged:
   - `WorktreeAgentScopedToolDispatcher`, which gives file tools only;
   - the declared verification command, through
     `WorktreeAgentVerificationRunner`;
   - `WorktreeAgentExecutionEvidenceRecorder`, which records the changed files.
4. **Results** appear on the dashboard and in the overview as
   `running`, `verified-green`, `failed`, or `needs recovery`, with the branch
   and the changed files. Nothing merges automatically (invariant 8). The user
   reviews the branch and merges or discards it.
5. **Concurrency.**
   - At most one background task per project and a global cap that follows
     the inference capacity (LL20 slots and the LL8 mesh).
   - Workspace leases keep a background task and a foreground thread from
     editing the same worktree.
   - A second request queues. It is never dropped.
6. **Taint (invariant 4).** A task started from a proposal carries the taint
   of the turn that produced the proposal. If untrusted content influenced
   that turn, the approval sheet says so and background execution is refused:
   only Start work is offered.
7. **Cancellation.** Stopping a background task cancels only its own run and
   leaves its worktree for inspection, following LL13's recovery behavior.

**Slices.**
- **4a.** The project policy entity, its repository, and a settings page. No
  execution.
- **4b.** Run in background through LL13, with approval, one per project,
  and a results surface.
- **4c.** The global concurrency cap and queueing across projects, then a
  two-project live canary proving that prompts and tool results never cross
  (extending the multi-thread canary).

**Acceptance criteria.**
- With no policy, or with a `needsHuman` proposal, no background action is
  offered.
- A verification command outside the policy is rejected before it runs.
- Two projects run at once with no crossed prompts or tool results.
- Cancelling reaches only its own work.
- Every background run is recorded, with its task, command, and branch, in
  the LL13 task registry, which persists across restarts. Corrected
  2026-09-26: the approval audit records only automated decisions the user
  never saw ("manual approvals are intentionally not recorded here" in
  `tool_approval_audit_log.dart`), and a background run is always confirmed
  by the user in a dialog. Writing one there would break the audit's
  charter.

Dependencies: FARM3. The user reviewed the design and said to continue on
2026-09-26.

Progress:
- **Slice 4a (2026-09-26).** Added `ProjectFarmPolicy`: allowed verification
  commands, with a concurrency default of 1.
  - It is stored in the project-farm repository and edited only from the
    dashboard's **Background runs** card. No tool writes it.
  - `policyCommandProblem` is stricter than the LL13 runner. It rejects
    quotes, globs, and every shell metacharacter, so a declared command is a
    plain argv.
  - `ProjectFarmPolicy.allows` matches commands exactly, with whitespace
    collapsed.
  - Nothing executes yet.
- **Slice 4b (2026-09-26).** Run in background. The user authorized
  continuing on 2026-09-26.
  - `backgroundRunBlocker` offers the action only when all four gates pass:
    a policy with at least one command, a verified task, a proposal that names
    that very task as `unattended`, and no unfinished background task in the
    project.
  - `RunInBackgroundDialog` shows the task, its quote, and a picker limited to
    the policy's commands. It states that the result is a branch for review.
  - `runProjectTaskInBackground` rechecks the policy just before enqueueing
    and refuses any other command. It then enqueues on the unchanged LL13
    route (`WorktreeAgentTaskLauncher` and
    `WorktreeAgentTaskOrchestrator.startAndExecuteReady`). The prompt tells
    the agent not to merge, push, or mark the roadmap item done.
  - The overview shows the project's latest background task, with its state
    and branch.
  - Concurrency: one unfinished task per project through the gate. The global
    cap is LL13's existing one per endpoint.
  - Taint: proposals are built from repository documents and thread states,
    not from a chat turn, so there is no turn taint to carry. Revisit if
    proposals ever take web or MCP input.
  - Not live-verified end to end: a live run would create a real worktree and
    branch. The execution path is the existing LL13 route, which its own
    canary covers (`tool/canaries/ll37_worktree_agent_live_canary_test.dart`).
  - The record of each run is the LL13 registry, which keeps the title,
    command, and branch. The approval audit is deliberately not used; see the
    corrected acceptance criterion.
- **Slice 4c (2026-09-26).** Two-project isolation.
  - Cross-project queueing is LL13's existing scheduler: one task per
    endpoint, with the rest held `queued`, never dropped. The 4b gate adds
    one unfinished task per project, so no new queue was needed.
  - `tool/canaries/farm4_background_two_project_live_canary_test.dart` runs
    two projects' tasks at once through the production LL13 execution
    delegate, with the FARM4 prompt and policy-declared commands, in scratch
    directories.
  - On `qwen3.8-27b-exl3` (one run, 19 s) both were verified green, each
    changed only its own `lib/greeting.dart`, and each wrote only its own
    marker. Nothing crossed between projects.
- **Cancellation (2026-09-26).** Building the cancel surface found an LL13
  defect: `markCompleted` and `markFailed` overwrote a cancel, and a running
  task kept editing until it finished. The existing banner's Cancel button had
  the same problem.
  - The registry now keeps `cancelled` when a later completion or failure
    arrives.
  - `WorktreeAgentTaskExecutionContext.isCancelled` is read by the scoped
    dispatcher, which refuses every tool call after a cancel with
    `task_cancelled`, and by the delegate, which skips verification.
  - The overview's Cancel acts on the project's latest unfinished task only.

### FARM5: Bounded Autonomous Operation

Status: `done` for the first bounded version (2026-09-26).

**Gate decision (user, 2026-09-26).** The roadmap gated FARM5 on OBS1 and
SEC1. The user replaced that gate with a FARM-local minimum, for these
reasons:
- **OBS1**, the trace timeline for every agent run, is not started and is
  large. FARM5 needs only an inspectable record of its own decisions: the FARM
  run ledger.
- **SEC1 slice 7** classifies HTTP and browser actions and host-wide reads.
  The FARM execution path is worktree-scoped file tools plus one declared
  command, and it touches none of those.
- The original FARM5 policy excluded project-code execution because a test
  could run generated code with host authority. On 2026-10-01, shared enforced
  verification containment replaced that restriction. User-authorized tests
  can run unattended; missing containment stops verification. See
  [Project Execution Boundaries](project_execution_boundary_design.md) for
  SDK provisioning and platform limitations.

**What runs.** A `farm_advance` stage in the LL18 idle-maintenance pipeline,
between `adopt` and `precompute`, so the cache warm-up stays last. It runs
only in LL18's window: idle, on AC power, at night. For each project,
`FarmUnattendedRunner` does the following:
1. **Skips the project entirely** unless its policy has unattended runs on,
   and at least one allowed command the user authorized for unattended
   verification. A project that did not opt in costs no model call.
2. **Stops at the daily limit** (default 1), counted from the ledger.
3. **Rereads the roadmap and recomputes the proposal**, one project at a time.
4. **Starts a run only when all the Run in background gates pass:** a
   verified task, a proposal naming it `unattended`, and no unfinished
   background task in the project. The run uses the user-authorized
   command and requires enforced workspace containment. After the model calls,
   the runner rereads the current policy and daily run count before enqueueing.
   Revoked permission records `unattended_disabled`; a newly spent limit records
   `daily_limit`. Command selection uses the current policy.
5. **Records every start and every skip** of an opted-in project in the
   ledger, with its reason.

Between projects and after each model call it polls the maintenance cancel
handle, so a returning user stops the pass before another task is enqueued.
This is a dispatch boundary, not cancellation of an already enqueued task.

**Settings.** The dashboard's Background runs card has an **Unattended**
dialog with an on/off switch (off by default), runs per day, and per-command
checkboxes authorizing contained verification commands, including tests. The
card lists the project's five most recent ledger entries, manual and unattended.
The stage's summary ("started N, skipped M") appears in the morning
maintenance report.

**Not included, by design:**
- merging;
- any project that did not opt in;
- work outside the idle window.

The automatability label remains advice. It is one of four gates, never the
only one.

**Evidence.**
- Unit tests cover opt-in, the daily limit, each gate, command selection,
  cancellation, and the ledger.
- On 2026-10-04, 55 focused Farm and maintenance tests passed with static
  analysis. Integration tests connect the real `IdleMaintenanceScheduler` to
  `FarmUnattendedRunner` with controlled model callbacks and an injected idle
  environment: one dispatch per idle window, gated projects, and cancellation
  during a pending proposal. Policy and daily-limit changes during proposal
  generation are covered. Enqueue/start callbacks are recorded substitutes;
  these tests do not prove live model calls, OS idle detection or native
  worktree execution from the unattended scheduler.
- The execution path is the one the 4c two-project canary exercised live.
- An unattended pass has not been run against the user's real projects,
  because it would create real worktrees and branches.
- A synthetic unattended scheduler/worktree canary was added on 2026-10-04.
  Native worktree creation, live HTTP, file edits and contained verification
  ran, but the exact newline oracle still failed after one bounded repair.
  Live unattended readiness remains blocked; see
  [the canary coverage record](live_llm_canary_coverage.md#software-farm-unattended-worktree-canary)
  for artifacts and the injected environment/proposal boundaries.
- Following the user-approved upstream parser repair and EXL3 restart,
  `farm_unattended_live_canary.Pw8ZFI` passed the same acceptance and independent
  evidence gate. It proves synthetic idle dispatch through real native worktree
  creation, live model editing, contained verification, persisted task state
  and the daily limit. OS idle detection and live proposal generation remain
  injected boundaries; no unattended run was made against a user project.
- The live-proposal extension `farm_unattended_live_canary.C097B4` then passed
  with the production proposal service and structured completion adapter.
  The file-edit candidate was admitted and verified; the physical-device
  candidate was declined with `needsHuman`, zero enqueue/start and a skip
  ledger entry. Roadmap snapshots and the idle environment remain injected.

- The live-extraction extension `farm_unattended_live_canary.uFmSV1` passed
  production roadmap discovery, live extraction, source quote verification
  and snapshot persistence before proposal admission and native execution.
  Two extraction and two proposal HTTP calls produced a green file edit and
  a physical-device decline with zero enqueue/start. OS idle and fixture
  access remain injected; large-document outline extraction is not covered.

- The maintenance-provider extension `farm_unattended_live_canary.tEIzvY`
  passed the production scheduler/pipeline providers and selected
  `farm_advance` stage. Foreground blocked dispatch, synthetic background
  duration admitted one task, the same window did not repeat, and resume
  reset idle to zero. Native worktree verification remained green. Lifecycle
  events, AC state and report sink are fixtures; other maintenance stages,
  OS event delivery and overnight timer behavior remain unverified. The
  current idle signal is app background duration, not system-wide HID idle.

- Foreground return now synchronously latches maintenance cancellation via
  the production lifecycle provider. The native macOS host canary
  `farm_foreground_host.ZGRPE9` observed real background/resume events and a
  five-second timer-driven pending proposal; it drained 69 ms after window
  restore with zero enqueue/start. Re-backgrounding does not revive the pass.
  Related suites passed 53 tests and analysis; the live-model regression
  `farm_unattended_live_canary.f8wvq3` also passed. This stops further dispatch,
  not already-started worktrees or in-flight HTTP. Overnight windows, real
  AC/notification plugins and signed release behavior remain unverified.

- Unattended tasks now register held (`needsRecovery`) and are admitted only
  after persistence and a fresh cancellation/policy/command/limit check.
  Registry changes during admission leave the task held, avoiding stale state
  publication; rejection records the planned branch and requires manual
  recovery. The run handle rechecks time/config/power gates without waiting
  for another polling tick. The native registration case
  `farm_foreground_host.LziEst` passed with one held task and zero starts;
  `farm_unattended_live_canary.EI0KzH` passed the normal live admission path.
  Related suites passed 59 tests and analysis. Running-task termination,
  overnight windows and physical power/notification plugins remain outside
  this evidence.

### FARM6: Pull Requests

Status: `later`

Scope:
- Show pull request and CI status on the dashboard.
- Later, let the farm open pull requests. This mutates a remote service, so it
  is approval-gated.

Open: token storage and the egress review.

## Open Questions

Resolved 2026-09-26:
- **Roadmap path and farm policy storage.** Both live in a separate
  per-project record in the project-farm repository, not in a `CodingProject`
  field.
- **Automatability.** The proposal's label is advice only. Background work
  also needs a verified task, a user-declared policy, and, when unattended, a
  command the user authorized for contained verification.
- **The cross-project overview** opens from the projects header of the coding
  drawer.

Open:
- **Real-app check.** Every FARM surface is covered by widget and unit tests
  and live canaries, but none has been exercised in the running macOS app,
  including sandbox file access and app-issued `git`.
- **Review.** The FARM diff (`a33200f14..af45d9084`) was merged into local
  main without a human code review.
- **Storage.** Policies, pins, proposals, and the run ledger are JSON in
  SharedPreferences. If the ledger or project count grows, move them to the
  drift store.
- **SEC1 classification.** `start_project_task` is not yet classified; it is
  approval-gated at the tool.
- **FARM6.** Where the GitHub token is stored, and the egress review.

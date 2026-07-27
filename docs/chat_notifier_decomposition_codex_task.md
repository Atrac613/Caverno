# ChatNotifier Library Decomposition Program (Phase 1, Tranche 2)

Status: program planned; Slice 1 not started.

This is an umbrella plan, not one implementation task. It continues
`docs/large_file_refactor_plan.md` Phase 1 after Tranche 1
(`PlanningResearchCollector`, `WorkflowProposalParser`,
`ActiveResponseRegistry`, `ProjectScopedToolArgumentResolver`, and related
extractions).

## Execution Rule

- If a request says only "implement this document", execute **Slice 1 only**.
- Every later slice requires its own task specification based on
  `docs/codex_task_template.md`.
- Keep each slice within one focused review pass. The workstreams below are
  ordering constraints and risk groupings, not permission to combine them into
  one PR.
- Target at most roughly 500 changed production lines per slice. Split sooner
  when one file contains more than one risk domain.
- A slice is complete when its own acceptance criteria pass. The program-wide
  criteria apply only after every approved slice is complete.
- Before starting a slice, remeasure its named files and compare the current
  call sites with this plan. If the baseline has drifted, update that slice's
  task and acceptance arithmetic before editing production code.

## Motivating Evidence

On 2026-07-25/27, roughly twenty defects were fixed on
`fix/cross-thread-tool-result-contamination`, squashed as `b0c19fdb`. They
shared one cause:

> `ChatNotifier` serves every thread from one object, while `ChatState` belongs
> to the thread on screen. Turn-scoped code that reads visible-thread state can
> therefore receive another turn's value without any type error.

A background turn quoted another thread's history, resolved relative tool paths
against the visible project, leased the wrong workspace, persisted its
transcript onto the visible conversation, lost queued work and plan state on a
switch, and stranded lifecycle resources after a plan question crossed threads.

The durable boundary is a library boundary:

> A file that is `part of 'chat_notifier.dart'` can reach `state`, `ref`, and
> every private field. An independently importable collaborator cannot.

The objective is to remove ambient capability, not merely move lines. Line
counts measure progress but do not prove the architecture.

A one-off call-graph review reported 45 turn-reachable methods that read visible
state without accepting turn identity. That number is historical evidence, not
an acceptance baseline: no checked-in tool currently reproduces it. Slices
2a1-2a3 must establish the canonical measurement and enforcement before later
extractions use it.

## Program Scope

- Goal: replace same-library helper and handler code with independently
  importable collaborators that receive explicit, immutable turn inputs.
- User-visible behavior: none. Every extraction is behavior-preserving.
- Expected architectural result:
  - the notifier remains the orchestration and lifecycle shell;
  - extracted code cannot import or receive the notifier or ambient UI state;
  - turn identity, project, messages, settings, and approval capabilities are
    explicit at each boundary;
  - each independently moved concern has direct tests and a shrink-only size
    budget.
- Non-goals:
  - opportunistic behavior fixes found during an extraction;
  - the per-thread notifier split described as stage 3 in
    `docs/multi_thread_architecture_study.md`;
  - provider renames, `ChatState` schema changes, or persistence migrations;
  - raising a ratchet budget;
  - forcing a whole current `part` file to become one collaborator.

## Measured Baseline

Measured on 2026-07-27 at `b0c19fdb`, using the same physical-line semantics as
`File.readAsLinesSync()` in `test/quality/file_size_ratchet_test.dart`:

| Boundary | Physical lines |
|---|---:|
| `chat_notifier.dart` orchestrator | 9,375 |
| 43 declared part files | 13,674 |
| **Same-library aggregate** | **23,049** |
| Aggregate ratchet budget | 23,030 |
| **Current ratchet debt** | **19** |
| Five lifecycle `keep` parts | 644 |
| Candidate part lines outside the `keep` set | 13,030 |
| Exact half-of-baseline reference point | 11,524.5 |

The aggregate ratchet is intentionally red at the start of Slice 1:
`23,049 > 23,030`. Do not change the budget to make the baseline green.

The previous inventory counted the trailing empty split result once per file,
inflating the aggregate by 44 lines. All program measurements must use the
ratchet's physical-line method.

### Planning Inventory

This table is an exposure and sequencing inventory. It is not an instruction to
move each listed file wholesale.

| Group | Part lines | Current files | Required treatment |
|---|---:|---|---|
| Lifecycle `keep` set | 644 | `execution_runtime`, `response_finalization`, `error_handling`, `turn_exit`, `cancellation` | Keep with the orchestrator |
| Slice 1 formatter | 149 | `content_tool_result_format` | Move to an independent chat-domain service |
| DTO- or callback-blocked proposal facades | 699 | `proposal_parsing`, `proposal_option_extraction`, `workflow_proposal_parser`, `task_proposal_quality`, `terminal_tool_response_policy`, `task_proposal_parser` | Defer until draft DTOs leave `ChatState` and JSON-repair or terminal-policy callbacks become explicit result values or narrow typed ports |
| Low-state but side-effecting or callback-driven | 712 | `prompt_context`, `python_attachment_repair`, `duplicate_recovery`, `mesh_routing`, `planning_research`, `turn_rollback_handlers` | Split by responsibility; require explicit turn inputs |
| Recovery and verification | 2,872 | `tool_loop_batch`, `unexecuted_action_recovery`, `coding_verification_feedback`, `coding_continuation_recovery`, `turn_finalization_recovery`, `final_answer_recovery` | Characterize each recovery route before extraction |
| Tool execution and approval | 4,892 | `local_file_handlers`, `computer_use_handlers`, `git_handlers`, `ssh_handlers`, `subagent_handlers`, `browser_handlers`, `routine_handlers`, `serial_handlers`, `skill_handlers`, `ble_handlers`, `python_handlers`, `approval_handlers`, `tool_handler_registry` | Separate execution from notifier-owned approval/UI ports before moving code |
| Guardrails and telemetry | 1,480 | `command_guardrails`, `context_surgery`, `tool_result_telemetry` | Add deterministic two-thread poison tests first |
| High-coupling orchestration | 2,226 | `goal_auto_continue`, `participant_turns`, `ask_user_question` | Narrow interfaces only; keep unextractable orchestration in place |
| **All declared parts** | **13,674** | **43 files** | |

Do not use raw `state`, `ref.`, or `_settings` occurrence counts as a coupling
classifier. They miss line-wrapped member access and ignore private fields,
private methods, callbacks, file I/O, persistence, and other side effects. For
example, `prompt_context` contains provider reads, persistence, file loading,
logging, project resolution, and an optional visible-conversation fallback. It
is not a pure helper.

## Safety Contract

### Collaborator boundary

Every extracted collaborator must satisfy all of these rules:

1. It is an independent library and does not use `part of`.
2. It does not import, extend, accept, store, or return `ChatNotifier`,
   `ChatState`, Riverpod `Ref`/`WidgetRef`, or `ProviderContainer`.
3. It does not read `TurnThread`, `TurnProjectRoot`, or another Zone-scoped
   value internally. The notifier resolves those values at the call site and
   passes plain immutable inputs.
4. It does not receive a broad closure that merely captures the notifier or
   visible-thread state. Side effects cross narrow typed ports whose methods
   include the owning turn identity.
5. It receives the smallest settings snapshot it needs. Passing all
   `AppSettings` requires an explicit justification in that slice's task.
6. Public notifier APIs may remain as thin delegates when external callers need
   them. A delegate must not reintroduce an ambient lookup.
7. Every program collaborator carries an exact discovery marker:
   `// ChatNotifier decomposition collaborator: <collaborator-id>`.
8. Every new production file is added to
   `test/quality/file_size_ratchet_test.dart`, or to an equivalent
   shrink-only package budget, at its achieved size.
9. Every collaborator with executable logic has a direct test. Overall
   repository coverage alone is not sufficient.

### Lifecycle `keep` set

Keep `_startRuntimeTurn`, `_completeRuntimeTurn`, `_failRuntimeTurn`,
`_finishStreaming` finalization, cancellation, error handling, and turn-exit
recording with the orchestrator. They release the active-response registration,
runtime handle, and workspace lease together. Splitting that ownership can
reopen the lifecycle leak this program is intended to prevent.

### Stop conditions

Stop the current slice and record a follow-up when any of these is true:

- extraction requires passing the notifier, `ChatState`, `Ref`, or a broad
  notifier-capturing callback;
- preserving behavior requires an ambient visible-conversation fallback on a
  turn-reachable path;
- the current file mixes execution with approval or UI state and no narrow port
  exists yet;
- an extraction needs a behavior fix, schema change, or provider rename;
- the destination would exceed an existing budget;
- the slice cannot remain one focused review pass or would move roughly 500
  production lines without a smaller cohesive boundary.

Do not hide a stop condition by widening the context object.

## Measurement and Regression Gates

Slices 2a1-2a3 must make the central safety claim reproducible before any
post-Slice-1 production extraction starts.

### Static audit

Add a checked-in audit, tentatively
`tool/audit_chat_notifier_turn_scope.dart`, that:

- reads a checked-in `tool/chat_notifier_decomposition_manifest.json` shared by
  the audit and structural tests;
- preserves one entry per original part with stable `id`, `partPath`,
  `entrypoints`, `status`, and `collaborators` fields; every collaborator record
  has its own stable `id`, `path`, and `sizeBudgetKey`;
- reconstructs the original 43-part inventory and entrypoints from `b0c19fdb`;
  because Slice 1 runs first, its formatter entry starts as `extracted` with the
  Slice 1 collaborator record, while the other current parts start as
  `remaining`, `keep`, or a justified `deferred`;
- uses only `remaining`, `partial`, `extracted`, `keep`, or `deferred` as status
  values; extraction transitions the status and appends collaborator records
  but never deletes the historical part entry;
- records the exact files, entrypoints, and call-graph assumptions it scans;
- parses complete method signatures rather than a fixed number of lines;
- reports each ambient read independently instead of skipping a whole method
  after finding one turn-scoped accessor;
- scans every currently declared `partPath` whose status is `remaining`,
  `partial`, `keep`, or `deferred`, plus every collaborator record attached to
  a `partial` or `extracted` entry;
- emits a deterministic method/read inventory suitable for review;
- establishes a canonical baseline committed with the tool.

The historical count of 45 must not be copied into a ratchet until this audit
reproduces and explains it.

### Structural test

Add `test/quality/chat_notifier_collaborator_boundary_test.dart` to:

- freeze all original `partPath` values, reject any new notifier part, and
  require the currently declared parts to equal the entries whose status is
  `remaining`, `partial`, `keep`, or `deferred`;
- require an `extracted` entry's old part to be absent, a `partial` entry's old
  part to remain, and every declared collaborator path and size-budget key to
  exist;
- scan Dart files under `lib/features/chat` for the discovery marker
  independently of the manifest and require a one-to-one marker ID/path match;
- use syntax-aware whole-file checks on every collaborator record attached to
  a `partial` or `extracted` entry to reject `part of`, forbidden imports or
  references to `ChatNotifier`, `ChatState`, Riverpod reference types, and
  direct turn Zone reads;
- separately reject forbidden types in public collaborator signatures;
- ensure every new collaborator is size-budgeted;
- fail when a completed slice silently adds another notifier part.

### Existing thread-scope ratchet

Strengthen `test/quality/thread_scoped_state_ratchet_test.dart`. Its current
implementation inspects only the first six signature lines and skips the entire
method when any turn-scoped accessor appears. Both behaviors can hide another
ambient read in the same method.

When the stronger implementation surfaces a pre-existing read, reconcile it
exactly with the reviewed Slice 2a1 audit and label the ratchet change as a
baseline migration. After Slice 2a3 establishes that migrated baseline, forbid
new production reads; do not require an out-of-scope behavior fix merely to keep
the old blind baseline numerically unchanged.

### Deterministic two-thread coverage

Slices 2b2-2b7 must add or extend tests that poison the visible thread with
different project, task, approval, queue, question, and protected-path values.
The owning turn must continue to use only its own values.

At minimum, cover:

- production-release approval cannot cross threads;
- approval from an earlier interaction generation cannot authorize a later
  generation;
- saved validation and target scope come from the owning turn;
- pending approvals, questions, and queued work block only their owning turn;
- compact-result protected paths come from the owning turn;
- participant turns retain their messages, approval, handoff, and lifecycle
  while another thread is visible.

### Live canary

Before using the live canary as a program gate, Slice 2b1 must make all four
scenarios assert both:

- no thread remains in `busyConversationIds`;
- every completed turn records a `turn_exit` entry.

The current shared lifecycle helper checks only busy registrations, and the
queued-turn and handback scenarios do not independently assert an exit entry.
Each scenario must define its expected completed turns and assert exactly one
exit per conversation and interaction generation; a non-empty exit list is not
sufficient.

Run the corrected live canary after any slice that touches prompt context,
recovery, tool execution, approval, guardrails, telemetry, participant turns,
questions, or goal continuation.

Record the exact model and reachable base URL used for each run. Verify the
model endpoint before starting; on macOS, use a loopback relay when the Flutter
test process cannot reach the LAN endpoint.

Example command shape (replace the endpoint and model with the warmed target):

```bash
curl -fsS http://127.0.0.1:11434/v1/models
CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL=http://127.0.0.1:11434/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart -d flutter-tester
```

## Ordered Work Plan

Slices 1, 2a1-2a3, and 2b1-2b7 each require one task specification and PR.
Workstreams 4-8 require further sub-slice task documents; a workstream row is
never one PR. Deferred-boundary rows are not approved implementation slices.

| Slice or workstream | Scope | Review boundary | Live canary |
|---|---|---|---|
| **1** | Extract `content_tool_result_format` | One pure formatter and direct domain-service tests | Not required |
| **2a1** | Reproducible turn-scope audit and shared decomposition manifest | One audit tool and named baseline | Not required |
| **2a2** | Collaborator structural boundary test | One manifest-backed architecture gate | Not required |
| **2a3** | Repair the existing thread-scope ratchet | Complete-signature and per-read detection only | Not required |
| **2b1** | Complete live-canary exit accounting | Exact expected exits per conversation/generation | Required to validate the gate |
| **2b2** | Approval isolation tests | Cross-thread and cross-generation approval only | Not required |
| **2b3** | Pending-question isolation tests | Question ownership and clearing only | Not required |
| **2b4** | Queued-work isolation tests | Queue blocking and resumption only | Not required |
| **2b5** | Saved-validation and target-scope isolation tests | Validation and target ownership only | Not required |
| **2b6** | Compact-result protected-path isolation tests | Protected-path ownership only | Not required |
| **2b7** | Participant-turn isolation tests | Participant messages, approval, handoff, and lifecycle only | Not required |
| **Deferred boundary** | Proposal parsing, option, workflow, task-parser, and quality facades | Blocked because draft DTOs are declared in `ChatState` and JSON-repair uses notifier-bound callbacks; both prerequisites are outside this tranche | Not applicable |
| **Deferred boundary** | Terminal tool-response facade | Blocked until its notifier-capturing callback bag becomes a narrow explicit-input API | Not applicable |
| **Workstream 4** | Low-state and prompt-context concerns | Extract one independent concern per sub-slice; leave unrelated code in its existing part | Required for prompt, planning, mesh, Python repair, or rollback paths |
| **Workstream 5** | Recovery and verification services | One recovery route or tightly coupled pair per sub-slice | Required |
| **Workstream 6** | Tool handlers | Separate execution from approval/UI; split local-file and Computer Use into sub-500-line concern tasks; registry moves last | Required |
| **Workstream 7** | Guardrails, context surgery, and telemetry | One concern per sub-slice after poison tests exist | Required |
| **Workstream 8** | Goal continuation, participant turns, and user questions | Narrow interface extraction only; leave justified orchestration in place | Required |

Do not begin any Workstream 4-8 sub-slice until Slices 2a1-2a3 and 2b1-2b7 are
green.

## Slice 1 Codex Task: Extract ContentToolResultFormatter

### Task

- Goal: move the compact `<tool_result>` payload and tag formatting logic out of
  the `ChatNotifier` library into an independent chat-domain service.
- User-visible behavior: none. Output strings and JSON payloads remain exactly
  compatible for the same inputs.
- Non-goals:
  - changing summary wording, truncation limits, JSON keys, or tag syntax;
  - refactoring other proposal, prompt, recovery, or tool-loop code;
  - adding the Slice 2 audit and structural gates;
  - changing the content parser.

### Context

- Source:
  `lib/features/chat/presentation/providers/chat_notifier_content_tool_result_format.dart`
  (149 physical lines).
- Current callers: three `_buildContentToolResultTag` calls in
  `lib/features/chat/presentation/providers/chat_notifier.dart`.
- Destination:
  `lib/features/chat/domain/services/content_tool_result_formatter.dart`.
- Direct tests:
  `test/features/chat/domain/services/content_tool_result_formatter_test.dart`.
- Quality budget:
  `test/quality/file_size_ratchet_test.dart`.
- Related plan:
  `docs/large_file_refactor_plan.md`.
- Reference boundary:
  `lib/features/chat/domain/services/goal_completion_elicitation_prompt.dart`
  and
  `test/features/chat/domain/services/goal_completion_elicitation_prompt_test.dart`.

### Implementation Notes

- Add an `abstract final class ContentToolResultFormatter` with exactly one
  public member:
  `static String format(String toolName, String result)`.
  Keep payload construction, map summarization, value compaction, and
  truncation private to that service.
- Add
  `// ChatNotifier decomposition collaborator: content-tool-result-formatter`
  as the exact discovery marker for the later structural gate.
- Import the service directly from `chat_notifier.dart`; do not add a package,
  barrel export, provider, notifier field, or dependency-injection binding.
- Preserve the existing behavior for:
  - entry maps with implicit or explicit counts;
  - match maps with query, pattern, or neither and implicit or explicit counts;
  - content maps, byte-write maps including `created`, and replacement maps
    including `replace_all`;
  - generic JSON maps;
  - JSON lists;
  - valid JSON scalar values;
  - plain-text and malformed JSON results;
  - empty results;
  - whitespace normalization and truncation;
  - final `<tool_result>{json}</tool_result>` construction.
- Replace the three notifier call sites with the public formatter API.
- Remove the old part directive and part file after all callers move.
- Add the new domain-service source file to a shrink-only size budget at its
  physical line count.
- Never increase either ChatNotifier size budget. Lower the aggregate budget to
  its achieved count. Lower the primary-file budget only if the primary file's
  measured physical count decreases.
- Keep each direct replacement call on one physical line. The intended edit
  swaps one part directive for one import and preserves the three call-site line
  counts, producing a zero notifier line delta and an expected aggregate of
  22,900 before measurement.
- Calculate the expected aggregate as
  `23,049 - 149 + notifier physical-line delta`, where the notifier delta is
  its achieved count minus 9,375 and includes the removed part directive, new
  import, and call-site rewrites. Record the achieved count rather than
  assuming the delta.
- Refresh the ChatNotifier counts and Slice 1 status in
  `docs/large_file_refactor_plan.md`.
- No generated files or data migrations are required.

### Similar-Pattern Search

Before finishing, search for:

```text
_buildContentToolResultTag
_buildContentToolResultPayload
<tool_result>
```

Inspect all matches, but do not widen the slice. Record non-equivalent formatters
or protocol follow-ups in the handoff.

### Acceptance Criteria

1. The old formatter part is no longer declared or present, and the declared
   part count falls from 43 to 42.
2. The three notifier callers use
   `ContentToolResultFormatter.format(toolName, result)` directly.
3. Direct tests cover every existing formatter branch and exact tag output.
4. The new collaborator has no dependency on `ChatNotifier`, `ChatState`,
   Riverpod, providers, turn Zones, settings, persistence, or file I/O.
5. The ChatNotifier primary and aggregate size tests pass; neither budget
   increases, the aggregate budget is lowered to its achieved count, and the
   primary budget is lowered only when its measured count decreases.
6. The new domain-service source file has a shrink-only size budget.
7. The new source file has the exact decomposition discovery marker.
8. The thread-scope ratchet still passes with no allowlist growth.
9. `docs/large_file_refactor_plan.md` records the achieved physical counts.
10. No unrelated production behavior or files enter the change.

### Verification

Run focused checks:

```bash
fvm dart format \
  lib/features/chat/domain/services/content_tool_result_formatter.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  test/features/chat/domain/services/content_tool_result_formatter_test.dart \
  test/quality/file_size_ratchet_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test \
  test/features/chat/domain/services/content_tool_result_formatter_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart test/quality/thread_scoped_state_ratchet_test.dart
```

Run the repository gate:

```bash
tool/codex_verify.sh --coverage
git diff --check
```

The live multi-thread canary is not required for this pure formatter move.

### Handoff Notes

Record:

- old and new primary, part, and aggregate physical line counts;
- old and new ratchet budgets;
- direct formatter branch cases and the target file's hit/line counts from
  `coverage/lcov.info`;
- the final declared-part count;
- searches performed and any deferred follow-up.

Use one focused Conventional Commit, for example:

```text
refactor: Extract content tool result formatter
```

## Requirements for Later Slice Specifications

Every later concrete slice or workstream sub-slice task document must state:

- one concrete concern and destination API;
- exact source methods and call sites, not only a current part filename;
- explicit immutable inputs and typed side-effect ports;
- expected part-count and aggregate-line deltas;
- manifest status, collaborator records, and discovery markers;
- direct test file and a target-file coverage expectation with a checked
  verification command;
- deterministic two-thread cases when turn ownership is relevant;
- whether the corrected live canary is required;
- stop conditions and deferred adjacent findings;
- focused verification plus `tool/codex_verify.sh --coverage`.

`tool/codex_verify.sh --coverage` generates a report and lists files below the
display threshold; it does not fail on that threshold. Do not describe it as a
numerical coverage gate. If a slice requires a minimum percentage, its task
must provide and check an explicit target-file command.

Within a slice, use one commit per independently reviewable concern. Never mix
an extraction with a behavior fix.

## Program Completion Criteria

The program is complete only when:

1. Every remaining part belongs to the five-file lifecycle set or is an
   explicitly justified high-coupling deferral covered by the structural
   boundary test. Report the final count. The currently scoped floor is 11
   parts: five lifecycle parts plus six proposal/callback deferrals. Lowering
   that floor requires separately approved prerequisite work.
2. No completed slice leaves an undocumented notifier part or collaborator
   boundary exception.
3. The canonical turn-scope audit reports no unreviewed ambient reads in
   extracted collaborators and no increase in remaining notifier exposure.
4. The repaired thread-scope ratchet exactly reconciles any newly detected
   pre-existing reads with the Slice 2a1 audit, then has no production-read
   baseline growth after Slice 2a3.
5. Every extracted production file has a shrink-only size budget and direct
   tests.
6. The ChatNotifier primary and aggregate budgets never increase. After each
   production extraction, every measured boundary that actually shrinks has
   its budget lowered to the achieved count; test-only gate slices do not
   invent a reduction.
7. The final aggregate is reported against the exact 11,524.5 half-baseline
   reference. Halving is directional, not permission to force unsafe
   extraction.
8. The corrected four-scenario live canary passes after every applicable slice,
   with no busy thread and exactly one `turn_exit` entry for each expected
   completed conversation and interaction generation.
9. `tool/codex_verify.sh --coverage` completes for every slice, and the handoff
   records target-file coverage for each new collaborator. Any numerical
   threshold is enforced by an explicit checked command in that slice.
10. `docs/large_file_refactor_plan.md` records the final counts, exceptions, and
    Tranche 2 status.

## Reference and Warning Notes

- Read `docs/multi_thread_architecture_study.md` before any turn-context or
  high-coupling slice.
- For the pure Slice 1 API shape, use the directly tested
  `GoalCompletionElicitationPrompt` or `WorkflowTaskTurnRoutePolicy` as a
  reference: both are stateless `abstract final` classes with static methods.
- Other directly tested boundaries demonstrate only individual techniques.
  `ProjectScopedToolArgumentResolver` shows a narrow lazy input and
  `PlanningResearchCollector` shows a typed side-effect callback, but their
  callers still require ownership review.
- `ActiveResponseRegistry`, `WorkflowProposalParser`, and
  `PlanningDecisionPromotion` import `chat_state.dart`; they do not satisfy this
  program's strict collaborator contract as written.
- Do **not** use `TurnToolResultLedger` as the finished concurrency pattern while
  it remains a single flat ledger. Its own documentation says interaction-
  generation keying is still required.
- Do not call `TurnCodingProjectResolver.effective` from turn-scoped code; it
  intentionally retains a visible-conversation fallback for UI-scoped callers.
- Do not preserve `prompt_context`'s optional visible-conversation fallback on a
  turn-reachable path merely to keep an extraction mechanical. Characterize the
  callers and stop for a separate behavior fix if explicit ownership would
  change behavior.
- Do not fix adjacent findings inside an extraction. Record them and create a
  follow-up task.
- Never use whole-file checkout or another destructive rollback to undo a
  partial edit in a dirty file.
- All code, comments, docs, commit messages, and PR text must be English.
  Commits and PR titles use Conventional Commits, imperative subjects no longer
  than 72 characters, no trailing period, and no AI attribution.

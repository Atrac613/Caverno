# Anabasis Roadmap

Scope, acceptance criteria, and dated evidence for this track.
[Cross-track priorities](roadmap.md#active-focus) remain in the main
roadmap; dated investigation notes below preserve the implementation history.

## Anabasis Orchestrator Track

The 2026-09-04 build of ANA0-ANA3 is narrated in
`docs/anabasis_orchestrator_build_2026-09-04.md`: the three decisions settled by
live measurement, the two defects only the running app found, and the
extractions the ratchet asked for. It exists because that work was squashed
into one commit.

Anabasis is a parent orchestrator over Caverno's existing Goal, Plan,
provenance, subagent, and verification machinery — not a second coding agent
and not a fourth authoritative conversation state. The full design, including
the Existing Caverno Mapping that decides what may be built, is in
`docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`. The concept and naming reference
is `docs/anabasis_brand_story.md`; the superseded first plan, kept as the
record of why it was superseded, is `docs/anabasis_mvp_plan_superseded.md`.

These milestones use `ANA<number>` and live here rather than in the Local LLM
roadmap because this is orchestration policy and a user-facing surface, not
local-LLM execution work.

**Track rule, and the reason this track exists as a written design at all:**

> Anabasis reuses existing Caverno state whenever that state already expresses
> the required concept. New authoritative state is introduced only when an
> existing representation is demonstrably insufficient.

Three separate design passes each re-derived something Caverno already had
(`AnabasisState` ≈ `ConversationWorkflowSpec`; `AnabasisProjection` ≈
`ExecutionSnapshot`; "generate acceptance criteria" ≈ `acceptanceCriteria`,
already emitted). Check §3 of the design document before adding any type.

### ANA0: Epistemic Grounding

Status: `done`

Scope:
- Confirmation path: record a user's confirmation as a
  `ConversationContractSourceKind.userConfirmedAssumption` source, link it into
  the item's `sourceIds`, then set `confirmed = true`.
- Assumption producer: emit `assumption` / `material` per contract item from
  the planning JSON schema and proposal parsers.
- Parent execution identity and tool authority: `ModelUsageRole.anabasisParent`
  for accounting, an explicit executing-role parameter for authority, and a
  guard restricting the parent to `inspection | verification | delegation`.
- Projection: extend `ExecutionSnapshot` to carry assumption *items* alongside
  `blockingAssumptionCount`. Do not add a new projection class.

Ordering constraint (not negotiable), restated 2026-09-02:
- **A way to unblock lands before the guard is armed.**
  `MaterialContractAssumptionGuard` is already wired into the tool-loop guard
  chain and already refuses mutations while
  `assumption && material && !confirmed`. Arming it without a confirmation
  path refuses every mutation in the conversation permanently while the loop
  burns on verbatim retries.
- The earlier wording said the confirmation path must precede the *producer*.
  That is stricter than the hazard requires and it forced the confirm surface
  to be designed before anyone knew how many material assumptions a real plan
  produces — a number that decides whether the surface is a per-assumption
  approval or a batch review. The producer therefore ships in **shadow**: it
  writes the marks, and the guard is fed an empty blocking list until the
  surface is built to fit the measurement.
- The shadow is now implemented rather than assumed. It was neither, until
  2026-09-03: the feed site in `chat_notifier_tool_loop_batch.dart` read the
  spec's own `blockingAssumptions`, and the guard was unarmed only because no
  producer wrote `assumption: true`. PR 3a ended that without anyone noticing —
  `ContractItemMarks.parseBullet` makes a user typing `(assumed, material)`
  onto a plan-document bullet a producer, so the hazard was already reachable
  one hand-typed bullet away, before PR 3b. Arming now lives in
  `MaterialContractAssumptionArming.armed`, the single place PR 4 changes.

PR split:

| PR | Content | Status |
|---|---|---|
| 1 | Failing canary: confirming a material assumption unblocks mutation | done |
| 2 | Confirmation provenance — the transformation, no caller yet | done |
| 3a | Epistemic marks round-trip through the plan document | done |
| 3a2 | Guard arming stated at one site, so the shadow is implemented rather than accidental | done |
| 3b | Planning prompt emits marks; producer runs in shadow | done |
| 3c | Measure: material assumptions per plan, and how often the model over-asserts | done |
| 3d | Marks are for what the plan asserts: restrict the marker by item kind, enforce it centrally, report marks by kind, re-measure | done |
| 3e | Define materiality by consequence rather than by restating the word, and re-measure | done |
| 4a | Room, then the slot: three extractions off ratchet ceilings, `PendingAssumptionConfirmation`, its `ChatState` / `ThreadScopedChatState` projection, the item-text lookup the surface needs, and its compact-surface description | done |
| 4b-1 | Room on the UI side: nine approval sheets leave the chat page library for `ApprovalSheetDispatcher` | done |
| 4b-2 | Confirm surface sized to 3c (**per-assumption approval**, not batch review), guard armed in `MaterialContractAssumptionArming.armed`, and **unskip the canary's reachability assertion** | done |
| 4c | Parent execution identity (`ModelUsageRole.anabasisParent`), the explicit executing-role parameter, and the `inspection \| verification \| delegation` authority guard | done |
| 5a | `ExecutionSnapshot` carries the assumed claims, and the prompt stops describing them with the wrong list | done |
| 5b | Assumed contract items stop rendering as facts, where the user already reads the contract | done |

Supporting decision: the confirm surface is the **approval flow** — the guard
refuses at the moment a mutation is attempted, so a pending interaction raised
there is the only surface with no dead end. A plan-review-only affordance
would leave a blocked run with nowhere to answer. The open question 3c settles
is not *where* but *how many at once*.

Acceptance criteria:
- Confirming a material assumption unblocks mutation end to end.
- A material assumption is detected, marked, and never presented as a fact.
- The parent cannot call a workspace-mutating tool; delegation still works.
- Baseline for every canary is current Caverno, not a plain chat session.

Verification evidence:
- PR 1: `anabasis_assumption_confirmation_canary_test.dart` — 4 passing (the
  guard's existing block/unblock semantics and the confirmation's provenance
  shape) and 1 failing by design. The first version of that canary asserted
  only that some production file *mentions* `userConfirmedAssumption`, and it
  went green the moment the domain transformation existed with no caller
  anywhere — moving the value from "declared and never written" to "written
  and never called". It now asserts a caller as well, which is the weakest
  honest proxy for reachability a source scan can express.
- PR 2: `conversation_contract_provenance_confirmation_test.dart` — the three
  steps, guard unblocking end to end, idempotence, and a recorded limitation:
  `attachApprovedPlanSource` rebuilds provenance wholesale, so a re-approved
  plan starts from unconfirmed.
- Extraction: `chat_state.dart` sat at its ratchet ceiling with no margin, so
  the eleventh pending type could not be added without raising a budget the
  ratchet forbids raising. `PendingToolApproval` and its hierarchy moved to
  `pending_tool_approvals.dart` (684 lines to 162, re-exported, no importer
  changed), with a declared budget on the destination.
- PR 3a: `contract_item_marks_round_trip_test.dart` — marks survive build and
  projection, unmarked documents project exactly as before, a hand-typed
  marker is honoured, and marking never changes an item's `itemId`.
- PR 3a2: `anabasis_assumption_confirmation_canary_test.dart` gains a shadow
  group — a spec whose item does block is still handed an empty armed list,
  and the feed site no longer names `blockingAssumptions` at all. The second
  assertion is a source scan because the failure it guards is a one-line
  reversion at a single call site, and a behavioural test of the tool loop
  would not fail on it while the list stays empty for want of a producer.
- PR 3b: `anabasis_planning_prompt_marks_test.dart` — the proposal prompt, in
  both its full and compact forms, teaches a marker that
  `ContractItemMarks.parseBullet` actually accepts. The test reads the quoted
  marker forms back out of the generated prompt instead of restating them,
  because the two halves are string literals in different files and nothing
  else relates them. It also pins the marker to English while the fields around
  it are translated: `parseBullet` matches `assumed`/`material` and nothing
  else, so a translated marker is silently dropped.
- PR 3b, second defect found while building it: the planning prompt echoes the
  saved contract back before a revision, and that echo listed constraints,
  acceptance criteria, and open questions without their marks. A revision was
  therefore shown a contract in which nothing had ever been assumed, and would
  have laundered every assumption into a fact on the next pass — measured in
  PR 3c as the model declining to mark. The echo now renders marks through
  `ConversationPlanDocumentBuilder.markerFor`.
- PR 3b keeps the proposal JSON schema unchanged: the marker rides inside the
  item string and becomes a mark only in the plan document, which is the
  authoritative middle. Weak local models lose structured-output fidelity when
  a schema grows, and the round trip already existed.
- PR 3c instrument: `tool/ana0_assumption_marking_measurement.dart` plus
  `test/tool/ana0_assumption_marking_measurement_test.dart`. Six scenarios run
  in paired arms — `ungrounded` omits one load-bearing fact, `grounded` adds one
  message stating it, and nothing else differs. A constraint restating that fact
  is an assumption in the first arm and a fact in the second *by construction*,
  so an unmarked ungrounded plan is an over-assertion and a marked grounded plan
  is an over-mark, with no heuristic reading the model's prose to decide which.
  Scoring runs the production path: real prompt, real proposal parser, real plan
  document, real projection, marks counted off provenance.
- PR 3c instrument, verified before it is believed: 13 scripted-response tests
  fix the verdict for each case in advance, including the two that decide
  whether a number is honest — a response that is not a proposal is recorded
  `unparsed` rather than scored as a plan that marked nothing, and a transport
  failure is likewise never read as a model that declined to mark. A run that
  reached nothing must not look like a measurement.
- PR 3c result, `qwen3.8-27b-vision`, 36 requests, 18 per arm, 0 unparsed:

  | | ungrounded | grounded |
  |---|---|---|
  | material assumptions / plan | 0.28 | 0.06 |
  | assumption marks / plan | 0.78 | 0.22 |
  | open questions / plan | 2.17 | 2.50 |

  Over-assertion — a plan that neither marked anything nor asked anything — is
  1 in 18. Over-marking is 1 in 18. The +0.22 aggregate discrimination these
  averages show does not survive the by-kind breakdown recorded below; read
  that before using this table.
- **PR 4's surface question is answered: a per-assumption approval, not a batch
  review.** The per-plan distribution of material assumptions is 0 in 14 plans,
  1 in 3, and 2 in 1; grounded is 0 in 17 and 1 in 1. No plan produced more
  than two. A batch review is a surface for a list, and the measured list is
  zero, one or two items.
- **Correction, same day, from breaking the marks down by item kind — PR 4 is
  not ready to arm the guard.** Of the 14 marks the ungrounded arm produced,
  seven land on `openQuestions`, and four of the five *material* ones do. "An
  open question I am assuming" is not a coherent claim, and
  `ConversationContractItemProvenance.blocksExecution` does not look at `kind`,
  so arming the guard today would refuse mutations because of marked
  *questions*. On constraints — the only kind where the mark means what ANA0
  means by it — the arms are identical at 3 of 18 each, with one material mark
  on either side. The headline +0.22 discrimination was carried almost entirely
  by marked open questions; on constraints it is zero.

  | ungrounded marks | total | material |
  |---|---|---|
  | constraints | 5 | 1 |
  | acceptanceCriteria | 2 | 0 |
  | openQuestions | 7 | 4 |

  This was invisible in the summary because the instrument counts marks without
  their kind. It is the same failure as the two metric defects above, one level
  down: an aggregate that cannot express the distinction it is being asked
  about.
- The reason the model marks so little is visible in the responses and is not a
  capability limit: it routes unknowns into `openQuestions`, at roughly 2.2–2.5
  per plan, because the same prompt tells it to. The marker and that rule
  compete for the same content. This is a prompt-design question for PR 4, not
  a defect: an open question does not block execution and a material mark does,
  so which one the model reaches for decides whether the guard ever fires.
- Three transport and metric defects were found by running it, each by reading
  evidence rather than by reasoning about it:
  1. llama.cpp (b10523) answers a *chunked* request body with HTTP 500
     "attempting to parse an empty input". Dart's `HttpClient` chunks any body
     written without an explicit `contentLength`. Confirmed by an A/B with curl
     on the same body. Five other `tool/` measurement scripts still send
     chunked bodies and would fail the same way.
  2. The first over-assertion metric counted every unmarked ungrounded plan and
     scored 6 of 6. Reading the raw responses showed it was measuring the
     prompt's own "if important information is missing, use openQuestions"
     rule. A plan that asks about a fact has not asserted it.
  3. The corrected metric still required a *material* mark, and then flagged a
     plan that had marked three items as assumptions without calling any
     material. Marking non-materially is a claim about consequence, not about
     knowledge. With any mark counted as disposal, over-assertion is 1/18
     rather than 2/18.
- PR 3d result, same 36 requests, same model, 0 unparsed. Restricting the
  marker to what the plan asserts did not merely stop the miscounting — it
  moved the model:

  | | 3c | 3d |
  |---|---|---|
  | marks on open questions (both arms) | 8 | **0** |
  | marks on constraints, ungrounded | 5 | **24** |
  | marks on constraints, grounded | 3 | 7 |
  | ungrounded plans with any assumption mark | 3/18 | **12/18** |
  | grounded plans with any assumption mark | 3/18 | 3/18 |

  Plan-level discrimination is now 67% against 17%, where 3c had 3 of 18 on
  both sides. Telling the model where a mark *means* something did not
  redistribute a fixed budget of marks; it produced five times as many in the
  arm that should have them and left the other arm alone.
- **The weak link has moved to materiality, and that is what gates blocking.**
  Only `assumption && material && !confirmed` blocks, and material marks run
  28% ungrounded against 11% grounded — 2.5x, against 4x for marks overall. One
  grounded plan produced three material marks. So a guard armed on materiality
  today fires on a signal noticeably noisier than the one the model actually
  produces well. PR 4 has to decide deliberately whether it blocks on
  `material` or on `assumption`, and the answer is not free either way: the
  first under-fires and mis-fires, the second blocks roughly two thirds of
  ungrounded plans.
- Surface sizing is unchanged by 3d: at most three material assumptions in a
  plan, zero in 13 of 18 ungrounded plans. Still a per-assumption approval.
- PR 3e answers the question 3d opened, and reverses its worry. The old rule
  said to write `(assumed, material)` "when the plan would change materially" —
  a definition that restates the term. It now names the consequence: material
  when being wrong would make work done under the plan have to be **thrown away
  rather than adjusted** — a different architecture, data model, dependency or
  task set — and plain `(assumed)` when only a value, a detail or an ordering
  would change.

  | | 3d | 3e |
  |---|---|---|
  | material marks per plan, ungrounded | 0.33 | **0.56** |
  | material marks per plan, grounded | 0.28 | **0.11** |
  | material discrimination | +0.06 | **+0.44** |
  | plans with a material mark, ungrounded / grounded | 28% / 11% | **33% / 6%** |
  | over-mark | 2/18 | 1/18 |
  | over-assertion | 1/18 | **0/18** |

  **Materiality is no longer the weak link; it is now the strongest signal.**
  It separates the arms six to one, where marks overall separate under two to
  one — the grounded arm's plain-`(assumed)` rate rose to 44% once the two
  forms were distinguished, which costs nothing because a plain mark does not
  block. So the guard should block on `material`, and the decision PR 4 was
  going to have to make on judgement is settled by measurement instead.
- Both 3d and 3e reproduce the same lesson at the prompt level: the model was
  not failing at epistemics, it was being asked in terms it could not check.
  Naming where a mark belongs multiplied marks fivefold; naming what
  materiality costs multiplied its discrimination sevenfold. Neither change
  touched the model, the schema, or the parser.
- Evidence: `build/ana0/marking_3e.json` and `build/ana0/raw3e/`.
- Evidence: `build/ana0/marking_3d.json` and `build/ana0/raw3d/`, against
  `build/ana0/marking_r3.json` plus the raw responses under
  `build/ana0/raw3/`. Re-run with
  `fvm dart run tool/ana0_assumption_marking_measurement.dart --endpoint
  http://<host>:1234/v1/chat/completions --model <id> --repeats 3
  --out build/ana0/marking.json --dump-dir build/ana0/raw`.
- PR 4a: `pending_assumption_confirmation_slot_test.dart` and
  `conversation_contract_item_value_lookup_test.dart`, plus two cases in
  `pending_approval_summary_test.dart`. The slot is asserted where it can be
  lost silently: a confirmation raised on a background thread survives the
  stash and lists the thread as waiting, a late answer does not blank a
  successor's slot, an expired turn cancels to `false` rather than confirming,
  and the registry answers it by id from outside its thread. The item-text
  lookup is pinned to the same id definition the forward derivation uses,
  because two definitions would show the wrong item's text under the right
  item's question.
- PR 4a: three files sat *exactly* at their ratchet ceilings, so the eleventh
  pending type cost three extractions before it cost a line of its own:
  the outstanding-approval registry (`pending_tool_approval_registry.dart`),
  `PendingAskUserQuestion` (`pending_ask_user_question.dart`, never part of the
  sealed hierarchy), and the per-type clear dispatch
  (`pending_tool_approval_projection.dart`, which grows once per pending type
  and so does not belong in a class about what a thread stashes). All three are
  re-exported, so no importer changed.
- PR 4a, found by the compiler rather than by reading: `PendingToolApproval` is
  sealed and `describePendingApproval` switches exhaustively over it, so the
  new type could not be added without declaring how it appears on the Watch and
  in notifications. That is the design working — a new approval kind cannot
  silently fail to reach a compact surface — and it is why the type carries
  `origin` / `remoteDeviceId` from the start: SEC4.5g's ownership gate reads
  them, and a type lacking them cannot be filtered.
- **PR 4b is bigger than its diff will look, for two reasons found in 4a and
  not in the earlier scoping.** First, the `chat_notifier.dart` library
  aggregate is at 19,827 of 19,829: there are two lines of margin in the
  whole library, so the resolve handler and the ask site need an offsetting
  extraction before they can be written. The chat page library was in the same
  state — 8,800 of 8,800, no margin at all — which PR 4b-1 cleared. Second, the obvious write-back,
  `updateCurrentWorkflow(preserveWorkflowProjection: true)`, appears able to
  *discard* the confirmation: `shouldPreserveProjectedTasks` replaces the
  requested spec with the conversation's own whenever the plan document is
  preferred, execution task views exist, and the requested spec has no tasks.
  **Checked in 4b-2 and it cannot fire here**, which is worth recording because
  the branch reads as if it can: `executionTaskViews` is derived from
  `effectiveWorkflowSpec.tasks`, and a confirmation is the current spec with
  two provenance lists replaced, so "the conversation has tasks" and "the
  requested spec has none" are mutually exclusive for this caller. That also
  means `ConversationsNotifier` — itself at 1,791 of 1,791 — needs no new
  method.
- PR 4b-1: nine `_show*Dialog` methods were nine copies of the same four steps
  — show the sheet, check `mounted`, read the notifier, resolve by id — sitting
  inside a library with no margin, so each new approval kind paid for a copy in
  the place that could least afford one. They are now methods on
  `ApprovalSheetDispatcher`, an independent file with its own budget, and the
  page pays only for the listener that routes to one. The library drops from
  8,800 to 8,670, ten of which are left as a stated margin so the eleventh
  approval's listener does not have to re-extract. The workflow-decision and
  ask-user-question sheets stay behind on purpose: their sheet widgets are
  private to the chat page library and cannot be named from outside it.
- **What PR 4b-2 still needs, measured rather than estimated.** In the notifier
  library the ask site is roughly neutral — moving the arming read and the
  guard call into a collaborator removes about as much as the call adds — so
  what needs room is the raise method and its `resolve` pair, about 18 lines
  against 2 available. `_ChatNotifierSshPorts` is the obvious candidate to move
  out and is not yet eligible: it reaches four private notifier members
  (`_settings`, `_expiredApproval`, `_resolveToolApprovalGate`,
  `_buildAutoReviewRequest`) and would need a seam for them first.
- PR 4b-2 closes ANA0's first acceptance criterion end to end: a material
  assumption is raised as `PendingAssumptionConfirmation` at the guard's
  refusal site, answered in `AssumptionConfirmationSheet`, recorded through
  `confirmMaterialAssumption`, and the same tool call then proceeds.
  `MaterialContractAssumptionArming.armed` returns the spec's blocking
  assumptions, and **the canary's reachability assertion is unskipped** — the
  file that has carried a deliberate skip since PR 1 now runs all eight.
- PR 4b-2's mechanism is `MaterialAssumptionConfirmationGate`, and three of its
  properties are specified rather than discovered, each pinned by a test:
  the blocking list is read **per call** (a confirmation answered mid-batch, or
  on the watch, has to reach the next call in that batch); an item is asked
  about **at most once per gate** (a confirmation that fails to clear its item
  must refuse rather than reopen the dialog forever); and declining **refuses**
  rather than deferring or confirming.
- PR 4b-2's canary change replaces a shadow-era assertion with its successor.
  "The feed site goes through the arming policy" was the right invariant while
  `armed` returned nothing; now that it returns the real list, the invariant
  that carries the same hazard is that the loop evaluates through the gate,
  which asks, and never calls the guard directly, which can only refuse.
- **What the ratchet cost, recorded because it is the honest size of the
  slice.** The feature is 63 lines inside the notifier library, which had 2.
  The `run_tests` command spelling left first (six pure functions, ~96 lines),
  and that still was not enough once the gate wiring landed, so how a
  computer-use action is redacted and described left too (six more, ~84 lines).
  Both are now independently testable, which the `run_tests` path had never
  been. The chat page library was paid for in 4b-1.
- PR 4b-2 follow-up, because the canary's own comment calls its reachability
  assertion "the weakest honest proxy a source scan can express":
  `chat_notifier_assumption_confirmation_part.dart` drives the wiring through
  the real notifier — the loop refuses, the confirmation is raised as a pending
  approval, the answer is given by id the way the sheet gives it, and the same
  call is re-evaluated. Two of the three tests hung on the first run, which is
  the finding: a confirmed `write_file` reaches **its own** approval, so the
  proof that the assumption gate stopped holding the call is that a second gate
  now holds it. That is asserted rather than worked around.
- PR 4b-2 registers `material_assumption_confirmation` in
  `tool/check_fix_firings.py`. It reports *not yet observed, 0 logs on a build
  that could produce it*, which is the honest state: ANA0 has measured the
  model marking assumptions (3c/3d/3e) and has never observed a real turn being
  held by one. The refusal code is the half that reaches a session log; the
  answer arrives through an approval, not a model request.
- PR 5a found the defect it was meant to prevent, already shipped. The prompt
  line "Material assumptions requiring user confirmation" rendered
  `clarificationQuestions` — a set unioning unresolved open questions *with*
  assumption questions, then sampled head-and-tail to three. With three open
  questions the line could name none of the assumptions while claiming to list
  them. `ExecutionSnapshot` now carries the assumed **claims**, resolved
  through `itemValueFor`, and the two lists are rendered separately; a blocked
  contract also stops hiding its open questions, which the old `else if` did.
- PR 5a, second finding, from splitting the lists: the snapshot's `action`
  silently became `execute` for a contract blocked on an assumption, because
  `_actionFor` read the conflated count. Blocking assumptions are now a named
  input to that decision rather than an inflated question count, and
  `toRedactedLogSummary` reports `assumptions=` beside `questions=` so the two
  can be told apart in a session log.
- PR 5a also corrects an instruction that 4b-2 made false. The guard's
  `required_action` told the model to "ask the user this one focused
  clarification question and wait" — but this payload now only reaches the
  model *after* the user has been asked and has not confirmed, so it sent the
  model back to re-ask a question the user had just declined. It now says not
  to mutate, and to investigate or say what it needs. The prompt context lost
  its parallel "ask one focused clarification question" for the same reason:
  asking the model to run a mechanism the app runs is the humility instruction
  this track exists to replace.
- PR 5b is deliberately **not** the panel the milestone sketched. ANA0's track
  rule is to reuse the representation that already expresses the concept, and
  "what is this plan assuming?" is answered by the constraint list the user is
  already reading — which rendered every item as an identical plain bullet, so
  the one surface where the distinction had to survive was the one place it did
  not. `ContractItemListSection` replaces the page's private list builder at
  all nine call sites and marks an assumed item three ways: blocking,
  confirmed, or plain `(assumed)`. A separate panel would have added a second
  place to read the same contract, and left the first one lying.
- PR 5b marks constraints and acceptance criteria only. Open questions keep
  plain bullets, which is PR 3d's rule (`marksApplyTo`) reaching the UI: asking
  about something already says you do not know it.
- PR 5b paid for itself: deleting the shared private builder took the chat page
  library from 8,678 to 8,645, and the widget carries its own budget. The
  primary file's ceiling moves 1,853 → 1,854 for the import, and that is worth
  naming as a mistake rather than a rule change: 1,853 was tightened mid-
  milestone in 4b-1, one commit before the import it had to accommodate. The
  same thing happened to `approval_sheet_dispatcher.dart` (145 → 159). Set a
  new file's budget when the milestone using it is finished, not at its
  halfway line.
- PR 4c closes ANA0's last acceptance criterion, deliberately **before** the
  parent has an execution path: the design's own instruction is to enforce the
  boundary from MVP 0, because retrofitting one after the parent has learned to
  edit is much harder than starting with it closed. `AnabasisParentAuthorityGuard`
  refuses anything that is not `inspection`, `verification`, or a delegation
  tool, as a structured `McpToolResult` rather than a throw — a throw ends the
  turn and leaves the call unexecuted, which is the wrong shape for a policy.
- PR 4c takes the executing role as an **explicit argument**. `ModelUsageRole`
  is added for accounting, but it is ambient and defaults to `unknown`: for
  accounting an unclaimed path showing up as a gap is useful, while for
  authority a missed `runWith` would silently drop the parent out of its own
  restrictions. The tool loop reads the ambient value once and hands it down;
  the guards are pure functions of what they are told.
- PR 4c refuses `unknown` effects, where `MaterialContractAssumptionGuard`
  passes them, and the asymmetry is pinned by a test. There a false positive
  blocks ordinary work; here an unclassified tool is not proof of safety.
- PR 4c introduces `TurnToolPolicyChain` so the loop has one entry point rather
  than a growing run of early returns, and **order is policy**: authority is
  evaluated first, because asking the user to confirm an assumption before
  refusing a parent mutation would raise an approval whose answer changes
  nothing — and a confirmation is durable state the user gave for a reason that
  never applied.
- PR 4c is the one place today's work **raised** a ratchet ceiling: the
  notifier library goes 19,733 → 19,737 for the chain's construction and an
  import. Recorded in the ratchet with its reason rather than absorbed by
  trimming a comment or shuffling whitespace. Net for the day is −92; the
  library entered at 19,829. Two attempted offsets were reverted first — one
  moved a queued-message predicate into the domain layer, where the message
  type is not visible, and the layer-safe version of it made the primary file
  *larger* by turning one call site into six lines.
- **PR 4c's guard is no longer unobserved.** `@anabasis` from the shared chat
  is the first of the three entry points §5 names, and it is live: the address
  is parsed, the turn runs in `ModelUsageRole.anabasisParent` through a zone,
  the tool loop reads that role, and the authority guard refuses the mutation
  there. `chat_notifier_assumption_confirmation_part.dart` asserts it end to
  end without naming the guard — if the wiring is wrong, the write simply
  happens.
- The address is **parsed, not inferred**: `@anabasis` at the start of a
  message, as a whole word. "ask @anabasis about it" is a message to the
  assistant *about* the parent and is not routed to it. Nothing is being
  decided from prose, which is the line the heuristic-removal track draws.
- **A guard without a prompt block is a dead end**, so the block ships with the
  entry point. A model told nothing reads a structured refusal as a transient
  failure and retries — the loop ANA0's ordering constraint exists to prevent.
  The block names delegation as the route out, not only what is forbidden, and
  it states that a child reporting success means `produced` rather than
  `accepted`.
- The zone is ambient on purpose and only carries *prose*: the guard still
  takes the role as an explicit argument. A missed zone therefore costs the
  parent its instructions — a confused turn — and can never cost it its
  restrictions. A test pins the role reaching an async continuation, since the
  tool loop reads it several awaits into the turn.
- Full suite green with **no skips**; `flutter analyze` clean.
- Full suite green apart from the canary; `flutter analyze` clean.

Next action:
- PR 4c: parent execution identity (`ModelUsageRole.anabasisParent`), the
  explicit executing-role parameter, and the authority guard restricting the
  parent to `inspection | verification | delegation`. None of it exists yet,
  and it is the last of ANA0's acceptance criteria still open.
- Then PR 5: the `ExecutionSnapshot` extension and the Understanding panel.
- The decision PR 4b-2 shipped on, for the record: **block on `material`**,
  which `blocksExecution` already does. It separates the arms six to one and
  mis-fires once in eighteen grounded plans.
- The confirm surface is a **per-assumption approval** on the existing
  `PendingToolApproval` hierarchy. `PendingAssumptionConfirmation` and its
  projection landed in PR 4a; what remains is raising it from the guard's
  refusal site in `chat_notifier_tool_loop_batch.dart` and resolving it into
  `confirmMaterialAssumption`. The approval flow is the only surface with no
  dead end, and the registry answers by id from outside the thread, so a
  blocked background turn is not stranded. Sizing: at most three material
  assumptions in a plan, none in 12 of 18.

  Scoped 2026-09-03, with the obstacles named so PR 4 is not mistaken for a
  small change:
  - ~~`pending_tool_approvals.dart` (527) and `thread_scoped_chat_state.dart`
    (238) are both **exactly at their ratchet ceilings**~~ — cleared in PR 4a,
    which also found `chat_state.dart` (162) at its own ceiling and the
    `chat_notifier.dart` library one line under its aggregate.
  - The guard's blocking list is captured **once per batch**
    (`ownerBlockingAssumptions`). A confirmation mid-batch does not clear it,
    so it has to become a per-call read of current conversation state, and the
    ask-then-re-evaluate loop needs an itemId seen-set so a confirmation that
    fails to clear an item cannot spin.
  - The write-back is `ConversationsNotifier.updateCurrentWorkflow`, which
    resets `workflowSourceHash` and `workflowDerivedAt` unless
    `preserveWorkflowProjection` is set. A confirmation must preserve both; it
    changes provenance, not the plan.
  - The `execute:` closure the guard runs inside is already `async`, so the ask
    can be awaited there — but every await needs the
    `_isCurrentInteractionGeneration` check the surrounding loop uses.
- ~~Arm `MaterialContractAssumptionArming.armed` and unskip the canary's
  reachability assertion **only once a human can answer the approval in the
  app**~~ — honoured: 4b-2 landed the sheet, the arming and the unskip in one
  commit, so the guard was never armed without a way to answer it.

### ANA1: Decompose

Status: `done`

Scope:
- Precondition edges on `ConversationWorkflowTask`, covering all three blocking
  shapes: task accepted, assumption confirmed, question resolved.
- A derived `ready` predicate. Never stored — the graph determines it, and
  storing it would add a second writer.
- Decomposition rendered but not executed.

This is the first substantially new implementation in the track: no dependency
or precondition field exists on `ConversationWorkflowTask`,
`WorktreeAgentTask`, or `SubagentTask` today.

PR split:

| PR | Content | Status |
|---|---|---|
| 1 | Precondition edges on `ConversationWorkflowTask` and the derived readiness predicate | done |
| 2a | The plan document round-trips preconditions, including hand-typed ones | done |
| 2b | Measure which channel the model writes an edge through | done |
| 2c | Ship the measured channel: the task schema carries `preconditions` | done |
| 3 | Decomposition rendered — a task says what it is waiting on | done |

Verification evidence:
- PR 1: `conversation_task_readiness_test.dart` and two cases in
  `conversation_workflow_test.dart`. `ConversationTaskPrecondition` carries a
  kind and a ref; `ConversationTaskReadinessResolver` derives readiness and
  returns the *unmet* edges rather than a boolean, because every consumer has
  to explain itself — a scheduler that only knew "not ready" would have nothing
  to tell the user when nothing moves.
- PR 1 resolves each kind against state that already exists: task status plus
  its validation evidence, `ConversationContractItemProvenance.confirmed`, and
  `ConversationOpenQuestionStatus.resolved`. Nothing is stored, so no second
  writer can disagree with the graph.
- PR 1's one judgement call, made conservatively: the lifecycle wants
  `accepted` for a task precondition and no status enum has it — `completed`
  conflates produced, verified and accepted until ANA3 separates them. So a
  task that *declares* a validation command must also have passed it. Reading
  the lenient of two notions of "verified" is a mistake this codebase has
  already paid for once.
- PR 1: an edge pointing at something absent is **unmet**, never vacuously
  satisfied, for all three kinds. A malformed plan must not run work it said
  depended on something.
- PR 1 defect found by its own persistence test: freezed's generated `toJson`
  emitted the nested precondition objects raw, so a saved task could not be
  read back. The file's own established pattern — an explicit
  `@JsonKey(fromJson:, toJson:)` converter pair, as `sources` and `provenance`
  already use — fixes it. Every conversation on disk predates this field, and
  the test that loads a task without a `preconditions` key is what keeps the
  migration to none.

- PR 2a: `task_precondition_round_trip_test.dart`. Each edge is its own
  `- Requires: <kind>: <ref>` line rather than a comma list, because a question
  is referenced by its own text and may contain a comma; only the first colon
  separates kind from reference, because an assumption is referenced by a
  contract item id that is itself `constraint:<hash>`.
- PR 2a's one deliberate asymmetry with the rest of the parser: an unreadable
  `Requires:` line is **dropped, not fatal**. Every other task detail is
  something the plan states about itself and an unknown one is an error; this
  one is optional, and a misspelled kind must cost the edge rather than the
  user's whole document. It stays visible as prose in the markdown either way.
- PR 2a covers the hand-typed case, as ANA0 PR 3a did for epistemic markers:
  the plan document is a surface the user edits, so what they can type into it
  is part of the contract.

#### PR 2b measurement (2026-09-04)

Instrument: `tool/ana1_precondition_channel_measurement.dart` with 15
scripted-response tests fixing each verdict before any number was believed.
Three arms differing only in one instruction appended to the production task
prompt — `none` (control), `title` (`[requires: <kind>: <ref>]` in the task
title, ANA0 PR 3b's shape), `schema` (a `preconditions` array per task).
`qwen3.8-27b-vision`, temperature 0.7, 4 scenarios, 3 repeats, 36 requests.

| arm | parsed | tasks | edges | resolved | plans with an edge | edges/task |
|---|---|---|---|---|---|---|
| none | 12/12 | 68 | 0 | 0 | 0/12 | 0.00 |
| title | 12/12 | 67 | 43 | 43 | 11/12 | 0.64 |
| schema | 12/12 | 65 | **69** | **69** | 11/12 | **1.06** |

**The reason ANA0 kept its marker out of the JSON schema does not reproduce
here.** PR 3b's stated rationale was that a growing schema costs weak local
models their structured-output fidelity; the schema arm parsed 12 of 12,
exactly like the other two. So the choice is settled by what the channels
produce rather than by inheriting that judgement: schema yields 1.06 edges per
task against title's 0.64, and **every edge in both arms resolved** — 43 of 43
and 69 of 69 named a task or a contract item the plan actually contains.

**The control is the finding that matters most.** It wrote no edges, as it
must — but in 6 of 12 responses it described the ordering in prose anyway. The
model already knows what depends on what; without a channel it spends that
knowledge on text nothing can read. That is the same shape as ANA0 3c, where
the model routed unknowns into `openQuestions` because the prompt gave it
nowhere else to put them.

**Instrument defect, found by reading raw responses rather than the counts.**
The first run scored 12 of 12 unparseable and would have read as a model that
refuses to write edges. The *proposal* prompt returns `kind: decision` and no
tasks at all — tasks are drafted in a second phase against an approved
contract, so an edge had nowhere to live in what was being measured. The
scenarios now carry an approved contract and the measurement runs
`buildTaskProposalRequest`. Edge references resolve against *that* contract,
not against text the same response invented.

**Scope, stated rather than implied.** This measures whether a channel works —
edges written, references that resolve, proposals still parseable. It does not
score over-generation: 69 edges across 65 tasks is close to one per task, and
whether that is a graph or a reflex needs a fixture with a known-correct
answer. Evidence: `build/ana1/channel_r3.json` and `build/ana1/raw_r3/`.

- PR 2c: `TaskPreconditionParsing` reads the array, `TaskProposalParser` puts
  it on the task, and the task prompt's schema line teaches it. Tolerant on the
  way in for the reasons every parser here is — a synonym key, an entry
  flattened into `"task: Audit the model"` — and an unreadable entry costs the
  edge rather than the task.
- PR 2c: the measurement instrument now reads edges *through* the production
  extractor, so the extractor that chose the channel is the one that ships and
  a later change to it cannot quietly make the measurement unreproducible. Its
  15 scripted tests still pass against production code.
- PR 2c pins prompt and parser together by reading the kinds back out of the
  generated prompt, as ANA0 PR 3b's marker test does: the two are string
  literals in different files and nothing else relates them. A kind the parser
  supports but the prompt never mentions is an edge the model will not know it
  may write.

- PR 3: `TaskPreconditionNotice` renders the **unmet** edges under the task
  card, not a "not ready" flag. Two of the three kinds — an unconfirmed
  assumption, an unanswered question — are things the user can clear
  themselves, so naming which one is missing is what makes the row actionable
  rather than merely informative. Readiness stays derived; nothing is stored.
- PR 3 paid for its five lines in the task card by extracting the task menu,
  which is a pure function of a status and two permissions, to
  `workflow_task_menu_items.dart`. The chat page library goes 8,645 → 8,607.
  The primary file's ceiling moves 1,854 → 1,857 for three widget imports:
  that file grows by one line per widget the page renders, and forcing an
  extraction to avoid it would only move an import somewhere it does not
  belong.

Next action:
- ANA1 is complete. ANA2 next, or the over-generation measurement below.
- Not measured, and worth measuring once real plans carry edges: whether the
  model **over**-generates them. 69 edges across 65 tasks is close to one
  apiece, and telling a graph from a reflex needs a fixture with a
  known-correct answer. The producer question is which
  channel the model writes an edge through, and the honest answer is not
  Open question still to answer before ANA2: how a child inherits the parent's
  confirmed assumptions as premises without re-sending the contract.

#### A task edge could never resolve (2026-09-05, session `6a5d42a0`)

The first session with a real plan behind it — plan mode on, a new thread,
`stage=plan tasks=1` becoming `stage=implement tasks=4`, progress running
0→1→2→3. The model wrote the edges: four tasks, three `task` edges, a clean
serial chain. And not one of them could ever be satisfied.

- The planning prompt asks for `{"kind":"task","ref":<the other task's
  title>}`, and it has to: `TaskProposalParser` mints `id: _createId()` *after*
  the model has answered, so a proposal can only reference ids it invented. The
  model complied exactly. `_isTaskDone` then compared that title to `task.id`,
  a UUID.
- `assumption` was broken the same way — the prompt asks for the constraint's
  text, the resolver compared it to `itemId`, which is a hash *of* that text.
  Only `question` was ever right, and only because it alone compared text to
  text.
- The snapshot shows it plainly: `Saved task progress: 3 of 4 completed` with
  all three dependents still under `Tasks not ready`, each waiting on work that
  had already finished.
- **This is why the delegation queue was empty in all three sessions.**
  `TaskDelegationBriefBuilder.candidates` gates on readiness, so the queue
  could only ever hold tasks with no preconditions — writing an edge made a
  task *less* delegatable, which inverts what ANA1 was built for. The two
  earlier sessions had `totalTaskCount: 0` and hid it behind a second cause.
- Every readiness test passed throughout, because each one hand-writes a ref
  that matches a hand-written id (`ref: 'inspect-model'`). Real ids are UUIDs
  and real refs are prose, so the fixtures agree with each other and with
  nothing else. [[caverno-canary-harness-blindness]] again, in the layer the
  measurement was reading.
- Fixed by resolving a ref through `ConversationTaskPreconditionRefs`: id
  first, then exact trimmed text, with the id form kept for edges typed by hand
  against an existing plan. No fuzzy matching — two tasks sharing a title
  resolve to neither, on the same reasoning that makes an edge pointing nowhere
  unmet. The premise lookup moved onto the same resolver, so the brief builder
  and the readiness predicate cannot drift apart.
- Worth noting what found it: not a failing test, and not the queue being empty
  — that had been explained away twice. It was reading `Tasks not ready` in a
  logged prompt against `3 of 4 completed` in the same snapshot.

### ANA2: Delegate

Status: `done`

Current summary (2026-09-13): the policy and live ready-queue baseline is
complete. The worktree runner choice is defined but not dispatched by the
parent; the acceptance handler still audits subagent results only. This
integration limit is recorded under ANA3 and is not covered by the successful
queue observation. Earlier references below to a remaining queue observation
are historical; the 2026-09-12 canary closed that evidence gap.

Integration regression added after `012ee320b`:
`test/features/chat/domain/services/parsed_plan_delegation_test.dart` feeds
model-shaped JSON through the production parser with generated UUIDs, then
checks readiness through the delegation builder and execution snapshot. It
covers verified dependency completion, confirmed premise transmission,
unconfirmed assumptions, and ambiguous task titles. It does not replace the
remaining live planned-parent queue observation.

Verification: `tool/codex_verify.sh --no-codegen` with focused targets
`parsed_plan_delegation_test.dart`, `conversation_task_readiness_test.dart`,
and `task_delegation_brief_builder_test.dart` passed all 32 tests on 2026-09-05;
application and workspace-package static analysis also passed. Adjacent review
covered reference resolution in the readiness resolver, delegation brief
builder, and snapshot projector. The parser removes duplicate titles, so the
ambiguity regression models a subsequent plan edit.

Live session `bc715399-444c-4688-8039-3e9287e942b3` then exposed a separate
false recovery. A foreground child ran a command successfully, but
`spawn_subagent` returned only its prose summary, so the parent command-claim
guard requested another execution. The synchronous delegation result now
projects a successful exit only when the child runner observed a structured
successful command outcome. A completed status, summary text, absent outcome,
or failing exit remains insufficient. Focused claim, retry-policy, and
foreground-delegation tests pass, together with the notifier line-count and
tool-result-origin gates. The same session crossed into the next saved task,
so a clean single-task live rerun was still required before closing ANA2.

Live session `727c85d3-d279-453c-9522-ee46e0f51cb9` confirmed that the
structured child exit now reaches both `spawn_subagent` results and prevents
the false command-action retry. It also exposed a planning-parser defect: a
proposal truncated during a later task contained a complete earlier
`validationCommand`, but loose JSON recovery treated the command's escaped
quote as the end of the field and saved `python3 -c \\`. Loose scalar recovery
now decodes escaped JSON strings and declines unterminated quoted fields, with
utility-level and task-parser regressions covering both boundaries. One live
rerun remains before ANA2 closes because the malformed saved command prevented
the session from validating its first task cleanly.

Session `1aac111f-63ae-4bdb-99fc-c01d6a990de4` exposed a separate incomplete
plan: task generation hit `length` during the second task, and prefix recovery
published only two tasks, omitting the requested unittest work. Task generation
now checks truncation before parsing and retries without retaining that prefix
as a review candidate. Exhausted attempts use the existing requirement-based
fallback. A notifier regression covers all three truncated attempts. This run
invoked Anabasis only after both saved tasks completed and made no child calls,
so it does not close the planned delegation observation.

Corpus measurement 2026-09-11, over 191 session logs: the admission gate has
never been exercised, which is not the same as failing. Twelve sessions carry
the Anabasis parent prompt; two rendered a non-empty ready queue
(`bc715399`, five subagent candidates; `727c85d3`, two worktree candidates),
and both predate the gate. No log carries the `workflow_task_id` instruction
line, so no parent turn has run on a build that could consult the queue by id,
and neither the refusal nor the acceptance has appeared. The two live queues
show bare titles because `[workflow_task_id: ...]` was added with the gate in
`8102fab48`, and show no premises because those tasks had none — neither is a
projection defect.

Where the queue was empty is also accounted for, and it bounds when a live run
can be attempted. Both parent sessions predating the ANA1 precondition fix
(`012ee320b`) had an empty queue, which is that defect's known symptom; both
sessions from the day it landed had a non-empty one; and the three since —
`808fa8f17`, `1021760fa`, `ea1356558` — were empty because their saved tasks
had already completed, which the delegation-harness record corroborates. So the
queue is non-empty only between a plan being saved and its tasks being worked,
and a run that addresses the parent after the work is done observes nothing.
Note also that the `if (delegatable.isNotEmpty)` guard around the header is
gone on current main: a parent turn now always renders the header, so an empty
queue is readable as the header with no lines rather than as silence.

The same pass found the registered firing signature could not close this gap.
It matched only `anabasis_delegation_not_ready`, on the reasoning that an
accepted selection leaves no trace; it does. `AnabasisDelegationAdmission`
appends the saved contract to the *child's* prompt, and child requests are
logged under `usageRole: subagent` like any other request, so the accepted
half is as greppable as the refusal. `tool/check_fix_firings.py` now carries
both — `anabasis_delegation_refused` and `anabasis_delegation_admitted` —
each verified against the string the production path emits, so one planned
parent run closes this by measurement rather than by reading a transcript.
There is still no Anabasis canary among the repository's live canary scripts;
every piece of this track's live evidence has come from hand-driven sessions.

**The standing evidence gap is closed, 2026-09-12.** Run 9 of
`tool/run_anabasis_delegation_live_canary.sh` (`qwen3.8-27b-vision`) fired
`anabasis_delegation_admitted`: the parent was offered two ready tasks,
selected one, and its saved contract reached a child that began running a real
command. `anabasis_delegation_not_ready` did not appear at all. This is the
live planned-parent queue observation the milestone had been waiting for across
four notes.

Run 8 first looked like a defect, and recording why it was not is the more
useful half. It measured one ready candidate, rendered its
`[workflow_task_id: …]` into the parent's prompt, and then had all three of the
parent's `spawn_subagent` calls — each carrying exactly that id — refused with
`ready_task_ids: []`. Two explanations were proposed and both were measured
false: the prompt and admission paths do **not** resolve different owners
(`_turnOwnerForGeneration` is `_turnOwnerSnapshotForGeneration(…)?.owner`), and
`currentConversation` does **not** diverge from the saved `conversations` entry
(`current: inList=true candidates=2 projected=2`, `saved: candidates=2
projected=2`). Per-request tracing showed run 8's queue was already empty in
the *turn-opening* request rather than flipping mid-turn, so the model had read
the id from the plan body. That discrepancy between the pre-send measurement
and the turn-open prompt was called unexplained here for a day; it was a defect,
and the paragraph below names it. Being careful not to convict the path on a
refusal alone was still right: the builder and the gate were both innocent.

The canary's verdict is three-way for a reason found the same day: whether the
queue is non-empty depends on the plan the model writes — an independent first
task opens it, a pure chain does not — and it was open in three of five runs
that got that far. So an empty queue exits 77 as inconclusive rather than
failing, and only a queue that was offered and not taken is a regression.

Getting there took five other fixes, none of them the model's: the scenario
judged its log expectations before the follow-up turn ran; saved plans are
chains, so nothing is delegatable while the first task runs and a cancelled
task stays `inProgress`; approval started that first task inside the same call
that saved the plan; and every task was held by unanswered open questions,
which is what the parent prompt tells the model to expect. The fifth was the
run budget: `resolvePlanModeOverallRunTimeout` never counted the follow-up
turn, so a run that had already delegated was killed at 500s while its child
was running. The queue's window is therefore narrower than "a plan exists" —
approved, unstarted, and answered — which is the real reason only 2 of 12
parent sessions ever rendered one.

**The sixth fix was the parent turn eating its own queue, found 2026-09-12 and
fixed in `8bcf664bc`.** `_markPendingExecutionTaskStarted` runs in
`_sendMessage` before the system prompt is built, and it marks the execution
focus task `inProgress` — which is how an ordinary coding turn says it is
working on something. `TaskDelegationBriefBuilder` offers only `pending` tasks.
So opening a parent turn removed the task from the queue that same turn, and a
chain plan — whose single ready task is always the focus task — showed the
parent an empty Ready block and then refused the id it had read from the plan
body. The claimed task was the worse half: the parent may not execute it,
nothing else was going to, and it could never return to `pending`.

This rewrites two claims above. Delegation is **not** gated on the model
happening to write an independent first task: the run that closed ANA2's gap
had two ready tasks and survived the claim with one, which is why it passed
where four single-candidate runs refused. And the 2-of-12 corpus figure is
partly this defect rather than only the narrow window. Measured on the fix:
`anabasis_delegation_live_canary_1789198545` offered **one** ready task, carried
its `[workflow_task_id: …]` into the turn-opening prompt, fired
`anabasis_delegation_admitted` on build `8bcf664bc`, and logged no
`anabasis_delegation_not_ready` at all — a pure chain delegating, which was
impossible the run before. The regression is a notifier test that asserts the
turn-opening prompt rather than the refusal, because the prompt is what lost the
queue; the empty-queue exit 77 stays, since a plan whose tasks have all
completed still offers nothing.

Scope:
- Map ready tasks onto `spawn_subagent` (in-conversation children, depth fixed
  at 1) and `WorktreeAgentTask` (isolated branch work with verification and
  changed-file evidence). New code is the mapping and scheduling policy, not a
  runner.

PR split:

| PR | Content | Status |
|---|---|---|
| 1 | What may be delegated, and what a child has to be told | done |
| 2 | Runner mapping: which candidates go to `spawn_subagent` and which to `WorktreeAgentTask` | done |
| 3 | Contradiction policy for a running child | done |

Verification evidence:
- PR 1: `task_delegation_brief_builder_test.dart`. `candidates` offers a task
  only when its preconditions all hold and nothing is already running it —
  reading *recorded* progress rather than the authored status, because nothing
  writes completion back to the authored one and reading it alone would hand
  running work to a second child.
- **PR 1 answers the design's MVP 1 open question, and ANA1 is why it can be
  answered.** `spawn_subagent`'s own contract says the child cannot see the
  conversation and its prompt must be complete on its own, so anything it needs
  must be in that prompt. Without precondition edges there is no basis for
  choosing which assumptions matter and the only safe option is all of them —
  which is the re-send the question was trying to avoid. An assumption edge
  names exactly the premises a task stands on, so a brief carries those and
  nothing else.
- PR 1 carries **confirmed** assumptions only, and that costs nothing to
  enforce: an unconfirmed one would still be holding the task, so a task that
  reaches a brief has none outstanding. An edge pointing at an item a revision
  dropped is unmet, so the task is held rather than delegated with a premise
  nobody can read.
- PR 1 adds no execution machinery. It decides what may be delegated and what
  to say, never who runs it.

- **PR 2's rule follows from what the two runners return, not from task size.**
  `SubagentTask` carries `resultSummary`, `output` and `error`: no changed-file
  evidence, no verification result, and no worktree — it runs where the parent
  runs. `WorktreeAgentTask` carries `branchName` / `worktreePath`,
  `verificationCommand` / `verifiedGreen` and `changedFiles`. ANA3's rule is
  that a child saying "done" means `produced` and only evidence promotes it to
  `accepted`, and a subagent has no evidence to offer. So work that changes the
  workspace goes to a worktree.
- PR 2 **fails toward isolation**, and the asymmetry is the argument: two
  subagents editing one workspace corrupt each other's work *and* leave nothing
  to accept on, while a worktree spent on inspection costs one worktree. Only
  one of those errors is recoverable. A task routes to a subagent only when it
  declares neither a file to change nor a command to verify — the task's own
  statement about itself, never a guess read off its title, which is what the
  heuristic-removal track exists to stop.

- **PR 3 answers the design's MVP 2 open question: invalidate.** The child is
  not stopped; its result is barred from acceptance. This is a judgement rather
  than a measurement — there is no corpus of contradicted children to count —
  and the argument is ANA3's ownership rule: "done" means `produced`, and only
  evidence promotes it to `accepted`. A lapsed premise is missing evidence, so
  the promotion is what must fail, not the work.
- PR 3's three rejected options, stated so the choice can be re-examined:
  *cancel* throws away a partial result mostly unrelated to the premise — a
  worktree child leaves a branch, an inspecting child leaves findings;
  *restart* is a decision that belongs to the user after the assumption is
  settled again, not to a policy running while it is unsettled; *continue*
  without a bar is the only option that is simply wrong, because it ends with
  unverifiable work being accepted.
- PR 3 matches premises by the **claim's own text**, not by item id. The id is
  a hash of that text, so an edit that rewrites the claim changes it, and
  treating the new id as "the same premise, still confirmed" would carry a
  confirmation across a change of meaning.
- PR 3 is reachable rather than hypothetical, in two ways: ANA0 PR 4b-2 gave
  the user a way to answer an assumption, which is a way to decline one, and
  ANA0 PR 2 recorded that `attachApprovedPlanSource` rebuilds provenance
  wholesale — so a re-approved plan starts unconfirmed with nobody having
  changed their mind.
- **Historical checkpoint before the parent entry point: ANA2's policies
  were complete and none was wired.** That was the milestone's stated shape —
  mapping and scheduling policy, not a runner — but it meant three services
  existed with no caller, which is the state ANA0
  PR 4a was careful not to leave behind for long.

- PR 3 follow-up: readiness now has a second consumer. `ExecutionSnapshot`
  carries `waitingTasks`, so the prompt says which tasks are not ready and what
  each waits on, rendering the *claim* behind an assumption edge rather than its
  item id — an id is a hash, and a prompt line naming one tells the model
  nothing it can act on. Before this the prompt listed a task as remaining and
  said nothing about the edge holding it, leaving the model to either start
  work that cannot be finished or guess why it should not.

Next action:
- **The parent has an execution path and its candidates**: `@anabasis` from the
  shared chat is the first of §5's three entry points, 4c's guard fires there,
  and `ExecutionSnapshot.delegatableTasks` — built from
  `TaskDelegationBriefBuilder` — reaches the parent's prompt and nowhere else.
  So every policy this track has written now has a caller.
- The queue is emitted only for a turn addressed to the parent, and is
  deliberately absent from `toPromptContext`: a delegation queue in an ordinary
  turn reads as a suggestion to spawn children. Each line carries the task, its
  runner, and the premises a child would have to be told, so a premise reaches
  the parent before it can reach the child.
#### Parent boundary measurement (2026-09-04)

`tool/ana_parent_boundary_measurement.dart`, two arms over the same request and
the same four tools — `read_file`, `write_file`, `local_execute_command`,
`spawn_subagent` — scored off the tool call the model makes rather than its
prose. `qwen3.8-27b-vision`, 18 requests across two runs.

| arm | edited | delegated |
|---|---|---|
| bare (no parent block) | **9/9** | 0/9 |
| parent | **4/9** | 5/9 |

**The prompt block is necessary and not sufficient, and that settles a question
the unit tests could not.** The control edited every single time, so the
fixture really is asking for work. Told it may not edit and should delegate,
the model delegated five times in nine — and reached for `write_file` the other
four. So neither half of the boundary is decoration: without the block the
parent tries to edit 100% of the time and is refused on every turn, which is
the loop ANA0's ordering constraint exists to prevent; without the guard the
block leaks in nearly half of turns.

Recorded because it is the opposite of the comfortable conclusion. "The prompt
tells it not to, so it won't" would have been easy to assume, and it is wrong
four times in nine.

#### Observed in a real session (2026-09-04, `459bd75f`, build `7d362b177`)

**The boundary fired, and the model delegated.** The parent called
`write_file`, the guard refused it, and in the *same* request the model called
`spawn_subagent` instead. The child then edited successfully, ran a command,
listed a directory and edited again — which is delegation working as the
parent's only route to effect rather than as a restriction on the work. The
final answer came back through the child's result.

That answers the other half of the refusal-loop question, and answers it
better than the fixture did: **no repeat, so the refusal wording needs no
work.** The live boundary measurement had the model reaching for `write_file`
four times in nine; what it could not show was whether a refused model tries
again or moves on. It moves on.

`anabasis_parent_boundary` is registered in `tool/check_fix_firings.py` and
now reports FIRED, confirmed against that session's build. It is the first of
this track's mechanisms observed outside a test.

The two surfaces a log cannot show were confirmed on screen in the same build:
the `@` completion offers its target at the start of a draft and Tab inserts
it, and a parent reply carries the **Anabasis · orchestrator** header. Worth
recording because both were broken once while every test was green — the header
on one of three assistant-message literals, and the role in a zone the request
path nested past.

Investigating that half found the loop is already bounded, and found a defect
next to it. The tool loop ends after **two** consecutive failures on the same
`toolFailureKey`, and `commandRetryGeneration` advances only on the *success*
path — so a refused `write_file` re-issued verbatim hits the same key and the
loop stops. What it stopped as was wrong: `ToolFailureClassifier.isApprovalDenial`
was a substring test for `denied` / `auto-review`, and **neither** of ANA0's
guards says either word, so both refusals classified as `executionFailure`.
That meant the abort notice told the user to check their server configuration
for a policy working exactly as designed — the notice's own comment says not to
do that for a policy decision — and `lifecycleResultStatus` recorded
`tool_failure` for a decision, which is the population
[[caverno-tool-failure-abort-population]] measures. Fixed by reading the
machine-readable `code` both guards already return, with the prose branch kept
as the remainder for refusals that predate a code rather than replaced.

- **`@anabasis` shipped broken, and typing it into the real app is what found
  that.** The role was carried in a zone opened around the turn. Inside it,
  `_runWithLlmSessionLogContextForGeneration` opens its own zone defaulting to
  `ModelUsageRole.chat` — deliberately, so a secondary role started mid-turn
  wins — and an inner zone beats an outer one. So the parent's role was
  replaced before the system prompt was built: two real turns reached the model
  with `@anabasis` in the user message, a 29,784-character system prompt, and
  none of the parent's instructions in it. The tool loop was worse off still:
  it runs outside the request zone entirely, so `ModelUsageRole.current` was
  `unknown` there and the authority guard never armed.
- Every test passed throughout, and so did the live measurement. The unit tests
  exercised the zone directly; the 18-request measurement built the parent's
  system prompt itself and posted it. Neither went through the path that nests
  inside the zone. This is [[caverno-canary-harness-blindness]] with a new
  surface: a green harness that verifies the old path.
- Fixed by carrying the role per interaction generation in `AnabasisTurnRoles`
  and reading it explicitly at both sites — which is what §5 asked for in the
  first place. Its warning was about authority, and it turned out to apply to
  the prompt path too: ambient is the wrong channel for anything a turn needs
  to be sure of.
- `chat_notifier_turn_teardown_contract_test.dart` caught the new
  generation-scoped field and demanded its release entry, which is the gate
  working: one destructor per key, and a leak into a later turn fails the build
  rather than the next session.
- The regression test reads the system prompt the datasource was handed, not
  the zone. Nothing weaker would have caught this.
- ANA3 remains available and does not need the parent: separating `produced` /
  `verified` / `accepted` is the change ANA2's invalidate policy already
  depends on conceptually.

#### Delegation observed with no refusal (2026-09-04, session `7a18cc33`)

The first `@anabasis` turn on the merged build (`6218b6440`) that delegated
without being refused first. Nineteen records, eight of them carrying the
parent prompt, `anabasis_parent_authority_refused` zero times.

- Turn 1 the parent researched with `http_get` twice and answered. Turn 2 it
  called `spawn_subagent` as the **first tool call of the turn**, the child
  wrote the file, and the parent then read that file back before answering.
- So the prompt alone was sufficient here. Session `459bd75f` reached
  delegation the other way, by attempting an edit, being refused, and switching
  within the same request. Both live paths to delegation are now observed, on
  the same model and prompt — which is the 4/9-edited, 5/9-delegated split of
  the PR 2b measurement showing up in real turns rather than in a probe.
- The task was research (tomorrow's weather in Kyoto) that ended in a write.
  The parent did the read-only half itself and delegated only the write, which
  is the authority boundary landing exactly where `ToolCommandEffect` draws it,
  with no refusal needed to steer it there.
- The child's four requests carry no parent prompt. A delegate is not itself
  bound as a parent, which is what lets it do the work the parent may not.
- `Ready to delegate` was empty, and correctly so: the execution shadow reads
  `workflowStage: idle`, `totalTaskCount: 0`. With no contract tasks there are
  no candidates, so **ANA2's queue is still unobserved rather than broken**.
  Seeing it needs a coding thread that has a plan, then `@anabasis` on it.
- **The log could not say which `ModelUsageRole` a request ran under** — the
  session-log `context` carries `workspaceMode`, `phase`, ids, and no role. The
  zone defect above was found by grepping the system prompt for its text, and
  after the fix that was still the only available signal. **Closed by schema
  v4's `request.usageRole`**, captured by the caller at issue time and written
  even when `unknown`, so an entry point that claimed no role reads as a gap
  rather than as an unrecorded field.
- Writing it turned up a latent defect on the way: `streamWithToolResult` is
  the one logged operation whose body is an `async*` generator, so it resolved
  the session-log context *and* the role only on first listen. A stream
  listened to outside the caller's zone got no context at all — the test that
  now guards it fails by finding no log file written, not by reading the wrong
  role. Nothing calls that operation today (zero occurrences across the
  corpus), so this is insurance rather than a recovered record, but it is the
  same mistake [[caverno-zone-attribution-lazy-stream]] names and the only
  generator-bodied site on the class.

### ANA3: Accept

Status: `current`

Current summary (2026-09-13): PR 2b's guarded acceptance write was observed live
on 2026-09-12; PR 3's derived lifecycle now reaches both prompts and panels
(`c4cc61380`, `455af1bc8`, `70466c022`). The implementation slices below are
complete. The worktree route was then dispatched on 2026-09-13, which closes the
acceptance-evidence limit in code; keep the milestone current pending a live
observation of it, since the canary's temp-directory project cannot host a branch.

Scope:
- `produced` / `verified` / `accepted` as distinct states. Both existing status
  enums collapse all three into `completed`.
- The four-level acceptance model: mechanical (`verificationCommand`), evidence
  (`changedFileEvidence`), semantic (the parent's own judgment), user
  (`awaitingConfirmation`).
- One writer per state, per §10 of the design document.

Standing principle to adopt before there is a second child agent:

> A child saying "done" means `produced`. It never means `accepted`. Only
> Anabasis writes `accepted`, and only on evidence.

Precedent for taking the ownership table seriously:
`ConversationExecutionValidationStatus` already has three writers, one of which
judges prose; a fourth exit-code writer was added and reverted after the
investigation found stderr outranking a clean exit 0.

PR split:

| PR | Content | Status |
|---|---|---|
| 1 | The two derivable acceptance levels, as a verdict nobody writes | done |
| 2a | Where an acceptance lives, and what has to hold before one may be written | done |
| 2b | The parent's route to writing one | done |
| 3 | `produced` / `verified` / `accepted` as distinct states, one writer each | done (derived, prompt + panels) |

Verification evidence:
- PR 1: `task_acceptance_audit_test.dart`. `TaskAcceptanceAudit` derives levels
  1 and 2 from evidence the runners already record — `verificationCommand` /
  `verifiedGreen`, and `changedFiles` — and leaves 3 and 4 outstanding, so
  **nothing it returns is ever accepted**. That is the honest answer while the
  parent has no way to record a judgement, and it is what stops "the tests are
  green" being read as "the goal is met".
- **PR 1 stores nothing, deliberately.** This milestone's design opens by
  warning that adding acceptance levels before fixing ownership reproduces the
  `ConversationExecutionValidationStatus` problem — three writers, one judging
  prose, a fourth added and reverted — at a larger scale. A derived verdict has
  no writer at all, so PR 3 can introduce stored states once there is one owner
  for each.
- PR 1 keeps *inapplicable* apart from *passed*. A task with no verification
  command owes nothing mechanically and has proved nothing; collapsing those
  two into one is how a green light appears for work nobody checked.
- PR 1 asks the two runners different questions, which is ANA2 PR 2's routing
  reaching acceptance: a worktree child was sent there because the work changes
  files, so an empty `changedFiles` owes the evidence level; an inspecting
  child changes nothing by design, so evidence is inapplicable *unless* it
  reported nothing at all.
- Truncated evidence is not evidence: a partial list cannot show the artifacts
  match the claim, only that some of them might.

- PR 2a: `ConversationTaskAcceptance` on the conversation, with one writer by
  design. It carries the rationale, the evidence the mechanical levels rested
  on, and — the field that makes an acceptance revisitable — the **premises in
  force when it was written**. ANA2's contradiction policy can only bar a
  result whose premise has lapsed if the premises at acceptance time were
  recorded.
- PR 2a deliberately keeps it off `ConversationExecutionTaskProgress`. That
  record already has three writers, one of which judges prose, and a fourth was
  added and reverted after the investigation found stderr outranking a clean
  exit 0. §10 exists because of that history.
- **PR 2a's rule is the whole milestone in one line: the parent supplies level
  3 by judging and cannot supply levels 1 and 2.** `mayParentAccept` refuses
  while the mechanical or evidence level is outstanding, so a confident
  rationale cannot stand in for a test that did not pass or files nobody can
  see. An inspecting child is the interesting case: both derivable levels are
  *inapplicable* to it, so the judgement is the whole test — unless it reported
  nothing, which leaves nothing to judge.

Next action:
- Trace a mutating planned task from the runner choice through parent dispatch
  to the acceptance audit, and specify the missing production adapter and its
  evidence contract. Decide the remaining integration scope before closing the
  milestone or promoting ANA4. PR 2b and PR 3 no longer need implementation;
  the earlier stored-state proposal was superseded by the derived projection.

PR 2b landed 2026-09-12, and two of its three obstacles were not the ones the
roadmap had recorded.

The file-size ceiling was real and was cleared first: the progress writers moved
to `conversations_notifier_progress_writers.dart`, taking the notifier from
1,775 of 1,775 to 1,674, and the acceptance writer landed there rather than back
in it. Only the two writers nothing subclasses could move, because a part file
cannot hold part of a class — its members are an extension, and an extension
member is unreachable through `super`, which two test doubles rely on.

The obstacle nobody had measured was that **the acceptance record had no home**.
PR 2a is recorded above as putting `ConversationTaskAcceptance` "on the
conversation"; it was on `ConversationCheckpoint` and only there, with no
writer, no reader and no test — and structurally unwritable, since the
checkpoint is built by copying fields off `Conversation`. It now lives on the
conversation, is carried into the checkpoint, and is restored by the rewind
along with everything it rests on; leaving it out of the rewind would let an
acceptance outlive the evidence it was judged on.

The third was the delegation binding. `TaskAcceptanceAudit` takes a
`SubagentTask`, and a `SubagentTask` had no way to say which planned task it was
for — the admission gate wrote the contract into the child's prompt and kept the
binding nowhere else, and prompt text cannot be audited. `prepare()` now reports
the id it admitted and both spawn paths carry it onto the task.

`accept_task` is the route itself: parent-only, stripped from the inherited
catalog and checked again at dispatch, refusing on five distinct grounds so each
names a different thing the parent has to go and do. `anabasis_acceptance_refused`
and `anabasis_acceptance_recorded` are registered firing signatures, so the path
can be measured the way ANA2's was rather than argued, and the delegation canary
now asks the parent to record its judgement as well as delegate. Acceptance is
reported there rather than gated: delegation is the one thing a run can demand,
and failing on a longer chain the canary does not control would retire a working
gate for a model's pacing. The follow-up asks for the outcome and never names
the tool, because a probe that spells out the mechanism measures its own
wording.

Measured 2026-09-12 on `c08d92eb7`: the canary passes on delegation — two ready
tasks offered, one delegated, its contract reaching a child — and the parent
**never attempts** an acceptance. Not refused; never tried, with the tool in the
catalog and the follow-up asking in as many words to verify the result and record
the judgement. So PR 2b's handler remains unexercised live, and the cause is the
model's pacing rather than a gate. `update_goal` has the same shape and a known
remedy: the local model does not volunteer it either and calls it when asked, so
one restricted elicitation turn is the cheap thing to try before concluding
anything about the tool.

The same run settled an open question. Two earlier runs had the queue non-empty
immediately before the turn and empty in the prompt that turn built, which looked
like staleness. Measured on the way out: `candidates=1 projected=1` — the builder
and the projector agree, and the 2 → 1 drop is the delegated task correctly
leaving the queue. The earlier discrepancy was a single-candidate queue being
consumed mid-turn, not a projection defect.

Getting a non-empty queue at all needed one more canary fix, and it was the
canary's bug rather than the product's: it answered
`unresolvedOpenQuestionProgress`, which is derived from recorded progress
entries, and a freshly approved plan has none — so it reported "Answered 0 open
question(s)" on a plan whose first task waited on exactly one question. It
answers `effectiveWorkflowSpec.openQuestions` now.

**That limit is closed, 2026-09-13** (`5682c34a6`, `28bbdb3d7`, `3786d610d`).
`spawn_subagent` takes `runner: "worktree"`, which enqueues a `WorktreeAgentTask`
through the launcher the UI and LL37 already used, bound to the saved plan task;
`get_subagent_result` answers for it with the two things only it can report --
whether the saved verification went green, and how many files changed;
the delegated-results block lists it first; and the audit prefers a worktree
result over a subagent one for the same task, because it is the only kind that can
pass a level. The queue names the real runner again, having printed `(subagent)`
for a day while the label described a route the harness could not take.

So an acceptance can now rest on more than the parent's word. The one recorded live
the day before passed zero levels, with `evidence: ["child summary recorded"]`; a
worktree acceptance names the branch and the command instead, because that line is
what the next turn reads instead of redoing the work.

Three things the slice decided rather than deferred. The binding travels
entity -> plan -> registry -> launcher in one commit, since a field with no writer
is how PR 2a left one dead. The route refuses rather than downgrades when there is
no saved task or no coding project: falling back to a subagent would hand the
parent a summary it would read as evidence, which is the failure the route exists
to fix. And the registry read is defensive, because a throw inside a tool handler
ends the turn -- at the end of the work, which is the expensive place to lose one.

**The scenario exists** (`live_anabasis_worktree`, `0bb23a0ec`): one workspace is a
real git repository on `main`, which no other scenario is, because a repository the
model can see changes what it does. Six live runs of it each surfaced one defect or
contradiction, in this order: nothing started the enqueued child; the parent never
asked for the runner the queue named; the canary reported a successful run as
FAILED; the parent opened two branches for one task; the audit demanded changed-file
evidence from a task that declared no files; and the planner was told to write
compound validation commands that neither runner will execute. All six are fixed
(`314e2a2be`, `ee75ea92b`, `de09f1d29`, `4d0fe`, `2092bc395`, `84b9da7df`), and the
last reaches ordinary saved-task execution too.

Runs seven through ten added three more, and the seventh is the one that matters:
with `targetFiles` defined and the command single, a worktree child **wrote the file
it declared, its verification passed, and one changed file was recorded** —
`verified: true, changed_file_count: 1`. Both audit levels satisfiable at once, for
the first time. The parent then spent the rest of its turn checking the branch with
`git_execute_command`, which is level 2 gathered by the parent itself, and ran out of
budget before recording anything; the scenario's turn allowance is 20 minutes now
(`cb1335576`).

Runs eight through ten were inconclusive, and not from variance. The plan gave its
first task three `assumption` preconditions whose refs were question-shaped sentences
the model invented, matching no contract item — so readiness held the task forever:
nothing for the user to confirm, nothing for them to answer. The harness now confirms
real assumptions (`ac26d96f3`, the fourth precondition a ready queue needs, after
approved / unstarted / answered), and the planning prompt now states what a dangling
ref costs (`…`).

**The durable fix for that is the next slice, and it belongs in the parser, not the
prompt:** an `assumption` edge whose ref resolves to nothing should become the open
question it already reads like, so the block survives ANA0 intact and becomes
answerable. Dropping the edge would let work start on an unconfirmed assumption,
which is the one thing that machinery exists to prevent.

The eleventh run is the clean measurement the other ten were working towards. The
repair opened the queue — `Answered 6 open question(s)` where the previous runs
answered three and offered nothing, the three extra being the invented assumptions
turned into questions — one worktree child ran, and it came back
`verified: true, changed_file_count: 1`. The parent polled it four times, read the
files, checked the branch with git, and **both turns settled on their own**: it had
the evidence, it had the time, and it reported in prose instead of calling
`accept_task`.

That is the `update_goal` shape exactly, and the precedent names the remedy: the
local model does not volunteer a bookkeeping call and makes it reliably when a turn
asks for nothing else. The acceptance scenario already showed `accept_task` being
called and recorded, so the tool is reachable; what is missing is a turn whose only
available action is to record the judgement, which is what
`GoalCompletionElicitationPrompt` is for `update_goal`. Building that analogue is the
next slice, and it is a nudge rather than a defect.

**Proven live:** the parent choosing the worktree runner, a branch and second
checkout created, the child running in isolation, the saved verification command
running, `verified: true` reaching the parent, and a changed file recorded against a
task that declared one — the mechanical and evidence levels both satisfiable, with
the parent gathering level 2 itself through git. **Not yet proven live:** an acceptance *written* on that evidence.
The last run waited for the child properly and then declined, correctly, because its
verification had been refused for its shape.
- Session `7a18cc33` grounds that in a turn nobody set up for it: the parent
  called `read_file` on what the child had written, judged it, and answered.
  That is level 2 evidence gathered by the parent through a tool its authority
  allows, and level 3 supplied by the judgement — `mayParentAccept`'s two
  halves both present in one real turn, with nowhere to write the result down.
  PR 2a built the verdict; the gap PR 2b closes is that the next turn starts
  over from the same files.
- **PR 2b needs an extraction before it can write a line**, and which one has
  narrowed. Measured 2026-09-04 all three ceilings were at zero slack:
  `conversations_notifier.dart` 1,791 of 1,791, `chat_notifier.dart` 8,778 of
  8,778, the notifier library 19,731 of 19,731. Re-measured 2026-09-11 after
  `aa6c53651`: `chat_notifier.dart` is at 8,668 of 8,681 and the library at
  19,645 of 19,662, so those two now carry 13 and 17 lines. The binding one is
  `conversations_notifier.dart`, still at exactly 1,775 of 1,775 — and it is
  the one no session has touched, so its seams remain unknown. The tool
  definition, its handler and the write path do not fit in 13 lines. Worth
  naming here because five extractions were needed for the work before it and
  each was found by hitting the ceiling rather than by looking first.

**PR 2b shipped and was unreachable, 2026-09-12.** Three canary runs reported
"the parent never attempted an acceptance", and none of the three was about the
model.

- `accept_task` never joined `BuiltInToolRegistry.tools`. It was reserved and
  offered in the *catalog* while absent from the **initial tool-search
  selection**, which is the list a turn actually receives — `spawn_subagent` and
  `get_subagent_result` were both in it. So the parent's prompt named a third
  tool, told it to record its judgement with that tool, and its list did not
  contain the name. Skipping the registry is also what kept it out of the F6
  guard, which asserts every registry tool is either initial-loaded or
  deliberately deferred: a tool in neither set is not checked at all
  (`e8ac0843b`, initial 22 → 23).
- With the tool in the list, the parent called it — and was refused in 0 ms by
  `AnabasisParentAuthorityGuard`, whose named exception was `{'spawn_subagent'}`
  and which refuses `unknown` effects by design. A child is refused as
  `acceptance_not_parent`; between the two guards the tool had no caller at all,
  which is why PR 2b's five refusal grounds were never reached. Probing the rest
  found `update_goal` and `ask_user_question` refused the same way, both also
  named in the parent's own instructions (`81aea8858`). `create_routine` stays
  refused: it schedules real runs and nothing in the instructions asks for it.
- With both of those fixed, a notifier-level test found the third block: the
  acceptance handler locates the child it must audit through
  `SubagentTaskNotifier`, and only the *background* spawn path ever registered a
  task there. Foreground is the parent's ordinary route, so a normal delegation
  left nothing to accept on and refused as `acceptance_no_delegated_result`
  (`3f67eb9a7`). PR 2b had no test above `recordTaskAcceptance` itself, which is
  why three stacked blocks could ship green; the new regression walks the real
  dispatch chain -- parent turn, delegate, accept, assert the record -- and fails
  on each of the three in turn.
- The canary itself was wrong twice, which is the reusable finding. The
  elicitation prompt was sent while the delegation turn was still streaming, so
  `ChatNotifier` queued it and it never became a turn — one `Initial tools:`
  line in the whole run — and the verdict read that as the model declining.
  Later the call *was* attempted and refused by a code the capture did not look
  for. It now counts delivery and attempts, and "never asked", "attempted and
  recorded none" and "never attempted" read differently (`d2cb2a625`).

Two more blocks, found by driving the scenario at it rather than by reading code:

- `get_subagent_result` looked the child up through `byId`, which matches the
  turn owner, so a child spawned in an earlier turn read back as `not_found` --
  while the acceptance audit two methods away reads by conversation and could see
  it. The parent asked for the result it was told to judge, was told there was
  none, and re-delegated the task (`d86d44392`). The regression needs two real
  turns, which is why no single-turn test could see it.
- Then it had no way to *name* the child at all. `task_id` comes back from
  `spawn_subagent` and lives nowhere the parent can see again -- tool results do
  not persist into the next turn's history, and no prompt block named them; in
  the corpus the real id appears only under `usageRole: subagent`. So the parent
  invented plausible ids and re-delegated. `0c5b6d756` gives the parent a
  `Delegated results awaiting your judgement` block beside the delegation queue:
  child_id, the saved task it was admitted against, its terminal status, accepted
  tasks dropped, and `- none` when there is nothing -- silence is what the parent
  filled with a guess.

Five blocks, and the instrument wrong twice on top. Every one of them, read from
outside, looked exactly like a model that would not record its judgement. The
ANA3 lesson is the one the validation-status precedent already taught: when a
path has never run in the wild, "the model does not do X" is a claim about the
wiring until each layer has been proven to carry X.

**The acceptance was observed live, 2026-09-12, session `ad2dbe83`.** One run of
`live_anabasis_acceptance` fired three signatures together —
`anabasis_delegation_admitted`, `delegated_results_named`, and
`anabasis_acceptance_recorded`, the last of which had never fired on any build —
and wrote `accepted_task_id: 918158bd-…` with `evidence: ["child summary
recorded"]`. The parent delegated a ready saved task, read the child back by the
id the new block named, judged it, and recorded the judgement, in the elicitation
turn. ANA3 PR 2b is exercised end to end in a real session.

The scenario is the reason it took a seventh run, and the finding is worth as much
as the firing: six runs on the delegation scenario measured a parent that was
right to keep working, because the task it had delegated was an implementation a
child does not finish in one call. A judgement cannot be observed on work that is
not done. `live_anabasis_acceptance` is the same scenario with a reading goal, and
the acceptance arrived on the first run of it.

That earlier reading — "the elicitation turn cancels the delegation turn, so no
child finishes" — was half right and is superseded. The child did finish; what
did not finish was the *task*, and the parent was judging the task.

Two follow-ups the confirmation run then forced, both about a turn ending where
the model still had a move:

- A policy refusal that carries a `required_action` no longer ends the turn
  (`25a2fc6dc`). Measured across this canary's corpus: five aborts in four runs,
  on `spawn_subagent` (the admission gate), `ask_user_question` (the authority
  guard refusing a tool the parent's own prompt names), and
  `local_execute_command` (a compound shell expression the harness asked it to
  split). The refusal still stands and is still counted; the loop's iteration cap
  bounds a model that ignores it, and an approval denial still aborts because
  there the answer came from the user.
- `get_subagent_result` answers an unknown id with the ids that exist
  (`f59c47e9a`). The parent passed a *workflow* task id to a tool whose parameter
  is `task_id`, twice, and the second failure ended the turn as if the tool were
  unreachable. The old result said only `not_found`, which names nothing to
  correct. Note the shape: the delegated-results block could not have helped
  there, because the child was spawned inside that same turn and the block is
  built before it.

**PR 3's own question, written down before it is built: stored or derived?** The
row says "distinct stored states, one writer each", and the second half argues
against the first. Three facts already exist, each with an owner:
`ConversationWorkflowTaskStatus` (`pending` / `inProgress` / `completed` /
`blocked`) is the mechanical lifecycle, `ConversationExecutionValidationStatus`
carries verification, and `ConversationTaskAcceptance` carries the acceptance and
has exactly one writer — `recordTaskAcceptance` — which was PR 2a's whole point.
Adding `accepted` to the task-status enum would hand every existing status writer
the ability to set it, which is the `validationStatus` shape the design opens by
warning about: three writers, one judging prose, a fourth added and reverted.

So the recommendation is **distinct but derived**: a projection over (status,
validationStatus, taskAcceptances) that reads `produced` / `verified` /
`accepted`, with the enum left alone. The stored states stay one-writer because
they stay where their writer already is. What PR 3 then owes is the projection,
the UI and prompt surfaces that currently say `completed` where they mean
`produced`, and a test that a task with a passing command and no acceptance never
reads as accepted. **Built that way, `c4cc61380`.** `TaskLifecycleProjection` derives the six states
from (progress status ?? spec status, validationStatus, taskAcceptances); the
snapshot carries them by task id so the prompt renders them without reaching for a
conversation, and the status enum stays the fallback for an id it does not name.
Two rules are pinned by test: a finished task with no *passing* check stays
`produced` — including one with no command to run, because owing nothing
mechanically is not the same as having proved something — and an acceptance
outranks a later status edit, since the judgement was recorded against evidence at
a point in time.

The UI followed in `455af1bc8`, once the chat_page aggregate had room: both task
chips ask what the task has actually reached, and the plan row is told whether an
acceptance exists -- the one state it cannot derive, because only the conversation
records one. An accepted task says so over its verification, since a judgement
outranks the check it rested on.

PR 3 is done. What it does *not* do is make an acceptance mean more than the
parent's word: see the worktree-dispatch limit recorded earlier in this section.

The extraction note above also resolved itself the other way: the write path
landed without touching `conversations_notifier.dart`, and the extraction this
work actually needed was the guard's exempt-tool list, moved to
`anabasis_parent_authority_tools.dart` when it stopped being one name.

### ANA4: Anabasis Workspace

Status: `later`

Purpose:
- Reduce the work of reconstructing progress and composing the next instruction,
  so the user can concentrate on decisions that need their judgment.
- Deliver a workspace where the user entrusts **one goal through completion**.
- The independent [Anabasis Project Vision](anabasis_project_vision.md) defines
  the longer-term destination.

Scope:
- A fourth `WorkspaceMode`, with the current goal's state beside the
  conversation: plan, assumptions, open questions, tasks, and result evidence.
- Reuse the owning conversation's existing goal, workflow, progress, and
  acceptance records. ANA4 does not require a new project-wide state owner.
- Widening `MaterialContractAssumptionGuard` beyond `WorkspaceMode.coding`,
  which today is where epistemic execution control is scoped by construction.

Acceptance criteria for the first destination:
- The user can identify what is progressing, what is blocked and why, and what
  decision they need to make without reconstructing the conversation history.
- Pending confirmations and questions lead to an actionable response surface.
- Produced, verified, and accepted results remain distinguishable, with the
  evidence behind acceptance accessible from the workspace.

Deliberately last: the parent boundary and the acceptance model should be
proven before they get a surface.

Next action:
- ANA0 and the ANA2 policy/queue baseline are complete. Resolve ANA3's remaining
  closure and integration scope, then define one representative goal journey
  with a user decision and visible produced, verified, and accepted states.

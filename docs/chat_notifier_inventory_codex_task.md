# ChatNotifier Inventory: Codex Investigation Task

Phase 1 of the architecture renewal. **Investigation only — do not refactor, do
not delete, do not change behaviour.** The deliverable is three findings
documents plus a consolidated candidate list.

Written 2026-08-02. Read
`docs/chat_notifier_architecture_renewal_plan.md` first for why this comes
before any design work.

## Why inventory precedes design

The renewal moves the turn loop into a `TurnRuntime` object. Migrating dead
code into a new architecture is the worst available outcome: it pays the
migration cost twice and preserves the thing that should have been deleted.

There is direct evidence this risk is real. On 2026-08-01 the
stalled-diagnostic-repair feature was found to be **completely unreachable in
production** — three stacked defects meant nothing could ever reach it — while
its unit tests were green the whole time
(`caverno-stalled-repair-unreachable-chain` in the agent memory, and
`docs/execution_contract_design.md` for a design that was built on a
measurement whose instrument turned out to be a placeholder). Nobody has asked
the reverse question: how much code exists for paths that never execute?

## Ground rules

**Never grep the session logs.** They contain a full tool catalogue per
request, replay history and payload text, so grep counts are inflated by
roughly an order of magnitude and mix declarations with executions. Parse them
structurally instead — `tool/analyze_tool_results.py` is the existing starting
point, though investigation 1 needs more than it currently reads. This is a
recorded lesson, not a preference.

**Distinguish three states for every candidate**, and never collapse them:

- **Dead** — no execution path can reach it. Delete candidate.
- **Unexercised** — reachable, but never observed firing in the log corpus.
  Investigation candidate, *not* a delete candidate. The stalled-repair feature
  looked exactly like this and was worth fixing, not removing.
- **Live** — observed firing. Migrate.

**Report what you measured and how.** Every number needs a command that
reproduces it. If a question cannot be answered from available data, say so
rather than estimating.

## Measured starting point

Re-derive any of these you rely on; they are recorded so a drift is visible.

| Fact | Value | How it was obtained |
| --- | --- | --- |
| `lib` total | 231,093 lines / 806 files | `find lib -name '*.dart' -not -name '*.freezed.dart' -not -name '*.g.dart'` |
| chat_notifier library | 19,683 lines, 37 declared parts | library + `part` files |
| Files over 1,000 lines in `lib` | 40 | same find, `awk '$1>1000'` |
| Manifest entrypoints | 414 recorded / 271 still resolvable | manifest vs `tool/audit_chat_notifier_turn_scope.dart` |
| owner/generation plumbing | 798 lines (4% of the library) | regex over the library and its parts |
| Ambient reads | 67, of which 50 turn-reachable | `tool/audit_chat_notifier_turn_scope.dart` |
| Extractable pure members left | 9 members / 82 lines | AST walk, recorded in the decomposition doc's WS8 section |
| Lines created per line removed | 5.8 | 71 collaborators: 18,107 created vs 3,115 removed |
| `return null;` in `domain/services` | 377, of which 376 have no log within 6 lines | grep + a short python scan |

## Investigation 1: Which guards and recovery mechanisms actually fire

**Question.** Of the guards, recovery paths and policies in the turn loop,
which have been observed firing in real sessions, which never have, and which
cannot fire at all?

**Why it matters.** This is the largest single category of code in the library
and the one most likely to contain unreachable paths. It is also where the
2026-08-01 defects lived.

**Where to look, and what the existing tool cannot do.**

`tool/analyze_tool_results.py` parses tool results and some payload fields. It
does **not** read `turn_exit.transforms[]`, arbitrary `trigger` values, or
tool definitions that were never invoked, so it cannot produce this deliverable
on its own. Either extend it or add a sibling analyser; do not fall back to
grep for the reasons above.

`turn_exit.transforms[]` and the `trigger` field on tool results record guard
firings — `completionClaim` is the documented example. `docs/` contains dated
measurement notes for several mechanisms; use them to cross-check rather than
as the primary source.

**Pin the corpus before measuring.** Record the date range, the exact file set
and the build revisions represented, and report them with every count. Without
that, results cannot be compared across runs — a re-measurement during review
produced 33 invoked tools where an earlier note recorded 41, and there is no
way to tell drift from a different corpus.

**Deliverable.** A table of every named guard/recovery mechanism with: where it
lives, what triggers it, observed firing count in the corpus, and a state of
dead / unexercised / live. For anything marked dead, the specific reason no
path reaches it.

**Watch for.** A mechanism can be live but only through a path the canaries
never take — that is neither dead nor healthy. Note it separately.

## Investigation 2: Tool catalogue residency

**Question.** Which tool handlers must be resident in the core turn loop, and
which could live behind a registry that the loop does not know about?

**Prior measurement (verify before relying on it).** 106 tools exist, 41 have
ever been invoked, and 8 account for 67.6% of all tool results. Recorded in
`caverno-tool-traffic-concentration`. Re-derive with
`tool/analyze_tool_results.py`.

**Why it matters.** `ChatToolHandlerCatalog` already exists, with its own
tests, and is used by `subagent_catalog_child_tool_execution_adapter`. The
production tool loop does not use it: it still builds
`ChatToolHandlerRegistry.fromModules`, which captures the notifier. The
migration is specified in workstream 6 slice 19 and was never completed.

**Answer this first: why is the catalogue unwired?** A step that was specified
and skipped may have been skipped for a reason, and that reason would also
obstruct the wider renewal. This is cheaper to learn here than in Phase 3.

On payload composition, which this investigation must not touch: sending the
whole catalogue every request is a deliberate KV-cache prefix-stability
trade-off **only when `enablePrefixStableToolLoop` is on, and it defaults to
false**. With it off, `ToolDefinitionSearchService` already subsets above its
threshold. This investigation is about **code residency, not payload
composition**.

**Deliverable.** For each tool handler: invocation count, which notifier state
it reads, whether it needs approval/owner plumbing, and whether it could be
registered rather than wired. Flag any handler that reaches into turn state in
a way a registry could not provide.

## Investigation 3: Concept overlap between goals, plans, workflows and routines

**Question.** Are these four genuinely distinct concepts, or are some of them
the same idea reached from different entry points?

**Why it matters.** This is the only one of the three that is a design review
rather than a measurement, and it is the one with the largest potential
saving. Candidate scale: `workflow_task_run_coordinator.dart` is 2,378 lines,
`conversation_plan_execution_guardrails.dart` is 1,662, plus the
`conversation_plan_*` and `conversation_execution_*` service families and the
whole `features/routines/` tree.

**Where to look.** `ConversationGoal`, `ConversationWorkflowTask`,
`ConversationExecutionTaskProgress`, `Routine`, and the plan artifact entities.
Compare their lifecycles: who creates them, what state they carry, what
decides they are finished, and whether a user can tell them apart.

**Deliverable.** A concept map with, for each pair, either a defensible reason
they are distinct or a proposed unification and what it would cost. Explicitly
state which of the four the *user* experiences as separate — a distinction that
exists only in code is a merge candidate; one the user relies on is not.

**Do not propose a unification you have not costed.** An estimate in
files-touched and behaviours-at-risk is enough; a guess is not.

## Consolidated deliverable

One document, stratified by confidence first and ordered by size within each
band — not a confidence × lines product, which lets a large speculative
candidate outrank a small certain one. Keep delete candidates separate from
investigate candidates throughout. Deletion is the only reduction that does not
pay the 5.8× extraction tax, so the highest-confidence band is the one worth
acting on regardless of how little it removes.

## What success looks like

The renewal design can be written knowing what will not be migrated. If this
investigation finds nothing removable, that is a valid and useful result —
report it plainly rather than manufacturing candidates.

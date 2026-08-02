# ChatNotifier Inventory: Codex Investigation Task

Status: Phase 0A static guard inventory completed on 2026-08-02. The checked-in
manifest contains 65 decision candidates and 15 explicit helper exclusions,
and its deterministic discovery check is covered by eight focused Python tests.
Phase 0B telemetry selection completed on 2026-08-02 with one bounded
candidate and 51 explicit deferrals. The first selected telemetry event is now
implemented and marked covered. Catalogue snapshot validation and structured
tool-result observation joins are complete. The tool catalogue residency
inventory now links 118 static and 52 private dynamic definitions to six
production binding groups and traces the unwired catalogue to the unmet
WS6-19 registry-last gate. The concept-overlap inventory now identifies three
durable user concepts and costs the plan/workflow/progress consolidation
boundaries; no dynamic action state is claimed. The private corpus contract now
validates hashes, build provenance, complete configuration segments,
canonical snapshot fingerprints, exact schema-v1 catalogue provenance, and
submitted tool membership before measurement. A 2026-08-02 structural scan
found no provenance-bearing record for the first telemetry event, so a new
clean capture is required. Static review has proven
`_tryRepairAndDecodeMap` and `_repairJsonCandidate` unreachable, but their action
state remains unresolved until matching-build observations exist.

Phase 1 of the architecture renewal. **Do not refactor, delete, or change
product behaviour.** A prerequisite tooling slice may add measurement code and
tests; no architectural implementation starts in this task.

The deliverables are:

- `docs/chat_notifier_guard_reachability_inventory.md`
- `docs/chat_notifier_tool_catalog_residency_inventory.md`
- `docs/chat_notifier_concept_overlap_inventory.md`
- `docs/chat_notifier_renewal_candidate_ranking.md`

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

**Never grep the session logs.** Requests can contain selected or full tool
definitions as well as replay history and payload text, so grep counts are
inflated and mix declarations with executions. Parse them structurally instead
— `tool/analyze_tool_results.py` is the existing starting point, though
investigation 1 needs more than it currently reads. This is a recorded lesson,
not a preference.

**Anchor classification to one clean source revision.** Report
`currentStaticState` separately from `observedByBuild`, then derive one of four
action states from sessions whose build revision exactly matches the source
revision:

- **Dead** — the current source is statically unreachable, the proof has no
  unresolved edge, and no matching-build observation contradicts it. Delete
  candidate for the classified source revision only.
- **Unexercised** — the current source is statically reachable and a non-empty
  matching-build corpus observed zero firings.
  Investigation candidate, *not* a delete candidate. The stalled-repair feature
  looked exactly like this and was worth fixing, not removing.
- **Live** — the current source is statically reachable and a matching-build
  session observed it firing. Migrate.
- **Unresolved** — static reachability is ambiguous, or a statically reachable
  candidate has no non-empty matching-build corpus with reliable provenance, or
  another unproven edge remains. Investigate; never rank as a delete candidate.

Absence from telemetry cannot establish that code is dead. Only the static
proof can do that, and any unresolved edge forces the unresolved state. Keep
observations from older or dirty builds in `observedByBuild` as historical
evidence; they never determine the current action state. If a matching-build
observation fires a candidate classified statically dead, fail the analysis and
repair the proof instead of choosing either label.

**Report what you measured and how.** Every number needs a command that
reproduces it. If a question cannot be answered from available data, say so
rather than estimating.

## Measurement tooling prerequisite

The current analyser cannot satisfy this task. Before Phase 1 measurements,
add a sibling tool at `tool/analyze_chat_notifier_inventory.py` and a focused
test at `test/python/analyze_chat_notifier_inventory_test.py`. The tool must:

- accept `--source-revision`, `--require-clean-source`, `--corpus-manifest`,
  `--guard-manifest`, `--tool-manifest`, and `--output`;
- read only the exact JSONL files listed by the corpus manifest, validate their
  hashes, and use logged timestamps rather than filesystem modification times;
- resolve the classified source revision to a full Git SHA and treat a logged
  short SHA as matching only when it is an unambiguous prefix of that commit;
  reject unknown or ambiguous revisions rather than guessing;
- parse build provenance, `turn_exit.transforms[]`, arbitrary tool-result
  `trigger` values, tool definitions and actual invocations;
- enumerate built-in definitions from the static tool manifest and dynamic
  definitions from the configuration-specific catalogue snapshots named by
  the private corpus manifest, even when their invocation count is zero;
- combine dynamic observations with the static guard inventory without
  treating zero observations as proof of death; and
- write deterministic JSON containing the corpus-manifest digest, file count,
  logged date range, represented build commits and dirty-state markers,
  analyser revision, guard-manifest revision, tool-manifest revision, and
  catalogue-snapshot digests; and
- emit `currentStaticState`, `observedByBuild`, and the derived action state
  separately, rejecting a matching-build dead/live contradiction.

Phase 0A establishes the static guard contract. The analyser validates the
finite guard and static tool manifests, including generated and platform-gated
definitions. `--check-corpus-manifest` validates the immutable private input
and every pinned schema-v1 catalogue snapshot, verifies canonical definition
fingerprints and segment/file provenance joins, and structurally counts only
normalized tool-result submissions. The full `--corpus-manifest`,
`--guard-manifest`, `--tool-manifest`, and `--output` command now emits private,
deterministic definition-level tool residency evidence. It preserves every
static definition and every configuration-scoped dynamic definition, including
zero observations, and links them to named, intercepted, or generic fallback
bindings. Guard observation rows and derived action states remain a later
slice.

`--require-clean-source` checks the classified `lib/` paths plus the analyser
and checked-in manifests against the resolved source commit. Findings documents
may be uncommitted; changes to classified code or measurement definitions may
not be.

Keep the corpus manifest private because paths, session identifiers and log
content are sensitive. Store it under Caverno's private home, for example
`${CAVERNO_HOME:-$HOME/.caverno}/tmp/chat_notifier_inventory_corpus.json`, and
do not commit it or the measurement output. The manifest must pin each file by
path and SHA-256 and record its represented build revision and dirty state. For
every file it must also define complete, non-overlapping timestamp segments,
each with `startTimestampInclusive`, `endTimestampExclusive`, a non-secret
`configurationFingerprint`, `catalogueSnapshotPath`, and
`catalogueSnapshotSha256`, plus the exact snapshot-capture command and exporter
revision. This supports configuration changes within one log file and gives
every record exactly one snapshot join; gaps, overlaps and out-of-range records
are errors.

Each pinned snapshot must contain the full catalogue for its represented
runtime configuration, including dynamically fetched MCP definitions, with
secrets removed. Request-level `tools` arrays are not complete snapshots when
definition search sends only a subset.

Use this exact measurement entrypoint after creating the manifest:

```bash
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --corpus-manifest "${CAVERNO_HOME:-$HOME/.caverno}/tmp/chat_notifier_inventory_corpus.json" \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --tool-manifest tool/chat_notifier_tool_catalog_inventory.json \
  --output "${CAVERNO_HOME:-$HOME/.caverno}/tmp/chat_notifier_inventory_measurements.json"
```

The checked-in `tool/chat_notifier_guard_inventory.json` is the finite source
of truth for Investigation 1. At minimum, each entry records `id`, `path`,
`symbol`, `kind`, `selectionRoots`, `staticEdges`, `reachabilityImpact`,
`telemetryEvent`, and `unresolvedEdges`. The manifest also records the audited
source roots, discovery commands or rules, explicit exclusions, and source
revision. Every discovery result must be represented or explicitly excluded;
an open-ended list of interesting guards is not complete.

The checked-in `tool/chat_notifier_tool_catalog_inventory.json` is the finite
source of truth for built-in and locally registered definitions and handler
bindings. It must record each definition's stable name, binding kind, binding
symbol, registration path, configuration gate, discovery evidence, and whether
it resolves through the generic MCP fallback. Its discovery rules must cover
named registry bindings, intercepted tool paths, generated or platform-gated
definitions, and the generic fallback itself. Generate the initial manifest by
reviewing every discovery result, then make `--check-tool-manifest` re-run those
rules and fail on an unrepresented result or stale source revision.

Dynamic MCP definitions remain in the private per-configuration snapshots;
never copy their schemas or endpoint details into the checked-in manifest unless
they are already public repository data. The analyser must fail when a logged
configuration has no matching full catalogue snapshot. Treat each dynamic
definition as a definition-level row mapped to one generic fallback binding,
not as a bespoke resident handler.

Verify the tooling slice before using its output:

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py --help
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --check-tool-manifest tool/chat_notifier_tool_catalog_inventory.json
git diff --check
```

## Measured starting point

The following structural measurements were reproduced at source revision
`6ec71141`. Re-run the exact commands at the revision used by the investigation
and record that revision beside the output.

| Fact | Value | How it was obtained |
| --- | --- | --- |
| `lib` source files | 806 | `rg --files lib -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart' \| wc -l` |
| `lib` source lines | 231,093 | `rg --files lib -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart' \| xargs wc -l \| tail -n 1` |
| Files over 1,000 lines in `lib` | 40 | `rg --files lib -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart' \| xargs wc -l \| awk '$2 != "total" && $1 > 1000 { count += 1 } END { print count + 0 }'` |
| Declared chat_notifier parts | 37 | `rg -c "^part 'chat_notifier_.*\\.dart';" lib/features/chat/presentation/providers/chat_notifier.dart` |
| chat_notifier library lines | 19,683 | `wc -l lib/features/chat/presentation/providers/chat_notifier.dart lib/features/chat/presentation/providers/chat_notifier_*.dart \| tail -n 1` |
| Recorded manifest entrypoints | 414 | `jq '[.parts[].entrypoints[]] \| length' tool/chat_notifier_decomposition_manifest.json` |

The following are **historical evidence only** because their original notes do
not provide a complete reproducible command or their checked-in gate currently
needs reconciliation. Do not use them as a start gate or decision input until
a checked-in script re-derives them: 271 resolvable entrypoints; 798 lines of
owner/generation plumbing; 67 ambient reads, 50 turn-reachable; 9 pure members
totalling 82 lines; a 5.8 created-to-removed line ratio; and 377 `return null;`
statements, 376 without a nearby log. The turn-scope figures must ultimately be
re-derived with the baseline command in the renewal plan rather than copied
from this paragraph.

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
and the build revisions and dirty states represented, and report the private
manifest's digest with every count. Without that, results cannot be compared
across runs — a re-measurement during review produced 33 invoked tools where an
earlier note recorded 41, and there is no way to tell drift from a different
corpus. Do not publish sensitive file paths or session identifiers in the
findings documents. Select one clean source commit for static classification;
partition all observations by build and configuration, and derive action states
only from the partition matching that commit.

**Deliverable.**
`docs/chat_notifier_guard_reachability_inventory.md`, containing one row for
every entry in `tool/chat_notifier_guard_inventory.json`: where it lives, what
triggers it, observed firing count in the corpus, static selection roots and
edges, unresolved edges, reachability impact, telemetry coverage,
`currentStaticState`, `observedByBuild`, and an action state of dead /
unexercised / live / unresolved. For anything marked dead, include a reviewable
static proof that no selection root reaches it at the classified source
revision. The report is incomplete if a manifest entry is missing or a
discovery result is neither represented nor explicitly excluded.

**Watch for.** A mechanism can be live but only through a path the canaries
never take — that is neither dead nor healthy. Note it separately.

## Investigation 2: Tool catalogue residency

**Question.** Which tool handlers must be resident in the core turn loop, and
which could live behind a registry that the loop does not know about?

**Historical observations (do not treat as current).** An earlier note recorded
106 catalogue definitions, 41 tools observed in its corpus, and an eight-tool
67.6% share of tool results. The existing `tool/analyze_tool_results.py` can
recompute invocation counts and traffic share for the files it discovers, but
it cannot enumerate uninvoked definitions and therefore cannot reproduce the
106-definition count. Re-derive all three from the new manifest-driven
analyser. Say "observed in the pinned corpus", never "ever invoked".

**Why it matters.** `ChatToolHandlerCatalog` already exists, with its own
tests. `SubagentCatalogChildToolExecutionAdapter` can consume it, but that
adapter is also absent from the production composition path. The production
tool loop still builds
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

**Deliverable.**
`docs/chat_notifier_tool_catalog_residency_inventory.md`, with two linked
tables. The definition table contains every static-manifest definition and
every dynamic definition in each pinned configuration snapshot, including zero
invocations. The binding table contains each named or intercepted handler and
one explicit generic MCP fallback row. For each binding, report which notifier
state it reads, whether it needs approval/owner plumbing, and whether it could
be registered rather than wired. Flag any binding that reaches into turn state
in a way a registry could not provide. Include the read-only conclusion about
why the catalogue is currently unwired. Do not wire it in this investigation.

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

**Deliverable.** `docs/chat_notifier_concept_overlap_inventory.md`, with a
concept map that gives, for each pair, either a defensible reason they are
distinct or a proposed unification and what it would cost. Explicitly state
which of the four the *user* experiences as separate — a distinction that
exists only in code is a merge candidate; one the user relies on is not.

**Do not propose a unification you have not costed.** An estimate in
files-touched and behaviours-at-risk is enough; a guess is not.

This concept review may run in parallel with Investigations 1 and 2. It does not
block the bounded `TurnRuntime` prototype or the WS6-19 gate unless it finds a
confirmed dependency inside the ChatNotifier turn boundary. Routines are a
separate user-facing feature; their size alone is not evidence that they belong
in this renewal.

## Consolidated deliverable

Write `docs/chat_notifier_renewal_candidate_ranking.md`, stratified by confidence
first and ordered by size within each band — not a confidence × lines product,
which lets a large speculative candidate outrank a small certain one. Keep
delete candidates separate from investigate candidates throughout. Deletion is
the only reduction that avoids the historical extraction tax, so the
highest-confidence band is worth considering regardless of how little it
removes.

All four documents must record the source revision, exact inspection commands,
explicit exclusions, and unresolved items. Documents that use dynamic
measurements must additionally record the analyser revision, corpus manifest
digest, corpus file count, logged date range, and represented build revisions
and dirty states. Refer to the private manifest by digest and storage class,
not by sensitive absolute paths or session identifiers.

## Acceptance criteria

- The prerequisite source-of-truth and turn-scope-baseline reconciliation in
  the renewal plan is complete and recorded before Phase 1 begins.
- The checked-in guard manifest has finite discovery scope, represents or
  excludes every discovery result, and passes the focused analyser test.
- The checked-in tool manifest covers every static discovery result, separates
  named/intercepted handlers from the generic MCP fallback, and passes
  `--check-tool-manifest` at the classified source revision.
- The analyser rejects missing files, hash mismatches, absent build provenance,
  unknown or ambiguous commit prefixes, incomplete or overlapping configuration
  segments, missing catalogue snapshots, and malformed guard or transform
  records instead of silently skipping them.
- Re-running the analyser with the same source revision and corpus manifest
  produces byte-identical JSON output.
- Every guard manifest entry appears exactly once in the guard report. No dead
  classification has an unresolved edge or relies only on zero observations.
- Both dynamically measured reports separate current static reachability from
  observations grouped by build. The analyser canonicalizes `HEAD` and logged
  short hashes to one full commit; only clean sessions matching that commit
  derive live or unexercised states. A matching-build dead/live contradiction
  fails the run.
- Every statically enumerated tool definition appears in the residency report,
  including zero-invocation tools. Every dynamic definition in each pinned
  configuration snapshot is also represented, and no request subset is treated
  as a full catalogue.
- All dynamic counts say "observed in the pinned corpus" and are traceable to
  the measurement output; no finding claims lifetime frequency.
- The catalogue investigation remains read-only, and concept overlap does not
  become an implicit expansion into the routines feature.
- The consolidated ranking keeps dead, unexercised, live and unresolved
  candidates in separate action bands.

## Verification

Run and record:

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --check-tool-manifest tool/chat_notifier_tool_catalog_inventory.json
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --corpus-manifest "${CAVERNO_HOME:-$HOME/.caverno}/tmp/chat_notifier_inventory_corpus.json" \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --tool-manifest tool/chat_notifier_tool_catalog_inventory.json \
  --output "${CAVERNO_HOME:-$HOME/.caverno}/tmp/chat_notifier_inventory_measurements.json"
git diff --check
```

Also run the turn-scope baseline check from the renewal plan. A mismatch is a
blocking prerequisite to explain, not a baseline-refresh instruction.

## What success looks like

The renewal design can be written knowing what will not be migrated. If this
investigation finds nothing removable, that is a valid and useful result —
report it plainly rather than manufacturing candidates.

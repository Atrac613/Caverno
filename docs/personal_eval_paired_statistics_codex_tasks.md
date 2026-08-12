# Personal Eval Paired Statistics Tasks

## Task

- Goal: turn the existing Personal Eval bake-off into an evidence-backed
  comparison of coding performance between two models.
- User-visible behavior: comparison artifacts report paired success-rate
  effects and uncertainty instead of only a candidate-adoption verdict.
- Non-goals: inventing a composite intelligence score, collecting sessions
  without explicit consent, or running a large live corpus in the first slice.

## Context

- Affected components: `tool/personal_eval_suite_report.dart`, Personal Eval
  replay artifacts, and the local-only LL12/LL19 workflow.
- Related docs: `docs/local_llm_agent_roadmap.md` LL12, LL19, and LL39.
- Reference pattern: the existing report already pairs incumbent and candidate
  results by case ID and records verification, duration, turns, and tool calls.
- Compatibility rule: incomplete or inconclusive pairs must not be silently
  counted as verifier failures in a binary significance test.

## Task 1: Distinct-Case Paired Statistics

- Status: completed.
- Add candidate-minus-incumbent pass-rate difference with a deterministic 95%
  task-bootstrap interval.
- Add candidate-only and incumbent-only pass counts plus a two-sided exact
  McNemar p-value.
- Add paired medians for duration, turns, and tool calls in physical units.
- Keep missing and inconclusive pairs visible and excluded from binary tests.
- Emit the statistics in both JSON and Markdown and bump the report schema.

## Task 2: Repeated Trials And Hierarchical Uncertainty

- Status: completed.

### Task 2a: Repeated-Trial Artifact Identity

- Status: completed.
- Replay artifact schema v2 accepts `caseId#trialId` input keys while treating
  legacy `caseId` keys as `trial-1`.
- Each result records `trialId` and one-based `executionOrder`;
  `distinctCaseCount` records logical tasks while the legacy `caseCount` and
  the explicit `trialCount` continue to count all run observations.
- The offline generator and in-app domain artifact emit the same v2 contract.

### Task 2b: Hierarchical Task Aggregation

- Status: completed.
- Pair incumbent and candidate observations by case and trial ID.
- Aggregate repeated runs within each task before resampling tasks, preventing
  repeated deterministic runs from masquerading as independent evidence.
- Keep the existing single-trial report behavior backward compatible.
- Suite report schema v3 exposes effect-task, repeated-task, paired-trial, and
  excluded-trial counts. Its 95% interval resamples tasks first and paired
  trials within each selected task.
- Exact McNemar evidence uses only tasks whose conclusive trial outcomes are
  internally consistent for each model; mixed or incomplete tasks remain in
  the hierarchical effect estimate but are excluded from the exact test.

### Task 2c: Reproducible Execution Protocol

- Status: completed.
- Record production sampler settings, AB/BA model order, model warm-up, and
  execution budget so a repeated comparison remains reproducible.

#### Task 2c1: Protocol Contract And Validation

- Status: completed.
- Canonicalize model identity, endpoint, sampler settings, confirmed warm-up,
  execution limits, and case/trial execution order in a versioned JSON artifact.
- Reject duplicate trial identities, incomplete conditions, and globally or
  per-case unbalanced AB/BA order before a comparison begins.
- Render a matching Markdown protocol for review beside machine-readable output.
- Generate the reviewed artifacts with:

  ```bash
  dart run tool/personal_eval_experiment_protocol.dart \
    --config build/personal_eval/protocol-config.json \
    --out-dir build/personal_eval/reports
  ```

  The input config uses this shape; extend `trialOrders` with the consented case
  and trial identities before the pilot:

  ```json
  {
    "schemaName": "caverno_personal_eval_experiment_protocol",
    "schemaVersion": 2,
    "label": "27B vs 35B coding pilot",
    "studyIntent": "model_selection",
    "decisionCriteria": {
      "minimumEffectTaskCount": 20,
      "minimumHeldOutEffectTaskCount": 6
    },
    "incumbent": {
      "model": "qwen3.6-35b-a3b-vision",
      "baseUrl": "http://192.168.100.241:1234/v1",
      "samplerSettings": {
        "temperature": 0.2,
        "topP": 0.95,
        "maxTokens": 8192
      },
      "warmup": {"completed": true, "iterations": 1}
    },
    "candidate": {
      "model": "qwen3.6-27b-vision",
      "baseUrl": "http://192.168.100.241:1234/v1",
      "samplerSettings": {
        "temperature": 0.2,
        "topP": 0.95,
        "maxTokens": 8192
      },
      "warmup": {"completed": true, "iterations": 1}
    },
    "executionBudget": {
      "maxDurationMs": 900000,
      "maxTurns": 24,
      "maxToolCalls": 100
    },
    "trialOrders": [
      {"caseId": "case-a", "trialId": "trial-1", "first": "incumbent"},
      {"caseId": "case-a", "trialId": "trial-2", "first": "candidate"}
    ]
  }
  ```

#### Task 2c2: Replay Pipeline Wiring

- Status: completed.
- Make the replay pipeline consume the validated protocol and prove that each
  replay artifact matches its assigned model role, case/trial set, and order.
- Carry the protocol reference and validation result into the suite report so
  results cannot be separated from their experimental conditions.
- The CLI now requires `--protocol`. It rejects model or endpoint mismatches,
  missing or unexpected trials, execution-budget overruns, missing timestamps,
  ambiguous timestamps, and any observed cross-model execution order that does
  not match the declared protocol.
- Replay-run schema v3 records the earliest primary-turn `startedAt` in both the
  offline and in-app artifacts. Schema v4 also carries case origin and split.
  Suite-report schema v4 embeds the canonical
  protocol path, SHA-256 digest, label, validation status, and validated trial
  and execution-event counts. The pipeline copies canonical JSON and Markdown
  protocol artifacts into the result bundle.

## Task 3: 27B Versus 35B Coding Corpus

- Status: **executed twice; no difference established.** The 2026-08-12
  inventory found no usable recorded corpus (below), so the hybrid strategy was
  adopted and an authored corpus carried the comparison. The first run's
  `candidate_ready` verdict was withdrawn as infrastructure; the corrected
  re-run establishes no quality difference between the two models.

### Progress, 2026-08-12

Shipped:
- `tool/personal_eval_corpus/` — 42 authored tasks over four dependency-free
  fixtures (`textkit`, `datekit`, `taskflow`, `numkit`): **29 held-in, 13
  held-out** across 30 tier-1, 10 tier-2, and 2 tier-3 tasks. Each fixture is
  committed green and each task ships a seed that breaks one behaviour. The
  locked production protocol still selects the original 26-task, 104-event
  comparison; the 16 later tasks support corpus-design probes.
- `PersonalEvalCaseOrigin` — authored cases can never be reported as recorded
  evidence.
- `PersonalEvalAuthoredWorkspace` — materializes a fixture plus its seed into a
  temporary directory, so a replay never edits the repository tree (LL19 has no
  worktree isolation yet) and never sees other tasks' seeds.
- `PersonalEvalAuthoredCaseRunner` — per-case workspace lifetime: prepare,
  drive, verify in the same directory, dispose in a `finally`.
- Measurement hardening prevents a candidate from earning a pass by changing
  `bin/verify.dart` or `pubspec.yaml`; harness mutations are inconclusive and
  the verifier is not executed. Preparation failures also remove partial
  temporary workspaces.
- Replay-run schema v4 and suite-report schema v5 preserve `origin` and `split`
  through offline and in-app artifacts. The report exposes origin/split counts
  and rejects replay provenance that differs from its manifest.
- Corpus parsing accepts only `heldIn` and `heldOut`, requires a non-empty
  verifier command, and rejects malformed seed-root metadata.
- `PersonalEvalAuthoredChatReplayDriverFactory` now binds every candidate turn
  to a dispatcher created for that case's temporary workspace. The live agent
  loop can list and read the fixture, edit or write only under `src/`, and run
  only the case's exact verification command at the fixture root.
- The dispatcher rejects absolute and relative workspace escapes, symlink
  escapes, verifier or package-metadata mutations, arbitrary commands, and a
  verification command requested from any subdirectory. Focused integration
  coverage proves that a model tool call edits the disposable source through
  the real `RoutineToolRunner` path.
- `tool/personal_eval_authored_operator.dart` consumes the locked protocol,
  switches only the two comparison models through the validated router API,
  performs the declared warm-up, executes one isolated live canary per event,
  and atomically checkpoints every transition. `--resume` skips only completed
  event identities; a changed protocol digest or order is rejected.
- `tool/personal_eval_corpus/protocol_config.json` defines the production pilot:
  26 cases, two opposite-order trials per case, 104 total model events, and a
  pre-registered model-selection minimum of 20 effect tasks including 6
  held-out effect tasks. Temperature, top-p, and max-token settings now flow
  into the live requests.
- A side-effect-free full-corpus dry run produced the expected 104-event plan
  with zero completed events. Live execution was intentionally not started.

Guards that already caught bad tasks, and what each one proved:
- Red/green per seed: rejected two "tasks" whose seeds changed nothing
  observable, because the code they removed was unreachable.
- Seeded workspace must analyze clean: catches a seed whose dead leftovers
  would tell an analyzing model what went missing, and a seed gone stale
  against a grown fixture. The second case is invisible to red/green — a stale
  seed breaks compilation, which still reads as "starts red, ends green" while
  measuring the wrong defect.

Current live readiness, verified 2026-08-12:
- Router catalog: `qwen3.6-27b-vision` is loaded and
  `qwen3.6-35b-a3b-vision` is unloaded. The validated `GET /v1/models` and
  root-level `POST /models/load` / `POST /models/unload` surfaces remain live.
- The remaining decision is operational duration: 104 agent events are a
  multi-hour external run. Start it explicitly with `--execute`; use the same
  output directory plus `--resume` after interruption. The default invocation
  is always a side-effect-free dry run.

```bash
fvm dart run tool/personal_eval_authored_operator.dart \
  --protocol tool/personal_eval_corpus/protocol_config.json \
  --corpus tool/personal_eval_corpus/corpus.json \
  --out-dir build/personal_eval/27b-vs-35b-pilot
```

Use the same checkpoint for a four-event live pilot and the remaining run:

```bash
fvm dart run tool/personal_eval_authored_operator.dart \
  --protocol tool/personal_eval_corpus/protocol_config.json \
  --corpus tool/personal_eval_corpus/corpus.json \
  --out-dir build/personal_eval/27b-vs-35b-pilot \
  --execute --resume --max-events 4

fvm dart run tool/personal_eval_authored_operator.dart \
  --protocol tool/personal_eval_corpus/protocol_config.json \
  --corpus tool/personal_eval_corpus/corpus.json \
  --out-dir build/personal_eval/27b-vs-35b-pilot \
  --execute --resume
```

### Pilot re-analysis, 2026-08-12

The first full 27B/35B run reported `candidate_ready` on a +9.6 point paired
effect with a 95% CI of [+1.9, +21.2]. **That verdict is not supported.** The
same report's exact test found **zero discordant pairs** across the 21
internally consistent tasks — no evidence of any difference — and the two
statistics were never reconciled.

Tracing the five 35B task-level failures:

| Case | trial-1 | trial-2 | order |
|------|---------|---------|-------|
| `numkit_median_empty` | passed | failed — **proxy 500** | 38 |
| `numkit_percent_zero` | passed | failed — **proxy 500** | 42 |
| `textkit_truncate_exact` | passed | failed — **proxy 500** | 48 |
| `taskflow_backoff_overflow` | passed | failed (no error) | 26 |
| `numkit_split_remainder` | failed | failed | 33, 34 |

Four of the five passed in their other trial, so the model demonstrably solves
those tasks. Three failed with `InternalServerException: proxy error: Failed to
read connection (status: 500)` — the model never answered. All 35B failures sit
in the back half of a 52-trial run and the three proxy errors are in its last
quarter, which is degradation over the run rather than capability.

Re-running the report's own hierarchical bootstrap (seed and iteration count
reproduced its published interval exactly) with those three trials treated as
inconclusive:

| Inputs | Effect | 95% CI | |
|--------|--------|--------|---|
| As reported | +9.62 pt | [+1.92, +21.15] | excludes zero |
| Proxy 500 → inconclusive | **+3.85 pt** | **[0.00, +11.54]** | **includes zero** |

Removing three trials out of 52 erases 60% of the effect and the interval no
longer excludes zero. The residual difference rests on two tasks.

The statistics layer needed no change: the effect estimate correctly includes
every trial pair whose two sides are conclusive, and the exact test correctly
demands internal consistency. The defect was upstream — a transport failure was
recorded as a conclusive `failed` — and is fixed in the case runners, where a
thrown turn can no longer produce a failure verdict.

Still open before a verdict can be trusted:
1. **The proxy.** Three 500s in the last quarter of one run, on the layer the
   most recent commit introduced (`fix: route eval model switches through
   proxy`). A comparison cannot outrun an endpoint that degrades under load.
2. **A re-run** on the fixed scoring. The corrected numbers above are a
   re-analysis of recorded data, not a fresh measurement.
3. **Speed needs re-reading too.** 27B averaged 48.3 s against 35B's 23.0 s, but
   the 35B's proxy-500 trials terminated early and dragged its mean down, so the
   2.1x gap is an overestimate.

### Reconstruction probe, 2026-08-12 — hypothesis confirmed

Eight tasks were authored on the axis the earlier probe identified — delete an
algorithm with awkward boundaries rather than invert an operator — and run with
`split_and_rank` as a control (9 tasks x 2 models x 2 trials).

Criteria were fixed before the run. **Both were met on the primary one:**

| Case | 35B | 27B |
|------|-----|-----|
| `rebuild_format` | **fail, fail** | pass, pass |
| `rebuild_iso_week` | pass, pass | pass, **fail** |
| `rebuild_csv` | pass, pass | pass, **fail** |
| `rebuild_split` | fail, fail | fail, fail |
| `split_and_rank` (control) | fail, fail | fail, fail |
| `rebuild_add_months`, `rebuild_truncate`, `rebuild_backoff`, `rebuild_rank` | pass | pass |

**Three of nine tasks separate the models, and they separate in both
directions** — the 35B loses `rebuild_format` while the 27B loses
`rebuild_iso_week` and `rebuild_csv`. A corpus that only ever favours one model
would be suspect; this one does not. The turn range widened from 6.0-9.0 to
7.5-10.0, a smaller effect than the outcome divergence and not the main signal.

The corpus now spans a real difficulty range: four tasks both models solve, three
that discriminate, and two neither can solve. `rebuild_split` and the control
both defeat both models on the same underlying algorithm — remainder
distribution over negatives — which is corroboration rather than noise. The
control's earlier 27B pass (1/2) did not reproduce, so that single pass is best
read as luck.

**This is a design result, not a model comparison.** Nine tasks at two trials
cannot support a statistical claim about 27B versus 35B; what it establishes is
that the reconstruction axis produces items that discriminate, where the
inversion axis did not.

### Difficulty probe, 2026-08-12 — hypothesis falsified

The re-run showed the corpus does not discriminate: both models solved 24 of 26
tasks and turn counts sat in a 6-9 band. The hypothesis was that tier-1 prompts
hand over too much — they name the file and describe the correct behaviour — so
five harder tasks were authored and run (5 tasks x 2 models x 2 trials).

**The hypothesis was wrong.** Measured:

| Change | Result |
|--------|--------|
| Unguided prompt (no file name, no described behaviour) | **All 12 trials passed.** Turns rose from ~7 to ~8.5 — about one turn of extra work, no outcome change. |
| Two files instead of one | **No effect on its own.** `collapse_and_title` spans two files and both models solved it fully. |
| Removing an algorithm rather than inverting an operator | **This is what bit.** |

Localization was never the difficulty. The 35B's own trace names both sites
before editing: "The issues are in `src/money.dart` (split method) and
`src/stats.dart` (rank method)."

The one task that discriminated — `authored_numkit_split_and_rank`, 35B 0/2 and
27B 1/2 — did so because its seed sets `remainder = 0`, deleting the
remainder-distribution algorithm instead of inverting a comparison. The repair
has to be re-derived, and both models broke on the negative case: *"`split of a
negative preserves the total`: Expected -100, actual -97."*

So difficulty is governed by **reconstruction depth**, not by what the prompt
gives away or how many files are touched. The tiers are redefined accordingly:
inversion (1), reconstruction (2), reconstruction across sites (3). Prompt style
moves to its own `promptStyle` field, since it is measurable but worth about one
turn.

Under the corrected definition the corpus is **30 tier-1 tasks and one tier-3**,
which restates the original problem rather than solving it: authoring genuinely
discriminating tasks means seeding *missing algorithms with awkward boundary
cases*, and only one exists so far.

### Re-run result, 2026-08-12

104/104 events on the corrected scoring and the representative readiness probe.

| | First run | Re-run |
|---|---|---|
| Transport errors | **3** | **0** |
| 35B passed | 21/26 (80.8%) | **24/26 (92.3%)** |
| 27B passed | 25/26 (96.2%) | 25/26 (96.2%) |
| Paired effect | +9.62 pt | **+3.85 pt** |
| 95% CI | [+1.92, +21.15] | **[0.000, +11.54]** |
| Discordant pairs | 0 | 0 |
| Exact test | undefined | undefined |

The re-analysis of the first run's recorded data predicted +3.85 pt with a CI of
[0.000, +11.54]. The fresh measurement reproduced both to four decimal places,
so the diagnosis held: the original effect was carried by three proxy failures.

**Conclusion: no quality difference is established.** On the 24 tasks where both
models produced a conclusive result, both passed every one. Discordant pairs
are zero, the exact test is undefined, and the interval includes zero. The
residual difference is one task.

The two remaining failures are genuine, not transport:
`authored_numkit_split_remainder` (35B fails both trials, 27B fails one) is the
only task either model struggles with, and `authored_textkit_truncate_budget`
(35B fails one trial of two).

Speed should be read from the median, not the mean: the paired median
difference is **29.0 s** (28.97 s in the first run) — the 27B is about 29
seconds slower per task, and that figure is stable across both runs. The means
(35B 14.0 s, 27B 48.9 s) moved between runs because the first run's 35B mean
carried a 263 s outlier.

**Unresolved.** Transport errors went from three to zero, but the network path
changed at the same time (loopback relay, below), so this run cannot separate
"the readiness probe fixed it" from "the path changed". Both are plausible and
neither is isolated.

### Verdict logic, corrected 2026-08-12

The re-run still emitted `candidate_ready`. The verdict consulted no
statistics — it was `hardRegressionCount == 0` — so a report could publish
"no difference established" and recommend adoption in the same breath. Since the
verdict is what an operator acts on, correct statistics under an overstating
verdict fix nothing.

The interval-based verdict remains the statistical rule only after decision
eligibility is established. Above zero is `candidate_ready`, below zero is
`reject_candidate` even without a case-level hard regression, and an interval
spanning zero is `no_difference_established`. A report without sufficient
pre-registered evidence is now `insufficient_evidence`, and a corpus-design
study is `not_applicable`. `isSuccessful` deliberately remains the raw
regression signal and still drives the exit code; decision authority is exposed
separately. The profile handoff is fail-closed on both the recommendation and
decision eligibility, so an automated profile mutation stops and names the
evidence blocker.

## Task 4: Pre-registered Decision Authority

- Status: completed.
- Experiment-protocol schema v2 requires an explicit `studyIntent`:
  `corpus_design` or `model_selection`. Model-selection studies must also
  declare minimum effect-task and held-out effect-task counts before execution;
  corpus-design studies cannot declare adoption thresholds.
- Suite-report schema v6 carries the intent, thresholds, observed eligible
  counts, and concrete blockers. Recommendation logic cannot reach
  `candidate_ready`, `reject_candidate`, or `no_difference_established` until
  the pre-registered sample minimums are met.
- The profile handoff rejects missing legacy eligibility metadata and includes
  the detailed decision blockers in its artifact.
- The existing nine-task reconstruction artifact was re-rendered offline as a
  `corpus_design` study. Its raw result is unchanged: effect 0.0 percentage
  points, 95% CI [-27.8, +33.3], exact p=1.0, and two hard regressions. Its
  recommendation is now `not_applicable`, and profile mutation remains blocked.
- This slice intentionally does not start another live model run. Evidence is
  reclassified from existing artifacts before any new inference is authorized.

## Task 5: Difficulty Metadata And Stratified Evidence

- Status: completed.
- `PersonalEvalCase` now carries an optional tier and prompt style. Legacy and
  recorded cases remain `unclassified`; authored corpus entries must provide a
  tier from 1 through 3 and either `guided` or `unguided` prompt style.
- Case manifests, in-app and offline replay runs, and suite-report entries
  preserve both dimensions. Replay-run schema v5 and suite-report schema v7
  reject metadata that disagrees with the source manifest.
- Suite reports expose tier and prompt-style counts plus independent paired
  statistics for every observed stratum. The overall decision remains based on
  the pre-registered complete sample; strata are diagnostic evidence and do
  not introduce post-hoc adoption thresholds.
- Missing metadata is rendered as `unclassified`, preserving compatibility
  with recorded cases and artifacts created before this schema slice.

## Task 6: Offline Metadata Backfill

- Status: completed.
- `tool/personal_eval_artifact_metadata_backfill.dart` upgrades an existing,
  protocol-validated authored suite into a separate output directory. It joins
  the committed corpus to manifests and replay trials by exact `caseId`, rejects
  missing or conflicting metadata, and never writes to the source bundle.
- The tool upgrades the copied replay artifacts to schema v5, reclassifies the
  copied protocol as a schema-v2 `corpus_design` study, regenerates the
  schema-v7 report and profile handoff, and rejects the operation if the paired
  statistics or scored outcome counts change.
- The nine-task reconstruction probe was migrated without model inference:

  ```bash
  fvm dart run tool/personal_eval_artifact_metadata_backfill.dart \
    --corpus tool/personal_eval_corpus/corpus.json \
    --suite-dir build/personal_eval/rebuild-probe/suite \
    --out-dir build/personal_eval/rebuild-probe-stratified/suite
  ```

- The migrated artifact contains 9 cases, 18 paired trial identities, and 36
  replay executions: eight tier-2 tasks, one tier-3 task, and nine unguided
  prompts. Every observed stratum has
  a 0.0 percentage-point candidate-minus-incumbent pass-rate difference. The
  overall effect remains 0.0 points with 95% CI [-27.8, +33.3] and exact
  p=1.0. Recommendation remains `not_applicable`, and profile mutation remains
  blocked.

## Task 7: Held-out Reconstruction Expansion

- Status: authored and mechanically validated; live measurement not started.
- Added three held-out, unguided, objective-distinct tasks:
  `authored_datekit_rebuild_parse` reconstructs tokenized duration parsing,
  `authored_textkit_rebuild_slug` reconstructs the slug normalization pipeline,
  and tier-3 `authored_taskflow_rebuild_state_and_budget` reconstructs both the
  state-transition graph and retry-budget policy.
- Stable `objectiveFingerprint` values make the three acceptance objectives
  explicit. The corpus test rejects duplicate fingerprints within this slice.
- Every new seed starts verifier-red, remains analyzer-clean, and returns green
  when the committed implementation is restored. The tier-3 workspace test
  additionally restores each seeded file independently and proves that either
  partial repair remains red.
- This raises the corpus to 42 tasks: 29 held-in and 13 held-out, with 30
  tier-1, 10 tier-2, and 2 tier-3 tasks. No model-selection authority follows
  from authoring these fixtures; they require a pre-registered corpus-design
  run before their discriminating value is known.
- Verification passed on 2026-08-12: all 42 seed contracts and the committed
  green fixture passed in the 47-test corpus suite; 13 focused parser,
  lifecycle, analyzer-clean, and tier-3 partial-repair checks passed; repository
  analysis reported no issues.

## Task 8: Reconstruction Expansion Protocol Lock

- Status: completed, including the live corpus-design execution.
- `tool/personal_eval_corpus/reconstruction_expansion_protocol_config.json`
  fixes the three Task 7 cases as a `corpus_design` study. Each case has two
  opposite-order trials, producing 6 paired trial identities and 12 model
  events with an exact 6/6 incumbent/candidate balance.
- The protocol retains the measured sampler and execution budgets: temperature
  0.2, top-p 0.95, 8,192 output tokens, 900,000 ms, 24 turns, and 100 tool
  calls per event. It uses the documented loopback relay endpoint
  `http://127.0.0.1:18234/v1` for both model roles.
- A dedicated contract test proves that the selected cases are exactly the
  three new held-out, unguided tier-2/3 tasks, the AB/BA order is balanced both
  globally and per case, no model-selection criteria are present, and the
  operator dry run produces exactly 12 pending events.
- The side-effect-free dry run wrote
  `build/personal_eval/reconstruction-expansion-plan/` with zero completed
  events. The committed protocol SHA-256 is
  `858749ed631698605bfd337fa994744530d60e7520095ab911cf73202e802698`.

```bash
fvm dart run tool/personal_eval_authored_operator.dart \
  --protocol tool/personal_eval_corpus/reconstruction_expansion_protocol_config.json \
  --corpus tool/personal_eval_corpus/corpus.json \
  --out-dir build/personal_eval/reconstruction-expansion-plan \
  --execute --resume
```

- The live run completed all 12 events from the committed protocol with no
  operator or transport failures. The candidate passed all six verifications;
  the incumbent passed four and failed two. The slug task was stable at 2/2 for
  both models. The date-parser and tier-3 taskflow tasks were 2/2 for the
  candidate but mixed at 1/2 for the incumbent.
- Across the three task-level repeated effects, the candidate-minus-incumbent
  pass-rate difference was +33.3 percentage points with a hierarchical 95% CI
  of [0.0, +83.3]. Tier 2 was +25.0 points [0.0, +75.0], and tier 3 was +50.0
  points [0.0, +100.0]. Exact McNemar evidence was unavailable: the two mixed
  incumbent tasks were excluded from binary task aggregation, and the only
  remaining binary task passed under both models.
- The candidate median was 46.9 seconds slower despite using 0.5 fewer turns
  and 2.5 fewer tool calls. The two incumbent failures were conclusive verifier
  failures rather than transport failures: the date parser used a full-string
  token expression that rejected compound input, while taskflow exhausted its
  response budget after repairing an overflow but before re-verifying the
  final change.
- The report result is `passed`, but the recommendation is `not_applicable` and
  the profile handoff remains blocked because `corpus_design` studies do not
  authorize model selection. The local evidence bundle is under
  `build/personal_eval/reconstruction-expansion-plan/suite/`.
- The next bounded measurement should repeat only the two mixed tasks with a
  pre-registered, balanced order. It must establish whether the incumbent
  failures reproduce before these fixtures are used to justify a broader
  model-selection run.

## Task 9: Mixed-Task Repeatability Probe

- Status: completed, including the live eight-event repeatability run.
- Task 9a locks a second `corpus_design` protocol containing only
  `authored_datekit_rebuild_parse` and
  `authored_taskflow_rebuild_state_and_budget`. Each task receives two new
  opposite-order trial identities, for four paired trials and eight model
  events. Models, endpoint, sampler, execution budgets, and fixture revisions
  remain unchanged from Task 8.
- Task 9b adds a contract test for exact case selection, new trial IDs,
  per-case AB/BA balance, zero model-selection thresholds, and an eight-event
  dry run. It also locks the selected corpus, seed, implementation, and verifier
  file digests so the repeat does not silently change the source state. The raw
  protocol SHA-256 is
  `893dfde164ff360a520e90b379de044d81c07d7058303c717bea77a8f0859c74`.
- Task 9c executes the fixed plan with resume support and compares each model's
  per-task repeat pattern with Task 8. Transport or operator failures remain
  separate from conclusive verifier failures.
- Task 9d records the result without changing model-profile metadata. A stable
  repeat can justify designing a broader pre-registered model-selection study;
  another mixed result instead classifies repeatability as the binding corpus
  risk and sends the fixture or execution budget back for review.

Pre-registered interpretation per task:

- Candidate 2/2 and incumbent 0/2 reproduces the discriminating failure and
  retains the task as a candidate fixture for a later model-selection study.
- A 1/2 result for either model is a repeatability risk. It sends the fixture or
  execution budget back for review rather than establishing a model effect.
- Both models at 2/2 means the prior incumbent failure did not reproduce; the
  task is stable in this repeat but non-discriminating.
- Any candidate failure means the observed candidate advantage did not
  reproduce.
- Operator or transport failures are not scored; resume retries the same fixed
  event. Conclusive verifier failures remain completed observations.
- Every outcome remains `corpus_design` evidence. Task 9 cannot update a model
  profile or authorize candidate adoption.

```bash
fvm dart run tool/personal_eval_authored_operator.dart \
  --protocol tool/personal_eval_corpus/mixed_task_repeatability_protocol_config.json \
  --corpus tool/personal_eval_corpus/corpus.json \
  --out-dir build/personal_eval/mixed-task-repeatability-plan
```

The Task 9 report covers trials 3 and 4 only. Comparing the pattern with Task 8
is sufficient for fixture triage, but the current pipeline does not combine
both protocols into one four-repeat statistical artifact. A broader
model-selection study must use a new pre-registered protocol rather than treat
the two corpus-design reports as adoption evidence.

Live result, 2026-08-12:

- All eight fixed events completed without operator or transport failures. Both
  models passed both new trials for both tasks, so every model-task cell was
  2/2 and all eight verifier outcomes were green.
- The task-level candidate-minus-incumbent pass-rate difference was 0.0
  percentage points with a hierarchical 95% CI of [0.0, 0.0]. Both task pairs
  passed under both models, leaving zero discordant pairs and no exact McNemar
  result.
- The candidate median was 41.7 seconds slower while using 0.5 fewer turns and
  2.75 fewer tool calls. These efficiency signals do not change the
  verification conclusion.
- Under the pre-registered rule, the Task 8 incumbent failures did not
  reproduce. The date-parser and taskflow fixtures are non-discriminating in
  this repeat and must not be used to justify a broader model-selection run
  without redesign or new evidence.
- The report recommendation is `not_applicable`; the profile handoff is blocked
  and no model metadata was changed. The local evidence bundle is under
  `build/personal_eval/mixed-task-repeatability-plan/suite/`.
- The next bounded Personal Eval slice is fixture review, not more inference:
  determine whether the Task 8 failures came from stochastic response-budget
  exhaustion or whether the acceptance surface needs a harder, deterministic
  reconstruction case. Do not merge the two corpus-design reports into an
  adoption claim.

## Task 10: Enforce Authored Replay Budgets

- Status: completed; no follow-up live comparison was run in this slice.
- Trace comparison found that the Task 8 failures were not evidence of a
  fixture ceiling. The date-parser failure ended after eight model calls, all
  with `tool_calls`; taskflow ended after ten calls while still requesting a
  write. The successful repeats reached a terminal response or left externally
  verifiable green work.
- The protocol pre-registered `maxTurns: 24` and `maxToolCalls: 100`, but the
  authored live canary forwards only duration and sampler settings. Its replay
  driver therefore uses `RoutineToolRunner`'s unrelated fixed 5-iteration main
  loop plus 3-iteration final loop. The report currently presents unused
  budgets as though they governed execution.
- The bounded fix is to make the Routine runner accept optional total turn and
  tool-call caps while preserving its existing defaults, pass the protocol
  values through operator environment, canary config, authored driver factory,
  and replay driver, and cover both extended progress and hard cap behavior.
- Non-goals: changing production Routine defaults, changing fixture contents,
  rerunning a model, or combining Task 8 and Task 9 evidence.
- Acceptance: an authored replay configured above the legacy loop limit can
  execute the ninth required tool action; `maxTurns` and `maxToolCalls` remain
  hard upper bounds; existing Routine callers retain the 5+3 defaults; and the
  focused driver, factory, operator, and protocol tests pass.
- `RoutineToolRunner` now accepts optional total turn and tool-call caps. The
  authored operator passes the pre-registered values through the live-canary
  environment and driver factory, while Routine and subagent callers that do
  not opt in retain the existing 5+3 loop bounds.
- Deterministic coverage proves an explicit 12-turn budget reaches and executes
  the ninth tool action, a four-turn budget performs no fifth completion, a
  three-tool budget performs no fourth tool action, and the default runner
  still stops after eight tool-action iterations. Focused replay-driver,
  factory, and operator tests remain green.
- Existing Task 8 and Task 9 reports remain historical observations of the old
  execution contract. Do not reinterpret or combine them after this fix. Any
  future comparison requires a new protocol and new trial identities.

### Re-run conditions, 2026-08-12

The re-run reaches the same upstream endpoint through a loopback relay
(`127.0.0.1:18234` → `192.168.100.241:1234`) instead of the LAN address the
first run used. This is not a preference: the `dart` binary that drives the
operator has no macOS Local Network grant, and a direct attempt fails
immediately with `No route to host, errno = 65`, while `curl` and `python3`
from the same shell reach the host normally. Verified per binary before
starting — dart to the relay returns HTTP 200, dart to the LAN address does
not.

**Recorded as a deviation, because it touches the very thing under
investigation.** The relay is a byte-level TCP forwarder that does not alter
HTTP semantics, and the two failure modes stay distinguishable: a proxy 500
still arrives as a 500 from upstream, while a relay problem would surface as a
connection error. So "did the 500s stop" remains answerable. It does mean a
clean re-run cannot *by itself* prove the readiness-probe fix was what stopped
them, since the network path also changed.

### Proxy investigation, 2026-08-12

What the failures are, measured from the run artifacts:

- **Immediate rejections, not timeouts.** All three 500s returned in 1.3-1.5 s,
  against a passing-trial median of 13.2 s (max 263.7 s). Nothing was generated.
- **Degradation across the run.** Non-passing trials by third: **0/34, 4/34,
  3/36**. The first third is clean.
- **Only the larger model.** All three hit the 35B; the 27B had none.
- **Not a readiness gap in the obvious sense.** The operator's warm-up is a real
  8-token completion with up to 12 retries, followed by a catalog check that the
  target is `loaded`. It succeeded immediately before each failure.

The gap it does show up in is the *shape* of the readiness check. Measured
against the live endpoint:

| Request | Payload | Prompt tokens |
|---------|---------|---------------|
| Warm-up (what readiness asserts) | 0.1 KB | **16** |
| The eval request sent right after | 41.6 KB | **9,471** |

Readiness is proven with a request ~600x smaller than the one that follows. In
a clean host state both succeed, so payload size alone is not the trigger; the
failures need the accumulated churn as well. The specific cause inside the
proxy or the host is **not established** — reproducing it needs the churn, which
is another multi-hour run.

Switching is also most of the run:

- Wall clock **143.5 min**, of which trial execution is 61.8 min (43%) and
  switching/idle is **81.7 min (57%)**.
- **103 model switches** — the protocol alternates on every single trial — at a
  mean 48 s of overhead each.

Recommended, in order:
1. **Make the readiness probe representative.** Gate on a request shaped like
   the eval's (tool catalog and a realistic prompt), not a 16-token ping. This
   converts the failure into a harness retry before anything is scored.
2. ~~Cut the switch churn.~~ **Reassessed and deferred (2026-08-12).** The
   recommendation was costed as a scheduler change. It is not:
   `PersonalEvalOperatorPlan.build` emits `[first, second]` per trial, and the
   pipeline validates the observed timeline against a *recomputed* alternating
   sequence, position by position. Blocking therefore requires changing the
   protocol contract and reworking a guard that currently proves a run followed
   its declared protocol.

   The benefit also shrank once (1) landed. Churn-induced failures are now
   caught by the readiness probe before anything is scored, and contained by
   the runner if they slip through, so what remains is wall clock (roughly 82
   minutes of a 143-minute run) and host stress — an efficiency win, not a
   correctness one. Against that sits a statistical cost: blocking clusters one
   model's executions in time, so residual drift lands asymmetrically, which is
   the confound interleaving exists to prevent.

   If it is taken up later, the non-weakening shape is to validate the observed
   order against the *declared* operator plan (`operator_plan.json` already
   carries an ordered event list) rather than against an assumed alternation.
   That keeps the guard exact while letting the schedule change.
3. **Retry an immediate 500.** A 500 returned in about a second is
   unambiguously not a model answer.

Already landed: a thrown turn can no longer produce a `failed` verdict, so a
recurrence costs coverage rather than corrupting the comparison.

### Original inventory (2026-08-12)

### Corpus inventory, 2026-08-12

| Source | Files | Grounded | Usable as distinct real coding cases |
|--------|-------|----------|--------------------------------------|
| Recorded eval cases (`personal_eval_cases.json`) | 1 | 1 | **0** |
| `~/.caverno/session_logs/coding` | 101 | 73 | **~2 distinct tasks** |
| `~/.caverno/session_logs/chat` | 1440 | 22 | **0** |

- The single recorded case is a **chat** question about a novel, not coding. It
  has `verificationCommand: null` with `verificationResult: passed`, so its pass
  is self-declared rather than mechanical, and its session ended
  `loop_limit_recovered`. It cannot anchor a verifier-based comparison.
- The 73 grounded coding sessions decompose as: 36 `Create a workflow
  proposal...` secondary calls (internal, not user tasks), 25 canary/benchmark
  fixtures, 6 runs of one macOS/iOS release task, 4 CLI2 smoke fixtures, and 2
  other internal requests. Distinct real user coding tasks: about two.
- Chat mode holds no coding-shaped work, and 1418 of its 1440 files are
  ungrounded — consistent with the known corpus-contamination note.
- **Canary fixtures must not become the corpus.** `cavernobench` already runs
  against them, so scoring the same fixtures would be circular, and they are
  deliberately hard rather than representative.

### What this changes

The statistics built in Tasks 1-2c are sound and ready; what they lack is data.
A corpus decision is required before any 27B/35B execution:

1. **Recording campaign** — record consented cases as real coding work happens.
   Faithful to LL12's intent, but the observed rate is roughly two distinct real
   coding tasks across two months of logs, so 20 pilot cases plus a held-out set
   is not reachable in a useful timeframe on its own.
2. **Authored task corpus** — deliberately write ~20 verifier-backed coding
   tasks against this repository, versioned like the benchmark suite. Available
   immediately and reproducible, but synthetic: it measures coding capability,
   not *this user's* work, and must be labelled as such wherever it is reported.
3. **Hybrid** — start with an authored corpus so the comparison can run, and let
   recorded real cases accumulate and progressively replace it. The same paired
   statistics apply to whichever corpus is current.

Until one is chosen, the acceptance criteria below stand but are unexercised.

### Original scope (unchanged)
- Record at least 20 distinct consented coding cases for a pilot and reserve a
  separate held-out confirmation set.
- Replay identical repository snapshots and verifier commands against
  `qwen3.6-27b-vision` and `qwen3.6-35b-a3b-vision`.
- Report verifier success, first-pass success where observable, turns to green,
  tool calls, duration, and user intervention separately; do not collapse them
  into an arbitrary point total.
- Randomize or alternate AB/BA execution order to reduce cache and host-load
  bias.

## Similar-Pattern Search

- Search terms: `personal_eval_suite_report`, `PersonalEvalBakeOffReport`,
  `schemaVersion`, `passRate`, `hardRegressionCount`.
- Inspected modules: offline suite report and pipeline, profile handoff parser,
  in-app bake-off report, replay run entities, and their focused tests.
- Follow-up: mirror the statistics in the in-app report after the offline
  artifact contract is proven.

## Acceptance Criteria

- Every binary statistic uses only cases with present, conclusive results from
  both models.
- A missing or inconclusive result increases the excluded-pair count.
- The exact test is symmetric when incumbent and candidate wins are swapped.
- Bootstrap output is reproducible from a declared iteration count and seed.
- Duration, turn, and tool deltas are explicitly candidate minus incumbent.
- Adoption and profile handoff fail closed when study intent, decision
  thresholds, or eligible sample counts are missing.

## Verification

```bash
tool/codex_verify.sh --test test/tool/personal_eval_paired_statistics_test.dart
tool/codex_verify.sh --test test/tool/personal_eval_suite_report_test.dart
tool/codex_verify.sh --test test/tool/personal_eval_replay_run_test.dart
tool/codex_verify.sh --test test/tool/personal_eval_experiment_protocol_test.dart
tool/codex_verify.sh --test test/tool/personal_eval_suite_pipeline_test.dart
tool/codex_verify.sh --test test/features/personal_eval/domain/entities/personal_eval_replay_run_test.dart
tool/codex_verify.sh
```

### Verification Result, 2026-08-12

- Focused personal-eval coverage passed: 136 tests.
- `fvm flutter analyze` completed with no issues.
- Code generation completed successfully and refreshed the committed Freezed
  and JSON serialization outputs.
- `tool/codex_verify.sh --no-codegen` completed successfully: 7,256 Flutter
  tests and 10 notification-relay tests passed, together with the workspace
  package and analysis checks.
- The ordinary wrapper was also exercised through its code-generation stage.
  It stopped at the generated-file cleanliness check because this task's
  generated updates were intentionally still uncommitted; the remaining
  stages are covered by the successful `--no-codegen` run above.

## Handoff Notes

- Summary: replay-run schema v5 preserves repeated-trial identity, observed
  start time, origin, split, tier, and prompt style. Suite-report schema v7
  pairs those trials,
  exposes evidence provenance, aggregates within
  logical tasks, emits a deterministic hierarchical task-bootstrap interval,
  binds validated experiment-protocol provenance to the result, separates raw
  outcomes from model-selection authority, and reports diagnostic strata.
- Risks: a small pilot can estimate a large effect but cannot establish a small
  model difference; the report must expose sample size and uncertainty.
- Follow-up: the Task 3 corpus inventory ran on 2026-08-12 and found no usable
  corpus — 1 recorded case (chat, no verifier command) and about two distinct
  real coding tasks in the logs, against a requirement of 20 plus a held-out
  set. Pilot selection is blocked until a corpus strategy is chosen; see the
  Task 3 inventory above.

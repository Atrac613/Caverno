# Knowledge Currency Track (KC1-KC5)

Design doc for the `KC` track in `docs/local_llm_agent_roadmap.md`: closing the
gap between a local model's training cutoff and the user's present environment.

Thesis 6 of the roadmap already names the problem — "local models are stale and
change weekly" — and LL10 answered one half of it. This track states the other
half precisely and plans the remaining work.

## 1. The Problem Is Not Missing Knowledge

The cutoff problem is usually stated as "the model does not know recent facts."
That framing produces the wrong mechanism, because a model that knows it is
missing something already behaves correctly: it searches, or it hedges.

The damaging case is the inverse. **The model does not know which of its beliefs
expired.** It answers with the confident fluency of a fact it learned ten
thousand times during training, and the fact was true in 2024.

Every freshness mechanism Caverno ships today is **pull**: the model must first
suspect staleness, then call `search_web`, `web_url_read`, or
`resolve_installed_dependency`. Suspicion is exactly the faculty a stale model
lacks. Prompt humility does not supply it either — it asks the model to make the
judgment call it is structurally unable to make.

The track rule follows directly:

> **Push what is cheap and certain. Pull only what is expensive. Never ask the
> model to decide whether it is stale.**

This is the same trigger/judge split the roadmap already applies elsewhere:
heuristics may nominate, ground truth decides.

## 2. Four Failure Classes, Four Different Grounds

Treating "knowledge cutoff" as one problem produces one bad mechanism. It is
four problems, and only one of them needs the network.

| Class | Example | Correct ground | Network? |
|---|---|---|---|
| 1. World facts | release dates, news, prices | web search | required |
| 2. API drift | writes the Riverpod 2 idiom against Riverpod 3 | project lockfile + installed source | **no** |
| 3. Environment facts | assumes Flutter 3.19 defaults on 3.44.8 | toolchain probe | **no** |
| 4. This repository | project conventions, prior decisions | repo map, skills, session memory, RAG track | **no** |

Class 2 and 3 are the leading hypothesis for damaging coding work, and they are
**fully answerable offline from the user's own disk**. KC1 must measure whether
they are actually the most frequent stale-error classes before later milestones
are promoted. That offline asymmetry is worth testing because it could remove a
high-value part of the cutoff problem without internet, indexing, or ranking.

Class 1 is the only one that needs the network; KC1 measures its relative size
rather than assuming it. Class 4 belongs to the RAG track and is explicitly out
of scope here.

## 3. Current State (audited 2026-08-22)

- `SystemPromptConstants.knowledgeCutoffHumilityInstruction`
  (`lib/core/constants/system_prompt_constants.dart:30`), emitted at
  `system_prompt_builder.dart:118`. Prose humility. Delegates the judgment to
  the model, which is the faculty in question.
- `SystemPromptConstants.researchHonestyInstruction`
  (`lib/core/constants/system_prompt_constants.dart:37`). Prevents the model
  from *claiming* it searched. It does not prevent a confident stale assertion,
  which is honest by its own lights.
- `SystemPromptBuilder.build` (`system_prompt_builder.dart:847-856`) already
  emits the local datetime anchor on every turn. `TemporalContextBuilder.build`
  (`temporal_context_builder.dart:9`) conditionally adds only the expanded
  today/yesterday/week table when `_relativeDatePattern` (`:4`) matches. That is
  already the correct trigger/judge split: the cheap source-of-truth anchor is
  unconditional, while a heuristic only nominates extra explanatory context.
- `knowledgeCutoffHumilityInstruction` says "the current date above", although
  the dynamic datetime block is appended later in the prompt. That wording is a
  small prompt-order defect, not a missing-grounding mechanism, and should be
  corrected independently from KC2. Fixed in `1b05243fb`: the instruction now
  follows the datetime block in the dynamic tail.
- **LL10 `resolve_installed_dependency`** (`done`) is the one real ground-truth
  mechanism, and it is pull-only.

### 3.1 The LL10 blind spot worth naming

LL10 answers "does this symbol exist in the installed version," returning
`symbol_found` (`installed_dependency_grounding_service.dart:533`). That
detects an API the model *invented* or one that only exists upstream — the
failure LL10's canary measured and closed.

It cannot detect a **deprecated-but-still-present** API, and that is the shape
most real version drift takes: the v2 idiom still resolves under v3, compiles
with a deprecation warning, or — worse — resolves and behaves differently.
LL10 returns `symbol_found: true` and thereby *confirms the model's stale
belief*. KC3 exists for exactly this gap.

## 4. Milestones

### KC1: Cutoff Exposure Census

Status: `done` (2026-09-24). Measurement instrument; ships no production
behavior.

Closed 2026-09-24 with one scope item cut: classifying real answers from both
corpora for classes 2-4. The paired replays answered the question KC1 exists
for (the §4 gate: class 2 does not dominate, so KC3 was re-scoped), and every
acceptance criterion is met. The cut item was not worth its cost: the
real-session corpus is dominated by this repository's own release work (24 of
25 `pubspec.yaml` edits were version bumps), so a frequency drawn from it would
describe that workload rather than coding in general, and judging API use in
free-form answers would rebuild KC4's nomination stage. Real-use frequency is
better read from ground truth when KC2 is evaluated: LL11
`deprecated_member_use` diagnostics raised on code the model just edited.
Checked the same day: the real-session corpus holds only two post-edit analyze
feedback payloads (`caverno_dart_analyze_feedback`, deduplicated by message
id), both `undefined_method` from one session on 2026-09-19, and no
`deprecated_member_use`. That is too little to read a rate from, so KC2's
evaluation rests on the paired replay until post-edit feedback accumulates.

Following the LL31/LL36 precedent — build the instrument before the mechanism,
and never implement a fix whose target has not been counted.

Scope:
- Classify final answers across both corpora (the split recorded in
  `docs/canary_evidence_outside_the_corpus_2026-08-06.md`: coding evidence in
  `build/integration_test_reports`, interactive evidence in the session logs)
  for version-sensitive assertions, attributed to classes 1-4 of §2. Include
  assertions in visible prose, response code blocks, and changed code artifacts;
  API drift that appears only in a generated import or method call still counts.
- Use a versioned claim record with `claim_id`, class, asserted value, expected
  value, truth source, truth verdict (`correct`, `stale`, or `unscorable`),
  grounding verdict (`supported`, `contradicted`, or `absent`), and grounding
  provenance (`prompt_context`, `tool_result`, or `none`). A tool result being
  present is not itself proof that the claim is correct.
- Build a labeled deterministic fixture set with authoritative expected values,
  then replay the same prompts under fixed model, endpoint, sampler, build, and
  tool-catalog settings. Historical logs may seed cases but do not replace the
  paired replay.
- Report per-class stale-claim rate, unsupported-claim rate, and detector
  precision/recall. For class 3, also report environment-exposure rate: the
  fraction of scorable answers that redundantly restate an installed default.
  Do not collapse these into one aggregate that hides the network/offline
  boundary.

Acceptance criteria:
- A negative control passes: an arm fed deliberately stale fixtures must make
  the suite fail against the fixture oracle. A correct claim with `absent`
  grounding and a stale claim with `absent` grounding must receive different
  truth verdicts.
- A prompt-context control proves that KC2 evidence is attributed as
  `prompt_context`, not incorrectly reported as an absent same-turn tool result.
- Turn counts, corpus, and build provenance (`build.commit` / `dirty`) are
  recorded per run, together with model, endpoint, sampler, and tool-catalog
  identity; grounded logs only.
- Production prompt and tool behavior are unchanged.

Promotion gate:
- KC3 and KC4 stay `later` until claim correctness and class attribution exist.
  If class 2 does not dominate the measured stale claims, KC3 is re-scoped or
  dropped rather than built on assertion frequency or the argument in §3.1.

#### First measurement (2026-09-03)

Instrument: `tool/kc1_cutoff_exposure_census.dart` with `tool/kc1_cutoff_oracle.dart`.
Model `qwen3.8-27b-vision`, temperature 0.7, no tools attached, build `4cdd095e`.
Five fixtures, two arms, five repeats: 50 claims, plus a 10-claim re-run of one
fixture after its wording was corrected.

| case | class | bare | grounded |
|---|---|---|---|
| flutter-pop-scope (`WillPopScope` → `PopScope`) | 2 | 4/5 stale | 5/5 stale |
| color-with-values (`.withOpacity` → `.withValues`) | 2 | 2/5 stale | 2/5 stale |
| riverpod-notifier (`StateNotifierProvider` → `NotifierProvider`) | 2 | 1/4 stale | 1/5 stale |
| freezed-abstract (`class X with _$X` → `abstract class`) | 2 | 4/5 stale | 5/5 stale |
| repo-state-management (`ChangeNotifier` → `NotifierProvider`) | 4 | **5/5 stale** | **0/4 stale** |
| **class 2** | | **58%** | **65%** |
| **class 4** | | **100%** | **0%** |

**The asymmetry is the finding, and it is not the one KC2 was designed around.**

Naming the *dependency* fixes "what does this project use". The class 4 arm went
from every plan reaching for `ChangeNotifier` to none of them, because the block
listing `riverpod: 3.4.2` told the model which library the project holds state
in. A lockfile is repository evidence, not only version evidence.

Naming the *version* does not fix "what changed in that version". Class 2 did
not improve — 58% against 65%, inside the run-to-run noise. The block named
`freezed: 3.2.5` and the model still wrote the v2 declaration in five of five
grounded runs. A version number is actionable only where the model already
knows what that version changed, which is the same expired belief the block was
meant to correct.

So KC2 should carry **what changed**, not only which version — or the check has
to move to the symbol level after generation, where the oracle already holds the
answer. It should also expect its largest measured win to be class 4 rather than
class 2.

**Variance.** Three runs of this instrument disagree substantially on class 2's
grounded rate: 83%, 40%, 65%, at n ≤ 5 per cell and temperature 0.7. They are
recorded as separate observations rather than averaged. What is stable across
all three is that the bare class 2 rate is high and that grounding does not
reliably move it.

**Four instrument defects, each found by reading raw responses rather than by
reasoning about the numbers.** They are recorded because the pattern is the
point: every one of them would have been published as a fact about the model.

1. A substring match in the oracle reported `NotifierProvider` as legacy,
   because `StateNotifierProvider` contains it — which inverts the fixture it
   was meant to validate.
2. The deprecation-message extractor picked up apostrophes from prose above the
   annotation.
3. The class 4 pattern matched only `ChangeNotifierProvider`, and `\b` does not
   match inside the longer name. The model answered bare `ChangeNotifier` every
   time, so the arm scored *unscorable* and read as a model that had asserted
   nothing, when it had asserted the wrong thing five times out of five.
4. `color-with-values` first asked for "the expression for a Color at 50%
   opacity", which invites constructing a colour rather than transforming one.
   The model answered `const Color(0x80FF0000)` in eight of ten runs — neither
   idiom. Reworded to name an existing colour, the fixture scores 10 of 10.

**Scope, stated rather than implied.** Class 1 had no offline oracle by
definition; its registry-backed oracle landed 2026-09-23 (below), and sizing it
still needs a networked run. Class 3 now
has a separate oracle-backed verdict shape in the census tool: `required`,
`inherited`, `unnecessary`, `wrong`, or `unscorable`. The environment fixture
asks for a minimal Material 3 configuration without prescribing the
`useMaterial3` assertion. It reads the installed `ThemeData.useMaterial3`
default, treats omission on a true-default SDK as `inherited`, and reports an
explicit redundant `true` as `unnecessary`. The paired replay exposes that
latter case through a separate environment-exposure rate, while ordinary
truth/staleness remains distinct. The class 3 replay is now recorded below.
The §4 promotion gate, which asks whether class 2 *dominates*, is still open
because class 1 has no oracle yet and one environment fixture does not size the
whole class.

#### Second measurement (2026-09-03): what KC2 should carry

The first measurement said a version number only helps where the model already
knows what that version changed. A third arm tests the obvious next move before
KC2 is built around it: the version block **plus** a record of what those
versions changed, assembled by the oracle from the installed SDK's `@Deprecated`
annotations, riverpod's `legacy/` directory, and freezed's changelog.

Deliberately general rather than per-question — a block naming the exact
replacement for each fixture would measure instruction-following. It is capped
by release recency, which leaves `WillPopScope` (deprecated at v3.12) outside
the window and turns that case into the control.

75 claims, `qwen3.8-27b-vision`, five repeats, build `916b333b`.

| case | in digest | bare | +versions | +deltas |
|---|---|---|---|---|
| flutter-pop-scope | **no** | 5/5 | 4/5 | **4/5** |
| color-with-values | yes | 3/5 | 3/5 | **0/5** |
| riverpod-notifier | yes | 2/5 | 3/5 | **1/5** |
| freezed-abstract | yes | 4/5 | 5/5 | **2/5** |
| repo-state-management (class 4) | no | 5/5 | 1/2 | **0/5** |
| **all claims** | | **76%** | **73%** | **28%** |

**The delta block fixes the cases it covers and does nothing for the one it
does not.** Covered class 2 cases went from 9 of 15 stale to 3 of 15; the
uncovered one went 5/5 to 4/5. The control is what makes this a finding rather
than an observation that more text helps.

So KC2's content is settled by measurement rather than by argument:

1. **Carry what changed, not only which version.** On covered APIs this is the
   difference between 60% and 20% stale.
2. **Coverage is the design problem, not the mechanism.** A recency window
   decides which APIs are reached, and everything outside it stays exactly as
   stale as with no block at all. How the window is chosen — recency, the
   project's own imports, the symbols a draft actually used — is now the
   substantive KC2 question.
3. **Keep the version list anyway.** It is what fixes class 4: naming the
   dependency tells the model which library this project holds state in, and
   that case reached 0 of 5 with deltas and was already improving with versions
   alone.

### KC2: Environment And Dependency Ground Truth Block

Status: `current`. **Deliberately not gated on KC1**: it is deterministic, offline,
and introduces no heuristic, so there is nothing for a measurement to authorize.
KC1 measures its effect; it does not grant it permission.

Progress (2026-09-24): all five slices are done, and slice 5 is negative. `PubDependencyResolver`
(`lib/features/chat/data/datasources/pub_dependency_resolver.dart`) now holds
LL10's pub lockfile parser and root resolution, shared rather than duplicated,
and `DependencyInventoryService` attests each direct, non-SDK Dart dependency
as `exact` only when the lockfile version equals the version the installed
package declares, naming manifest, lockfile, and installed-metadata sources.
On this repository all 66 direct dependencies attest `exact`.
`EnvironmentGroundingContextBuilder` renders the block: Flutter and Dart
versions only when `package_config.json` and the SDK's own
`flutter.version.json` agree, attested dependencies with versions,
unattested ones named with versions withheld, a stated cut at 1,600
characters, and a cache keyed on file size and mtime. Slice 3 (`a07b951fa`)
puts the block in the dynamic tail directly after the datetime anchor, for a
coding-capable mode with a selected project; the stable prefix is unchanged
(tested). The gate lives in `ProjectPromptContextSource`, together with the
repo map's, because the ChatNotifier library had one line of ratchet slack.
Slice 4 (`749eb84d0`) appends the change digest: each attested package's
legacy library (`lib/legacy.dart` `show` lists and `legacy/` classes) and
its changelog's breaking entries within the installed release line, plus the
newest deprecations of an attested Flutter SDK. The SDK scanner moved from
the KC1 oracle into `InstalledChangeDigest`, and the oracle delegates to it.
Breaking entries must open with the marker ("Non-breaking updates" and
"Revert the breaking change" are not entries), and link targets, issue
numbers, and commit hashes are stripped. Slice 5 (`50c3b7a3e`, the seventh
KC1 measurement) ran the production block: class 2 stale 68/56/50% at the
default/32k/64k budgets against 60% bare and 30% for the prototype digest,
and class 4 **100% at every budget** against 75% bare and 0% for the
prototype, because every class 4 answer used the legacy providers the
digest's legacy line names. The block is live in coding prompts as of
`a07b951fa`/`749eb84d0`, so the keep-or-remove decision is open and
pressing.

The digest budget is spent in a fixed order (legacy lines unclipped, an SDK
allowance of 1,600 characters, then breaking entries round-robin across
packages) and steps with usable context. Coverage of the measured idioms on
this repository, with `WillPopScope` (deprecated at v3.12) as the uncovered
control at every budget:

| usable context | digest cap | `withOpacity` | riverpod legacy | freezed `abstract` |
|---|---|---|---|---|
| < 16k | none | no | no | no |
| unknown / 16k-32k | 1,600 | no | yes | no |
| 32k-64k | 6,000 | yes | yes | no |
| ≥ 64k | 10,000 | yes | yes | yes |

Stated plainly: the 10,000 step was added after the 6,000 budget was seen to
miss freezed's second breaking entry, so it is a coverage adjustment made
with a KC1 fixture in view. The general argument for it stands on its own
(the prototype spent ~3.8k characters on three hand-picked packages; all 31
packages here with entries need more, and 2.5k tokens is under 4% of a 64k
window), but slice 5 must report coverage per budget rather than only at the
most generous one.

Decided for slice 3 (2026-09-24): the cut on this repository dropped 7 of 66
dependencies at the default cap, `freezed` among them, a KC1 fixture package.
Rather than order by project imports, which the model's own edits would
change and so thrash the tail, the cap steps with LL39 usable context: 400
characters below 16k tokens (toolchain kept, dependencies dropped first, as
scoped), 1,600 by default and up to 32k, and 3,200 from 32k, which lists all
66 here. A step function, so profile noise does not move the bytes.

Review of this plan against the roadmap, 2026-09-24:

- **The measured content had not reached this scope.** KC1's second
  measurement settled that the block must carry *what changed*, not only which
  version (76% to 28% stale over 75 claims), and the cross-track index already
  said so, but this scope and its acceptance listed versions only. Built as
  written, KC2 would ship the arm that measured no class 2 improvement
  (73%). The change digest is now in scope below, and the KC3 re-scope depends
  on it.
- **The paired re-run must measure the production block.** The census builds
  its grounded arm from `groundTruthBlock` in `tool/kc1_cutoff_exposure_census.dart`,
  not from the KC2 builder, and uses its own one-line system prompt. A re-run
  that does not consume the builder's output measures the prototype again.
- **The class 2/4 baseline was not frozen as an artifact.** The 2026-09-03
  measurements survived only as tables. Resolved the same day: re-run on a
  clean build and frozen in `docs/evidence/` (sixth KC1 measurement), with the
  earlier findings reproduced.
- **"The existing prompt data-perimeter policy" does not exist by that name.**
  SEC1's classifiers cover tool content, not system-prompt blocks. The working
  precedent is the repo map: `ChatNotifierPromptContext._repoMap` emits only
  in coding mode for a selected project root. Slice 3 follows that gate and
  says so, rather than citing a policy that is not there.
- **Real-session value is unproven.** Replay is the only evidence: the
  real-session corpus holds two post-edit analyzer payloads and no
  deprecation diagnostic. The block costs up to ~400 tail tokens on every
  coding request, so the slice 5 re-run is a keep-or-remove decision, not a
  formality.

Scope:
- An `EnvironmentGroundingContextBuilder` that emits *measured* facts rather
  than a warning:
  - detected toolchain versions (Flutter/Dart, Node, Python) for class 3;
  - direct dependencies with attested installed versions and locked-version
    provenance for class 2;
  - a digest of what those versions changed, for class 2 (added 2026-09-24;
    see the review above).
- Preserve the existing unconditional datetime anchor and the conditional
  relative-date expansion unchanged. KC2 starts immediately after that dynamic
  datetime block; it does not add a second timestamp.
- Extract a shared dependency inventory from LL10's parsing and root-resolution
  logic rather than calling the current single-package tool or duplicating its
  private parsers. Each record carries manifest source, locked version,
  installed metadata source, installed version, resolved root, and an
  attestation verdict (`exact`, `mismatch`, or `unverifiable`).
- **Direct dependencies only**, sorted, hard-capped (target ≤400 tokens). Never
  the transitive closure. On a small-context profile (LL39 usable context) the
  dependency list is the first thing dropped; the datetime anchor is the last.
- Prompt placement is load-bearing. The block changes per project and per
  lockfile edit, so it belongs in the same tail region as temporal and memory
  context, never in the LL6/LL22 stable prefix. Within a project its bytes must
  be stable turn-to-turn so the tail does not thrash.
- Inventory collection is cached by canonical project root plus manifest and
  installed-metadata fingerprints. Do not spawn toolchain commands or rescan
  dependency trees on every request.
- Emit dependency details only for an explicitly selected coding project and
  through the existing prompt data-perimeter policy; private package names are
  project metadata even when collection is offline.

Why it works where prose does not: "your knowledge may be outdated" is
unactionable, and the model cannot act on it without already knowing what
changed. "flutter_riverpod 3.1.2 is what is installed" is a fact it can write
code against.

Acceptance criteria:
- Deterministic golden output per ecosystem; no network call on any path.
- A missing or unreadable lockfile omits the block. It never guesses a version.
- A lockfile/installed-metadata mismatch is labeled and omitted from the
  authoritative dependency list; `unverifiable` never becomes an exact claim.
- Byte-identical block across two consecutive turns in the same project.
- A paired KC1 re-run reports the change in class 2/3 stale-claim rate and
  unsupported-claim rate, and the class 1 stale rate as a non-regression check.
  The re-run's grounded arm consumes the production builder's output, not the
  census's prototype block
  (added 2026-09-24: the installed block can steer a new-project dependency
  choice to the lockfile line). If neither moves, that is recorded as a negative
  result — not a reason to keep tuning the wording.

Known risk (must be handled, not deferred): **the block carries authority.** If
`pubspec.lock` is stale relative to what is actually installed, the block states
a wrong version with full confidence — strictly worse than saying nothing.
Resolving an installed root is not sufficient because the current LL10 result
still reports the lockfile version. Mitigation requires comparing version-bearing
installed metadata (`pubspec.yaml`, `package.json`, or `dist-info` `METADATA`)
with the lock record and naming both sources in the inventory result.

#### Third measurement (2026-09-03): the post-generation check, replayed offline

The second census left coverage as KC2's open problem: a prompt block has to
guess which APIs will matter before the model writes anything. KC4 does not have
that problem by construction — it reads the answer. `tool/kc1_post_generation_check.dart`
replays the 75 dumped responses against an **uncapped** stale-symbol index built
from the same oracle, with no model, no endpoint and no new requests.

| | KC2 digest | post-generation index |
|---|---|---|
| symbols | 40 (recency-capped) | **157** |
| which APIs it must choose | before generation | none — it reads what was written |
| `WillPopScope` (v3.12) | outside the window | **in the index** |

Result over 75 responses, 42 labelled stale:

- **Recall on deprecation-class staleness is 25 of 25.** Every stale usage of
  `WillPopScope`, `.withOpacity` and `StateNotifierProvider` was caught,
  including the case the delta block could not reach. It also flags the
  deprecated *parameter* beside the widget — `onWillPop` as well as
  `WillPopScope` — which a prompt block has to spend a separate line on.
- **Recall overall is 27 of 42 (64%), and every miss is outside what a symbol
  index can see**: 11 on `freezed-abstract`, whose staleness is a codegen
  contract rather than a name, and 4 on `repo-state-management`, where
  `ChangeNotifier` is not deprecated by anyone — it is simply not what this
  repository does. Those need a changelog reader and a repo-convention oracle
  respectively, not a bigger symbol list.

**And the run supplies empirical support for the clause in KC4 that reads like
boilerplate.** The design says the verdict comes only from ground truth and that
a pattern "may trigger verification but never decide correctness". Bare-name
matching flagged 14 of 30 *correct* answers, and almost every flag was a
collision on a common word — `alpha`, `value`, `builder`, `of`, `blue` — because
those are deprecated field names somewhere in the SDK and a bare name has no
receiver type. `.withValues(alpha: 0.5)`, the current idiom, trips `alpha`.

As a **nominator** that is fine: nineteen nominations over thirty answers is
cheap to verify. As a **verdict** it would fail KC4's own precision gate on its
first run. So KC4's verdict must come from LL11 `deprecated_member_use`, which
knows the receiver's type, and the name index is only what decides where to
look. That is what the design already said; this is the measurement that shows
what it costs to ignore it.

Implications for the track order:

1. KC4's nomination stage is measured and has a 100% recall ceiling on
   deprecation-class staleness — the class KC2 can only partly reach.
2. KC2 remains worth building for what happens *before* generation and for
   class 4, where naming the dependency is what fixes the answer.
3. `CutoffOracle` is already a working prototype of KC3's resolver: it answers
   "the symbol exists in both versions but the installed one deprecates it",
   which is KC3's stated acceptance criterion and the case LL10 answers wrongly.
   What it lacks is the LL10 response envelope and containment, not the lookup.

#### Fourth measurement (2026-09-23): class 3 environment exposure

One oracle-backed environment fixture, three arms, five repeats: 15 claims,
`qwen3.8-27b-vision`, temperature 0.7, no tools, clean build `9d613c364`.
Flutter 3.47.4 reports `ThemeData.useMaterial3` defaulting to `true`. The task
asks for a minimal Material 3 configuration that preserves that installed
default and explicitly says not to add redundant overrides. The
[evidence record](evidence/kc1_class3_environment_exposure_2026-09-23.json)
includes all fifteen raw answers; the exact
[census output](evidence/kc1_class3_environment_exposure_2026-09-23_census.json)
and [offline replay](evidence/kc1_class3_environment_exposure_2026-09-23_postgen.json)
are retained with matching SHA-256 hashes.

| arm | required | inherited | unnecessary | wrong | unscorable | exposure among scorable | unsupported |
|---|---:|---:|---:|---:|---:|---:|---:|
| bare | 0 | 0 | 4 | 0 | 1 | **100%** | 100% |
| +environment fact | 0 | 0 | 5 | 0 | 0 | **100%** | 0% |
| +environment fact + deltas | 0 | 0 | 5 | 0 | 0 | **100%** | 0% |

**The environment fact fixed attribution, not behavior.** Grounded answers are
supported rather than absent because the prompt carries the installed default,
but every scorable answer still wrote `useMaterial3: true`. The delta block did
not move the result either. This is the negative result the acceptance rule
requires preserving: do not tune the fixture wording merely because the rate
did not improve.

All 15 raw responses were inspected. Fourteen contain a literal
`ThemeData(... useMaterial3: true)` and match `unnecessary`. The one
`unscorable` response uses
`copyWith(useMaterial3: existing.useMaterial3 ?? true)`, not a literal
constructor setting, so excluding it is correct. The offline post-generation
replay likewise labels fourteen behaviorally correct and one unscorable. Its
bare-name nominator flags `Theme.of` through the common symbol `of`; that is the
receiver-less false-positive class already measured above and is not used for
the environment verdict.

This closes the class 3 measurement gap for the present fixture without
claiming population-level dominance. The remaining KC1 implementation slice is
the class 1 network oracle.

#### Class 1 instrument (2026-09-23): the registry is the oracle

Class 1's correct ground is the network, but for the world facts a coding
answer actually asserts, the network has a deterministic answer: the package
registry. `tool/kc1_world_fact_oracle.dart` reads pub.dev's
`/api/packages/<name>` for the latest stable release, and the census scores the
release line a pubspec constraint names against it:

- `current` — the constraint names the latest line (`^4.0.0` when 4.0.2 is
  latest, or a range that admits it);
- `behind` — an older line: the expired belief KC1 measures;
- `ahead` — a version newer than anything published. Counted as not correct,
  but kept apart so a fabrication is never read as a cutoff effect;
- `unscorable` — no entry, `any`, conflicting entries, or an unparsed form.

Truth maps `current` to `correct` and the other two to `stale`; grounding and
provenance keep their shared meaning. Four fixtures ask for the dependency
entries of **a new app, created today**, on the package's current stable
release: freezed, go_router, and flutter_riverpod moved a major within the
last year, and dio has not and is the control. The fixture names no version;
the snapshot decides every expected value, and a stale snapshot flips the
verdict on the same response (the negative control, tested).

**The two oracles disagree, and that is kept as a measurement.** This
repository locks freezed 3.2.5 while pub.dev's latest is 4.0.2, and Flutter
3.47.4 against a 3.47.5 stable. A new-project answer that copies the lockfile
is correct about this project and stale about the world. So class 1 runs its
own arms — bare, the unchanged installed-toolchain block, and a
`worldFactGrounded` block carrying the registry versions — and the middle arm
measures whether the installed block drags a new-project answer back to the
installed line. The idiom and environment fixtures keep their three arms, so
their replay baseline is unchanged.

**A world fact expires.** Each run records the snapshot it was scored against
(source URL, publish date, fetch time) in `run.worldFacts`. Runs against
different snapshots are not paired; `--world-facts` replays a frozen one and
`--save-world-facts` freezes it. The snapshot fetched at build `86bf4e28c` is
kept as [evidence](evidence/kc1_class1_world_facts_2026-09-23.json) for the
first paired measurement. `--offline` leaves class 1 out entirely.

The first live attempt on 2026-09-23 never reached the model: the `dart`
binary had lost its macOS Local Network grant. It was restored and the
measurement ran the next day.

#### Fifth measurement (2026-09-24): class 1 world facts

Four registry-backed fixtures, three arms, five repeats: 60 claims,
`qwen3.8-27b-vision`, temperature 0.7, no tools, clean build `0b29c6b3f`,
scored against the frozen 2026-09-23 snapshot. The
[evidence record](evidence/kc1_class1_world_facts_2026-09-24.json) holds all
sixty raw answers plus SHA-256 hashes of the
[census output](evidence/kc1_class1_world_facts_2026-09-24_census.json) and
the snapshot. No request failed.

| case (latest) | bare | +installed block | +registry block |
|---|---|---|---|
| freezed (4.0.2; installed 3.2.5) | 5/5 behind (`^2.5.x` ×4, `^3.2.0`) | 5/5 behind (`^3.2.5` ×5) | 0/5 |
| go_router (18.0.1; not installed) | 5/5 behind (`^14.x`) | 5/5 behind (`^14.x`) | 0/5 |
| flutter_riverpod (3.4.3; installed 3.4.3) | 5/5 behind (`^2.x`) | 0/5 | 0/5 |
| dio (5.11.1; control) | 0/5 | 0/4, 1 empty response | 0/5 |
| **stale rate** | **75%** | **53%** | **0%** |

**Every package that moved a major in the last year was stale in every bare
answer: 15 of 15.** The control, whose major has not moved, was current 5 of
5, so the fixtures discriminate rather than failing every answer. The bare
answers are not random either: freezed was written as `^2.5.2` in three of
five, which is a remembered version, not a guess.

**The installed-toolchain block helps only where installed equals latest, and
drags the answer to the lockfile where it does not.** flutter_riverpod went
from 5/5 stale to 0/5 because the block's `3.4.3` happens to be the latest
release. freezed moved from the 2.x line to the installed `^3.2.5` in all five
answers, still one major behind, for a task that says *a new app, created
today*. go_router, which the block does not list, did not move. This is the
lockfile drag the grounded arm was kept to measure: a KC2 block improves a
new-project claim only by coincidence, and can anchor it to the wrong line.

**The registry block reads as attribution, not knowledge.** 20 of 20 answers
repeated the block's exact version. That proves the claim is groundable in
prompt context and that provenance is attributed correctly; it says nothing
about what the model knows, because the block names the answer.

**Read against the §4 gate.** The first measurement put class 2's bare stale
rate at 58% over its fixtures; class 1's is 75% here, and 100% on the
packages that moved. At n = 5 per cell, and with different fixtures, these do
not rank the two classes. They do show that class 2 does **not** dominate the
measured stale claims, and the gate's rule for that outcome is that KC3 is
re-scoped or dropped rather than promoted.

#### Decision (2026-09-24): re-scope KC3, do not drop it

The gate exists so KC3 is not built on assertion frequency or on the §3.1
argument alone. Neither is what now supports it. The second measurement
showed the mechanism KC3 serves, installed-version change evidence, cutting
covered class 2 claims from 9/15 stale to 3/15, while the case the digest did
not cover stayed stale (4/5). What it did not show is that class 2 is *the*
problem, and the fifth measurement shows it is not the only one. So KC3 keeps
its mechanism and loses its priority claim:

1. **KC3 is the pull side of KC2's delta content, scoped to coverage.** KC2
   pushes a recency-capped digest of what the installed versions changed; the
   measured weakness is what that window leaves out (`WillPopScope`). KC3's
   job is the on-demand lookup for a package or symbol outside the pushed
   window, from the same inventory and the same oracle logic, not a second
   channel for what KC2 already carries.
2. **KC3 is not a class 1 remedy and must not be presented as one.** It
   answers "what did the installed version change". It cannot answer "what
   is the current release", and the fifth measurement shows installed-version
   evidence is at best neutral for that question: it anchored freezed to the
   lockfile line.
3. **Status stays `later`.** Promotion needs KC2 shipped and a paired re-run
   showing which class 2 claims remain stale because the push window missed
   them. That number is what KC3 would be built to reduce.

Two consequences outside KC3:

- **KC2 gains a class 1 non-regression check.** Its paired re-run reports the
  class 1 stale rate alongside classes 2 and 3. The installed block did not
  raise it here (75% bare, 53% with the block), but freezed shows the block
  can steer a new-project choice, and the block's scope, "installed for this
  project", is not something the model reliably respected.
- **Class 1 has no owning milestone.** For dependency choices the ground truth
  already exists in the toolchain: `dart pub add <package>` resolves the
  current compatible release itself, so a version written by hand is the only
  place this staleness can enter. Whether Caverno's coding turns add
  dependencies by editing `pubspec.yaml` or through the package manager is
  unmeasured; that is the question to answer before any class 1 milestone is
  proposed. Nothing in `lib/` currently steers toward `pub add`.

**Answered the same day, from the real-session corpus.** 2,872 distinct tool
calls (deduplicated by call id from logged responses, not grepped) across 131
session logs, 2026-06-26 to 2026-09-23:

| manifest activity | calls |
|---|---:|
| package-manager commands (`pub add`, `npm install`, `pip install`, ...) | **0** |
| `pubspec.yaml` edits | 25 |
| ... of which release version bumps (`version: 1.3.x+n`) | 24 |
| ... of which a dependency added | **1** |

The one addition (session `64b978ca`, 2026-09-11) was hand-written:
`shared_preferences: ^2.5.3`, when pub.dev's latest was 2.5.5. By this
instrument's release-line rule that is `current`, because shared_preferences
has stayed on 2.x since 2021.

So the only entry path observed is the hand-written version, which confirms
where class 1 staleness would enter, and it was observed once in three months
on a package that had not moved. Real exposure is too rare to justify a class 1
milestone on current evidence, and none is proposed. Reopen it if dependency
additions become a regular part of coding turns. The canary corpus was not
checked: `build/integration_test_reports` currently holds only
`flutter test` reporter output, not session logs.

#### Sixth measurement (2026-09-24): class 2 and 4 baseline, frozen

The first two measurements survived only as tables, so the build order's
"freeze the baseline before KC2 lands" step was unmet. Re-run on clean build
`25907eb35`, before any KC2 prompt wiring: five idiom fixtures, three arms,
five repeats, 75 claims, `qwen3.8-27b-vision`, temperature 0.7, no tools, no
request failures. Raw answers and the census output are frozen in
[`kc1_class24_baseline_2026-09-24.json`](evidence/kc1_class24_baseline_2026-09-24.json)
and [its census](evidence/kc1_class24_baseline_2026-09-24_census.json).

| case | in digest | bare | +versions | +deltas |
|---|---|---|---|---|
| flutter-pop-scope | no | 4/5 | 3/4 | 4/5 |
| color-with-values | yes | 4/5 | 1/5 | 0/5 |
| riverpod-notifier | yes | 2/5 | 2/5 | 1/5 |
| freezed-abstract | yes | 2/5 | **5/5** | 1/5 |
| repo-state-management (class 4) | no | 3/4 | 1/4 | 0/4 |
| **class 2** | | **60%** | **58%** | **30%** |
| **class 4** | | **75%** | **25%** | **0%** |

It reproduces the 2026-09-03 findings rather than revising them: the delta
block halves class 2 staleness and does nothing for the uncovered
`WillPopScope`; the version list fixes class 4; and naming `freezed: 3.2.5`
alone again made the freezed case *worse* (5/5 stale, as on 2026-09-03). One
cell moved: color-with-values improved with versions alone (1/5), where it had
not before, which is inside the variance recorded for the first measurement.

Four answers were unscorable, and two expose a fixture gap rather than a
model property: the class 4 patterns do not recognize `ValueNotifier` or
riverpod's legacy `StateProvider`, both off-convention for this repository.
Recorded, not retuned: widening a pattern after reading the result is the
tuning the acceptance rule forbids. The other two used neither idiom
(`@riverpod` code generation; a `PopScope`-free confirm flow).

#### Seventh measurement (2026-09-24): the KC2 production block (slice 5)

The paired re-run through the production builder: all ten fixtures, the
block `EnvironmentGroundingContextBuilder` emits at three usable-context
budgets, five repeats, 150 claims, `qwen3.8-27b-vision`, temperature 0.7, no
tools, clean build `50c3b7a3e`, no request failures, class 1 against the
frozen 2026-09-23 snapshot. Raw answers and the exact block bytes per arm are
frozen in [`kc2_production_rerun_2026-09-24.json`](evidence/kc2_production_rerun_2026-09-24.json)
and [its census](evidence/kc2_production_rerun_2026-09-24_census.json).
Compared against the frozen baselines of the sixth, fourth, and fifth
measurements (same model and sampler).

| stale rate | bare | prototype versions | prototype deltas | production default | production 32k | production 64k |
|---|---|---|---|---|---|---|
| class 2 (API drift) | 60% | 58% | **30%** | 68% | 56% | 50% |
| class 4 (this repository) | 75% | 25% | **0%** | **100%** | **100%** | **100%** |
| class 3 exposure | 100% | 100% | 100% | 75% | 60% | 40% |
| class 1 (world facts) | 75% | 53% | - | 50% | 50% | 50% |

**The production block is a negative result, and on class 4 a regression.**
All fifteen class 4 answers reached for riverpod, which is the part the
dependency list gets right, and all fifteen wrote the legacy
`StateNotifierProvider` or `StateProvider`. The baseline arms did that in one
answer of five each. Those are exactly the names the digest's legacy line
lists ("flutter_riverpod 3.4.3 keeps these only in its legacy library: ...").
The prototype delta block also listed them ("riverpod moved these to legacy:
...") and scored class 4 at 0/4, so the difference lies in what changed
between prototype and production, and two things did at once: the legacy
line's wording, and the context around it (three packages in the prototype,
59-66 dependencies plus 31 packages' changelog entries in production). This
run cannot separate them.

Class 2 improves with budget (68%, 56%, 50%) but never approaches the
prototype's 30%. freezed-abstract stayed 5/5 stale even at 64k, where its
entry is present: coverage did not translate into behavior there. Class 3
exposure fell from 100% to 40-75% although no production arm states the
`useMaterial3` default; that is unexplained and, at n = 5, not a finding to
build on. Class 1 did not regress (50% against 75% bare), for the reason the
fifth measurement gave: flutter_riverpod's installed version happens to be
the latest.

Per the KC2 acceptance rule this is recorded as a negative result, not a cue
to tune the wording until the numbers move. The keep-or-remove decision it
feeds is recorded with KC2's status.

### KC3: Installed Version-Delta Evidence (LL10 Extension)

Status: `later`. Re-scoped 2026-09-24 by the §4 gate (see the KC1 decision
above): the on-demand lookup for what KC2's pushed delta window does not
cover. Promotion needs KC2 shipped and a paired re-run that counts the class 2
claims left stale by that window.

Closes §3.1 by extending `resolve_installed_dependency` through the shared KC2
inventory and resolver rather than creating a second package-resolution path.
Given a package and optional symbol, return the **attested installed version's**
CHANGELOG or migration section from the local package cache (pub cache,
`node_modules`, site-packages / `dist-info` METADATA), plus the deprecations that
version declares where the ecosystem marks them (`@Deprecated`, JSDoc
`@deprecated`, `DeprecationWarning`). Reuse LL10's existing documentation/source
result envelope and budgets. A new public tool name is justified only if
tool-discovery evaluation shows that an LL10 query mode is not discoverable
enough; it must never duplicate parsing, root resolution, or containment.

This beats web search on its own ground: search returns articles about the
*latest* version, which is not the version installed, and the mismatch is itself
a source of drift.

Why this is not a RAG milestone: no index, no ranking, no embeddings. It is a
path lookup keyed by the lockfile. It must not queue behind RAG1-RAG3.

Acceptance criteria:
- Fully offline; version-exact by construction.
- A fixture where the symbol exists in both versions but is deprecated in the
  installed one is answered correctly — the case LL10 answers wrongly.
- Changelog/deprecation evidence includes package, attested version, relative
  source path, line span, and truncation metadata under the existing LL10
  response-size limits.

### KC4: Cutoff-Sensitive Claim Guard

Status: `later`. Gated on KC1, then a shadow period.

Scope:
- A guard that reuses the `FinalAnswerClaimDetector` recovery plumbing but is not
  limited to visible prose. Assertion shapes such as "the latest is", "X is
  deprecated", "since vN", and their supported non-English equivalents
  **nominate** prose claims. Response code blocks, changed dependency-using code,
  and LL11 deprecation diagnostics nominate code-artifact claims.
- The verdict comes only from ground-truth evidence: KC3/LL10, LL11 diagnostics,
  compile/test output, or web results. Regexes and model-cutoff metadata may
  trigger verification but never decide correctness.
- The existing synthetic tool-result re-entry can serve prose claims. Artifact
  claims require a small turn-evidence adapter that carries changed paths,
  relevant diff excerpts, and structured diagnostics into the same bounded
  recovery decision; this is not accurately described as "a new detector only."
- **Degrade to annotation, never to blocking.** With no verifying tool available
  (offline, no lockfile, no search endpoint) the guard annotates and the answer
  ships. A local-first app that refuses to answer offline is worse than a hedge.

Anti-goals: no confidence scoring of the model's prose; no judgment rendered by
the regex.

Promotion gate:
- Shadow-only first: log firings without transforming any answer, and report
  precision and recall against KC1's labeled prose and code-artifact set. A stale
  API fixture that appears only in edited code must fire. Low precision or a
  material code-artifact false-negative rate means deletion or re-scoping, per
  the LL36 delete-by-measurement precedent — not an open-ended tuning pass.

### KC5: Model Cutoff Registry

Status: `later`.

Scope:
- A `knowledgeCutoff` field on the model capability profile, carrying a date and
  its source (`static_table`, `user_override`, `unknown`).
- **Never from self-report.** A model's claimed cutoff is training-data
  folklore; models routinely state it wrongly in both directions.
- Consumers: KC2 can state the gap in months as context (not as proof that any
  specific belief is stale); KC4 may use the gap to nominate verification work,
  never to render a verdict; MLIB2/MLIB3 provenance already wants the field.

Open question (unresolved, not assumed): whether an LL39-style dated-fact probe
can measure a cutoff empirically well enough to beat a static table. Recording
`unknown` honestly is preferable to a probed number nobody trusts.

## 5. Boundaries

- **No web-document cache, no embeddings, no ranking in KC.** That is
  RAG2/RAG3, and RAG4 owns durable external knowledge. The RAG track's own
  corollary applies: do not stand up a third knowledge store.
- **No automatic retrieval on every turn.** Automatic retrieval stays behind
  RAG5's shadow gates.
- **No change to the trust model.** Web-fetched freshness data remains external
  evidence under SEC1/SEC2 and never acquires instruction authority.
- Class 4 (this repository) is owned by repo map, skills, session memory, and
  the RAG track. KC does not touch it.

## 6. Build Order

1. **Capture the KC1 baseline before KC2 lands.** KC2 changes the prompt; once
   it ships, the before/after comparison is gone. This is the one ordering
   constraint in the track.
2. Freeze the KC1 baseline artifact, then implement KC2 while the remaining KC1
   analysis continues. KC2 needs no promotion permission, but must not erase the
   before arm. All four classes are frozen in `docs/evidence/` as of
   2026-09-24 (classes 2 and 4 in the sixth measurement).
3. KC3 only as the coverage complement to KC2's delta window, and only once
   a paired re-run counts what that window misses (re-scoped 2026-09-24,
   because KC1 did not show class 2 dominating).
4. KC4 in shadow, deleted if imprecise.
5. KC5 when a second model family is in regular production use; until then a
   static table for the one endpoint in use is not worth the schema change.

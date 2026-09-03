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
  corrected independently from KC2.
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

Status: `next`. Measurement instrument; ships no production behavior.

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
  precision/recall. Do not collapse them into one aggregate that hides the
  network/offline boundary.

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

**Scope, stated rather than implied.** Classes 1 and 3 are absent, and neither
is an oversight. Class 1 has no offline oracle by definition; sizing it needs a
networked run. Class 3 does not decompose into a two-idiom pair, because its
failure is an *unnecessary* line rather than a wrong one — a model setting
`useMaterial3: true` on an SDK where it is both the default and deprecated —
and that needs a different verdict shape. So the §4 promotion gate, which asks
whether class 2 *dominates*, is not yet answered; what this measures is class 2
against class 4.

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

Status: `next`. **Deliberately not gated on KC1**: it is deterministic, offline,
and introduces no heuristic, so there is nothing for a measurement to authorize.
KC1 measures its effect; it does not grant it permission.

Scope:
- An `EnvironmentGroundingContextBuilder` that emits *measured* facts rather
  than a warning:
  - detected toolchain versions (Flutter/Dart, Node, Python) for class 3;
  - direct dependencies with attested installed versions and locked-version
    provenance for class 2.
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
  unsupported-claim rate. If neither moves, that is recorded as a negative
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

### KC3: Installed Version-Delta Evidence (LL10 Extension)

Status: `later`. Gated on KC1 attribution.

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
   before arm.
3. KC3 only if KC1 shows class 2 dominates.
4. KC4 in shadow, deleted if imprecise.
5. KC5 when a second model family is in regular production use; until then a
   static table for the one endpoint in use is not worth the schema change.

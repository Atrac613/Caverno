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

Class 2 and 3 are the ones that damage coding work, they are the most frequent,
and they are **fully answerable offline from the user's own disk**. That is the
asymmetry the track exploits: the highest-value half of the cutoff problem needs
no internet, no index, and no ranking — only a lockfile and a path.

Class 1 is the smallest and the only one that needs the network. Class 4 belongs
to the RAG track and is explicitly out of scope here.

## 3. Current State (audited 2026-08-22)

- `SystemPromptConstants.knowledgeCutoffHumilityInstruction`
  (`lib/core/constants/system_prompt_constants.dart:30`), emitted at
  `system_prompt_builder.dart:118`. Prose humility. Delegates the judgment to
  the model, which is the faculty in question.
- `SystemPromptConstants.researchHonestyInstruction`
  (`lib/core/constants/system_prompt_constants.dart:37`). Prevents the model
  from *claiming* it searched. It does not prevent a confident stale assertion,
  which is honest by its own lights.
- `TemporalContextBuilder.build` (`temporal_context_builder.dart:9`) returns
  `null` unless `_relativeDatePattern` (`:4`) matches the user's input. Two
  consequences:
  - Its regex contains `latest|current|recent`, so it fires for questions
    *about* freshness, and stays silent for work that silently *depends* on it.
    "Define a provider with Riverpod" carries no date word and receives no
    temporal anchor at all.
  - It is a text heuristic that **judges** — it decides that no temporal
    grounding is needed — which the standing rule ("heuristics may trigger,
    never judge") rejects. The datetime line itself costs a few tokens; there is
    no reason for it to be conditional.
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
  for version-sensitive assertions, attributed to classes 1-4 of §2.
- For each assertion, record whether a ground-truth tool result in the same turn
  supports it, contradicts it, or is absent.
- Report per-class rates, not one aggregate. A single "staleness rate" would
  average the network-bound class into the offline-answerable ones and hide the
  asymmetry the track is built on.

Acceptance criteria:
- A negative control passes: an arm fed deliberately stale fixtures must make
  the suite fail. An instrument that cannot detect known-stale output is never
  reported as green.
- Turn counts, corpus, and build provenance (`build.commit` / `dirty`) are
  recorded per run; grounded logs only.
- Production prompt and tool behavior are unchanged.

Promotion gate:
- KC3 and KC4 stay `later` until the class attribution exists. If class 2 does
  not dominate, KC3 is re-scoped or dropped rather than built on the argument
  in §3.1 alone.

### KC2: Environment Ground Truth Block

Status: `next`. **Deliberately not gated on KC1**: it is deterministic, offline,
and introduces no heuristic, so there is nothing for a measurement to authorize.
KC1 measures its effect; it does not grant it permission.

Scope:
- An `EnvironmentGroundingContextBuilder` that emits *measured* facts rather
  than a warning:
  - the local datetime anchor, **unconditionally** (removing the
    `TemporalContextBuilder` trigger gap; the regex keeps its narrower job of
    expanding the relative-date table);
  - detected toolchain versions (Flutter/Dart, Node, Python) for class 3;
  - direct dependencies with their locked versions for class 2.
- Ecosystem detection reuses LL10's resolver rather than re-implementing
  lockfile parsing.
- **Direct dependencies only**, sorted, hard-capped (target ≤400 tokens). Never
  the transitive closure. On a small-context profile (LL39 usable context) the
  dependency list is the first thing dropped; the datetime anchor is the last.
- Prompt placement is load-bearing. The block changes per project and per
  lockfile edit, so it belongs in the same tail region as temporal and memory
  context, never in the LL6/LL22 stable prefix. Within a project its bytes must
  be stable turn-to-turn so the tail does not thrash.

Why it works where prose does not: "your knowledge may be outdated" is
unactionable, and the model cannot act on it without already knowing what
changed. "flutter_riverpod 3.1.2 is what is installed" is a fact it can write
code against.

Acceptance criteria:
- Deterministic golden output per ecosystem; no network call on any path.
- A missing or unreadable lockfile omits the block. It never guesses a version.
- Byte-identical block across two consecutive turns in the same project.
- KC1 re-run moves the class 2/3 rate. If it does not, that is recorded as a
  negative result — not a reason to keep tuning the wording.

Known risk (must be handled, not deferred): **the block carries authority.** If
`pubspec.lock` is stale relative to what is actually installed, the block states
a wrong version with full confidence — strictly worse than saying nothing.
Mitigation: prefer the resolved installed root (LL10's path) over the lockfile
when both are available, and name the source in the block.

### KC3: Version-Delta Documentation (`read_dependency_doc`)

Status: `later`. Gated on KC1 attribution.

Closes §3.1. Given a package, return the **installed version's** CHANGELOG or
migration section from the local package cache (pub cache, `node_modules`,
site-packages / `dist-info` METADATA), plus the deprecations that version
declares where the ecosystem marks them (`@Deprecated`, JSDoc `@deprecated`,
`DeprecationWarning`).

This beats web search on its own ground: search returns articles about the
*latest* version, which is not the version installed, and the mismatch is itself
a source of drift.

Why this is not a RAG milestone: no index, no ranking, no embeddings. It is a
path lookup keyed by the lockfile. It must not queue behind RAG1-RAG3.

Acceptance criteria:
- Fully offline; version-exact by construction.
- A fixture where the symbol exists in both versions but is deprecated in the
  installed one is answered correctly — the case LL10 answers wrongly.

### KC4: Cutoff-Sensitive Claim Guard

Status: `later`. Gated on KC1, then a shadow period.

Scope:
- A detector in the `FinalAnswerClaimDetector` family: assertion shapes such as
  "the latest is", "X is deprecated", "since vN" **nominate** a claim; the
  verdict comes only from a ground-truth tool result (KC3, LL10, or web). The
  existing plumbing already emits a synthetic tool result and re-enters the
  loop, so the mechanism is a new detector, not new machinery.
- **Degrade to annotation, never to blocking.** With no verifying tool available
  (offline, no lockfile, no search endpoint) the guard annotates and the answer
  ships. A local-first app that refuses to answer offline is worse than a hedge.

Anti-goals: no confidence scoring of the model's prose; no judgment rendered by
the regex.

Promotion gate:
- Shadow-only first: log firings without transforming any answer, and report
  precision against KC1's labeled set. Low precision means deletion, per the
  LL36 delete-by-measurement precedent — not a tuning pass.

### KC5: Model Cutoff Registry

Status: `later`.

Scope:
- A `knowledgeCutoff` field on the model capability profile, carrying a date and
  its source (`static_table`, `user_override`, `unknown`).
- **Never from self-report.** A model's claimed cutoff is training-data
  folklore; models routinely state it wrongly in both directions.
- Consumers: KC2 can state the gap in months (actionable where "may be outdated"
  is not); KC4 scales its aggressiveness with the gap; MLIB2/MLIB3 provenance
  already wants the field.

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
2. KC2 in parallel with KC1's analysis — it needs no permission.
3. KC3 only if KC1 shows class 2 dominates.
4. KC4 in shadow, deleted if imprecise.
5. KC5 when a second model family is in regular production use; until then a
   static table for the one endpoint in use is not worth the schema change.

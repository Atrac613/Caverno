# DeepSeek Harness Comparison — Harness Contract Findings (2026-10-08)

Source under comparison: `tmp/deepseek-harness`, the published TypeScript
source of DeepSeek AI's agent harness `dsh` (MIT, HEAD `5badb15009`,
release `0.2.1-alpha.1`). It occupies the same design space as Caverno's agent
loop: tool calling, approval policy, compaction, goals, subagents, and a
durable session log. Its repository also keeps decision records with
alternatives and rejected proposals (`.agents/notes/`), so its choices come
with the reasoning behind them.

This document records what the comparison found and which milestones it
produced. It is a source record, not a plan: the plans live in
`docs/local_llm_agent_roadmap.md` under the Harness Contract Track
(LL43-LL47).

Licensing note: `dsh` is MIT. Everything below is adopted as *design* and
reimplemented against Caverno's own types; no source or prompt text is copied.

---

## The organizing finding

`dsh` makes several facts that Caverno infers into facts that a producer must
state, and it records the rule next to the bug class that motivated it:

- **A request is a function of the log.** Every model request must be
  reconstructable byte-for-byte from the session log ("model-visible ⟺
  logged"). The request envelope (model, call config, tool schemas) is a
  durable `request/header` event, written only when it changes. Prefix-cache
  stability is a consequence of the append-only log, not a separately managed
  mode, and a with-key e2e asserts a positive cache-read count after the first
  request.
- **Independent outcomes are reported independently.** `timedOut`, `signal`,
  and `exitCode` are separate fields, because a process can time out *and*
  exit 0. Tool cancellation has two codes: `ABORTED_BEFORE_DISPATCH` (the body
  never ran, so no side effect is possible) and `ABORTED` (the body ran).
  A started tool is awaited to quiescence, never raced and abandoned.
- **Provider failures carry structured facts, not prose.** `LlmFailure` holds
  `code`, `status`, `providerRetryAfterMs`, and `requestId`. Retryability is
  decided by a separate policy; no recovery listener parses an error message.
  An empty completion is the retryable `EMPTY_RESPONSE`. A failed attempt is
  recorded as a log-only `assistant/attempt` and never enters model history.
- **Every model-facing plugin declares its model experience.** Each package
  README has a fixed "Model Experience" section: the exact text the model
  sees, its token effect, and its KV-cache effect (append-only versus
  replacing). This is the inventory Caverno lacks for its injected notices.

Each of these maps to a defect Caverno has already shipped, listed below.

## Findings and the milestones they produced

### 1. Request envelope fingerprint and cache-break detection → LL43

`dsh`: `docs/architecture.md` (Session log, "Model-visible means logged");
`.agents/notes/implemented/architecture/2026-07-05-reconstructable-requests.md`.

Caverno: LL6 made a prefix-stable mode and measured it once
(`docs/ll6_prefix_stability_live_measurement_2026-06-14.md`), but nothing
records the request envelope per request at runtime. Session logs write
`cachedPromptTokens` only when it is positive, so a cache miss is the absence
of a field. Two prefix breaks were found only by hand-diffing requests: the
per-minute prompt clock (11.4 min of a 71.7-min session lost to prefill,
fixed by pinning the clock per turn) and mid-loop tool-catalog flapping
(fixed by `TurnToolCatalogSource`).

Adopted: log a digest of each request's stable envelope and the provider's
cache-read count every time, so a prefix break is a field comparison rather
than an investigation. Not adopted: full event-sourced request
reconstruction. LL33 already deferred "Level 3 event sourcing" on evidence,
and API1 owns any future event core.

### 2. Non-execution as a typed fact → LL44

`dsh`: `docs/defensive-patterns.md` ("Report orthogonal outcomes
independently");
`.agents/notes/implemented/architecture/2026-07-19-cooperative-tool-cancellation.md`.

Caverno: `ToolOutcome.exitCode` documents that `null` covers "denied, timed
out, or failed to spawn" — three non-executions with no field telling them
apart. Non-execution is declared as markers inside the result JSON string
(`ok: false`, `ToolResultOrigin`), and each consumer parses it back. The
defect this produced: `UninspectedCommitGuard` returned a success-typed
refusal, so the call joined `executedToolCallKeys`, the identical commit after
`git diff --cached` was deduped, the stale refusal was replayed, and the turn
digest reported blocked `git commit` / `git tag` as "ran" (3 of 9 sessions
where the guard fired). `6ab0621de` fixed it per producer by declaring the
commit and tag blocks as refusals.

Adopted, evidence-gated: one typed "was the body invoked" fact that every
non-executing path sets and every consumer reads. The per-producer fix holds
today, so this waits for the next misclassification.

### 3. Structured LLM request failure → LL45

`dsh`: `.agents/notes/implemented/architecture/2026-06-21-bounded-llm-request-recovery.md`,
`2026-07-29-terminal-llm-stream-failures.md`.

Caverno: `ChatErrorMessageBuilder` classifies errors by substring
(`contains('401')`, `contains('429')`). On 2026-10-08 a
`SqliteException(14)` whose message embedded the conversation payload was
shown as "Authentication failed". A branch fix narrows the match to a
word-bounded `401` in the first 300 characters, which reduces the blast
radius but keeps text as the classifier. `RateLimitException.retryAfter` is
already read structurally in `chat_completion_request_fallback.dart`, so the
structured path exists for one case.

Adopted: a provider-neutral failure value captured at the transport boundary
(code, HTTP status, retry-after, provider request id), with user-facing text
and retry policy both derived from it. Storage and other non-provider errors
never reach the provider classifier.

### 4. Model-visible injection inventory → LL46

`dsh`: every package README's "Model Experience" section, for example
`packages/guard/repeat-tool-reminder/README.md` and
`packages/compaction/compaction-basic/README.md`.

Caverno: guards and recovery paths inject notices into model input, and
several shipped defects were notice defects — a brace made a claim notice
permanent, claim notices deleted the answer, guardrail feedback on
non-verification commands never settled. LL33/LL36 give each firing a stable
transform id, but there is no single list of what text each producer injects,
when it settles, and whether it appends or rewrites the cached prefix.

Adopted: an inventory keyed on the existing transform ids, with a test that
fails when a producer has no entry.

### 5. Oversized output spill files → LL47

`dsh`: `packages/spill/spill-policy/README.md`;
`.agents/notes/implemented/architecture/2026-07-08-tool-output-spill-files.md`.

Caverno: LL14 and LL30 evict and summarize old tool results, and per-tool
truncation keeps a head and tail, but the omitted middle is gone for the
model. `dsh` writes the complete result to a private (0700, exclusive-create)
file and names its path in the truncated result, so the model can read the
omitted part on demand.

Constraint specific to Caverno: the read fence does not cover `~/.caverno`,
so a spill directory there would be unreadable by the model's own tools. The
location has to be decided with SEC1.

### Corroboration only

- **Advisory repeat reminder** (`packages/guard/repeat-tool-reminder`):
  reminds at 3, 5, and 8 identical calls, never blocks, matches exact
  arguments only, and resets on a new user message. Corroborates LL29's
  "warn, don't abort" scope; recorded there rather than as a new milestone.
- **Cancelled-stream prefix** (`2026-08-10-cancelled-stream-prefix-finalize.md`):
  the delivered prefix is kept in history, marked `interrupted`, with tool
  calls omitted. Caverno already keeps the streamed partial bubble on cancel
  (`chat_notifier_cancellation.dart`); no milestone.
- **Goal state as its own durable event**
  (`2026-07-31-goal-owned-durable-events.md`): consistent with LL35; no
  milestone.
- **"Verify the world, not the self-report"** (`docs/testing.md`): consistent
  with the existing canary and grounded-verification practice.

## Not adopted

- The Cordis "everything is a plugin" runtime, profiles, bundles, and HMR.
  The value there is third-party composition in a Node runtime; Caverno is a
  single Flutter application.
- Per-file 100% line coverage as a CI gate, and the bilingual documentation
  pipeline.
- Rejecting a truncated interrupted turn on load. `dsh` itself rejected this
  (`rejected/simplification/2026-06-20-truncate-interrupted-turns.md`): a
  single turn can hold substantial work.

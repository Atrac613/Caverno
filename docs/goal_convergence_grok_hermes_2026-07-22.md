# Goal convergence: what grok-build and hermes-agent actually do (2026-07-22)

Investigated after the live measurement in
`docs/goal_completion_live_reproduction_2026-07-22.md` showed a goal with no
reachable ending: the model never calls `update_goal`, the lexical path misses
the completion, and auto-continue skips on "no incomplete evidence" leaving the
goal active forever.

The recollection that grok-build asks the LLM several times and takes a
majority is **correct**. It is also, for this particular gap, the wrong thing to
copy first — see "The panel is downstream of the gap".

## grok-build: the skeptic panel

`session/goal_classifier.rs` (6586 lines). A completion claim is adjudicated by
an N-member skeptic panel; `aggregate_skeptic_verdicts` counts the votes.

```rust
let (needed, not_refuted) = if total <= 1 {
    (1, total - refuted_count)                 // sole judge
} else {
    let cold_count = results.iter().filter(|r| r.skeptic_idx >= 1).count();
    let cold_not_refuted = results.iter()
        .filter(|r| r.skeptic_idx >= 1 && !r.refuted).count();
    (cold_count / 2 + 1, cold_not_refuted)     // variant-C
};
(refuted_count, total, not_refuted >= needed)
```

Four design decisions worth stealing whenever Caverno builds LL37:

1. **Skeptic 0 is a gatekeeper whose approval does not count.** It is the
   resumed reject-gatekeeper; letting its *not-refuted* vote tip a borderline
   panel toward approval is the bias they explicitly avoid. Its *refute* still
   counts, and a high-confidence one overrides the quorum entirely
   (`decisive_refute`).
2. **The quorum is derived from the cold-panel size, not the total.** For a
   contiguous panel `cold_count/2 + 1 ≡ ⌈total/2⌉`, but the cold form stays a
   true majority if skeptic 0 is ever missing, where `⌈total/2⌉` would silently
   degrade to a plurality.
3. **The bias-to-fail lives upstream of the aggregator.** Transport errors,
   cancellation, runtime faults and malformed output each degrade to a
   synthetic `refuted: true` inside `run_one_skeptic`. The comment is the whole
   principle: *"The aggregator counts votes; the bias lives upstream where the
   missing evidence is."* A counter that also applies policy is a counter you
   cannot reason about.
4. **Model-written evidence is neutralized before it is inlined.**
   `sanitize_evidence` breaks `</system-reminder>` and `<goal-state>` with a
   zero-width space and caps on `char` boundaries, because the skeptic's
   evidence is the only model-controlled text on that path. Caverno inlines
   guard notices into answers and acks; this is a real hardening idea, not a
   theoretical one.

Caps and pauses are first-class: `max_runs`, reserved attempt slots,
`ClassifierCapReached`, and distinct `GoalClassifierFailOpen` /
`FailClosed` events with reasons.

## The panel is downstream of the gap

grok-build's panel fires **in response to an `update_goal` call** — the drain
that processes those calls is what invokes `run_verification_stage`. So it has
exactly the same dependency Caverno has: the model must claim completion.

My measurement says there is no claim. A panel adjudicates claims; it cannot
manufacture one. Building it first would leave the measured symptom untouched.

## What actually differs, and it is not the voting

`acp_session_impl/goal.rs`:

> If a goal is active, inject a continuation nudge so the model keeps working
> on it after the current turn completes.

**While the goal is active, every turn gets a nudge.** grok-build has no state
that says "nothing looks incomplete, so stop nudging and leave the goal
running". Its goal ends one of a few ways: an approved completion, the
classifier cap, a no-progress pause, a back-off pause, or a labelled premature
stop (`GoalPrematureStopDetected { pattern }`, which selects a bail-specific
nudge flavour rather than ending anything).

Caverno's auto-continue does have that state, and it is exactly where both live
runs stranded: `skip — "no incomplete evidence"`, goal still active, nothing
further scheduled.

**That is the transferable finding.** "Nothing looks incomplete" is not a
terminal state; it is an unresolved one. Today it is treated as terminal by
omission — the loop simply stops scheduling and no one closes the goal.

## hermes-agent: how to ask cheaply

hermes has no voting (the greps for majority/quorum/consensus hit unrelated
code). What it has is `agent/background_review.py` — a mechanism for asking the
model a focused extra question without paying for it twice:

- **Fork the agent on the conversation snapshot** and ask it one question.
- **Run on the MAIN model by default**, precisely so the fork hits the parent's
  prefix cache — the replay is a cache read, not a cold write. If routed to a
  different model the cache cannot be reused, so it replays a compact **digest**
  instead. That trade-off is stated explicitly in the module docs.
- **Fire after the response is delivered**, "so it never competes with the
  user's task for model attention".
- **Thread-scoped tool whitelist** — everything outside the review's tools is
  denied at runtime, not merely un-offered.
- **Best-effort**: exceptions are swallowed; the main turn never breaks.

This is the answer to the cost objection I raised against "ask the model once at
the boundary". On Caverno's LL6 prefix-stable payload the same property holds:
a completion elicitation issued at the turn boundary rides the warm prefix.

## Recommendation

Ordered by what the measurement supports, not by what is most interesting.

1. **Treat "no incomplete evidence + goal still active" as a state that must
   resolve.** This is the actual defect and it needs no new LLM traffic to
   name. Today the loop goes quiet and the goal is stranded; grok-build shows a
   design where that state cannot exist.
2. **Resolve it by asking the user** — LL35's fourth rung. The harness knows
   what it knows: no incomplete evidence, verification caught up with mutation.
   It does not know the objective was met. Surfacing that on the goal chip is
   honest, costs nothing, and has no dependency on instruction-following, which
   is the variable the measurement just showed to be unreliable.
3. **Optionally, first ask the model once**, hermes-style: at the same
   boundary, after the answer is delivered, on the warm prefix, with the tool
   set restricted to `update_goal`. Measure it on the CMVP-1 fixture with a
   negative control — disabled, the goal must still strand. Do not assume it
   works; the same model just ignored a tool it was offered.
4. **Keep the panel for LL37**, and when it is built, take grok-build's four
   decisions above verbatim. It is a good design. It is not this problem.

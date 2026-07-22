# How Often Does a Turn End on an Unkept Promise? (2026-07-22)

Follow-up to `docs/session_2659093b_deferred_verification_2026-07-22.md`, which
recorded one turn that announced "next I will actually run the commands to
verify" and then stopped, with no guard firing and auto-continue skipping. That
was n=1 and explicitly deferred any frequency claim. This counts it.

Instrument: `tool/analyze_deferred_verification.py`.

## The denominator is much smaller than the turn count

The corpus has 1006 session logs and **1571 turns**, but only **168 turns have a
recoverable final answer**. The reason is structural:

| File shape | Files |
|---|---:|
| `turn_exit` only | **799** |
| `turn_exit` + completion records | 97 |
| completion records only | 108 |
| neither | 2 |

Median records per file: **1**. For most sessions the LLM request/response log
is not written at all — only the LL33 `turn_exit` provenance record is. So the
answer text needed to detect a deferral simply does not exist for ~90% of turns.

**Every rate below is conditional on that 168-turn subset**, which comes from
the 97 fully-logged sessions and is therefore biased toward runs made with
verbose logging on (canaries, debugging). It is not a random sample of use.

## Result

**11 lexical candidates, 6.5% of the 168 turns with a recoverable answer.**

Candidates are matches on forward-commitment phrasing ("次に〜します",
"次のステップ", "I will now"). That is a trigger, not a verdict, so all 11 were
reviewed by eye:

| Judgement | Count | Notes |
|---|---:|---|
| **Real — committed to an action, turn ended** | **5** | The shape under investigation |
| Confounded | 2 | Exit reason was `pending_batch_executed` or `tool_failure_abort`, so the stop has another cause |
| False positive | 4 | The model was handing the decision back to the user |

So the honest rate is **5–7 of 168 ≈ 3–4%** of turns whose answer is visible.

The five real ones (`2659093b`, `316cf8fe`, `922fcce0`, `d778264f`, `fb9d799b`)
span different sessions, so the shape **recurs** — it is not a one-off. Notably
they all commit to *verification* specifically ("動作確認を行います", "次に
`fvm flutter analyze` を実行します", "次にCLIで永続化を確認します"), which is a
tighter and more actionable class than generic "next steps".

## The false positives are a coherent class, and the regex only half-catches them

All four are the model **handing the decision back to the user** — presenting
options, asking which approach to take, or listing recommended next steps at the
end of a review. Those are legitimate turn endings.

An automated discriminator (question markers, ご希望, どちら) was added to the
tool and catches only **2 of the 4**: it misses the ones phrased as
recommendations without a question ("### 推奨される次のステップ", a numbered
project plan). At this sample size **eyeballing beats the regex**, so the tool
prints the raw candidate count and the split, and this document's manual
judgement is the number to trust — not the tool's `commit` line.

## What this means for the deferral detector

The follow-up in the previous document asked whether
`StructuredCodingExecutionDeferralDetector` should grow prose-form Japanese
patterns. On this evidence: **not yet, and not on this basis.**

- 5 confirmed instances is real recurrence, not noise — the behavior exists.
- But 3–4% of a **biased, small** subset is not a mandate to widen a regex that
  currently matches heading-shaped planning blocks. Widening it would pull in
  the recommendation/handoff class, which is 4 of the 11 candidates here and is
  legitimate behavior. A detector that fires on "推奨される次のステップ" at the
  end of a code review would be a regression.
- A tempting refinement — trigger only when the commitment is to *verification*
  and no verification command ran afterwards — **does not work either**, for the
  reason in the correction below: `dart analyze` counts as a verification
  command, and it ran. In the traced case that signal would stay silent too.
  Anything built here would have to distinguish *which kind* of verification was
  promised from *which kind* happened, which is a much finer judgement than the
  evidence supports.

## The upstream lever I proposed does not survive reading the code

An earlier draft of this document argued that the stronger fix was upstream:
`mutatedWithoutExecution` was `false` in the traced session because `dart
analyze` ran after the write, and I described that as a static check satisfying
a signal "meant to mean the change was exercised". **That was wrong.**

The signal means *did you check anything at all* — its own notice text is "a
file was edited but **nothing was run or tested** in this turn" — and `dart
analyze` legitimately satisfies it. `_hasAnyExecutionVerification` counts a
`local_execute_command` whose `ToolCapabilityClassifier` effect is
`verification`, which analyze is. The choice is documented in place:

> Unlike the Dart analyzer (**a safe static re-run**) an arbitrary shell command
> may have side effects, so surface the gap as a caution instead of
> auto-running it.

Splitting analysis from execution there would flag legitimate analysis-only
turns — docs edits, config changes, a deliberate analyze pass — as unverified.
That regression is not paid for by 5 confirmed cases in a biased 168-turn
subset. **Withdrawn.**

## So: none of *these* candidates is justified — but a real defect was found elsewhere

All three candidates considered here fail on their own terms:

| Candidate | Verdict |
|---|---|
| Widen the deferral detector to prose | No — 4 of 11 candidates are legitimate recommendations; it would fire at the end of code reviews |
| Split analysis from execution in `mutatedWithoutExecution` | No — deliberate, documented design; changing it regresses analysis-only turns |
| Make auto-continue drive incomplete tasks absent negative evidence | Superseded — see below |

**The third was superseded by an actual defect.** Auto-continue never read
`VerificationCadencePolicy`, which had been reporting `required` from the first
mutation through the final answer of the traced session while the evidence
reported nothing incomplete. That is not a product decision about how eager
continuation should be — it is an authoritative signal the policy ignored. Fixed
in `a2c1d0c5`; the full account is in
`docs/session_2659093b_deferred_verification_2026-07-22.md`.

Note what that means for this document's own framing: the frequency measured
here (~3-4% of visible turns matching a *prose* shape) was never the right lever.
The mechanical signal was already present and simply unconsulted, and it needs no
prose matching at all.

## What looked like a product question was a missing signal

I framed this as "should auto-continue recover only from evidence of
incompleteness, or drive an incomplete task forward when the evidence is clean?"
That framing assumed the evidence was genuinely clean. It was not — the cadence
said `required`. The policy was not being too conservative; it was reading an
incomplete picture.

That ambiguity exists only because completion is **inferred**. It is the same
argument as LL35: an explicit `update_goal` call, or the confirmation rung when
the model does not make one, replaces the inference with a stated fact and the
question stops arising. This corpus contains a live instance of the tool being
offered and not called, which is what the remaining LL35 slices address.

## Method caveats

- Order-based correlation: `turn_exit` carries an `assistantMessageId` but
  responses carry no id, so the final answer is the last plausible response
  preceding the `turn_exit` in file order.
- JSON-object responses are dropped as memory-extraction calls; a genuine answer
  starting with `{` would be missed.
- Whether the user had to re-prompt after each real case is **not** established
  here — the logs do not reliably contain the following turn.

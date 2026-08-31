# Self-Correction Baseline (2026-08-30)

Instrument: `tool/analyze_self_correction.py`. Corpora: `~/.caverno/session_logs`
(110 grounded logs, 197 turns, 1015 tool-loop steps) and
`build/integration_test_reports` (289 grounded logs, 768 turns, 5308 steps) —
the coding corpus that sits outside `~/.caverno`
([[caverno-canary-logs-outside-the-corpus]]).

## The question

Frontier agents appear to notice their own mistakes mid-turn. The working
hypothesis was that this is not introspection but **evidence co-residency**:
their harness keeps every tool result of the turn in context, so a claim and the
evidence that contradicts it are visible at the same time. Caverno's tool loop
does not — a follow-up request carries only the current batch's results, and
earlier steps survive only as the label-only `ToolLoopContextDigest`.

So the hypothesis predicted: the local model almost never self-corrects, because
it structurally cannot.

## What was measured

For every tool-loop step the instrument reads:

- **residency** — how many of the turn's tool results were still attached when
  the model answered;
- **trigger** — whether the incoming batch carried a failure. This is read from
  **typed** fields (`outcome.exit_code`, `ok`, `error`), never from prose, so
  the split between *the harness corrected the model* and *the model corrected
  itself* is ground truth;
- **reversal** — lexical markers in `response.content`, split into `strong`
  (explicit admission: "I was wrong", 間違い, 訂正) and `weak` (course reversal
  without admission: "wait", "let me re-check"). Lexical detection is legitimate
  here because this is an instrument, not a gate — the rule it must not break is
  that a heuristic may trigger but may not judge
  ([[caverno-abolish-text-heuristics]]);
- **follow-through** — of the inspection calls a step then issues, how many
  repeat something already gathered in the same turn.

## Findings

**1. Residency is near-total loss, and it is universal.**

| corpus | results resident at the final step (median) | turns losing nothing |
|---|---|---|
| chat | 19% | 0 / 128 |
| coding | 14% | 0 / 701 |

7,263 tool results were dropped before the answer that depended on them. Not a
single multi-step turn in either corpus reached its answer with its evidence
intact. The structural precondition for noticing a contradiction is absent
essentially always.

**2. Explicit self-correction is effectively zero.**

`strong` markers on clean batches: 3 / 4,867 steps (0.1%); on the coding corpus
0 / 4,018. Across four models, `strong/clean` is 0.0% for every one. The model
never says it was wrong.

**3. But the hypothesis was wrong about self-*monitoring*, which is alive.**

`weak` markers on clean batches run at 3.1% (150 steps), and sampling shows they
are **not noise**. Representative hits:

> Wait, that's 8 rows, not 5. Let me re-read the acceptance criteria: "The
> combined fixture must emit exactly five TOC rows and no extras."

> The current code uses `count` starting at 0, so the first duplicate gets `-0`
> instead of `-1`. Wait, let me re-check…

> Wait, the diagnostics say `Severity.Error` but `Type.Info`. Let me re-read the
> diagnostics…

This is the behaviour the milestone was going to try to induce. It is already
happening. What is missing is not the noticing — it is the *resolution*.

**4. Self-monitoring resolves almost entirely into "let me go look again".**

| step kind | inspection calls | re-inspections | share |
|---|---|---|---|
| self-monitoring | 152 | 84 | **55.3%** |
| everything else | 2,586 | 880 | 34.0% |

A step that has just doubted itself spends the majority of its inspection budget
re-fetching material it already had. That is the correct instinct and the only
one available: the evidence is gone (finding 1), so re-reading is the only way
back to it.

**5. The harness taxes exactly that instinct.**

71.4% of self-monitoring steps (195 / 273) arrived carrying a digest that
discourages re-reading. The model doubts itself, reaches for the one repair
available to it, and is told in the same request not to.

**6. The turn's own edits are invisible to it — the largest single gap.**

`write_file` and `edit_file` are the second and third most-invoked tools in the
corpus (2,319 calls), and neither digest set contains them: a mutation leaves
**no trace whatsoever** in the follow-up request. 542 of 965 turns (56.2%)
mutate a file, and after the last edit the turn continues a median of 1 and a
mean of 2.4 further steps — up to 27 — with no way to see what it changed.
**29.9% of mutating turns (162/542) ran no verification-class tool after their
last edit.** The cadence machinery knows this; the model is never told.

## What this changes

The design target moves. "Make the model notice its errors" is largely solved by
the model; the harness converts noticing into nothing. Three consequences:

1. **Restore residency selectively, not wholesale.** Full residency is
   unaffordable on a 32k context and would wreck LL6/LL22 prefix stability. But
   the digest already knows the identity of everything dropped, and LL34 gives it
   typed outcomes. Carrying facts rather than labels — `path@hash`, `cmd → exit`,
   *written at step 3, nothing has verified it since* — is a few hundred tokens
   and turns invisible contradictions into stated ones.
2. **Stop taxing re-inspection; price it instead.** The corpus is measured
   almost entirely under the **pre-softening** digest wording ("do not re-read
   these": 4,326 steps vs 2 under the current text). The softening already
   shipped and is essentially unmeasured — re-running this instrument on
   post-fix logs is the cheapest next data point available, and may move
   finding 5 on its own.
3. **Elicitation beats hoping.** A model that reaches "let me re-check" and then
   stalls is one restricted turn away from a real check — the same shape that
   already works for `update_goal`
   ([[caverno-goal-completion-elicitation]]): the local model does not volunteer
   a self-check but performs it reliably when asked.

## Caveats

- `weak` markers are validated by sampling, not exhaustively; the rate is a
  floor for self-monitoring, not a precise count. Re-validate with `--examples`
  after any pattern change.
- Reasoning-block coverage differs between corpora: the coding canaries record
  no `<think>` content (`--reasoning off` on the LAN endpoint,
  [[caverno-lan-llamacpp-reasoning-off]]), so their reversals are all in visible
  text. Chat logs carry both.
- Build provenance was not filtered. Any conclusion about a shipped change needs
  `build.commit` narrowing first ([[caverno-session-log-build-provenance]]).

## Acted on

Consequence 1 shipped as `99c05391` — `ToolLoopContextDigest` now leads with a
mutation section stating which files the turn changed, which writes were
no-ops, which failed, and whether any command or check has run since the last
edit. Three signatures are registered in `tool/check_fix_firings.py`
(`mutation_digest_section`, `unchecked_mutation_notice`, `noop_write_notice`),
so the next question — does it fire, and does it move the 55.3% / 29.9%
numbers — is answered from real logs rather than from unit tests.

### Pre-flight: would the new lines be signal or wallpaper?

Replaying the mutation rules over the same 6,323 follow-up requests, before
spending any model time:

| line | requests | share |
|---|---|---|
| mutation section renders | 3,664 | 57.9% |
| "no command or check has run since" | 1,038 | **16.4%** |
| "no-op: the file was already exactly this" | 0 | **0.0%** |

53.5% of turns would never see the notice at all, and the section is a median
of 2 lines (max 8). A notice on a sixth of requests is a signal; one on nearly
every request would have been wallpaper, and that was the risk worth checking
before a live run.

**The no-op line is unearned and should be described that way.** `already_applied`
never fired once across 2,319 mutation calls, and no payload in either corpus
reports `changed: false` — the eight `no_change` edits present are caught by the
FAILED path instead. It reads a typed field, costs nothing when silent, and
targets a failure documented in the digest's own history, so it stays; but it is
speculative, not evidence-backed, and no payload-parsing fallback should be added
to "make it fire" — measurement says there is nothing to catch.

Post-fix measurement needs no replay: the digest text rides into
`request.assistantContent`, so the three registered signatures are read directly
out of the logs.

### Live verification, 2026-08-31

`mutation_digest_section` and `unchecked_mutation_notice` both **fired in a real
session** on a clean build (`ac2fdb27`, `dirty: false`), confirmed with ancestry
by `tool/check_fix_firings.py`. The rendered line reads:

```
- wrote bin/markdown_toc.dart (no command or check has run since)
```

`noop_write_notice` did not fire, matching the 0.0% pre-flight prediction.

The notice arms and clears correctly. In the verified run it fired on the two
steps between the write and the check, and went silent the moment a command ran:

| step | incoming | notice | model's next call |
|---|---|---|---|
| 2 | read x3 | — | `write_file` |
| 3 | `write_file` | **yes** | `read_file` |
| 4 | `read_file` | **yes** | `local_execute_command` |
| 5 | command result | — | `update_goal` |

**The behavioural A/B is a null, and not for an interesting reason.** A control
build (`fff99794` — only the two files `99c05391` touched, reverted) was run
against the same fixture and model. Both arms ran a check after their last edit:

| arm | build | steps | notices | checked after last edit |
|---|---|---|---|---|
| treatment (markdown_toc) | `ac2fdb27` | 6 | 2 | yes |
| treatment (minimal_prompt) | `ac2fdb27` | 6 | 1 | yes |
| treatment (todo_mvp) | `1529bc97` | 6 | 2 | yes |
| control (minimal_prompt) | `fff99794` | 5 | **0** | yes |

The control's zero notices confirm the arms differ as intended; the outcome does
not move because **the fixtures cannot reach the population the notice targets.**
Characterising the 149 unchecked turns in the corpus says why:

- all 149 are `coding` mode (133 canary, 16 app);
- **97 of 149 run 8 or more tool-loop steps**, while every fixture here finishes
  in 5–6;
- **111 of 149 did run a check somewhere in the turn**, just not after the last
  edit. The real shape is *verify → edit again → answer without re-checking* —
  verification staleness, not absence, which is exactly what the notice states.

Every available fixture completes in 5–6 steps on `qwen3.8-27b-vision`. Older
CMVP-1 evidence recorded 14 iterations and 717 s, but on `qwen3.6-27b-vision`
([[caverno-cmvp1-toolloop-exhaustion]]) — **the fixture suite has been outgrown
by the model**, so no canary here produces a long multi-round turn any more.

The consequence for measurement: this effect is **observational, not
experimental**, until a longer fixture exists. Re-run
`tool/analyze_self_correction.py` over accumulated post-`99c05391` logs and
compare the 27.5% / 55.3% figures against this baseline. That needs log volume,
not more canary runs.

### Second A/B, on a fixture that reaches the population (2026-08-31)

The first A/B was a null by ceiling. `coding_goal_live_edit` was then repaired
(`docs/canary_suite_rot_2026-08-31.md`) and turns out to be the one vehicle in
the suite whose turns keep going after the last edit — 5 to 17 tool-loop steps,
with `edit → re-read burst → verify` shapes the other fixtures never produce.

Two runs per arm, six turns each, same model and fixture, arms alternated:

| arm | build | turns | checked after last edit | notice steps | median calls after last edit |
|---|---|---|---|---|---|
| treatment | `9de1e04f` | 6 | 6/6 | 16 | 3.0 |
| treatment | `6afb2164` | 6 | 6/6 | 16 | 3.0 |
| control | `25b67aac` | 6 | **5/6** | 0 | 2.5 |
| control | `66e27c67` | 6 | **5/6** | 0 | 5.0 |

**Treatment 12/12, control 10/12.** Both control misses are the highest-mutation
turn of their run, and both end the way the notice exists to describe:

```
b1e036d6  17 steps  4 mutations  → read_file x9, no check, answer
e2940b62  12 steps  5 mutations  → read_file,   no check, answer
```

Treatment reproduced exactly across runs (6/6, 16 notices, median 3.0 both
times), so the fixture is close to deterministic and the two control misses
stand out against it rather than sitting inside normal spread.

**This is a consistent direction, not a result.** One-sided Fisher on 0/12 vs
2/12 gives p ≈ 0.24. Two events cannot carry a conclusion, and the honest
summary is: the notice fires where it was designed to, the only turns that
skipped verification were in the arm without it, and both were multi-edit turns
— which is the mechanism, not just the outcome. Settling it needs roughly an
order of magnitude more turns per arm (~10 runs each, about 50 minutes per arm),
and that is a cost decision rather than a technical one.

Consequences 2 and 3 are untouched and remain gated on post-fix log volume.

## Reproduce

```bash
python3 tool/analyze_self_correction.py --dir ~/.caverno/session_logs
python3 tool/analyze_self_correction.py --dir build/integration_test_reports --by-model
python3 tool/analyze_self_correction.py --examples 14   # precision check
```

# ChatNotifier TurnRuntime Pre-Prototype Decision

## Decision

**Conditional Go for one bounded production prototype on 2026-08-03.**

The original No-Go was correct at the time: the live gate was not stable enough
to attribute a later failure to the prototype. That blocking condition is now
met. After triage and gate repair, three of four seeded runs pass and the fourth
has a bounded signature that distinguishes the observed model-repair variance
from a prototype regression.

This decision authorizes only the mechanically selected one-part experiment. It
does not authorize Phase 2, full `TurnRuntime` extraction, or production
`ChatToolHandlerCatalog` wiring. The experiment must satisfy the structural
gates below before the renewal can proceed.

## Selected Scope

- Last clean selector revision: `b7d88fe43df0f54f69395bbd7234e7106bbe4e8f`
- Selected part: `chat_notifier_goal_auto_continue.dart`
- Explicit owner or generation entrypoints: 13
- Turn-reachable ambient reads: 0
- Production lines: 804
- Migrated-path symbols reserved by the verification manifest:
  - `_maybeAutoContinueCurrentGoal`
  - `_recordGoalAutoContinueSessionLog`

The selector correction excludes `Conversation` context from the explicit turn
identity ranking. The selected part did not change after that correction. A
fresh clean selector and `validate-gates` run must bind the prototype to the
decision-contract commit before production editing begins.

## Passing Evidence

- `python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py`:
  21 passed.
- Clean `select` and `validate-gates`: passed at `b7d88fe4`.
- Focused Flutter gate:
  `goal auto-continue dispatches one hidden continuation from current evidence`:
  passed.
- Canary non-live contract suite: 20 passed, 9 live cases skipped by their
  explicit environment gates.
- Live runner contract suite: 2 passed.
- The live canary now stages verifier failures at the built-in command boundary
  rather than at the shadowed fixture MCP tool, and its static gate requires
  that boundary to remain present.
- Seeded live baseline: 3 of 4 passed; all four called the verifier in turn 1,
  emitted at least two ordered continuations, and recorded diagnostic evidence.

## Historical No-Go Evidence

The required command was run against
`http://192.168.100.241:1234/v1` with model `qwen3.6-27b-vision`. Every run used
a clean recorded build.

| Build | Result | What the run established | Classification |
| --- | --- | --- | --- |
| `339dd00b` | Failed | A correct first-turn implementation and verifier success produced zero continuations, exposing that the staged failures were attached to a shadowed fixture tool. | Gate defect, fixed in `22f26bf9` |
| `22f26bf9` | Failed | The real verifier boundary produced two diagnostics, but a question in the generated final answer caused the goal policy to skip continuation. | Gate defect, fixed in `f0b830ce`; the veto itself is designed policy |
| `f0b830ce` | Failed | One ordered continuation occurred. The next turn exhausted its tool loop without re-running verification and correctly stopped as `post-verification repair was not revalidated`. | Gate defect, partly addressed in `b7d88fe4`; residual staging visibility remains |
| `b7d88fe4` | Failed | The model stopped in `awaitingConfirmation` before its first verifier call, so the selected path was not reached. | Model variance; policy correct |

The two latest reports are:

- `build/integration_test_reports/coding_goal_auto_continue_todo_fixture_1785750342/canary_summary.json`
- `build/integration_test_reports/coding_goal_auto_continue_todo_fixture_1785750584/canary_summary.json`

Build output is gitignored and is not decision history by itself; the table
above records the durable conclusion.

## Triage of the Four Runs

Added 2026-08-03 after the No-Go, to separate gate instability from findings the
gate produced. Each run's session log carries schema-v2 build provenance, and
all four were confirmed clean at the recorded commit. Evidence below is the
structured `goalAutoContinue`, `turnExit`, and tool-call records, not log prose.

Three of the four failures were gate defects that the next commit repaired. Only
`b7d88fe4` is model variance. The gate was therefore measuring itself for three
of four runs, which independently supports the No-Go.

- `b7d88fe4` — the model called `list_directory` twice and answered with text.
  `mutationGeneration: 0`, `unresolvedErrorCount: 0`, so auto-continuation
  correctly recorded `decision: skip`, `reason: no incomplete evidence`. The
  goal reaching `awaitingConfirmation` is the designed consequence of a goal
  with nothing left to schedule, not a premature capture of the turn. No product
  defect. The failure is that the model produced no work to verify.
- `f0b830ce` — turn 2 read `tool/verify_todo_app.dart` and
  `.verifier_invocations.jsonl`, then spent four consecutive `list_directory`
  calls searching for `canary_support.dart`, alternating between the same two
  directories, and exhausted the loop (`boundedToolLoopExhausted: true`,
  `unexecutedToolNames: ["list_directory"]`). The policy then correctly issued
  `stop_and_block`. `b7d88fe4` addressed this by directing the staged response
  to request the next verifier run. That treats the prompt, not the visibility:
  the staging *script* is already outside the workspace by design, but the
  verifier source and its invocation log remain readable from it.
- `22f26bf9` — `decision: skip`, `reason: final answer asks a question`, with
  `mutationGeneration: 1` and two unresolved errors present. The question
  originated in the canary's own staged response, which `f0b830ce` removed. The
  underlying veto is designed behaviour and is not a defect.
- `339dd00b` — no `goal_auto_continue` record was emitted at all; the turn ended
  `text_response` after `update_goal`. Consistent with the shadowed-tool
  diagnosis already recorded above.

### Cross-cutting finding: `diagnosticCounts` is not populated

`signals.goalAutoContinue.diagnosticCounts` was empty in every run, including
`f0b830ce`, whose structured record carries `unresolvedErrorCount: 2` on a
`continue` decision.

`tool/live_llm_canary_summary.dart:1629` derives the value by matching
`RegExp(r'evidence=(\d+) unresolved Error')` against log message text, while
`lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart:562`
emits `evidence=${evidence.summary}`, whose summary begins with
`execution verification failed; ` before the count. The pattern requires a digit
immediately after `evidence=`, so it matches only summaries that happen to start
with the number. The focused test at
`test/tool/live_llm_canary_summary_test.dart:413` uses that shape and passes.

This blocks Unblock Task step 4, which gates on diagnostic progression. The
structured `goalAutoContinue.evidence.unresolvedErrorCount` field is present in
the session log and unused; reading it removes the prose dependency entirely.

### Effect on the Unblock Task

The task as written remains correct and is now supported by run evidence: the
`b7d88fe4` variance is exactly what seeding a known-good fixture removes. Two
amendments followed from the triage, and both are now implemented ahead of the
seeding work, because each one changes what a rerun would measure.

1. **Staging is no longer visible from the workspace.** Seeding does not by
   itself close the `f0b830ce` leakage. The generated `tool/verify_todo_app.dart`
   now forwards to `tool/canaries/support/fixture_verification_runner.dart` and
   states only what a verifier entrypoint legitimately states; the scripted
   outcomes and the run log both live outside the project. The run log moved out
   of the workspace entirely rather than staying a dot-file, because
   `list_directory` reports dot-files and the model read it. Escape attempts
   were already refused (`Path must stay inside the TODO fixture root.`), so
   moving these two files out is sufficient.
2. **`diagnosticCounts` now reads the structured record.**
   `live_llm_canary_summary.dart` accepts `--session-log-dir` and derives the
   counts from `goalAutoContinue.evidence.unresolvedErrorCount`. The log-text
   derivation is retained as `logTextDiagnosticCounts` with a
   `diagnosticCountsSource` marker, so the two can be compared before the
   pattern is retired rather than deleted on one run's evidence. Replaying the
   four recorded runs through the new path yields `[2]` for `f0b830ce`, where
   the pattern yielded `[]`.

Step 4 can now be used as a gate condition.

Step 1's seeding is also implemented. `_TodoFixture.create` takes
`seedReferenceImplementation`, and the auto-continue scenario writes the
known-good `tool/canaries/support/todo_app_reference_cli.dart` into
`bin/todo_cli.dart` before the turn starts. The goal and prompt now ask for a
verified state rather than a build, and forbid a rewrite. A non-live test runs
the real `TodoAppBehaviorVerifier` against the seed and requires zero
diagnostics, because a seed that silently stopped satisfying the fixture would
make the gate fail for the exact reason seeding was meant to exclude.

Steps 2 and 3 are deliberately not implemented; see the gate contract below.

### First run after seeding

Build `c625e557`, clean, against the same endpoint and model as the four blocked
runs. **Passed** in 306 s — the first pass this gate has recorded.

| Signal | Value |
| --- | --- |
| `continuationCount` | 2 |
| `diagnosticCounts` | `[2, 1]` |
| `diagnosticCountsSource` | `sessionLog` |
| `logTextDiagnosticCounts` | `[]` |
| `firstVerifierTurn` | 1 |
| `successfulVerifierObserved` | false |
| `finalStopReason` | post-verification repair was not revalidated |

Turn shape: 11 `read_file`, 7 `local_execute_command`, 3 `edit_file` across three
turns, with ordered turn-exit, decision and continuation each time.

Three things this establishes.

**Step 2 is not needed.** The model ran the verifier unprompted in turn 1
(`firstVerifierTurn: 1`) and again in every later turn, without being handed the
narrow task of running a recorded command. Seeding alone removed the failure
mode that motivated step 2, so fixing when to verify would cost gate validity
for nothing. Steps 2 and 3 are dropped rather than held.

**The diagnostic-count fix was load-bearing for this evidence.**
`logTextDiagnosticCounts` is empty, so the `[2, 1]` progression — the strict
decrease the gate accepts as evidence of repair — would have been invisible on
the previous derivation. The gate would have had to fall back to terminal
verifier success, which this run did not reach.

**The run ended correctly blocked, not completed.** The last turn verified, then
edited, then only read, so `post-verification repair was not revalidated` is the
policy behaving as designed. `verificationGeneration` staying at `-1` is
consistent: the verifier never exited 0, and that counter tracks successful
verification rather than tool-result evidence.

### Baseline across four seeded runs

Three further runs followed on `882177b8`. Only documentation changed between
`c625e557` and `882177b8`, so all four exercise identical production code.

| Run | Result | s | `continuationCount` | `diagnosticCounts` | `firstVerifierTurn` | Green verifier | Stop reason |
| --- | --- | ---: | ---: | --- | ---: | --- | --- |
| `…754160` | passed | 314 | 2 | `[2, 1]` | 1 | no | post-verification repair was not revalidated |
| `…754644` | passed | 287 | 2 | `[2, 1]` | 1 | **yes** | none |
| `…754934` | **failed** | 469 | 3 | `[2, 2, 2]` | 1 | no | repair contract made no mutation twice |
| `…755406` | passed | 330 | 2 | `[2, 1]` | 1 | no | post-verification repair was not revalidated |

**3 of 4 passed**, against 0 of 4 before seeding.

Reproducible in all four: the verifier is called unprompted in turn 1, at least
two ordered continuations occur, and the first diagnostic count is 2. Three of
four then show the `[2, 1]` decrease, and one reaches a green verifier, so the
full success path is reachable rather than theoretical.

The failure is model repair variance, and the policy handled it correctly.
Turns 3 and 4 made one and zero tool calls; the repair contract observed no
mutation, granted one retry, observed none again, and stopped
(`noProgressStreak` 1 → 2 → 3, `identicalDiagnosticSignatureStreak` 2). No gate
defect and no product defect — this run is a case where the safety machinery is
demonstrably load-bearing.

### Attribution rule for the prototype comparison

The No-Go required a baseline stable enough that a later red canary can be
attributed to the prototype. A 1-in-4 flake would defeat that if the flake were
shapeless, but it is not:

> A red run whose `diagnosticCounts` are flat and whose stop reason is
> `repair contract made no mutation twice` is the known repair-variance flake.
> A red run with any other signature is attributable to the change under test.

Rerun the flake signature once before attributing it. Any red run that fails
before `firstVerifierTurn: 1`, or with fewer than two continuations, is outside
the observed baseline and should be treated as attributable, because all four
runs cleared both.

Environment note: the canary must reach the LAN endpoint through a loopback
relay. `flutter_tester` cannot open the LAN socket under macOS Local Network
Privacy and fails in ~200 ms with `No route to host`, while `curl` from the same
shell succeeds.

### What this gate preserves, and what it removes

Recorded so that a later narrowing has a criterion to fail:

> The gate may remove the model's freedom to **fail at writing the app**. It
> must preserve the model's freedom to choose **when to verify** and **how to
> phrase its answer**.

Those two are the inputs the auto-continue policy reads. Fixing them would leave
a live restatement of the focused unit test — which already scripts the data
source and asserts the same ordered decisions — at live-canary cost.

Unblock Task step 2, which would hand the model the narrow task of running the
recorded verifier command, sits on the wrong side of that line: it fixes when to
verify. The first seeded run settled it — the model verified in turn 1 on its
own — so step 2 is dropped rather than deferred. Reading and repairing an
existing CLI is a much smaller task than building one, and the `b7d88fe4`
read-only exploration was a response to the larger task.

### On keeping broad coverage

An earlier draft of this section argued for adding a broad, non-gating canary
alongside the narrowed one, on the grounds that the `22f26bf9` question veto
surfaced only because the gate was broad. Two corrections.

First, the file already carries eight environment-gated broad scenarios,
including `CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY`, which builds the app from a
prompt. Narrowing the gate scenario does not remove them, so this was never a
build decision — only a reason not to convert a broad scenario into the gate.

Second, the evidence was weaker than stated. The question in `22f26bf9`
originated in the canary's own staged response, so what breadth found was a gate
defect. Across the four runs breadth produced three gate defects and one
variance observation, and no product defect. It may still be that breadth had no
chance to find one, since three runs died at or before the first verification
cycle — but "breadth found something valuable here" is not supported.

## Current Interpretation

The original gate combined fixture construction with the selected
auto-continuation path. Seeding a known-good implementation removed only the
model's freedom to fail at writing the app. It preserved when the model verifies,
how it responds to diagnostics, the real ChatNotifier loop, and the policy's
terminal behavior. That is the relevant before/after surface for this
prototype.

The four-run baseline is sufficient for a bounded engineering experiment, not
a release reliability claim. A gate pass may end completed or correctly blocked;
it proves ordered continuation and safe terminal handling, not that every model
run finishes the fixture. Apply the recorded attribution rule to any prototype
red and rerun the one known flat-diagnostic flake signature once.

## Prototype Entry Contract

Before production editing:

1. Run `select` and `validate-gates` from this decision's clean commit and use
   that full revision as the comparison base.
2. Use `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`, which
   classifies all 26 external private dependencies while limiting the reserved
   prototype path to its 10 members and seven capability boundaries.
3. Keep `ChatToolHandlerCatalog` wiring and the full I2 six-group matrix out of
   the prototype slice.

The hard structural gates are:

- remove at least one explicit owner or generation parameter;
- do not increase turn-reachable ambient reads;
- introduce no callback or adapter that captures `ChatNotifier`;
- move no conversation- or thread-scoped state into `TurnRuntime`; and
- preserve the focused test, coverage gate, and live-canary behavior.

Report production line delta, new ports and callbacks, touched files, and public
surface as cost evidence. A positive line delta requires an explicit cost
review, but does not by itself reject the composition-root diagnosis. Failure of
any hard structural gate rejects the full renewal after the isolated prototype.

## Catalogue Decision

Production `ChatToolHandlerCatalog` wiring is No-Go in Phase 1.5. Its
investigation is complete: current bindings capture `ChatNotifier`, so the
WS6-19 stop condition requires the same explicit port boundary that the
prototype is testing. Reconsider it only after the prototype proves that
boundary and I2 maps it across all six binding groups. If the prototype is
abandoned, catalogue wiring remains blocked.

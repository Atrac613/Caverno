# LL36 structural enforcement: the guards were already advisory, so the work was locking it in (2026-07-22)

The second half of LL36 — "bar a lexical guard from setting terminal state at
the type/API level, not by convention" — described as the larger, unstarted
half in `docs/ll36_guard_firing_surface_2026-07-21.md`.

## Measuring first, again

Counting references to terminal-state types across the eight named lexical
guards:

| Guard | Terminal-state references |
|---|--:|
| `analysis_options_lint_edit_guard` | 0 |
| `coding_command_output_guardrail_service` | 0 |
| `coding_verification_claim_guard` | 0 |
| `final_answer_claim_detector` | 0 |
| `narrated_transcript_claim_guard` | 0 |
| `structured_coding_execution_deferral_detector` | 0 |
| `unwritten_file_claim_guard` | 0 |
| `workflow_tool_result_failure_detector` | 0 |

All eight are already advisory: they return assessment data and name no status
enum. The same shape as the firing-surface finding — the roadmap's framing
implied a large refactor, and the actual gap was small.

The real lexical judges of terminal state are the two **inferences**:
`ConversationExecutionProgressInference` (24 references) and
`ConversationGoalProgressInference` (5). Those are deliberately out of scope —
see "What is not enforced" below.

So the work is not demoting the guards. It is making the property **hold under
future edits without anyone remembering the rule**.

## What is enforced

`test/quality/lexical_guard_advisory_test.dart`, two checks per guard:

1. **Import reachability (transitive).** A guard may not reach
   `conversation_workflow.dart`, `conversation_goal.dart`, or
   `conversation.dart` through any chain of relative imports. This is the
   structural half: a guard that cannot see `ConversationWorkflowTaskStatus`
   cannot set it, and no review discipline is needed to keep it that way.
2. **Symbol naming.** The guard source names no terminal-state symbol, which
   catches a guard that reintroduces a verdict as a string instead of an enum.

### The transitive check earned its keep immediately

A direct-import check would have passed. `CodingVerificationClaimGuard`
imported `CodingVerificationFeedbackService` — for two constants — and that
producer imports `conversation_workflow.dart`. The guard could see terminal
task state through one hop.

Fixed by extracting `coding_verification_evidence_contract.dart`: a name shared
between a producer and its consumers should not drag the producer's dependency
graph along. The guard now imports only the contract.

## The test was blind on its first run

The first version passed the negative control — reintroducing the leak did not
fail it. Cause: relative imports resolve to
`.../domain/services/../entities/conversation_workflow.dart`, which does not
`endsWith('domain/entities/conversation_workflow.dart')`. No normalization, so
the leaking path was found and then not recognised.

This is the third time this session that an unverified green was wrong, and the
second time hand-rolled path/pattern handling was the cause. Both negative
controls are now recorded in the commit and were re-run against the final form
after the code changed under them:

| Control | Result |
|---|---|
| Guard re-imports the producer (2-hop leak) | fails, naming the library and the hop |
| Guard names `ConversationWorkflowTaskStatus` as a string | fails, naming the symbol |
| Clean state | 17 tests pass |

`package:path` was added to `dev_dependencies` rather than re-deriving
normalization by hand, since hand-rolling it is precisely what produced the
false pass.

The test also asserts each listed terminal-state library exists, so a rename
cannot turn the check into a silent no-op.

## What is not enforced, and why

The two prose inferences still set terminal state. That is the documented
fallback for when no mechanical evidence exists, and removing it now would
leave nothing in its place: LL35's fourth rung (ask the user) is still gated on
shadow data. Barring them structurally today would trade a prose verdict for no
verdict, which is worse.

They are named in the test's doc comment as deliberately excluded, with the
gate that would let them be added. That keeps the exclusion a recorded decision
rather than an omission someone has to rediscover.

## Remaining for LL36

**Delete-by-measurement** — remove a silent guard with its firing record as the
justification. Still gated on accumulated post-provenance logs, unchanged by
this slice. The current distribution (three of ten transform labels firing at
all) is a baseline, not yet evidence.

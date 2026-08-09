# LL36: The Guard Firing Surface Is Mostly Already Complete (2026-07-21)

Question this answers: **LL36 wants every lexical guard's firing to be
countable, so "delete-by-measurement" can run. How much of that surface exists
already, and what is actually missing?**

## 2026-08-09 correction

The 2026-07-21 inventory was incomplete in two ways. Four final-answer mutation
paths did not carry a transform ID through the shared mutation service, and a
nested recovery tool loop reset the turn-finalization registry after an earlier
transform had fired. Both gaps are closed: unexecuted tool requests,
unexecuted file side effects, timed-out command claims, and failed command
claims have stable IDs; the normal path derives the generation owner; and turn
state accumulates until finalization rather than resetting per tool loop.

The formerly zero `pending_action_length_recovery` label now has clean live
evidence. Build `4c0efc96` recorded it in `turn_exit.transforms` during a 1/1
passing `qwen3.6-27b-vision` canary, followed by a bounded
`coding_continuation_recovery_length_truncated_pending_action`. The staged
verifier exited 1, the real verifier later exited 0, and both LL34 comparisons
agreed. The implementation and evidence are detailed in
`docs/ll36_final_answer_transform_coverage_2026-08-09.md`.

The roadmap's framing — "every remaining lexical guard gets a stable label" —
implied a large gap. Measuring first (the discipline that repeatedly paid off
this session) shows the gap is small: most guard firings are already countable
through one of two existing channels.

## The two channels that already exist

**1. Final-message transforms → `_appliedTurnTransforms` → `turn_exit`.**
Guards that append a notice to the on-screen answer already record a stable
label, surfaced by `tool/triage_session_logs.py` under "Post-LLM transforms".
Ten labels exist: `unexecuted_command_action_notice`,
`unverified_read_only_inspection_notice`, `unwritten_file_claim_notice`,
`verification_claim_notice`, `narrated_transcript_claim_notice`,
`narrated_transcript_repair`, `unexecuted_tool_request_notice`,
`pending_action_length_recovery`, `truncated_tool_call_arguments_feedback`,
`final_answer_concise_retry`.

**2. Tool-call-blocking guards → tool-result errors → `analyze_tool_results.py`.**
Guards that reject a tool call return a failed `McpToolResult`, which appears in
the log as a tool result and is counted by `analyze_tool_results.py`'s parsed
error field. Confirmed firing in real logs:

| Guard firing (error text) | Count |
|---|--:|
| A validation-only continuation rejected a non-verification tool | 10 |
| A production release command was blocked | 14 |
| A command was blocked (claimed local execution) | 5 |
| Direct git write commands are blocked in local shell | 4 |

These are `AnalysisOptionsLintEditGuard`, the release-command guardrails, and the
git-write block — all already countable, none a blind spot.

## The one genuine blind spot (now fixed)

The **coding-continuation recovery** (`chat_notifier_coding_continuation_recovery.dart`)
is a final-message transform — it revives the tool loop with a synthetic tool
result when a lexical detector (including `StructuredCodingExecutionDeferralDetector`)
judges the model deferred execution in prose. It changed the on-screen answer
but recorded **no** transform, so the whole subsystem was invisible to triage.

Fixed: it now records `coding_continuation_recovery_<recoveryCode>` (a bounded
label) when it fires. This is the additive half of LL36 — completing the
measurement surface — with no deletion.

## Current firing distribution (baseline for delete-by-measurement)

From `tool/triage_session_logs.py` over the local logs, only three of the ten
labeled final-message transforms fire at all:

| Transform | Firings |
|---|--:|
| `unexecuted_command_action_notice` | 26 |
| `unverified_read_only_inspection_notice` | 5 |
| `unwritten_file_claim_notice` | 1 |
| (the other seven labels) | 0 |

**This is not yet grounds to delete the seven silent guards.** The caveats that
apply, learned the hard way earlier today and recorded in memory:

- These logs predate parts of this work; a guard added recently has had no
  chance to fire. Check `build.commit` provenance before concluding a guard is
  dead (`caverno-session-log-build-provenance`).
- A guard that never fired is not necessarily dead weight — it may guard a
  rare-but-critical case. `NarratedTranscriptClaimGuard` and the
  false-completion guards are flagged in memory as load-bearing or unproven
  live, not safe to remove on a zero count
  (`caverno-false-completion-claim-guards`).
- The count is per-firing, corrected for replay and payload contamination only
  because it comes from the record-parsing tools; a grep would have inflated it
  (`caverno-tool-traffic-concentration`).

## What remains for LL36

Structural enforcement completed on 2026-07-22 through
`test/quality/lexical_guard_advisory_test.dart`; the final instrumentation gaps
completed on 2026-08-09. The only remaining milestone acceptance item is
**delete-by-measurement**: accumulate enough model-varied logs produced after
`4c0efc96`, then remove a lexical path only when its firing and grounded
disagreement records show the grounded path covers its useful verdicts. The
single deterministic canary proves observability, not deletion safety.

The instrument (labels + the two counting tools) is now complete enough that
part 2 becomes a measurement rather than an argument — which was the point.

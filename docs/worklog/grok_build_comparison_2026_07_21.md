# Grok Build Comparison — Grounded Verification Findings (2026-07-21)

Source under comparison: `tmp/grok-build`, the published Rust source of xAI's
Grok Build CLI (Apache-2.0, `SOURCE_REV 2ec0f0c8488842da03a71eeee3c61154957ca919`).
It occupies the same design space as Caverno's agent loop — tool calling, plan
mode, cross-session memory, subagents — so its choices are usable as external
corroboration for (or against) Caverno's own roadmap hypotheses.

This document records what the comparison found and which milestones it
produced. It is a source record, not a plan: the plans live in
`docs/local_llm_agent_roadmap.md` under the Grounded Verification Track
(LL34-LL37).

Licensing note: Grok Build is Apache-2.0. Copying its source or prompt text
in-tree would require NOTICE handling and a §4(b) change notice. Everything
below is adopted as *design*, reimplemented against Caverno's own types.

---

## The organizing finding

Caverno decides several terminal states by reading the assistant's prose.
Grok Build decides none of them that way — but it did **not** delete its
regexes either. It demoted them.

`crates/codegen/xai-grok-shell/src/session/goal_stop_detector.rs` still matches
bail phrasing (`unable_to_proceed`, `giving_up`, `stopping_here`,
`agents_in_flight`, `check_back_later`) at the start of a turn's final
paragraph. What it is allowed to do with a hit is narrow: choose which
continuation nudge to render, and emit
`Event::GoalPrematureStopDetected { pattern }` with a stable label so the
panel's precision and recall can be audited later. It never decides whether
work is complete.

The operating rule this yields:

> **A heuristic may trigger. It may not judge.**

Terminal state in Grok Build is decided by three mechanisms instead, in
ascending cost:

1. **Mechanical ground truth** — exit codes, the git-derived changed-file list,
   file contents. Free and deterministic.
2. **Structured self-report with a real acknowledgement** — the model calls
   `update_goal(completed: true)`; the tool blocks on a `oneshot` ack so the
   tool reply carries the harness's actual verdict rather than an instant
   success (`xai-grok-tools/src/implementations/grok_build/update_goal/mod.rs`).
3. **Adversarial verification** — an N-way skeptic panel, used only for the
   judgment that ground truth cannot settle: *did this change actually satisfy
   the objective?*

---

## Caverno's heuristic inventory, classified

### Class 1 — lexical all the way to the verdict (the target)

| Site | Behavior |
|------|----------|
| `conversation_goal_progress_inference.dart:225-256` | `_looksComplete` / `_looksBlocked` / `_resolvedBlockerSignals` string lists move a goal to `completed` / `blocked`. `'passed'`, `'fixed'`, `'修正しました'` alone can complete a goal. |
| `conversation_execution_progress_inference.dart:316` | `'was successful'`, `'ran successfully'`, `'working as expected'` substrings infer verification success. |

Replaced by mechanism 2 (see LL35).

### Class 2 — lexical extraction, grounded verdict (keep, demote, audit)

`final_answer_claim_detector`, `narrated_transcript_claim_guard`,
`unwritten_file_claim_guard`, and `coding_verification_claim_guard` already
have the correct shape: prose is scanned to find a *claim*, but the verdict
comes from execution records, `File.exists()`, or parsed counts.

There is no structured signal for "the model asserted in prose that it ran the
tests", so the extraction side stays lexical by necessity. That is acceptable
precisely because the decision is grounded.

Two improvements the comparison surfaced:

- Grok's honesty check is stricter and cheaper: a claim about a file absent
  from the git-derived `CHANGED_FILES` list is fabricated, full stop
  (`session/templates/goal_verifier_prompt.md`, decision rule 2). Caverno's
  `unwritten_file_claim_guard` tests `dart:io` existence, which passes files
  that existed before the turn. Caverno already has `turn_diff_service`; using
  the turn's changed-file set as the ground truth is a strict upgrade.
- Every firing should leave a labeled record. LL33 already lands the transform
  record; extending it to every guard turns "is this guard load-bearing?" from
  an argument into a measurement (LL36).

### Class 3 — lexical only because the facts were flattened to text (the hidden bulk)

`mcp_tool_entity.dart:43` carries `String result` and `bool isSuccess` and
nothing else. `local_shell_tools.dart:585` has the real exit code and buries it
inside the JSON string. Downstream, `tool_failure_classifier`,
`workflow_tool_result_failure_detector`, and
`coding_command_output_guardrail_service` each independently re-parse that
string or substring-match phrases like `'no data found'`.

This is the largest single source of regex in the codebase, and none of it is
inherent — it exists because structure was discarded at the tool boundary.
Restoring the structure deletes the parsing (LL34).

The boundary to preserve: first-party tools become structured; third-party MCP
servers return opaque text and keep a lexical path. That is a defensible split
— it aligns with the SEC2 trust boundary rather than cutting across it.

---

## Mechanisms worth adopting

### Adversarial verification with convergence controls

`session/goal_classifier.rs` spawns N skeptic subagents in parallel; each writes
a fixed-schema JSON verdict (`refuted`, `findings[]`, `evidence`, `confidence`,
`blocking`) and the panel aggregates by majority-refute. Spawns go directly over
the subagent event channel rather than through a tool call, so the parent
transcript stays clean.

The verification is the easy part. The convergence controls are what make it
usable, and they are the transferable insight:

| Control | Purpose |
|---------|---------|
| **Anti-ratchet** | On a re-verification round the verifier's primary job is checking that the *previous* gaps were fixed. A new objection is grounds to refute only if it is a demonstrable defect or an unmet gating criterion — never a stylistic preference an earlier round implicitly accepted. The prompt names "a fresh nitpick each round" as the failure mode that makes goals unfinishable. |
| **Stall exit** | The same flagged gaps twice in a row auto-pauses the goal early, before the cap. Cheaper than exhausting the budget. |
| **Run cap** | `GOAL_CLASSIFIER_MAX_RUNS_DEFAULT = 10`, described in-source as a runaway-cost backstop rather than the primary stop. |
| **Blocking classification** | `none` (model-fixable) / `contradiction` (the objective precludes itself) / `unverifiable` (no honest evidence path in this environment). The latter two route to a user decision instead of another retry. |

The prompt also spends significant length forbidding over-reach: inventing
requirements beyond the contract is named as the most common false refute and
the top reason correct in-scope work fails to converge. Any Caverno port needs
that guard rail or the panel becomes an infinite-work generator.

### Evidence discipline

The verifier **audits** the implementer's committed tests and captured output
rather than building its own (`goal_rules.md`, `goal_verifier_prompt.md`
"Audit, don't author"). Each goal gets a private scratch directory; shared
`/tmp` is explicitly forbidden because concurrent goals and skeptics collide
there. The "NO TEST THEATER" rules are unusually concrete: no hard-coded
expected values, no starting past the unit under test, no re-implementing the
unit inside the test, no mocking the unit itself — while faking an
*environment* boundary (clock, RNG, network) is called out as legitimate.

### Strategist role for non-convergence

`goal_strategist_prompt.md`: after several consecutive failed rounds that each
flag a *different* gap (whack-a-mole), a strategist role investigates the run
itself — grepping `chat_history.jsonl`, `events.jsonl`, and the scratch tree
rather than receiving a digest — and writes one note recommending a structural
change. Its constraint is sharp: change the HOW, never the WHAT; the objective
and acceptance criteria are off-limits, and its plan-file edits are reverted.

### Graduated in-request tool-result pruning

`xai-chat-state/src/actor/request_builder.rs:166`: above 50% context
utilization, the last 3 turns are untouched, older tool results over 4000 chars
are cut to head 1500 + `[…trimmed…]` + tail 1500, and anything older than 10
turns is replaced with `[Tool result omitted — too old]`. No LLM call; applied
to the request clone only.

**Caveat that changes the port.** Mutating history per-request invalidates the
KV prefix at exactly the moment it fires. Caverno has spent LL6 and LL22 on
prefix stability and warm caches, so the per-request placement is wrong here.
The graduated *shape* is worth taking; the firing point should stay at
compaction boundaries, matching LL14's existing rule.

The image-eviction placeholder in the same file is worth copying verbatim in
spirit: it tells the model the image is gone and not to describe it from
memory, because a silently stripped image induces confident hallucination.

### Next-step mining from the plan checklist

`goal_next_step.rs` inlines the first unchecked `- [ ]` from the plan's
`## Task checklist` into the continuation nudge. Numbered acceptance criteria
are deliberately *not* mined: they never get checked off, so surfacing
criterion 1 repeated a stale line forever. Reads are capped at 8 KiB with the
trailing partial line dropped.

### Deferred discovery of subdirectory instructions

`xai-grok-tools/src/types/agents_md_tracker.rs` and
`reminders/skill_discovery.rs`: when a tool touches a path outside the initial
discovery chain, the tracker walks up to the git root looking for `AGENTS.md` /
`CLAUDE.md` / `.claude/rules` / `SKILL.md`, and reports newly found files
**as paths only**, once per session (or once per compaction cycle). The model
decides whether to read them.

This is the design that was parked in Caverno's notes as LL32. A second
production agent shipping it is the corroboration that was missing.

---

## Smaller items noted, not scheduled

- **`capability_mode`** on subagent spawn (`read-only` / `read-write` /
  `execute` / `all`) — a coarse tool filter. Relevant to Caverno's known
  subagent full-catalog overflow, as a cheap mitigation.
- **`resume_from`** — a new subagent continues a completed one's transcript and
  tool state, with system prompt and tools re-rendered from the current agent
  definition. Enables research → implementation handoff without re-priming.
- **Persona I/O contracts** — declared `inputs` / `outputs` with `io_type`, so
  one persona's output file is the next one's input.
- **Memory search shape** — FTS5 + vector hybrid (0.3 / 0.7), temporal decay
  applied *only* to session chunks (7-day half-life; curated global/workspace
  memory is exempt), automatic staleness notes on old results, `/dream`
  consolidation, and a pre-compaction memory flush.
- **Hashline anchors** — line-hash + chunk-fingerprint anchors that detect
  stale edits and re-locate shifted ones within a bounded radius. Still
  experimental in-tree (ships with its own benchmark harness); interesting for
  the LL15 weak-model edit path if edit-staleness telemetry ever justifies it.

---

## Where Grok Build's design must not be copied

Grok Build is a hosted frontier agent. Caverno is local-LLM-first. Three of the
adopted mechanisms invert when that assumption changes, and the inversions are
more important than the mechanisms.

**1. The verification panel's shape.** Grok spawns N skeptics in parallel on
every completion claim. Caverno's environment breaks each premise that rests
on: subagents already overflow small context windows on a full catalog,
concurrent spawns against a shared LAN endpoint thrash model load and stall the
user's own session, and prefill latency is the local UX killer (Thesis §3).
Adopted instead: **one** cheap verifier inline, the N-way panel moved to the
LL18 idle orchestrator where tokens are free (Thesis §4, §7). An overnight
"these three goals do not meet their objective" report is a better product than
40 seconds added to every completion.

**2. The uncertainty default.** Grok's verifier prompt says *default to
`refuted` if uncertain* — correct when the verifier is strong, because one
extra iteration beats passing broken work. With a weak local verifier the same
instruction is a work generator: an uncertain model refutes nearly everything
and correct work never converges. Caverno inverts it below an LL3 fidelity
threshold — default to `not refuted`, refute only on a concretely cited finding
(`path:line`, a failing command, a named missing artifact). A verifier that
cannot cite does not get a vote, and below the threshold the stage is disabled
rather than run at low confidence.

**3. The completion tool's reliability.** Grok can assume the model calls
`update_goal`. Caverno cannot — tool-call fidelity is the most variable
property across local models (Thesis §1). Removing the lexical completion path
without a fallback converts "false completion" into "goal never closes", which
is the worse failure. Caverno therefore adds a **fourth mechanism Grok has no
need for: ask the user.** At budget exhaustion, "here is what I did and what I
could not verify — is this done?" beats any lexical inference and costs
nothing.

One mechanism transfers *better* than it does for Grok: the structured tool
result. Grok wants it for hygiene; Caverno additionally needs it to stop
shipping 200-line build logs to models that misread them and context windows
that cannot hold them.

And one placement must be rejected outright: Grok prunes tool results
per-request, which invalidates the KV prefix at the moment it fires. Caverno
has spent LL6 and LL22 on prefix stability; the graduated shape is adopted, the
placement is not (see the LL30 note).

## What this produced

| Milestone | Status | Origin in this comparison |
|-----------|--------|---------------------------|
| LL34 | `next` | Class 3 — structured tool-result envelope, plus summary-first rendering as capability compensation |
| LL35 | `next` | Class 1 — explicit goal-state tool with a real ack, plus the user-confirmation rung and an LL3 fidelity probe |
| LL36 | `next` | Class 2 — demotion, labeled firings, deletion by measurement |
| LL37 | `later` | Convergence controls adopted; panel shape, uncertainty default, and strategist placement all inverted for local models |
| LL32 | `later` | Deferred subdirectory instruction/skill discovery (corroborated) |
| LL30 | (updated) | Graduated prune shape adopted; firing point kept at compaction boundaries |
| LL29 | (demoted) | Unrelated to this comparison — demoted `next` → `later` in the same pass because its own LL31 evidence gate came back negative |

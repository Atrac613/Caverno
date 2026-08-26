# Text Heuristic Inventory and Removal Plan

**Status:** inventory complete, no removal work started (2026-08-26)

Caverno decides a great deal by pattern-matching prose. Every such decision is
bound to the languages whose vocabulary someone happened to enumerate — today
English and Japanese — and fails silently everywhere else. This document
inventories those decisions, ranks them by what a wrong verdict costs, and sets
out the order to remove them.

The standing direction it serves: **a heuristic may trigger, but it must never
judge.** Triggering cheaply and then confirming against ground truth is fine.
Reaching a verdict from a word list is not.

## Scale

| Measure | Count |
| --- | --- |
| Prose-judging predicates (`looksLike*`, `mentions*`, `*Marker`) | 183 |
| Files containing them | 51 |
| Files carrying hardcoded Japanese literals | 10 |

The Japanese literals are written as `\uXXXX` escapes or `List<int>` code-unit
sequences to satisfy the English-only source rule. That keeps the source
compliant and also makes them invisible to anyone grepping for Japanese text —
budget for this when auditing.

## Tier A — safety gates

A wrong verdict performs an action the user did not authorize, or refuses one
they did.

### A1. `production_release_approval_policy.dart` — PROVEN BROKEN

Seven predicates decide whether the user approved a **production release**.
`_containsAny` is a bare substring test over an English word list, plus
hardcoded Japanese code-unit sequences. Running the real policy over real
strings:

```
APPROVED  <- I'd rather you didn't ship it
APPROVED  <- never release this
APPROVED  <- nao execute o release        (explicit=true; needs no prompt at all)
APPROVED  <- Nein, kein Release
blocked   <- Ja, bitte veroeffentlichen   (a genuine approval, refused)
blocked   <- Si, procede con el release   (approved only via the prompt path)
blocked   <- Shi de, qing fabu            (a genuine approval, refused)
```

Four of eight denials read as approvals, and the failure is in the dangerous
direction. The denial list carries `no`, `don't`, `do not` — not `didn't`,
`never`, `não`, `nein`. A Portuguese denial reaches `explicit == true`, which
approves with no preceding prompt required.

**The correct mechanism already exists in the same coordinator.**
`ProductionReleaseApprovalCoordinator.evidenceFor` computes
`directlyApproved || questionApproved`, where `questionApproved` comes from
`ask_user_question` results through `_policy.answerApproves` — a structured
answer to a structured question, with no prose parsing. The prose path is a
parallel grant that can approve on its own.

**Action:** make the structured path the only path that grants approval. Demote
the prose predicates to shadow logging so any divergence is recorded before
they are deleted.

### A2. `git_write_confirmation_policy.dart` (3 predicates)

Decides whether the assistant asked the user to confirm a git write. Same
shape, lower blast radius. Follows A1's pattern.

### A3. `conversation_plan_execution_guardrails.dart` (6 predicates)

Judges *commands and paths*, not natural language, so it is not
language-fragile in the same way. Lower priority; keep as heuristic-with-
confirmation rather than rewriting.

## Tier B — truthfulness guards

A wrong verdict lets a false claim reach the user, or wrongly accuses a
truthful answer.

| File | Predicates | State |
| --- | --- | --- |
| `final_answer_claim_detector.dart` | 31 | largest single surface; English word lists |
| `unwritten_file_claim_guard.dart` | 15 regex / 28 ja literals | **PROVEN BROKEN** |
| `coding_verification_claim_guard.dart` | 4 regex / 8 ja literals | untested against other languages |
| `narrated_transcript_claim_guard.dart` | 5 | diffs commands, not prose — lower risk |

`UnwrittenFileClaimGuard`'s Japanese vocabulary covers create, update and add
but not fix or apply, so an answer claiming a fix had been *applied* reached the
user unflagged in session `a0ca65b7` gen-4 — in a turn whose every `edit_file`
was refused and whose successful-mutation count was zero. Verified by running
the guard over the recorded answer: zero claims, where the same sentence with a
known verb yields one.

**Ground truth exists for this entire tier.** `ToolOutcome.fileMutations`
carries per-path `changed: true/false` straight from the mutating tool, and
`ToolOutcome.exitCode` carries command outcomes. `FileMutationEvidencePolicy.
isSuccessfulResult` already consults them *first* and only falls back to prose
when the outcome is absent.

**Blocker, and the cheapest thing on this list:**
`FinalAnswerClaimNoticeInput._freezeToolResult` rebuilds every `ToolResultInfo`
without its `outcome`. Inside the applicator — where all the claim guards run —
the structured evidence is therefore *always* absent and every check falls
through to the prose path. Fixing the freeze is a prerequisite for
de-heuristicating this tier and is a one-line change.

Note that `isSuccessfulResult`'s prose fallback also carries
`startsWith('error:')`, `startsWith('auto-review denied')` and a lenient
`catch (_) { return true; }`. Its default is "assume success", which for a
notice that reports *absence* of change is the safe direction — but it means
nothing downstream of it is purely ground truth today.

## Tier C — flow control

A wrong verdict costs a turn or a generation, not correctness.

| File | Predicates |
| --- | --- |
| `tool_terminal_response_policy.dart` | 24 |
| `coding_continuation_recovery_policy.dart` | 5 |
| `turn_finalization_recovery_policy.dart` | 5 |
| `python_attachment_repair_policy.dart` | 4 |

`ToolTerminalResponsePolicy` holds the carve-outs that decide whether a
tool-role answer may be shown directly instead of regenerated. That decision is
already under separate investigation — see
`caverno-tool-role-answer-discarded` — and should not be changed on current
evidence.

## Tier D — content extraction and UX

A wrong verdict degrades a suggestion. Language-bound but not
correctness-critical: `proposal_option_extraction.dart` (30 regex),
`conversation_goal_suggestion_service.dart` (45 ja literals),
`workflow_task_proposal_quality_service.dart` (10), composer shortcuts, memory
extraction drafting.

These are the largest surface and the lowest stakes. Do them last, or accept
them as permanently best-effort.

## Replacement strategy

In cost order. Reach for the cheapest tier that settles the question.

1. **Ground truth** — the fact already exists structurally. `ToolOutcome`
   fields, tool result codes, exit statuses, content hashes. No judgment
   required. Covers most of Tier B.
2. **Structured self-report** — ask the model for a machine-readable field
   rather than parsing what it wrote. This model has a recorded
   structured-output capability profile, so a completion report can be a field
   instead of a sentence.
3. **Structured elicitation** — for *user* intent, ask a structured question
   with structured options. `ask_user_question` already does this and already
   feeds the release gate. Covers Tier A.
4. **Adversarial verification** — re-run the claim and compare. Most expensive;
   reserve for claims nothing else can settle.

Where none applies, the heuristic may remain as a **trigger** — cheap
pre-filter — provided something in tiers 1-4 renders the verdict.

## Removal method

Never delete a heuristic outright. Each removal ships in three steps:

1. Add the replacement, and run both. Log divergence with a transform id.
2. Let real sessions accumulate. `tool/check_fix_firings.py` reports whether a
   new signature has actually been observed, qualified by git ancestry.
3. Delete the heuristic once divergence is understood — not merely once it is
   rare.

The reason is on record: heuristics in this codebase over-fire *and* under-fire,
and some are load-bearing in ways their authors did not document. See
`caverno-false-completion-claim-guards` for guards proven load-bearing in
ordinary use, and for a guard false positive that was real.

## Milestones

Registered in `docs/roadmap.md` under the `HEU` prefix. Statuses there are the
authority; the roadmap's own convention warns that status markers go stale, so
confirm against the code before implementing any milestone below.

### HEU1: Structured-only production release approval — `next`

**Scope.** Remove prose from the release approval decision.
`ProductionReleaseApprovalCoordinator.evidenceFor` currently grants approval on
`directlyApproved || questionApproved`. Make `questionApproved` — the
`ask_user_question` structured path through `answerApproves` — the only grant.
Keep `looksLikeExplicitProductionReleaseApproval`,
`looksLikeAffirmativeReleaseApprovalAnswer` and
`looksLikeProductionReleaseApprovalPrompt` running in shadow, recording
divergence, rather than deleting them in the same change.

`looksLikeProductionReleaseCommand` stays: detecting that a *command* is a
release is a trigger, not a verdict, and it gates only whether approval is
required at all.

**Acceptance criteria.**
- No code path grants release approval from free text.
- A denial in any language cannot produce `approved: true`.
- Divergence between the structured verdict and the shadow predicates is logged
  with a transform id and is discoverable through `tool/check_fix_firings.py`.

**Verification evidence.** A predicate table asserting denials and approvals in
at least English, Japanese, German, Portuguese, Spanish and Chinese, including
the six strings this inventory proved wrong. The table asserts the *coordinator
verdict*, not the individual predicates, so a later vocabulary edit cannot
reintroduce a false approval unnoticed.

**Next action.** Route approval through `ask_user_question` only; demote prose
to shadow.

### HEU2: Preserve structured outcomes at the claim-notice boundary — `next`

**Scope.** `FinalAnswerClaimNoticeInput._freezeToolResult` rebuilds each
`ToolResultInfo` without `outcome`, so inside the applicator every claim check
falls through to its prose path even when `ToolOutcome` carries the answer.
Preserve it, keeping the freeze contract intact.

**Acceptance criteria.** A claim check inside the applicator can read
`ToolOutcome.fileMutations` and `exitCode`; a test proves the outcome survives
the freeze.

**Verification evidence.** Existing claim-guard tests stay green, plus one test
asserting outcome survival.

**Next action.** One-line change; do it before HEU3.

### HEU3: Ground-truth completion claims — `later`

**Scope.** Tier B. Decide file and command completion from
`ToolOutcome.fileMutations` / `exitCode` and, where ground truth cannot settle
it, from a structured self-report field rather than a sentence. Begin with the
claims `ToolOutcome` already answers.

**Acceptance criteria.** Each converted check reaches its verdict without
consulting a word list; the word list, if kept, only triggers.

**Next action.** Gated on HEU2.

### HEU4: Structured git write confirmation — `later`

Same shape as HEU1 at smaller radius.

### HEU5: Tool-role acceptance carve-outs — `later`

`ToolTerminalResponsePolicy`'s 24 predicates decide when a tool-role answer may
be shown directly. **Blocked**: the surrounding regeneration behaviour is under
measurement and must not be changed on current evidence. See
`caverno-tool-role-answer-discarded`.

### HEU6: Proposal, goal-suggestion and memory-extraction parsing — `later`

Largest surface, lowest stakes. May remain best-effort by explicit decision
rather than being converted.

## Verifying multi-language behaviour

The failures above were found by running the real predicates over real strings,
not by reading regexes. Any replacement needs the same treatment: a table of
denials and approvals in several languages, asserted against the predicate, so
a future vocabulary edit cannot quietly reintroduce a false approval.

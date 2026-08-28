# Text Heuristic Inventory and Removal Plan

**Status:** HEU1 and HEU2 landed. HEU3 is blocked on a corrected premise and HEU4 measured but held, so nothing in this track is currently actionable from recorded evidence (2026-08-27).

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

**Correction (2026-08-26).** An earlier revision of this document claimed the
structured `ask_user_question` path was free of prose parsing and that the fix
was a wiring change. That was wrong. `answerApproves` took the structured
result and then ran the *same* broken predicates over the answer text, and
`productionReleaseApprovalRequiredAction` instructed the model to "call
ask_user_question with an option whose label explicitly approves" — so the
model authored both question and option labels in whatever language, and the
harness tried to interpret them. The path was structured in transport only.

**Resolved by the token design.** The harness now issues a per-release token,
tells the model to put it on exactly one option, and decides approval by
comparing that token — never by reading words. The "exactly one offered option
carries it" clause matters: the model can see the token, so nothing stops it
attaching the token to the declining option as well, at which point a decline
would report a selection carrying the token. An ambiguous token identifies no
option and approves nothing. Free text carrying the token does not approve
either: typing it is not selecting the option that bears it.

The wording predicates remain, computing `proseWouldApprove` for shadow
comparison only. Divergence is logged at the tool-loop call site.

### A2. `git_write_confirmation_policy.dart` (3 predicates) — MEASURED 2026-08-27

Decides whether the assistant asked the user to confirm a git write, and holds
the pending write until it is answered. The dangerous direction is inverted
from A1: a question it fails to recognise does not block, so the assistant asks
and then commits without waiting.

The judged text is the *assistant's*, which is written in the user's language.
Running the real predicate over real questions:

```
BLOCKS   en               Shall I commit these changes?
PROCEEDS en (no keyword)  Shall I save this to the repository?
BLOCKS   ja katakana      (katakana "commit") + question marker
PROCEEDS ja no katakana   a plain Japanese "may I apply the changes?"
PROCEEDS de, fr, zh, ko   all four
BLOCKS   es, pt           only because "commit" survives as a loanword
```

Eight of twelve go unrecognised, and two of those are in the languages the
predicate claims to cover: the English keyword list misses "save this to the
repository", and the Japanese path needs a katakana loanword plus one of three
exact sentence endings.

**Blast radius is bounded, unlike A1.** A non-read-only `git_execute_command`
still goes through `_resolveToolApprovalGate`, so the user is prompted anyway —
though that approval is cacheable, unlike the SEC4.4g shell approval. What is
lost when the predicate misses is the assistant's own question being honoured,
not the user's say. A degradation rather than a breach.

**Held at `later` for a reason other than severity.** A1 had a structural
replacement to route to: a token the harness issued and could compare. Here
there is none. The only structural way to know the assistant asked for
confirmation is for it to *ask through `ask_user_question`* rather than in
prose, and the prose detector exists precisely because models ask in prose
instead. So the real fix is moving confirmations onto the structured channel —
a prompt-and-contract change, not a predicate replacement. Extending the
vocabulary would be the symptomatic fix and would fail again on the next
language.

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

**Blocker, now cleared (HEU2, `9cc6b68c`).**
`FinalAnswerClaimNoticeInput._freezeToolResult` rebuilt every `ToolResultInfo`
without its `outcome`, so inside the applicator — where all the claim guards run
— the structured evidence was *always* absent and every check fell through to
the prose path. It now survives the freeze.

It was not the one-line change this document first called it. Three ground-truth
paths were dead behind it, each with a text fallback that hid the loss: the
typed mutation path, the no-op-mutation check (a byte-identical write counted as
a change), and the entire structured test-count path in
`CodingVerificationClaimGuard`, which returns early on a null outcome and so
never ran here at all. No existing test changed behaviour when the outcome was
restored, because none of the three had coverage through the applicator.

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

**Landed.** Two consequences worth knowing, both surfaced by the change rather
than designed in:

- **Asking for a release used to approve it.** `looksLikeExplicitProduction
  ReleaseApproval` matches `^\s*(release|ship)\b`, so the message "Release the
  app" granted approval for the release it was requesting. Nine background
  process tests passed only because of this, using a release script as their
  long-running command; they now use a non-release command, which is what they
  meant.
- **Approval is now cross-turn by construction.** The token exists only once a
  release has been blocked, so the flow is attempt, refusal carrying the token,
  ask, answer, retry. `BlockedProductionReleaseRetryPolicy` already assumed
  this ("approval almost never arrives in the turn that was blocked"), and the
  end-to-end test spans two turns for that reason.

  A same-turn retry — the user selects the approving option while the turn is
  still running — is dropped as a duplicate. The guard refusal returns
  `isSuccess: true`, deliberately, so the loop treats a policy decision as a
  decision rather than a tool failure; the loop therefore records it as a
  completed call and claims its dedupe key, which the identical retry then
  collides with.

  **Investigated and not fixed, on purpose.** The obvious lever does not
  apply: `toolExecutionKey` appends `stateChangeGeneration` only for
  *read-only* commands, precisely so a mutating command cannot become
  re-runnable because state moved — a release must not run twice. Bumping
  `commandRetryGeneration` instead does work, but that counter means "a file
  mutation changed what a command would do", and an approval would make every
  previously-executed command re-runnable once. Simply not claiming a dedupe
  key for refused calls is the widest option and the least safe: a guard
  refusal never increments `toolFailureCounts`, so the key is the only thing
  bounding a refuse-retry-refuse loop. None of the three is proportionate to a
  same-turn convenience when the cross-turn path works, so this stays recorded
  rather than patched.

A chat message can no longer approve a release in any language, including
"承認します". The user must select the option carrying the token.

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

### HEU3: Completion claims — `blocked`, premise corrected 2026-08-27

**The scope as first written is not achievable.** It said "decide file and
command completion from ground truth". Ground truth cannot decide a completion
*claim*, because a claim guard does two things and only one of them is a
verdict about the world:

1. **Detection** — does this sentence assert that something was completed?
2. **Verification** — does the evidence support it?

Step 2 is already ground truth throughout Tier B. Step 1 is the heuristic, and
no amount of tool-result evidence tells you what a sentence asserts. Replacing
it needs structured self-report (the model declares its claims in a field) or
the `BlockedMutationNotice` shape (state the fact unconditionally, detect
nothing). Neither is a slice; both are designs.

**Baseline taken before implementing, per the discipline in
`docs/execution_contract_design.md`.** Firings of every claim transform across
715 `turn_exit` records (180 in `~/.caverno/session_logs`, 535 in
`build/integration_test_reports` — see
`caverno-canary-logs-outside-the-corpus`):

| transform | firings |
| --- | --- |
| `unexecuted_command_action_notice` | 18 |
| `unexecuted_command_action_retry` | 14 |
| `unverified_read_only_inspection_notice` | 11 |
| `failed_command_claim_notice` | 5 |
| `verification_claim_notice` | 3 |
| `unwritten_file_claim_notice` | 2 |
| `narrated_transcript_claim_notice` | 0 |

The command family carries the traffic; the file-claim guards fire 2–3 times in
715 turns, and `NarratedTranscriptClaimGuard` has never fired at all.

**A low firing rate does not retire a guard.** `unwritten_file_claim_notice`
fires twice not because the state is rare but because the guard is partly
blind: session `a0ca65b7` gen-4 produced exactly the state it exists for and it
scored zero, because the claim used a verb its vocabulary lacks. Rate measures
where a heuristic fires, never where it silently fails.

**The obvious substitute was measured and rejected.** A command analogue of
`BlockedMutationNotice` — state the fact when a turn attempted commands and
none ran — looked justified at 22 of 715 turns. Auditing the instrument
collapsed it to **3 of 715 (0.4%)**: 19 of the 22 were harness-injected
results, not refusals. `BlockedMutationNotice` was built at 4.4% *with* a
confirmed user-facing harm case; 0.4% with none does not carry it.

**Prerequisite this uncovered.** A runtime refusal and a harness-injected
feedback result are indistinguishable in a tool result — both render as
`{"ok": false, "code": ..., "error": ...}` with no `stdout`. The synthetic
codes seen so far are `unexecuted_command_action_retry_required`,
`unchanged_verifier_replay_before_repair_blocked`,
`goal_validation_probe_requires_verifier` and
`duplicate_tool_call_result_reused`; the genuine ones include
`production_release_explicit_approval_required`,
`local_shell_git_write_blocked`, `project_mutation_outside_root` and
`saved_validation_command_modified`. Any measurement gated on refusal rates is
wrong by roughly 7x until that distinction is structural. Compare
`caverno-triage-marker-transport-inflation`.

**Next action.** None from this evidence. Unblocking needs either the
synthetic/refusal distinction (so refusal rates can be trusted) or a decision
to design structured self-report on its merits rather than on a firing rate.

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

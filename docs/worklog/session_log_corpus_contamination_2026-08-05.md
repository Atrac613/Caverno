# Session-Log Corpus Contamination (2026-08-05)

Question this answers: **the LL31 exit distribution shows `partial_fragment` as
the second-largest exit reason (191 turns, 5.9%). The recorded baseline was
97.9% `text_response`. Which is right?**

Neither. The corpus every roadmap measurement reads was 90% test output.

## How it surfaced

Regenerating the LL31 distribution put `partial_fragment` second at 5.9%, well
above the recorded baseline's implied floor. `partial_fragment` is a lexical
classification — a final answer of 24 characters or fewer whose last character
is not a sentence terminator
(`ToolLoopExitClassifier._looksLikePartialFragment`) — so the first check was
whether the label was real.

The first one opened was a whole session log containing exactly two entries:

```
response.content   "CLI2_CHAT_FIXED_OK"
response.finishReason  "stop"
turnExit.reason    "partial_fragment"
```

An 18-character canary sentinel that the provider reported as a completed
generation, classified as a truncated fragment. Ground truth (`finishReason`)
and the lexical label disagreed, and the lexical label was the one recorded.

## The measurement

Over the 1,740 files in `~/.caverno/session_logs`, count how many contain at
least one LLM request/response entry (`createChatCompletion`,
`createChatCompletionWithToolResults`, `streamChatCompletion`,
`streamChatCompletionWithTools`). A file with turn markers but no inference did
not record a session.

| Population | Files |
|---|---:|
| Contains ≥1 LLM request/response | **171** |
| `turn_exit` markers only, no inference | **1,569** |

The 1,569 carry no build provenance (`build.commit == "unknown"`), and their
mtimes run 2026-07-02 → 2026-08-05, i.e. they were still accumulating. Two of
them are appended to on every run and had grown to 1,004 and 484 turns —
**45.7% of all scanned turns came from two files.**

## Cause

`LlmSessionLogStore._defaultRootDirectoryProvider` fell back to
`$HOME/.caverno/session_logs` whenever `CAVERNO_SESSION_LOG_DIR` was unset, and
`llmSessionLogStoreProvider` builds a default store. Every widget/notifier test
that exercised the production provider therefore appended to the developer's
real corpus — the same directory `tool/triage_session_logs.py` reads.

Demonstrated rather than inferred: running
`test/features/chat/presentation/providers/chat_notifier_prefix_stability_test.dart`
with `CAVERNO_SESSION_LOG_DIR` pointed at an empty scratch directory produces
`chat/prefix-stability-conversation.jsonl` there — the same filename that held
1,004 turns in the real corpus.

The sibling class already had the guard.
`ToolApprovalAuditLog` disables itself under `FLUTTER_TEST` for exactly this
reason, and its doc comment names `LlmSessionLogStore` as the contrasting case.

## What the published figures become

| Published | Where | Corrected |
|---|---|---|
| "1,735 real session logs" | LL35, LL36 | 171 logs recorded an LLM call |
| 93.2% `text_response` / 5.9% `partial_fragment` over 3,258 turns | LL31 | 190 turns; `partial_fragment` is 4 turns (2.1%) |
| 44 transform firings across 5 labels | LL36 | **32 firings across 4 labels** |
| 1 shadow disagreement (`goal_completion_lexical_only`) | LL35 | **0** — the single record came from a fixture |
| 2nd-worst session, score 94.5 | LL31 ranking | `test-conversation-1.jsonl`, a fixture |

Per-label, LL36's distribution corrects to:

| label | published | real |
| --- | ---: | ---: |
| `unexecuted_command_action_notice` | 36 | **26** |
| `unverified_read_only_inspection_notice` | 5 | **3** |
| `coding_continuation_recovery_prose_only_coding_continuation` | 2 | 2 |
| `unwritten_file_claim_notice` | 1 | 1 |
| `goal_completion_lexical_only` | 1 | **0** |

**The overturned claim is LL35's.** Yesterday's reading recorded one shadow
disagreement and named it as the single case where prose completed a goal the
tool had not. All four `goal_completion_lexical_only` records in the corpus are
fixture output. Across every real session the shadow has recorded **zero
disagreements on all three labels**, from 7 shadow turns rather than 11.

That does not change LL35's decision — the sample is smaller than the one that
was already judged too small to act on. It changes what the sample says: not
"one disagreement in 1,735 sessions", but "no disagreements in 171".

## Also true, and separately important

**When this was measured, the newest log containing an LLM call was dated
2026-07-27.** Nine days had passed in which the corpus grew by hundreds of
files, every one of them test output. (Two grounded logs from build `731adfcf`
appeared while this fix was being written, so the corpus is live again — the
gap was real, not permanent.)

LL34's exit-status agreement, LL35's shadow sample, and LL36's
delete-by-measurement are each gated on "letting the instrument run longer", and
for those nine days none of them accumulated anything while the file count went
up. Passive waiting is not a plan for those three items; they need either real
usage with logging on, or canary runs whose logs are folded into the corpus.

## What was changed

1. `LlmSessionLogStore` no longer writes under `flutter test` unless the
   destination was chosen deliberately — an injected `rootDirectoryProvider`,
   or `CAVERNO_SESSION_LOG_DIR` (which the live canary scripts set, and which
   must keep working: they run under `flutter test` and read their logs back).
   Outside `flutter test` nothing changes.
   `test/features/chat/data/datasources/llm_session_log_store_write_gate_test.dart`
   covers all four combinations plus the two end-to-end cases.
2. `tool/triage_session_logs.py` counts only grounded logs by default and prints
   how many it skipped. `--include-ungrounded` restores the old behavior. The
   skip line is deliberately loud: a silent filter is how this happened.

Not changed: the 1,569 existing files. They are the user's data and deleting
them is their call, not a side effect of a fix. The tool now ignores them.

## Not concluded here

`partial_fragment` classifying a `finishReason: "stop"` canary sentinel as
truncated is a real instance of a lexical label outranking mechanical ground
truth, which is the pattern the LL34-LL37 track exists to remove. But all four
real instances are canary sentinels, so there is no evidence it misfires on user
traffic, and no change is proposed from a sample of four.

## Verification

```bash
python3 tool/triage_session_logs.py --top 5
```

```bash
fvm flutter test test/features/chat/data/datasources/llm_session_log_store_write_gate_test.dart
```

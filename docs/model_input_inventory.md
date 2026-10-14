# Model Input Inventory (LL46)

Every request Caverno sends to a model carries a session-log request label
(`request.label`, schema v3+). This inventory has one row per label: who
produces the request, what it adds to the model's input, and whether it keeps
the tool loop's cached prefix. `test/docs/model_input_inventory_docs_test.dart`
fails when a label in `lib/` has no row here.

Scope of this first slice: requests, keyed by label. Two other kinds of
model-visible text are not inventoried yet: system-prompt sections, and
guidance written into tool-result payloads.

## How to read the columns

- **Shape**: *loop* requests append to the running turn's history and send
  the loop's tool catalog; *separate* requests build their own message list,
  usually with a different system prompt and no tools, so they cannot reuse
  the loop's cached prefix.
- **Measured**: counts, median prompt tokens, and the median size of the last
  user/system message (the injection) across grounded session logs on
  2026-10-14, personal-eval replays excluded. Rerun the measurement before
  relying on a number.
- **Prefix**: whether a schema v6 log (LL43 envelope digests) has shown the
  prefix kept. `unmeasured` means no v6 evidence yet, not a known break.

## Main tool loop

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `turn opening request` | `chat_notifier.dart` `_sendWithTools` | The user's message | loop | 511 req, ~17.4k tok, ~950 ch | kept (b053bddd, ca7f4499) |
| `tool-result follow-up` | `chat_notifier.dart` tool loop | Tool calls and their results | loop | 5,000 req, ~23.6k tok, ~1.2k ch | kept: 12,288 of 12,756 cached (b053bddd) |
| `content tool-result continuation` | `chat_notifier.dart` content-tool path | Results of tool calls printed in content | loop | not seen | unmeasured |
| `tool-loop exhaustion recovery` | `chat_notifier.dart` loop limit | Instruction to finish after the move budget | loop | 94 req, ~22.8k tok, ~490 ch | unmeasured |
| `duplicate inspection recovery` | `DuplicateRecoveryKind` | Notice that a read repeated, with the earlier result | loop | 69 req, ~26.9k tok, ~390 ch | unmeasured |
| `duplicate follow-up recovery` | `DuplicateRecoveryKind` | Notice that a follow-up repeated | loop | 66 req, ~22.7k tok, ~640 ch | unmeasured |
| `browser-action repair` | `chat_notifier.dart` | Instruction to act on a recovered browser snapshot | loop | not seen | unmeasured |
| `background process monitor feedback` | `chat_notifier.dart` | Running-process state and next check | loop | 1 req, ~22.4k tok, ~1.9k ch | unmeasured |
| `coding verification feedback` | `chat_notifier_coding_verification_feedback.dart` | Verification result to act on | loop | not seen | unmeasured |
| `unexecuted command action retry` | `chat_notifier_unexecuted_action_recovery.dart` | Claimed command with no execution, to run it | loop | 23 req, ~26.5k tok, ~1.4k ch | unmeasured |
| `blocked production release retry` | `chat_notifier_unexecuted_action_recovery.dart` | Blocked release and how to proceed | loop | 1 req, ~23.2k tok | unmeasured |
| `narrated transcript feedback` | `chat_notifier_unexecuted_action_recovery.dart` | Narrated commands that never ran | loop | 5 req, ~26.9k tok, ~1.4k ch | unmeasured |
| `python attachment analysis repair` | `chat_notifier_python_attachment_repair.dart` | Instruction to analyse an attached file with Python | loop | not seen | unmeasured |
| `python attachment path repair` | `chat_notifier_python_attachment_repair.dart` | Corrected attachment path | loop | not seen | unmeasured |

### Coding continuation recovery (`CodingRecoveryText`)

One producer, `coding_continuation_recovery_request.dart`, labelled by
recovery code. Each adds a recovery prompt naming what the previous response
left undone.

| Label | Shape | Measured | Prefix |
|---|---|---|---|
| `structured coding task status recovery` | loop | 81 req, ~18.8k tok, ~870 ch | unmeasured |
| `reasoning-only stop recovery` | loop | 39 req, ~28.0k tok, ~670 ch | unmeasured |
| `project verification repair recovery` | loop | 36 req, ~20.2k tok, ~2.4k ch | unmeasured |
| `structured project subtask recovery` | loop | 30 req, ~30.0k tok, ~1.4k ch | unmeasured |
| `prose-only coding continuation recovery` | loop | 19 req, ~20.3k tok, ~630 ch | unmeasured |
| `length-truncated pending action recovery` | loop | 15 req, ~27.2k tok, ~570 ch | unmeasured |
| `unexecuted delegation recovery` | loop | 1 req, ~9.3k tok, ~520 ch | unmeasured |
| `bracketed coding tool request recovery` | loop | not seen | unmeasured |

## Separate requests

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `tool-result final answer` | `chat_notifier_final_answer_recovery.dart` | User-role re-send of the tool results (`buildAnswerPrompt`) | separate, no tools | 600 req unlabeled before `fe107074e`; ~3.5k tok in b053bddd | breaks: 0 cached (b053bddd); skipped when the loop's answer is kept |
| `final answer concise retry` | `chat_notifier_final_answer_recovery.dart` | Retry prompt for a truncated or degenerate final answer | separate, no tools | 13 req unlabeled before `fe107074e` | breaks |
| `approval auto-review` | `SecondaryRequestLabel` | Approval review packet (JSON) | separate | 1,161 req unlabeled before `8d450db34` | separate prefix by design |
| `memory extraction` | `SecondaryRequestLabel` | Profile and recent turns | separate | 517 req unlabeled before `8d450db34` | separate prefix by design |
| `planning request` | `SecondaryRequestLabel` | Task or workflow proposal prompt | separate | 44 req unlabeled before `8d450db34` | separate prefix by design |
| `goal suggestion` | `SecondaryRequestLabel` | Conversation summary for a goal suggestion | separate | not seen | separate prefix by design |
| `pro_reasoning_frame` | `pro_reasoning_run_notifier.dart` | Problem framing prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_investigate` | `pro_reasoning_run_notifier.dart` | Investigation prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_candidate` | `pro_reasoning_run_notifier.dart` | Candidate generation prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_critique` | `pro_reasoning_run_notifier.dart` | Critique prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_synthesis` | `pro_reasoning_run_notifier.dart` | Synthesis prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_summary` | `pro_reasoning_run_notifier.dart` | Summary of the run | separate | not measured | separate prefix by design |

## Known gaps

- Requests from producers outside the chat feature (routines, farm
  decomposition, diagnostics) carry no label yet.
- Prefix behaviour of the main-loop recovery labels is unmeasured until schema
  v6 logs exercise them. `tool/triage_session_logs.py` reports a cache-read
  fall against the changed envelope digest.

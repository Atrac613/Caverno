# LL36 delete-by-measurement evidence (2026-08-10)

## Decision

LL36 is complete. The measured slice produced four separate decisions:

1. **Remove lexical goal completion inference: Go.** Across twelve clean,
   model-varied coding runs on build `018a1825`, 37 owner-scoped goal turns
   produced 28 agreements and 9 explained disagreements. Every disagreement
   was `goal_completion_tool_accepted_lexical_missed`; there were zero
   lexical-only completions and zero unknown verdicts. The lexical branch never
   supplied a completion the structured path missed, so
   `ConversationGoalProgressInference` and its runtime shadow producer were
   removed in `3ec72fa4`. Historical shadow records remain readable by triage.
2. **Demote prose task-progress verdicts: Go.** Assistant narration still
   supplies a summary and advisory completion/blocker claims, but its result
   type can no longer return workflow or validation status. Saved tasks, typed
   validation outcomes, and tool-result completion assessments own terminal
   state. An unresolved grounded failure is persisted only after its bounded
   recovery route is exhausted (`160b38f7`).
3. **Remove pending-action recovery: No-Go.** The pre-change matrix recorded
   `pending_action_length_recovery` twice in natural Markdown TOC runs, in
   addition to the deterministic 1/1 recovery canary on `4c0efc96`. The path is
   reached and load-bearing.
4. **Remove the outcome-free workflow failure fallback: No-Go.** The twelve-run
   corpus contains no lexical-only failure result after deduplication, but it
   covers built-in tools and two fixtures rather than outcome-free third-party
   MCP failures. `137a74df` adds a durable failure-evidence distribution to
   `tool/triage_session_logs.py`; the compatibility fallback stays until that
   distribution includes its intended population.

## Pre-change measurement matrix

Every row used `http://192.168.100.241:1234/v1`, clean build `018a1825`, and
session logs isolated under the report root shown below. Two repeats per model
and surface prevent a one-off success from deciding deletion.

| Model | Surface | Report root suffix | Readiness |
| --- | --- | --- | --- |
| `qwen3.6-27b-128k` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786279085` | ready |
| `qwen3.6-27b-128k` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786279740` | ready |
| `qwen3.6-27b-128k` | Markdown TOC | `coding_markdown_toc_live_canary_1786280385` | ready |
| `qwen3.6-27b-128k` | Markdown TOC | `coding_markdown_toc_live_canary_1786281054` | blocked |
| `qwen3.6-27b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786281631` | ready |
| `qwen3.6-27b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786282285` | ready |
| `qwen3.6-27b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786282828` | blocked |
| `qwen3.6-27b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786283270` | ready |
| `qwen3.6-35b-a3b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786284398` | ready |
| `qwen3.6-35b-a3b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786284527` | ready |
| `qwen3.6-35b-a3b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786284641` | blocked |
| `qwen3.6-35b-a3b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786284799` | ready |

The 12 runs yielded 8 ready and 4 correctly blocked outcomes. The session-log
aggregate contained 37 turn exits:

| Signal | Count |
| --- | ---: |
| `text_response` | 19 |
| `pending_batch_executed` | 14 |
| `tool_failure_abort` | 3 |
| `unexecuted_tool_request` | 1 |
| LL34 typed agreement | 68 / 68 |
| LL35 agreement | 28 / 37 |
| LL35 accepted-tool / lexical-missed | 9 / 37 |
| LL35 lexical-only or unknown | 0 / 37 |

Observed transform firings were:

| Stable transform label | Count |
| --- | ---: |
| `failed_command_claim_notice` | 3 |
| `final_answer_concise_retry` | 2 |
| `truncated_tool_call_arguments_feedback` | 2 |
| `pending_action_length_recovery` | 2 |
| `coding_continuation_recovery_length_truncated_pending_action` | 2 |
| `unexecuted_tool_request_notice` | 1 |
| `unverified_read_only_inspection_notice` | 1 |

The new request-tool-result analysis deduplicated 746 serialized appearances to
401 distinct results: 282 `no_failure`, 85 `structured_payload`, and 34
`typed_exit`. No result depended on `lexical_only` evidence in this cohort.

## Post-change confirmation

Four clean runs on build `137a74df` checked the new terminal-state boundary on
two models and both surfaces:

| Model | Surface | Report root suffix | Result | Duration |
| --- | --- | --- | --- | ---: |
| `qwen3.6-27b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786286836` | ready | 283,188 ms |
| `qwen3.6-27b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786287132` | ready | 139,947 ms |
| `qwen3.6-35b-a3b-vision` | TODO goal | `coding_goal_auto_continue_todo_fixture_1786287284` | ready | 141,897 ms |
| `qwen3.6-35b-a3b-vision` | Markdown TOC | `coding_markdown_toc_live_canary_1786287440` | ready | 55,838 ms |

All four passed 1/1 and reached a successful verifier. The two TODO runs each
performed two continuations and reduced the staged diagnostic count from two to
one. The 35B TOC run performed one continuation. Across the four logs:

- all nine `turn_exit` records carry both `turnId` and `assistantMessageId`;
- LL34 recorded 15/15 typed agreements;
- 77 deduplicated results split into 61 `no_failure`, 12
  `structured_payload`, and 4 `typed_exit`, with zero `lexical_only`;
- `verification_claim_notice` fired once and remained owner-scoped;
- no new `goal_completion_shadow` marker was emitted, as expected after the
  measured comparator removal.

One internal TOC turn ended with `tool_failure_abort`; the owner-scoped goal
continuation recovered on the next turn and the canary remained ready. This is
useful LL29 monitoring evidence, not an LL36 regression.

The first repository-wide gate exposed one adjacent compatibility consumer:
the exact Git init/write/add/commit/revert/clean-status lifecycle already
stopped follow-up tools from mechanical results, but goal persistence had still
relied on the generated completion sentence. The lifecycle detector now records
its owner-scoped grounded completion before finalization. The original
ChatNotifier regression test passes with prose inference still absent.

## Verification

The implementation was verified with:

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_execution_progress_inference_test.dart \
  test/features/chat/presentation/providers/conversations_notifier_test.dart \
  test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart \
  test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  test/quality/lexical_guard_advisory_test.dart
python3 test/python/triage_session_logs_test.py
fvm flutter analyze
tool/codex_verify.sh
```

The live commands were the two existing wrappers with
`CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`, `no-key`, and the model
from the matrix:

```bash
tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh
tool/run_coding_markdown_toc_live_canary.sh
```

Session logs and report workspaces remain ignored build artifacts and are not
committed.

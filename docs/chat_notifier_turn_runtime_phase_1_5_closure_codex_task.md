# ChatNotifier TurnRuntime Phase 1.5 Closure: Codex Task

## Task

- Goal: Close the bounded production prototype with reproducible comparison,
  regression, coverage, and live-canary evidence, then record the Phase 2
  decision.
- User-visible behavior: None. This task records and verifies an architecture
  boundary experiment.
- Non-goals: Starting Phase 2 implementation, wiring
  `ChatToolHandlerCatalog`, completing the I2 catalogue matrix, or refreshing
  the global turn-scope baseline.

## Context

- Comparison base: `0bac2bc0`, whose selected source is byte-identical to the
  validated pre-squash selection revision.
- Final prototype build: `fc12a1f2`.
- Selected part: `chat_notifier_goal_auto_continue.dart`.
- Live model: `qwen3.6-27b-vision` at the same local endpoint used by the
  pre-prototype baseline.

## Acceptance Criteria

- Remove at least one explicit owner or generation parameter.
- Do not increase turn-reachable ambient reads.
- Add no callback that captures `ChatNotifier`.
- Move no conversation- or thread-scoped state into `TurnRuntime`.
- Pass the exact focused test, the repository coverage gate, and the selected
  live canary.
- Report line delta, port and callback surface, touched production files, and
  public declarations as cost evidence rather than structural gates.
- Keep production catalogue wiring blocked pending I2 and WS6-19.

## Verification

```bash
PYTHONDONTWRITEBYTECODE=1 python3 \
  tool/measure_chat_notifier_turn_runtime_prototype.py compare \
  --selection /tmp/chat_notifier_turn_runtime_selection.json \
  --before-revision 0bac2bc0 \
  --after-worktree . \
  --output /tmp/chat_notifier_turn_runtime_comparison.json
tool/codex_verify.sh --coverage
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
  tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh
```

## Handoff Notes

- Structural result: Pass. One identity parameter was removed, ambient reads
  changed by `-1`, no new callback captures `ChatNotifier`, and runtime state
  remains owner-scoped.
- Cost result: 15 production files changed by `+708` lines, with one introduced
  port method, two clock callback surfaces, and 19 public declarations. The
  positive delta is material and must constrain Phase 2 design, but it does not
  falsify the composition-root boundary.
- Regression result: Analysis passed, generated files were unchanged, all
  6,638 repository tests passed, and total line coverage was 79.39%
  (`70,844/89,239`).
- Live result: The clean `fc12a1f2` build passed 1/1 with readiness `ready`, two
  ordered goal continuations, diagnostic progression `2 -> 1`, and no blocker
  or warning failures. The model ended with the attributed
  `post-verification repair was not revalidated` stop instead of terminal
  verifier success; the canary contract still passed because it verifies the
  migrated continuation path, not full task completion.
- Decision: Go to Phase 2 design only. Do not start broad extraction until the
  design identifies reusable ports, a public-surface budget, and smaller
  independently reversible slices. `ChatToolHandlerCatalog` wiring remains
  No-Go until I2 maps all six binding groups and WS6-19 passes.

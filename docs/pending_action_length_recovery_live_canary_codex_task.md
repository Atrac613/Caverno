# Pending-Action Length Recovery Live Canary

## Goal

Add a deterministic hybrid Live LLM canary for the coding recovery path that
handles a final tool-result stream ending with `finishReason=length` while
verified work is still incomplete.

The canary must keep normal model generations live. It may inject exactly one
truncated final stream after a failed verifier result, then must prove that the
bounded recovery request reaches the configured Live LLM with the original
capability-filtered tool set and resumes tool use successfully.

## Affected Components

- `tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart`
- `tool/live_llm_canary_summary.dart`
- A dedicated Live canary wrapper under `tool/`
- Focused wrapper and summary tests under `test/tool/`

## Acceptance Criteria

- The fixture injects one final-stream `length` finish reason only after a
  failed TODO verifier result.
- The recovery request is sent to the configured Live LLM exactly once.
- The recovery request advertises the same filtered tools available before the
  injected truncation.
- The Live LLM responds with tool calls, the verifier later exits successfully,
  and the independent fixture verifier passes.
- No mutation occurs after verifier success and the goal does not become
  blocked.
- Canary reports expose pending-action deferral, recovery-request, and
  recovery-tool-call counters.
- The wrapper uses the normal model token budget rather than globally reducing
  `maxTokens`.

## Verification

```bash
tool/codex_verify.sh --coverage
```

Run the dedicated wrapper against the configured trusted OpenAI-compatible
endpoint after deterministic verification passes.

## Results

- Current implementation: `4c0efc96` (clean build provenance).
- Deterministic verification: the complete non-live TODO canary suite passed
  26 tests with 9 live-only skips; focused notifier, detached-owner, registry,
  wrapper, analyzer, file-size, and lexical-guard checks also passed. The full
  `tool/codex_verify.sh` gate completed successfully, including all 6,919 root
  Flutter tests.
- Live endpoint: `http://192.168.100.241:1234/v1`
- Model: `qwen3.6-27b-vision`
- Successful report:
  `build/integration_test_reports/coding_pending_action_length_recovery_live_canary_1786276525`
- Outcome: 1/1 test passed in 55,881 ms with readiness `ready`.
- Recovery evidence: one pending-action deferral, one bounded recovery request,
  one recovery tool-call response, one owner-scoped
  `pending_action_length_recovery` transform, and one bounded continuation
  recovery transform.
- Verifier evidence: the exact behavior-neutral source-marker diagnostic exited
  1, the model performed its one requested mutation, and the complete real
  verifier then exited 0. Both typed-vs-parsed tool outcomes agreed.
- Goal evidence: the goal completed without becoming blocked, no unchanged
  verifier replay was dispatched before repair, and no post-success mutation
  was attempted.

Three earlier 2026-08-09 runs are diagnostic evidence, not promotion evidence:
the first proved the staged failure was attached to the wrong tool boundary;
the second proved nested `_executeToolCalls` reset and erased the transform;
the third preserved the transform but exposed a fictional diagnostic that did
not deterministically lead to re-verification. Each failure produced the next
bounded repair used by the passing run.

# grok-4.5 Multi-Endpoint Verification Run - 2026-07-23

This note records the first CMVP-1 run made against a cloud endpoint registered
through the new multi-endpoint settings (branch `feature/multi-llm-endpoints`).
It is a record only: nothing here was investigated to a root-cause conclusion,
and no fix is proposed as verified.

## Inputs

| Item | Value |
|------|-------|
| Session log | `~/.caverno/session_logs/coding/64558af9-c0ae-46ab-afe0-a3295a0838d7.jsonl` |
| Build provenance | `commit 0006912c`, `dirty: true`, `builtAt 2026-07-23T13:39:06Z` |
| Prompt | `todo_app.md を参考にしてMVPを実装。言語はdartとする。` (CMVP-1 fixture, `tmp/MVP/todo/run9`) |
| Model / endpoint | `grok-4.5` via `https://api.x.ai/v1`, registered as a second endpoint profile |
| Wall clock | 6 min 16 s (22:42:51 - 22:49:07 JST) |
| Volume | 56 log records, 531,758 prompt tokens, 9,986 completion tokens |
| Turns | `gen-6`, `gen-7`, `gen-8` with two goal auto-continuations |

## Multi-Endpoint Result

The feature behaved as designed. Persisted settings held two profiles: `primary`
(seeded from the pre-existing single endpoint, `http://192.168.100.241:1234`) and
a newly added `xAI` profile (`https://api.x.ai/v1`, `grok-4.5`, created 22:41),
with the latter active and mirrored into `baseUrl` / `model`. Every one of the 56
requests went to `grok-4.5`; no request fell back to the previous endpoint and no
stale base URL appeared.

## Observations

### 1. Task finished in turn 1; the remaining 77% was harness churn

Turn 1 (88 s) wrote `pubspec.yaml` and `bin/todo.dart`, ran
`dart analyze` (exit 0, `No issues found!`) plus CLI checks, and `update_goal`
was accepted (`goal_completion_shadow: completionRecorded`). The goal
auto-continue that followed still reported `mutatedWithoutExecution: true` and
`verificationGeneration: -1`, and continued the goal.

### 2. Verification commands classified as workspace mutation

The verification command the model chose was

```
rm -f .todo.json && dart analyze bin/todo.dart && echo '--- help ---' && dart run bin/todo.dart help; ...
```

`ToolCapabilityClassifier` treats a compound command as `verification` only when
every segment is verification/inspection, so the leading `rm -f` makes the whole
command `workspaceMutation`. Downstream, in turn 2 a validation-only
continuation rejected commands of this shape outright
(`goal_validation_probe_requires_verifier`, `attempted_effect: workspaceMutation`),
and the turn's only other verification (`run_tests`) failed with exit 65 because
`package:test` was not yet a dev dependency. That continuation produced no
verification at all.

Whether this classification also explains observation 1 and 3 is a hypothesis,
not a finding.

### 3. Goal-completion deadlock in turn 3

Records 43-51 loop `update_goal -> run_tests -> update_goal ...` five times.
Every `update_goal(completed: true)` returned

```
Completion not recorded — the following remain outstanding:
- the last verification command failed
```

while the same turn's `run_tests` returned `exit_code: 0` (6/6 tests passing) and
`dart_test_verification_evidence` reported `validation_status: "passed"`. The
loop cost 9 requests, 163,837 prompt tokens and ~3.5 min, and the session ended
with the goal still open even though the MVP and its acceptance tests were
complete on disk.

### 4. Role endpoint pinned to a LAN host rejected the primary model

`memoryExtractionEndpointId` was pinned to `http://192.168.100.241:1234/v1` with
an empty `memoryExtractionModel`, so the role fell back to the primary model and
the LAN host answered `400 model 'grok-4.5' not found` (record 15, 110 ms).
`MeshSecondaryCompletionRunner` demoted the endpoint and retried on the primary
21 ms later, which succeeded; the cost was one wasted round trip. This failure
mode becomes reachable in normal use now that the primary endpoint can be a
different provider from the pinned mesh host.

## Observability Gap

Logged requests carry `model` but no `baseUrl` or endpoint id, so the endpoint
behind observation 4 had to be recovered from persisted settings rather than
from the log. Endpoint attribution in the request record is worth more now that
the primary endpoint is switchable.

## Status

Recorded, not acted on. No fix has been attempted for any observation above.

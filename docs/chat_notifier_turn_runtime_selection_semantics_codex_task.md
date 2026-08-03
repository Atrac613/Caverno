# Correct TurnRuntime Prototype Selection Semantics

## Goal

Make the `TurnRuntime` prototype selector rank only entrypoints that carry an
explicit turn owner or generation identity, as required by the architecture
renewal plan.

## Scope

- Treat `ChatTurnOwner`, `interactionGeneration`, and `generation` parameters
  as explicit turn identity.
- Keep `Conversation` parameters in the broad turn-scope audit, but exclude
  them from the prototype selector's identity-entrypoint ranking.
- Add a regression fixture proving that conversation context cannot outrank an
  explicit owner or generation.
- Re-measure the current candidate table and update decision documentation.

## Non-goals

- Refreshing the checked-in turn-scope baseline.
- Creating `TurnRuntime` or changing production Dart behavior.
- Implementing prototype comparison or executing the live canary.
- Changing the broad audit's ambient-read reachability semantics.

## Acceptance Criteria

1. The selector recognizes only explicit owner or generation parameters for
   its primary ranking key.
2. A `Conversation`-only entrypoint contributes zero identity entrypoints.
3. Existing owner-based fixtures, deterministic ordering, input bindings, and
   gate validation remain compatible.
4. The current candidate is re-measured from a clean revision before prototype
   work begins.

## Verification

```bash
python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py
python3 tool/measure_chat_notifier_turn_runtime_prototype.py select \
  --audit tool/chat_notifier_turn_scope_baseline.json \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --source-revision HEAD \
  --require-clean \
  --output /tmp/chat_notifier_turn_runtime_candidate.json
git diff --check
```

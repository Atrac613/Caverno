# Validation Probe Capability Gate

## Task

- Goal: Make coding-goal validation continuations execute verification before
  exposing mutation tools again.
- User-visible behavior: Weak models receive a verifier-only continuation after
  unverified changes, then regain repair tools only when verification reports a
  concrete failure.
- Non-goals: Increasing goal turn budgets, weakening diagnostic stall guards,
  or adding another persisted workflow state machine.

## Context

- Affected components: Goal Auto Continue, hidden-prompt tool selection, and
  tool-result completion evidence.
- Reference pattern: Existing tool-definition selection in `ChatNotifier` and
  the evidence-driven `ConversationGoalAutoContinuePolicy`.
- Known failure: An exact-short Markdown TOC canary exposed mutation tools on a
  validation-only turn, allowing the model to edit without re-running the
  verifier and causing a premature blocked goal.

## Implementation Notes

- Filter the existing hidden-turn tool definitions instead of introducing a
  parallel execution loop.
- Allow `local_execute_command` and `run_tests` during validation probes.
- Treat any completed execution verification as satisfying prior mutation
  evidence, even when it reports diagnostics.
- Count consecutive missed validation probes, resetting the count after an
  execution verification result.
- Preserve existing turn, diagnostic repair, and no-progress budgets.

## Similar-Pattern Search

- Search terms: `sendHiddenPrompt`, `_sendWithTools`,
  `requiresValidationContinuation`, `validationContinuations`, and
  `carryForwardIncompleteFrom`.
- Files inspected: Goal Auto Continue provider extension, tool-aware send loop,
  completion evidence builder, provider test doubles, and focused policy tests.
- Follow-up: Process-backed verification may need a later capability profile
  that includes `process_status` and `process_wait`.

## Acceptance Criteria

- Validation-only continuations expose verifier tools but no file mutation
  tools.
- A failed verifier clears stale unverified-mutation evidence while preserving
  its diagnostics.
- The following repair continuation exposes the normal tool set.
- A repair without verification returns to a verifier-only continuation.
- A successful verifier stops automatic continuation.
- Ignoring a verifier-only continuation remains bounded and blocks safely.

## Verification

```bash
tool/codex_verify.sh
```

After local tests pass, run the exact-short Markdown TOC live canary three
times with the configured local model endpoint.

## Handoff Notes

- Risks: Tool-aware context retries must preserve the same capability filter.
- Follow-up: Compare success rate and verifier-turn latency against the prior
  3/6 exact-short Markdown TOC baseline.

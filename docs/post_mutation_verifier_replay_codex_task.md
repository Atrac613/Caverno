# Deterministic Post-Mutation Verifier Replay

## Goal

Prevent a coding goal from ending with an unverified completion claim when a
model repairs files after running a verifier but does not invoke the verifier
again. Re-run the last observed verification command once after a later
mutation, using the existing tool execution and approval path.

## Background

The validation capability gate limits dedicated validation turns to verifier
tools. A weak model can still run a verifier, repair the reported failure, and
then claim success without issuing another verifier call. The evidence guard
correctly blocks that claim, but the harness has enough trusted history to
repeat the previously executed verifier deterministically.

## Scope

- Classify common test, analyze, and explicit verifier-script commands as
  verification effects.
- Retain only verifier calls that were actually dispatched by the current
  conversation.
- When the mutation generation is newer than the verification generation,
  replay the exact tool name and arguments once for that mutation generation.
- Route the replay through the normal tool dispatcher, guardrails, approval
  flow, result persistence, and diagnostic feedback.
- Distinguish a missing verifier call, a failed verifier, and a repair that
  ended without post-mutation verification in goal stop telemetry.

## Non-Goals

- Do not infer or synthesize a new command.
- Do not weaken command approval or filesystem confinement.
- Do not replay deployment, release, dependency, formatting, generation, or
  generic workspace-mutation commands.
- Do not increase the normal tool-loop or goal turn budgets.
- Do not retry the same mutation generation more than once.

## Integration Map

- `ToolCapabilityClassifier` identifies replay-eligible verification commands.
- `ChatNotifier._executeToolCalls` records dispatched verifier calls and checks
  generation state before finalization.
- The existing `_executeToolCalls` and `_dispatchToolCall` paths execute the
  replay, preserving approval and audit behavior.
- `ConversationGoalAutoContinuePolicy` remains the final safety boundary when
  replay is unavailable, denied, or unsuccessful.

## Acceptance Criteria

1. A previously executed verifier is replayed with identical tool arguments
   after a later file mutation.
2. A verifier is replayed at most once per mutation generation.
3. Commands not classified as verification are never replayed.
4. A successful replay settles the current verification generation.
5. A failed replay preserves diagnostics for the normal repair path.
6. Missing or denied replay candidates remain blocked rather than becoming a
   false success.
7. Existing approval, command guardrail, and audit paths are unchanged.

## Verification

```bash
tool/codex_verify.sh
```

After local verification, run the exact-short Markdown TOC Live LLM canary
three times and compare completion rate, verifier calls, continuation count,
and final stop reason.

# Stalled Diagnostic Repair Live Canary

## Goal

Add a dedicated Live LLM canary that proves the stalled-diagnostic repair
contract works across the complete coding loop. The canary must reproduce an
unchanged authoritative diagnostic signature without relying on model luck,
then observe a constrained repair turn and automatic verifier replay.

## Scope

- Extend the TODO fixture harness with an opt-in verifier plateau that returns
  the same synthetic diagnostic for its first two verifier attempts.
- Keep the user prompt short and unchanged from the existing TODO MVP canary.
- Add a separately gated live scenario and runner.
- Assert behavior from tool history and session-log evidence rather than from
  the final assistant text alone.

## Required Sequence

1. The model creates or edits the MVP and explicitly runs the fixture verifier.
2. The first verifier attempt returns one authoritative synthetic diagnostic.
3. A later verifier attempt returns the identical diagnostic signature and
   activates the stalled-diagnostic repair contract.
5. The repair continuation exposes file inspection and mutation tools, but no
   command execution tool.
6. The model performs a file mutation.
7. The saved verifier replays automatically and the real fixture verifier
   succeeds.

## Immediate Replay Policy

The repair contract must end its file-tool loop after the first successful
mutation batch. It must replay the saved verifier before asking the model for
another file action. A failed replay ends the repair turn without file tools so
the resulting diagnostics can drive a fresh bounded continuation. Other coding
turns retain the normal end-of-turn replay behavior.

If that immediate replay replaces the plateau signature with different
actionable diagnostics, treat the transition as one bounded repair advance even
when the raw diagnostic count grows. This exception applies only to the first
replay outcome after a constrained repair mutation; ordinary diagnostic
regressions remain no-progress outcomes.

If a constrained repair turn ends without any successful file mutation, grant
one dedicated retry with the same file-only capability boundary and an explicit
mutation-first instruction. A second no-mutation outcome must block. This retry
does not relax the diagnostic repair budget and never exposes command tools.

## Acceptance Criteria

- The live scenario is disabled unless its dedicated environment gate is set.
- The plateau diagnostic has a stable relative path, severity, code, and
  normalized message across both failed attempts.
- Verifier history includes only the exact fixture verifier command; rejected
  setup or inspection commands cannot occupy verifier attempt indexes.
- The session log contains at least one repair-contract activation with an
  identical-signature streak of at least one.
- A repair continuation request advertises only the supported file tools and
  does not advertise `local_execute_command`; later finalization requests with
  an empty tool list are not capability-advertisement samples.
- An active repair contract takes precedence over carried validation state in
  the continuation decision, prompt, and capability profile.
- Repair-request classification inspects only the latest user message, so a
  historical repair contract cannot relabel a later normal continuation.
- At least one successful mutation occurs after the second failed verifier.
- A repair turn that narrates work without mutating receives at most one
  file-only retry before blocking.
- A successful verifier call occurs after that mutation without requiring the
  model to issue another verifier command.
- The goal is not blocked, post-success mutations are absent, and independent
  fixture verification passes.
- The runner emits the standard Live LLM canary JSON and Markdown summaries.

## Verification

```bash
tool/codex_verify.sh
```

Run the live canary separately with `CAVERNO_LLM_BASE_URL`,
`CAVERNO_LLM_API_KEY`, and `CAVERNO_LLM_MODEL` configured.

# Stalled Diagnostic Repair Contract

## Goal

Help weaker coding models repair authoritative diagnostics without increasing
turn budgets or embedding fixture-specific fixes in prompts.

## Scope

- Detect a diagnostic plateau from consecutive goal evidence.
- Build a short repair contract from diagnostic paths, the latest diagnostic,
  and the current sourced execution snapshot.
- Require one concrete repair before another completion claim.
- Limit plateau repair turns to file inspection and mutation tools; verifier
  execution remains owned by deterministic post-mutation replay.
- Preserve existing approval, confinement, and goal stop policies.

## Non-Goals

- Do not invent a fix or restate fixture-specific expected output.
- Do not increase tool-loop, goal-turn, or token budgets.
- Do not suppress diagnostics or accept prose verification claims.

## Acceptance Criteria

1. A first diagnostic result uses the normal repair prompt.
2. An unchanged consecutive diagnostic result receives a compact repair
   contract containing authoritative paths and available sourced context.
3. Repair-only turns do not advertise command, network, git, or desktop tools.
4. A later mutation is verified through the existing verifier replay path.
5. Improved diagnostics clear the plateau behavior.

## Verification

```bash
tool/codex_verify.sh
```

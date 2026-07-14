# Successful Read-Result Replay

## Task

- Goal: Reuse successful `read_file` results while the active file-mutation
  generation is unchanged, including across bounded tool-loop recovery re-entry.
- User-visible behavior: Weak models that re-read an unchanged file receive the
  prior successful result without another filesystem dispatch and can converge
  with fewer tool round-trips.
- Non-goals: Caching directory listings, searches, commands, process state,
  network results, failed reads, or results across file mutations.

## Context

- Affected files or components: tool-call execution policy, ChatNotifier tool
  loop batch dispatch, Live canary summary signals, and focused tests.
- Related docs: `docs/pending_action_length_recovery_codex_task.md` and
  `docs/pending_action_length_recovery_live_canary_codex_task.md`.
- Reference implementation or pattern: Existing semantic tool-call key
  normalization and interaction-generation command ledger.
- Known quirks, compatibility rules, or release gates: The replay cache must
  survive recursive `_executeToolCalls()` recovery re-entry, but it must not
  survive a new interaction or a successful file mutation.

## Implementation Notes

- Preferred approach: Add a small domain service that keys successful reads by
  semantic arguments, normalized project path, interaction generation, and
  persisted mutation generation. Keep the cache on ChatNotifier so recovery
  re-entry shares it.
- Constraints: Strip narration-only `reason`; retain semantic paging arguments
  such as `offset` and `limit`; conservatively disable replay for batches that
  also contain a mutation.
- Generated files needed: None.
- Migration or data compatibility concerns: None; the cache is in-memory and
  interaction-scoped.

## Similar-Pattern Search

- Search terms: `read_file`, `shouldAllowRepeatedToolExecution`,
  `ToolLoopContextDigest`, `toolExecutionKey`, and `_executeToolCalls`.
- Files or modules inspected: tool-loop batch execution, duplicate recovery,
  tool execution policy, context digest, and pending-action length recovery.
- Follow-up tasks found: Consider other stable inspection tools only after
  `read_file` replay has independent Live evidence.

## Acceptance Criteria

- Required behavior: A semantically identical successful `read_file` call in
  the same interaction and mutation generation replays the prior result.
- Edge cases: Relative and absolute paths normalize to one key; `reason` does
  not affect the key; `offset` and `limit` do affect it.
- Failure paths: Failed reads are never cached, a new interaction misses, and a
  changed mutation generation misses.
- Safety expectations: A batch containing any file mutation performs real
  reads and does not populate replay entries.
- Observability: Logs and Live canary summaries count successful read replays.

## Verification

```bash
tool/codex_verify.sh --coverage
```

After deterministic verification, run the pending-action length recovery Live
canary once. If it passes, run a three-run comparison slice and record replay
count, duration, verifier outcome, and goal terminal state.

## Handoff Notes

- Summary: Added an interaction- and mutation-generation-scoped cache for
  successful `read_file` results, integrated it across recovery re-entry, and
  exposed replay counts in Live canary summaries.
- Tests run: `tool/codex_verify.sh --coverage` completed successfully with the
  full Flutter test suite.
- Coverage or low-coverage notes: The new cache service has 19/19 covered
  lines. ChatNotifier coverage exercises replay across pending-action recovery
  and rejects stale or unsafe reuse through focused unit tests.
- Risks or follow-ups: Files changed outside Caverno's mutation tools cannot
  advance the mutation generation. Interaction scoping limits exposure, but
  Live validation must confirm that replay reduces physical reads without
  hiding required refreshes. Directory-list replay remains out of scope.

## Live Validation

The dedicated pending-action length recovery canary ran three times against
`qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`.

| Report suffix | Result | Duration | Read replays | Tool calls | Read calls |
|---|---:|---:|---:|---:|---:|
| `1783997973` | passed | 309,214 ms | 1 | 29 | 13 |
| `1783998301` | passed | 218,841 ms | 2 | 21 | 10 |
| `1783998535` | passed | 224,569 ms | 1 | 18 | 8 |

All runs reported main readiness `ready`, first verifier turn `1`, a successful
verifier, a terminal success exit, no blocking after verifier success, no
failed tests, and no skipped tests. The replay signal appeared in every run,
showing that recovery re-entry reused successful reads without preventing the
fixture verifier from observing and accepting the final artifact.

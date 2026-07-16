# CLI3 Completion Audit And Contention Decision

## Task

- Goal: Close every remaining CLI3 persistence, resume, configuration, and
  ownership requirement with executable evidence, then decide from measured
  contention whether direct file leases remain sufficient.
- User-visible behavior: Default terminal runs share production state and logs
  with the GUI, isolated data roots retain their own state and logs, startup
  configuration follows the documented precedence, failed migrations retry on
  the next launch, and mixed GUI/terminal ownership remains safe under load.
- Non-goals: Standalone CLI packaging, Windows/Linux native entrypoint routing,
  terminal routine commands, a coordination daemon without evidence that one is
  needed, or changing the conversation/chat-memory schema.

## Requirement Audit

| CLI3 requirement | Current evidence | Audit result | Remaining action |
| --- | --- | --- | --- |
| Production settings and deterministic precedence | Runtime adapter resolves flags, environment, then persisted/default settings | Behavior present; direct tier-by-tier regression missing | Extract a pure resolver and test all tiers plus empty-value fallback |
| Drift conversations and chat memory | Shared bootstrap, isolated roots, migration tests, atomic memory merge | Proven | Preserve existing gates |
| Coding projects and checkpoints | Restart/resume and GUI-to-terminal tests retain project, messages, workflow, checkpoints, and provenance | Proven | Preserve existing gates |
| Routine storage | Default shared-preferences and isolated JSON repositories | Proven for composition | Keep execution commands unavailable until a per-routine lease is designed |
| Session logs | Default store is GUI-compatible, but CLI data-root injection was left as a follow-up | Incomplete | Inject a CLI-selected log store and prove default, explicit-root, and override behavior |
| Stable list/show/resume | Parser, query, packaged smoke, and cross-frontend resume tests | Proven | Preserve existing gates |
| Conversation/workspace ownership | Runtime lease lifecycle and packaged live contention evidence | Proven for correctness | Include both resources in the mixed contention soak |
| Chat-memory ownership | Authoritative refresh-and-merge under a short global lease | Proven for correctness | Include the memory resource in the mixed contention soak |
| CLI-only migration recovery | Failure cleanup and idempotence are tested independently | Evidence gap | Prove a failed first bootstrap can reopen and migrate successfully |
| Direct lock versus daemon decision | No repeatable measurement artifact | Incomplete | Add a separate-process soak, stable report schema, thresholds, and recorded decision |

## Implementation Tasks

1. Add a CLI session-log composition helper. A dedicated
   `CAVERNO_SESSION_LOG_DIR` override wins; otherwise an explicit `--data-dir`
   or `CAVERNO_HOME` owns `session_logs/` beneath that root; application-default
   runs retain the existing GUI-compatible default.
2. Extract endpoint/model/API-key precedence into one pure resolver used by the
   terminal runtime. Test flag, environment, persisted setting, built-in
   default, whitespace fallback, and secret non-exposure.
3. Add a migration retry regression that fails before setting a marker, closes
   the first database, then succeeds on the next bootstrap and preserves the
   migrated records.
4. Add `tool/cli3_contention_soak.dart`. Start separate GUI-like and
   terminal-like workers behind a shared barrier, repeatedly acquire the same
   conversation/workspace resources and the global chat-memory resource, and
   record conflicts, timeouts, owner diagnostics, latency percentiles, and
   throughput.
5. Emit schema-versioned JSON and Markdown reports. Recommend direct file
   locking only when all expected operations complete, no ownership timeout or
   invalid diagnostic occurs, and the measured p95 stays below the configured
   threshold.
6. Run the soak repeatedly, a packaged macOS CLI smoke, focused tests, and the
   full repository gate. Record measured values and mark CLI3 done only if
   every audit row has authoritative evidence.

## Contention Decision Contract

- Runtime conversation/workspace acquisition may encounter non-blocking
  conflicts, but workers must recover before their bounded operation timeout.
- Chat-memory mutations use the production retrying coordinator and must not
  time out or lose an operation.
- A conflict owner may be temporarily unavailable while metadata is being
  published, but any parsed owner must name one of the participating frontends
  and carry a valid process identifier.
- The report must not include raw data-root paths, workspace paths,
  conversation content, API keys, or lock filenames.
- A failed threshold produces `investigate_local_daemon`; it must not silently
  redefine the threshold or mark CLI3 complete.

## Acceptance Criteria

- Application-default session logs retain the existing GUI-compatible root.
- Explicit CLI data roots write session logs only beneath that root unless the
  dedicated session-log override is set.
- Runtime LLM configuration follows flags, environment, persisted settings,
  then defaults, with empty higher-priority values ignored.
- A failed first migration attempt leaves completion unset and a second attempt
  succeeds without manual cleanup.
- The contention tool uses at least two OS processes and exercises
  conversation, canonical workspace, and chat-memory resources in one run.
- JSON and Markdown reports expose configuration, operation counts, conflicts,
  timeouts, p50/p95/max latency, throughput, decision, and reasons.
- Three consecutive representative soaks pass the direct-lock threshold.
- Focused tests, a packaged CLI smoke, and `tool/codex_verify.sh` pass without
  generated-file drift or analyzer findings.
- `docs/roadmap.md` records the measured decision and changes CLI3 to `done`
  only after all preceding criteria pass.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/terminal/application/caverno_cli_session_logging_test.dart \
  --test test/features/terminal/application/caverno_cli_runtime_configuration_test.dart \
  --test test/features/chat/application/persistence/caverno_persistence_bootstrap_test.dart \
  --test test/tool/cli3_contention_soak_test.dart

dart run tool/cli3_contention_soak.dart \
  --iterations 100 \
  --hold-ms 2 \
  --out-json tmp/cli3_contention_soak/report.json \
  --out-md tmp/cli3_contention_soak/report.md
```

Repeat the representative soak three times, run the packaged macOS CLI
list/show or version smoke without opening a GUI window, then run
`tool/codex_verify.sh`.

## Handoff Notes

- Summary: Completed all four audit gaps. CLI composition now owns isolated
  session logs, runtime configuration has one tested precedence resolver,
  failed migration bootstrap retries are proven, and the mixed-resource
  contention decision is repeatable and machine-readable.
- Focused tests: The four-file completion gate passed 14 tests with no analyzer
  findings or generated-file drift. The separate-process contention test also
  passed independently after proving distinct worker process identifiers.
- Packaged smoke: A rebuilt Debug macOS executable returned version `1.3.13`
  and an empty schema-versioned conversation list from an isolated data root;
  both invocations exited successfully through the CLI entrypoint.
- Contention measurements: Three consecutive runs used two workers, 100
  iterations per worker, a 2 ms hold, a 5 second operation timeout, and a 250
  ms p95 ceiling. Every run completed 200 runtime and 200 chat-memory
  operations with zero timeout or invalid owner diagnostic. Runtime p95 values
  were 5.454/5.333/5.075 ms, chat-memory p95 values were
  6.317/4.961/4.528 ms, and throughput values were
  365.985/362.857/376.869 operations per second.
- Decision: `direct_file_locking_sufficient`. Current evidence does not justify
  a local coordination daemon. Terminal routine execution remains outside CLI3
  until a separate per-routine lease contract is designed.
- Full verification: `tool/codex_verify.sh` passed 3,394 tests with no
  generated-file drift or analyzer findings.

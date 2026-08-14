# Official Live LLM Loopback Relay

## Task

- Goal: Provide one Caverno-owned loopback method for live LLM canaries that
  need to reach an HTTP LAN endpoint from `flutter_tester` on macOS.
- User-visible behavior: Codex, Claude, and developers can wrap an existing
  canary runner with one command instead of creating and cleaning up an ad hoc
  SSH tunnel or relay.
- Non-goals: Proxying HTTPS endpoints, switching models, replacing the canary
  runners, or changing production application networking.

## Context

- Affected files or components: live-canary tooling, canary evidence metadata,
  and the shared live-canary documentation.
- Related docs: `docs/live_llm_canary_agent_runbook.md` and
  `docs/live_llm_canary_coverage.md`.
- Reference implementation or pattern: Existing runners accept
  `CAVERNO_LLM_BASE_URL`, while the shared documentation currently asks the
  operator to create an SSH local-port forward manually.
- Known quirks, compatibility rules, or release gates: macOS Local Network
  Privacy can block `flutter_tester` from connecting directly to a LAN host.
  Streaming responses must pass through without response buffering.

## Implementation Notes

- Preferred approach: Start a Caverno-owned byte-stream TCP relay on an
  ephemeral IPv4 loopback port, rewrite the child process environment, and
  terminate the relay when the child exits or the wrapper receives a signal.
- Constraints: Accept only `http` base URLs in the first slice, bind only to
  `127.0.0.1`, preserve the child exit status, avoid fixed ports, and record
  both the origin and effective URLs in canary evidence.
- Generated files needed: None.
- Migration or data compatibility concerns: Keep the existing `baseUrl` field
  readable by report consumers while adding explicit relay metadata.

## Similar-Pattern Search

- Search terms: `loopback relay`, `loopback tunnel`, `ssh -N -L`,
  `CAVERNO_LLM_BASE_URL`, and `live canary`.
- Files or modules inspected: `docs/live_llm_canary_coverage.md`,
  `tool/run_live_llm_benchmark_canary.sh`,
  `tool/run_chat_live_llm_canary.sh`, `AGENTS.md`, `CLAUDE.md`, `README.md`, and
  the live-canary runner inventory.
- Follow-up tasks found: Migrate additional canary runners only when they need
  relay-aware evidence; do not bulk-edit the full runner inventory.

## Acceptance Criteria

- Required behavior: Allocate a collision-free loopback port, forward bytes in
  both directions, rewrite `CAVERNO_LLM_BASE_URL` only for the wrapped command,
  expose the origin/effective URLs and relay mode, and preserve its exit code.
- Edge cases: Concurrent wrappers use different ports, and URL paths and query
  strings are preserved.
- Failure paths: Invalid or unsupported URLs fail before the child runs; relay
  startup failure is reported; signal and normal-exit cleanup stop the relay.
- Accessibility, localization, or platform expectations: Tool output and
  documentation remain English. The relay is intended for macOS but uses
  portable Dart socket APIs.

## Verification

```bash
tool/codex_verify.sh --test test/tool/live_llm_loopback_relay_test.dart
tool/codex_verify.sh --test test/tool/live_llm_canary_summary_test.dart
tool/codex_verify.sh --test test/tool/run_live_llm_benchmark_canary_test.dart
```

## Handoff Notes

- Summary: Added the managed relay and wrapper, relay-aware summary schema v4,
  representative Chat and benchmark runner integration, a canonical agent
  runbook, discoverability links for Codex and Claude, and self-documenting
  wrapper help.
- Tests run: Focused relay, summary, benchmark runner, and Foundation Models
  runner tests; agent-runbook link and help checks; Flutter analysis; bounded
  live streaming benchmark through the managed relay.
- Coverage or low-coverage notes: Deterministic tests cover byte streaming,
  path/query preservation, concurrent port allocation, child exit status, and
  unsupported HTTPS rejection. The resumed real LAN gate passed on 2026-08-14
  for the streaming production path; broader tool, vision, and coding probes
  were intentionally outside this bounded run.
- Risks or follow-ups: HTTPS requires a separate design because TLS hostname
  verification must not be silently weakened.

## Live Verification

The bounded live gate ran with:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision \
CAVERNO_BENCHMARK_CANARY_NAME=official_loopback_streaming_live_canary \
CAVERNO_BENCHMARK_CANARY_PROBE_IDS=streaming_response \
CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS=streaming_response \
CAVERNO_BENCHMARK_CANARY_MIN_POINTS=50 \
tool/with_live_llm_loopback.sh -- tool/run_live_llm_benchmark_canary.sh
```

- Artifact directory:
  `build/integration_test_reports/official_loopback_streaming_live_canary_1786672794/`
- Result: passed, main readiness `ready`, and benchmark points `50/50`
  attempted.
- Route evidence: origin `http://192.168.100.241:1234/v1`, effective
  `http://127.0.0.1:63132/v1`, and relay mode `loopbackTcp`.
- Streaming evidence: exact sequence `40/40`, 110 chunks, TTFT 1,257 ms,
  total 1,283 ms, 111 completion tokens, and finish reason `stop`.
- Delivery classification: likely buffered, so the report correctly withheld
  decode-rate claims despite the high chunk count.
- Cleanup evidence: no listener remained on port 63132 after the wrapper exited.

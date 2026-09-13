# Codex Developer Efficiency Roadmap

Scope, acceptance criteria, and dated evidence for this track.
[Cross-track priorities](roadmap.md#active-focus) remain in the main
roadmap; dated investigation notes below preserve the implementation history.

## Codex Developer Efficiency Track

This track controls output produced by repository development commands and
consumed by external coding agents. It does not change Caverno's product prompt
or tool-result behavior; LL34 continues to own the in-app summary-first policy.
The measurement baseline and prioritization are recorded in
`docs/codex_output_efficiency_investigation_2026-09-04.md`.

### DX1: Flutter Test Output Summarization

Status: **done**.

- Scope: route Flutter tests through the JSON reporter, keep complete JSON and
  stdout logs, and print only a success verdict or bounded failure evidence.
- Acceptance: preserve the test exit status, surface load/compile failures and
  incomplete runs, retain a raw escape hatch, and make the quiet path the
  `tool/codex_verify.sh` default.
- Evidence: PR #188 is present in current history; the 2026-09-04 focused run
  passed 334 tests and reduced default model-visible test output from 844,725
  to 137 bytes. Five summarizer regression tests passed.
- Follow-up completed: `--verbose` now streams the expanded reporter while
  retaining the complete stdout artifact. Its streaming and default-capture
  contracts are covered by repository-side regression tests.

### DX2: Summary-First Repository Discovery

Status: **done**.

- Scope: add `tool/codex_rg.sh` for discovery searches only. Report match and
  file counts, a deterministic bounded hit set, explicit truncation, and the
  complete artifact path; retain `--raw` for exact output.
- Acceptance: preserve `rg` exit codes for matches, no matches, and errors;
  cover invalid patterns, path and binary handling, result limits, and complete
  artifact retention; measure output characters and raw follow-up frequency.
- Promotion gate: diagnosis completeness must remain intact. The wrapper must
  not replace targeted raw searches used for exact or security-sensitive review.
- Evidence: 19 repository-side tests cover the wrapper, shared output helper,
  selected scripts, and the focused verification contract.
  A 3,241-line repository search produced 1,886 visible bytes
  instead of 367,396 raw bytes, a 99.49% reduction, while retaining a
  1,341,927-byte complete JSON artifact. The `--raw` path is tested; future
  agent sessions should be sampled for raw follow-up frequency before changing
  the default limits. Non-match output modes fail closed with a `--raw`
  diagnostic, unexpected non-JSON output fails closed, and saved evidence uses
  owner-only permissions.

### DX3: Log-First Long-Running Commands

Status: **done**.

- Scope: add an agent-oriented quiet path to selected release, build, and live
  canary entrypoints that currently stream complete output.
- Acceptance: preserve the full log and exact exit status, emit bounded stage
  heartbeats, and show failure markers plus a diagnostic tail on failure. Keep
  human-operated raw output available.
- Implemented entrypoints: `tool/release_ios_macos.sh`,
  `tool/publish_macos_sparkle_release.sh`,
  `tool/run_turn_steering_live_canary.sh`, and
  `tool/run_pro_reasoning_live_canary.sh`.
- Boundary: do not begin with a generic arbitrary-command wrapper; preserve the
  release scripts' existing success/failure interpretation first.
- Evidence: the repository-side integration suite covers quiet success,
  failure status and diagnostic tails, heartbeats, raw streaming, release and
  appcast logs, and both live-canary log/snapshot paths. Existing Dart script
  contracts pass eight focused tests. Quiet execution handles SIGINT/SIGTERM,
  reaps its command and heartbeat processes, and creates logs with owner-only
  permissions.

### DX4: Progressive Source And Git Inspection

Status: **done**.

- Scope: locate files and symbols before bounded source reads, then begin Git
  review with stats and paths before inspecting material diffs directly.
- Acceptance: reduce broad reads without hiding source or diff evidence needed
  for correctness and security review.
- Evidence: the 10-session baseline found search, polling, and source reads at
  76.67% of recorded output. `AGENTS.md` and `CLAUDE.md` now require bounded
  discovery, 200-300-line source regions, stat/path-first Git review, and direct
  inspection of every material diff. No lossy source or diff wrapper was added.

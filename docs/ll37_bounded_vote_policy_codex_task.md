# LL37 Bounded Vote Policy Slice

## Task

- Goal: Replace LL37's one-record-per-candidate stop condition with a bounded,
  deterministic vote policy that can accumulate serialized idle-window votes
  without duplicate requests or unbounded verifier work.
- User-visible behavior: Advanced idle-maintenance diagnostics show each
  persisted vote's stable identity and the aggregate state for its candidate.
- Non-goals: Parallel requests, multiple verifier routes, automatic retries,
  candidate mutation, continuation nudges, strategist passes, or interactive
  verification.

## Architecture

- Keep one LL18 `objective_verify` invocation bounded to one candidate and one
  tool-free request. Additional votes occur only in later idle windows.
- Identify a vote deterministically from the candidate ID, exact measured
  verifier profile key, accepted fidelity-report SHA-256, and one-based vote
  index. The same logical slot must retain the same vote ID across restarts.
- Cap each candidate/profile/report cohort at three votes. Two votes with the
  same blocking classification converge early.
- Treat two consecutive `unverifiable` votes with the same normalized error or
  finding fingerprint as a stall and stop before the cap. At the cap, a cohort
  without a two-vote majority terminates as `unverifiable`.
- Keep different verifier profiles and fidelity-report identities in separate
  cohorts so evidence from different measured routes is never combined.
- Upgrade the persisted projection to schema v2 with `voteId` and `voteIndex`.
  Read schema-v1 records as deterministic first votes and rewrite them as v2 on
  the next successful store update.
- Retain at most 50 votes newest-first. Deduplicate only the same vote ID, not
  all votes for a candidate.

## Acceptance Criteria

- Vote identity is stable for equivalent normalized inputs and changes when
  the candidate, route, report, or index changes.
- A one-vote cohort remains pending; any two matching classifications converge;
  two identical consecutive unverifiable gaps stall; a three-way split caps as
  unverifiable.
- No candidate/profile/report cohort can issue more than three requests, and a
  terminal cohort is excluded before another verifier request.
- A repeated stage invocation or app restart advances to the next unused vote
  slot without overwriting earlier votes.
- Cancellation and persistence failures retain the existing fail-closed
  behavior. Skipped and cancelled reports are not votes.
- Schema-v1 history remains readable as vote one, malformed neighbors remain
  isolated, and retention remains bounded.
- Diagnostics expose vote identity, index/cap, aggregate status, and aggregate
  blocking outcome without exposing changed-file contents or raw model data.
- Interactive chat code remains unable to import the LL37 panel or vote policy.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_objective_vote_policy_test.dart \
  test/features/maintenance/data/ll37_objective_verdict_repository_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  test/features/maintenance/presentation/pages/idle_maintenance_debug_page_test.dart
fvm flutter analyze
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Implemented immutable vote IDs, schema-v1-to-v2 migration, a
  three-vote cohort cap, two-vote blocking-classification convergence,
  repeated-unverifiable stall detection, deterministic cross-restart slot
  advancement, and aggregate diagnostics. Each idle window still issues at
  most one tool-free request and persistence failures remain stage failures.
- Tests run: 43 focused LL37 domain, persistence, provider, and maintenance
  tests passed; 392 maintenance, file-ratchet, and translation tests passed;
  `fvm flutter analyze` passed with no issues; `tool/codex_verify.sh` passed
  7,334 Flutter tests and 10 notification-relay tests.
- Risks: Repeated votes currently use one exact measured verifier route and are
  serialized across idle windows. They provide bounded repeated observations,
  not route-independent N-way evidence, and diagnostics make the shared cohort
  identity explicit.
- Follow-up: Measure a second verifier route against the existing consented
  fidelity corpus before adding it to the registry and deterministic vote-route
  assignment. Parallel fan-out, anti-ratchet continuation rounds, and reviewed
  nudges remain later slices.

# LL37 Idle Panel Slice 2

## Task

- Goal: Enable the bounded LL37 idle verifier only for the exact route that
  passed the fidelity gate, and connect one read-only unattended evidence
  source.
- User-visible behavior: An LL18 maintenance run can audit one eligible,
  mechanically green LL13 worktree-agent result when the active verifier route
  matches the accepted LL37 fidelity profile. Other routes and incomplete task
  records remain skipped.
- Non-goals: A persistent verdict store, multiple votes, majority aggregation,
  retries, continuation nudges, worktree mutation, Routine history adaptation,
  or interactive verification.

## Architecture

- Reconstruct the accepted fidelity profile from the schema-v3 report identity
  and SHA-256 recorded on 2026-08-13. Match provider, normalized base URL, and
  model exactly; a route mismatch is ineligible.
- Recheck the active route immediately before the request so a settings change
  between candidate selection and completion cannot send work to an unmeasured
  verifier.
- Load LL13 task history directly through its SharedPreferences repository.
  Do not instantiate the task registry notifier, recover tasks, write task
  history, inspect worktrees, or run verification commands.
- Admit only completed, `verifiedGreen` tasks with a declared objective,
  explicit objective acceptance criteria, a verification command, a non-empty
  verification summary, and complete changed-file evidence whose paths, sizes,
  and SHA-256 hashes are consistent. Legacy tasks without explicit criteria
  remain ineligible because LL34 settlement cannot be inferred safely.
- Extend `/agent` with a single `--accept CRITERION` segment before `--verify`
  so future LL13 records can declare the objective condition that the mechanical
  command does not settle. Preserve the result and verification summaries as
  implementation evidence.
- Keep verdict reports run-local. Retain only attempted candidate IDs in an
  in-memory session ledger so repeated LL18 windows do not spend another vote
  on the same task before a reviewable verdict store exists.

## Acceptance Criteria

- The accepted report route is eligible with equivalent trailing-slash URL
  normalization; a provider, endpoint, or model change fails closed.
- LL13 tasks that lack explicit acceptance criteria, are failed, mechanically
  red, truncated, missing evidence, path-unsafe, size-inconsistent, or
  hash-inconsistent do not become candidates.
- Candidate ordering is deterministic, duplicate task IDs collapse to one
  candidate, and one maintenance stage still issues at most one request.
- Reading candidates does not mutate LL13 task persistence or touch a worktree.
- The request contains no tools, uses the route-matched model, and is accounted
  as evaluation usage.
- Interactive chat code still does not reference the LL37 panel.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_verifier_fidelity_profile_test.dart \
  test/features/maintenance/domain/services/ll37_worktree_agent_candidate_adapter_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart
tool/codex_verify.sh
```

## Implementation Outcome

- `Ll37VerifierFidelityRegistry` reconstructs the accepted schema-v3 evidence
  identity, including its report SHA-256, thresholds, provider, normalized base
  URL, and model. Any active-route mismatch disables the stage.
- `Ll37WorktreeAgentCandidateAdapter` reads persisted LL13 records without
  recovering tasks or opening worktrees. It admits only completed,
  mechanically green records with explicit criteria and internally consistent
  bounded file evidence.
- LL13 task persistence now carries `objectiveAcceptanceCriteria`. The `/agent`
  command accepts one `--accept CRITERION` segment and requires `--verify` when
  that segment is present. Legacy records default to no criteria and remain
  ineligible.
- `Ll37ObjectiveAttemptLedger` suppresses duplicate votes for the same
  candidate during one application session. Verdicts remain run-local and are
  not persisted.
- Production composition uses the matched profile model, sends no tools,
  accounts the request as evaluation usage, and rechecks the active route
  immediately before sending.

## Verification Outcome

- Focused LL37 and LL13 suites passed: 90 tests.
- Translation and catalog regressions passed: 58 tests.
- The first full gate exposed only two file-size ratchet failures caused by the
  new `/agent` parsing lines. The parser and title derivation were extracted to
  `worktree_agent_command_args.dart`; the coordinator ratchet was lowered from
  364 to 331 lines and the catalog returned to its 100-line ceiling.
- The extraction regression group passed 297 tests, and `fvm flutter analyze`
  reported no issues.
- The final `tool/codex_verify.sh` run passed all generated-file checks,
  analyzers, internal package suites, 7,311 root tests, and 10 notification
  relay tests.

# LL37 Unattended Source Adapters

## Task

- Goal: Admit complete Routine and retry-until-green objective evidence into
  the idle-only LL37 candidate source alongside completed LL13 tasks.
- User-visible behavior: Eligible unattended results can appear in the existing
  LL37 verdict history after the idle panel evaluates them. Merely loading
  source history remains read-only.
- Non-goals: Changing an existing source result, automatically creating or
  running a repair task, parallel verifier fan-out, strategist passes, or
  importing LL37 into interactive chat.

## Source Contracts

- A Routine candidate comes only from a scheduled, completed run carrying a
  frozen objective contract, a successful mechanical-verification record, and
  complete changed-file contents captured by the producer.
- A retry-until-green candidate comes only from a bounded report with a green
  winning round, no residue risk, and the same complete frozen evidence.
- Both adapters reject blank or duplicate identities, attended sources,
  incomplete criteria, unsafe or duplicate paths, truncated files, mismatched
  byte sizes or hashes, and empty implementation evidence.
- Candidate IDs are namespaced by surface and immutable source identity.
- Mechanical verification is eligibility evidence, not an LL34 objective
  verdict. The LL37 panel still audits acceptance criteria not covered by that
  command.

## Integration Boundary

- The maintenance candidate provider reads Routine history and the persisted
  retry-until-green report store directly. It must not instantiate either
  execution notifier, run recovery, inspect a workspace, invoke a model, or
  write persistence.
- Existing LL13 ordering remains stable. The merged source is deterministically
  ordered and duplicate candidate IDs fail closed.
- Legacy Routine runs and retry reports without the new evidence envelope
  remain readable but are ineligible.

## Acceptance Criteria

- One valid candidate from each new surface maps objective, ordered criteria,
  plan, changed files, and implementation evidence exactly.
- Every incomplete, unsafe, mechanically non-green, non-terminal, attended, or
  residue-risk source is omitted.
- JSON round trips preserve evidence and legacy JSON still decodes.
- Loading all three production sources has no execution or persistence side
  effect.
- Interactive chat remains structurally unable to import the LL37 panel or
  candidate adapters.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_routine_candidate_adapter_test.dart \
  test/features/maintenance/domain/services/ll37_retry_until_green_candidate_adapter_test.dart \
  test/features/maintenance/presentation/providers/maintenance_ll37_candidate_source_provider_test.dart \
  test/features/maintenance/presentation/providers/maintenance_stages_test.dart \
  test/features/routines/domain/entities/routine_test.dart \
  test/features/chat/domain/services/retry_until_green_coordinator_test.dart \
  test/widget_test.dart
fvm flutter analyze
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added legacy-compatible frozen evidence envelopes, fail-closed pure
  adapters for both unattended surfaces, a bounded retry-report repository,
  and a read-only three-surface maintenance source. Scheduled Routines now
  produce the complete envelope, while the explicit LL7 retry preset rolls
  back failed candidates and persists the green winner report.
- Producer safety: Verification rejects shell control operators, changed files
  must remain inside the resolved workspace, contents are bounded and hashed,
  and missing retry workspace tools produce a failed run rather than a silent
  single-run fallback.
- Focused tests: 100 passed across producer capture, scheduled execution,
  retry coordination and rollback, JSON compatibility, adapters, three-source
  composition, idle-stage isolation, and interactive-chat structural
  isolation. `fvm flutter analyze` reported no issues.
- Full gate: `tool/codex_verify.sh` passed 7,371 Flutter/Dart tests and 10
  notification-relay tests, with analyzers and generated-file checks clean.
- Follow-up boundary: LL37 is complete. Parallel verifier fan-out, automatic
  repair execution/retries, and strategist passes remain separately scoped
  enhancements. Legacy and incomplete runs remain safely excluded.

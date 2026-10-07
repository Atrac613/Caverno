# F5 Goal-Update Fidelity Diagnostic Probe Extraction

## Task

- Goal: isolate exact goal-completion tool-call scoring.
- User-visible behavior: preserve exact JSON boolean validation, failure details,
  tool-call names, previews, usage and request/validation metadata.
- Non-goals: production goal updates, schema changes, transport, capability
  weights, release gates or RC1 device verification.

## Context

- Base: `c780e2f24`, the locally committed thinking-control extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- This diagnostic makes one completion and never executes a returned tool call.
  Production `GoalUpdateInput` validation already owns schema error messages.

## Implementation Notes

- Move scoring and prompt into `LiveLlmGoalUpdateFidelityProbe` behind completion
  and request-metadata ports.
- Keep tool-definition construction, model/temperature/512-token settings,
  thinking observation, provider/selection policy, metadata derived from
  transport overrides, exceptions, elapsed time and publication in the service.
- Accept exactly one `update_goal` call with only `completed: true`. Valid
  progress/blocker fields still fail this narrower diagnostic contract.
- Validate arguments only for a single correctly named call. Preserve all
  observed names and raw JSON arguments on other failures.
- Compute request metadata after completion, then overlay validation evidence.
  Keep strict tool choice, schema and thinking-override evidence unchanged.
- No tool execution port, generated entities, dependencies or persisted changes.

## Acceptance Criteria

- Preserve prompt bytes, request settings, schema metadata and report lifecycle.
- Cover exact/invalid/schema-valid-nonexact arguments, zero/multiple/wrong tool
  calls, textual tool calls, preview bounds and both port failures.
- Lower the service budget and add a module budget.
- Rollback: restore scoring/prompt from `c780e2f24`, remove module/bindings and
  restore the budget; retain contract tests.

## Verification

Three service contracts passed before extraction, including two new request,
publication and request-error contracts:

```bash
CAVERNO_TEST_REPORT_DIR=build/test_reports/f5_goal_fidelity_baseline \
  tool/flutter_test_quiet.sh \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --name update_goal
```

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_goal_update_fidelity_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Logs and coverage remain ignored.

## Implementation Evidence

- Service: 2,437 -> 2,397 lines. Independent module: 68 lines.
- Normalized scoring matches the committed original after explicit probe-ID and
  request-metadata port substitutions.
- Twenty-two isolated tests cover exact argument fidelity, validation branches,
  wrong/multiple calls, textual parsing, evidence and propagated port failures.
- The focused gate passed 170 tests across six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 23/23 executable lines covered (100%). Service: 628/730 (86.03%)
  in this focused run; this is not whole-suite coverage.
- Fourteen affected size checks passed, including both changed budgets.
- Formatting, diff whitespace and changed documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Thinking-control is locally committed
as `c780e2f24`. This goal-update fidelity slice remains uncommitted. No main
integration, push, full Flutter-suite, live-model or signed-device result is claimed.

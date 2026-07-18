# Workflow Tool Result Failure Detector Extraction

## Task

- Goal: extract generic tool-result failure classification from
  `WorkflowTaskRunCoordinator` into a pure domain service.
- User-visible behavior: saved workflow recovery retains the same failure
  precedence, recovery prompts, status transitions, and continuation behavior.
- Non-goals: changing recovery ordering, prompt content, workflow status,
  validation inference, tool execution, completion promotion, or retry limits.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
  - a new
    `lib/features/chat/domain/services/workflow_tool_result_failure_detector.dart`
  - focused detector, coordinator, saved-workflow recovery, and size tests
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference pattern: completed pure policy slices move deterministic decisions
  behind direct tests while the coordinator retains state and side effects.
- Known compatibility rules:
  - blank tool results are ignored;
  - JSON decoding is attempted only when normalized content starts with `{`;
  - malformed JSON falls through to raw-text markers without throwing;
  - non-zero numeric `exit_code`, false `success` or `isSuccess`, and non-empty
    `error` or `errorMessage` fields are failures;
  - command output guardrail issues remain failures;
  - existing case-insensitive raw failure markers retain exact matching and run
    after structured parsing, so serialized empty `error` and `errorMessage`
    fields remain failures through their raw markers;
  - one failing result makes the whole batch fail;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. add direct tests for every structured and raw-text failure class plus
     malformed and benign inputs;
  2. move the existing loop unchanged into
     `WorkflowToolResultFailureDetector`;
  3. replace all coordinator calls with the new service;
  4. remove the coordinator's JSON dependency if no longer used;
  5. add exact non-increasing line-count ratchets for both files.
- Constraints: the detector may depend on `ToolResultInfo` and the existing
  coding command output guardrail, but not on Flutter, Riverpod, conversations,
  workflow state, prompts, providers, or notifier classes.
- Generated files needed: none.
- Migration or data compatibility concerns: none; tool results remain transient
  and are not rewritten.

## Similar-Pattern Search

- Search terms: `_toolResultsContainFailure`, `exit_code`, `isSuccess`,
  `errorMessage`, `no matching tool available`, and
  `commandResultReportsOutputIssue`.
- Files or modules inspected: `workflow_task_run_coordinator.dart`,
  `conversation_plan_execution_guardrails.dart`,
  `coding_command_output_guardrail_service.dart`, coordinator tests, and saved
  workflow recovery tests.
- Follow-up tasks found: recovery route selection and completion evidence remain
  separate state-machine contracts. Do not include them here.

## Acceptance Criteria

- Required behavior:
  - all 12 coordinator call sites use one shared failure detector;
  - structured, command-output, and raw-text failure results remain failures;
  - blank, malformed, and benign results retain current behavior;
  - existing saved-workflow recovery precedence tests remain green;
  - the detector has no Flutter, provider, or workflow-state dependency;
  - both source files have non-increasing line-count ratchets.
- Edge cases: whitespace, mixed-case text, malformed JSON, zero and non-zero
  numeric exits, false boolean flags, empty error fields, multiple results, and
  a failure after benign results.
- Failure paths: arbitrary result text returns a boolean without throwing.
- Accessibility, localization, or platform expectations: no UI, copy,
  localization, accessibility, or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/services/workflow_tool_result_failure_detector_test.dart \
  --test test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart \
  --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `WorkflowToolResultFailureDetector` now owns structured JSON,
  command-output, and raw-text failure classification for all 12 coordinator
  call sites. `workflow_task_run_coordinator.dart` retains recovery ordering and
  state mutation and fell from 2,442 to 2,402 lines; the pure detector is
  ratcheted at 54 lines.
- Tests run: the focused gate passed 95 selected Flutter tests and 13 internal
  package tests. The full gate passed analysis, 3,898 Flutter tests, and 13
  internal package tests.
- Coverage or low-coverage notes: full line coverage rose to 74.98%
  (53,359/71,167). The detector reached 95.65% (22/23), the remaining
  coordinator reached 60.16% (450/748), and their combined coverage reached
  61.22% (472/771). The pre-extraction coordinator snapshot was 60.94%
  (465/763), and the selected private detector region started at 100.00%
  coverage (22/22).
- Risks or follow-ups: keep recovery route selection, prompts, status mutation,
  and completion evidence out of this extraction. Require a separate lifecycle
  contract before moving another coordinator concern.

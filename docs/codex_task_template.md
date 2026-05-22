# Codex Task Template

Use this template when asking Codex to implement, debug, refactor, review, or
investigate non-trivial Caverno work. Keep the task small enough for one focused
review pass. Split broad requests into follow-up tasks when the scope crosses
multiple unrelated components.

## Task

- Goal:
- User-visible behavior:
- Non-goals:

## Context

- Affected files or components:
- Related docs:
- Reference implementation or pattern:
- Known quirks, compatibility rules, or release gates:

## Implementation Notes

- Preferred approach:
- Constraints:
- Generated files needed:
- Migration or data compatibility concerns:

## Similar-Pattern Search

Before finishing a bug fix or migration, check whether the same pattern appears
elsewhere.

- Search terms:
- Files or modules inspected:
- Follow-up tasks found:

## Acceptance Criteria

- Required behavior:
- Edge cases:
- Failure paths:
- Accessibility, localization, or platform expectations:

## Verification

Use the smallest command set that proves the change.

```bash
tool/codex_verify.sh
```

For coverage-sensitive work:

```bash
tool/codex_verify.sh --coverage
```

For focused tests:

```bash
tool/codex_verify.sh --test test/path/to_test.dart
```

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:

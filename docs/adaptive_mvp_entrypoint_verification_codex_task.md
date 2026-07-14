# Adaptive MVP Entrypoint Verification

## Task

- Goal: Let docs-driven Dart CLI MVP canaries verify the single entrypoint the
  model actually created instead of requiring an undocumented canonical path.
- User-visible behavior: Short prompts can produce one runnable Dart file under
  `bin/` and proceed directly to behavioral verification without an artificial
  missing-path, duplicate-entrypoint, and deletion cycle.
- Non-goals: Changing production Coding Mode, accepting multiple ambiguous CLI
  entrypoints, changing verifier commands, or relaxing behavioral acceptance
  criteria.

## Context

- Affected files or components: Shared Dart CLI canary support, the TODO and
  derived MVP verifier services, focused tool tests, and Live canary coverage
  documentation.
- Related docs: `docs/coding_mvp_fixtures/README.md`,
  `docs/structured_execution_deferral_recovery_codex_task.md`, and
  `docs/live_llm_canary_coverage.md`.
- Reference implementation or pattern: The existing fixed entrypoint checks and
  root-relative diagnostics in the TODO fixture canary.
- Known quirks, compatibility rules, or release gates: The detailed controlled
  TODO prompt explicitly requires `bin/todo_cli.dart` and must keep fixed-path
  behavior. Short docs-driven CLI prompts do not specify a filename.

## Implementation Notes

- Preferred approach: Extract a pure resolver with fixed and single-under-bin
  policies. Keep fixed behavior as the default for existing unit scenarios and
  opt short-prompt Live fixtures into adaptive resolution.
- Constraints: Resolve only direct `bin/*.dart` files, accept exactly one in
  adaptive mode, and return repairable root-relative diagnostics for zero or
  multiple candidates. Do not choose arbitrarily among multiple candidates.
- Generated files needed: None.
- Migration or data compatibility concerns: None; this is test-harness-only.

## Similar-Pattern Search

- Search terms: `unexpected_entrypoint`, `bin/todo_cli.dart`,
  `bin/word_frequency.dart`, `bin/expense_tracker.dart`, and
  `bin/markdown_toc.dart`.
- Files or modules inspected: All four CLI MVP verifier implementations, their
  wrapper tests, the fixture corpus, and the latest three TODO minimal-prompt
  session logs.
- Follow-up tasks found: The URL-shortener fixture is an HTTP service and should
  use a separate service-launch discovery design if automated later.

## Acceptance Criteria

- Required behavior: Adaptive mode accepts one Dart file directly under `bin/`
  regardless of its filename and uses it for every behavioral verifier command.
- Edge cases: Fixed mode preserves the canonical path and rejects extra Dart
  entrypoints; adaptive mode reports zero candidates as missing and multiple
  candidates as ambiguous.
- Failure paths: Diagnostics identify repairable workspace-relative paths and
  never expose deleted verification-copy paths.
- Accessibility, localization, or platform expectations: No UI or platform
  behavior changes.

## Verification

```bash
tool/codex_verify.sh --coverage
```

After deterministic verification, run the TODO minimal-prompt Live canary three
times. Require 3/3 ready results with no `todo_cli_missing` followed by
`todo_cli_unexpected_entrypoint`, and no duplicate entrypoint creation/deletion.

## Handoff Notes

- Summary: Added a reusable fixed/adaptive Dart CLI entrypoint resolver and
  opted the short-prompt TODO, word-frequency, expense-tracker, and Markdown
  TOC canaries into single-entrypoint discovery. The controlled TODO canary
  keeps its fixed `bin/todo_cli.dart` contract.
- Tests run: `tool/codex_verify.sh --coverage` passed 3,153 tests. Focused
  resolver, fixture, and wrapper coverage passed 25 tests with 9 environment-
  gated Live tests skipped.
- Coverage or low-coverage notes: Repository line coverage is 70.24%
  (48,098/68,472). Flutter LCOV excludes the harness-only `tool/` resolver;
  its five focused tests cover fixed, adaptive, missing, unexpected, ambiguous,
  and unsafe-path behavior.
- Live evidence: Three consecutive post-fix runs on `qwen3.6-27b-vision` were
  ready. Each created only `bin/todo.dart`; entrypoint missing, unexpected, and
  ambiguity diagnostics were all 0, with no duplicate creation or deletion.
  Summary run ids: `1784009123`, `1784009257`, and `1784009382`.
- Risks or follow-ups: HTTP-service fixtures need a separate launch discovery
  design. Adaptive CLI resolution intentionally rejects multiple direct Dart
  files instead of guessing which one to execute.

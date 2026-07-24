# Project-Scoped Tool Argument Resolver Extraction

## Task

- Goal: Move project-scoped tool argument normalization out of
  `ChatNotifier` into an independently tested data-layer resolver.
- User-visible behavior: None. Tool paths, aliases, command normalization, and
  active project/worktree scoping remain unchanged.
- Non-goals: Changing tool schemas, filesystem containment, approval policy,
  command execution, or project selection.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart`
  - focused resolver and line-count ratchet tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 1
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference pattern:
  - focused data-layer helpers beside `filesystem_tools.dart`
  - thin notifier delegation with constructor-free static policy methods
- Known release gate:
  - both the primary `chat_notifier.dart` line budget and its declared-part
    aggregate must decrease

## Implementation Notes

- Preserve lazy active-project lookup so unrelated tools do not touch project
  state.
- Preserve the original input map for unknown tools.
- Keep the existing notifier test harnesses as thin delegates.
- Do not create another `part` file because it would not reduce the aggregate
  library ratchet.
- No generated files or data migration are required.

## Similar-Pattern Search

- Search terms:
  - `_resolveProjectScopedArguments`
  - `_normalizeWriteFileArgumentAliases`
  - `FilesystemTools.resolvePath`
  - `LocalShellTools.normalizeCommand`
- Files or modules inspected:
  - `chat_notifier.dart`
  - `planning_tool_policy.dart`
  - `tool_call_execution_policy.dart`
  - `filesystem_tools.dart`
  - `local_shell_tools.dart`
- Follow-up tasks found:
  - Broader tool-loop request preparation remains a separate refactor slice.

## Acceptance Criteria

- Every currently scoped tool keeps the same resolved argument shape.
- Missing read-only paths still default to the active project root or `.`.
- `contents` remains a fallback alias for `write_file.content`.
- Local command control tokens are stripped exactly as before.
- Unknown tools return the original argument map without loading project state.
- Focused tests and both ChatNotifier ratchets pass with lower ceilings.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/project_scoped_tool_argument_resolver_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

## Handoff Notes

- Summary: Extracted project-scoped path, alias, and command normalization into
  `ProjectScopedToolArgumentResolver`, leaving thin `ChatNotifier` delegates.
  The primary file fell from 9,507 to 9,378 lines and the same-library
  aggregate fell from 23,147 to 23,018 lines.
- Tests run: The focused verifier passed analysis and 400 root tests. The
  repository-wide `tool/codex_verify.sh --no-codegen` gate passed analysis, all
  internal-package suites, and 4,022 root tests; code generation was skipped
  because this slice changes no generated entities.
- Coverage or low-coverage notes: The resolver requires direct branch coverage;
  seven direct tests cover its scoped branches, while the existing notifier
  tests remain integration tripwires.
- Risks or follow-ups: Do not widen this slice into tool dispatch or filesystem
  policy changes.

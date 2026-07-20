# Component Packaging Foundation

## Task

- Goal: Establish a scalable internal-package foundation and prove it by
  extracting the shared LLM content parser into a pure-Dart package.
- User-visible behavior: None. Chat rendering, tool-call parsing, routine
  execution, diagnostics, and streaming recovery must preserve their existing
  behavior.
- Non-goals:
  - Do not package Flutter pages, Riverpod providers, persistence adapters, or
    application composition in this slice.
  - Do not implement a remote component catalog, marketplace, bundle installer,
    or user-created Tools runtime.
  - Do not permit runtime-downloaded Dart, shell, JavaScript, native, or other
    executable code.
  - Do not extract tool, LLM, workflow, MCP, or terminal contracts yet.

## Context

- Affected files or components:
  - Root and internal-package `pubspec.yaml` files
  - `packages/caverno_execution_runtime`
  - `lib/core/utils/content_parser.dart` and its consumers
  - `test/core/utils/content_parser_test.dart`
  - `test/quality/package_boundary_test.dart`
  - `tool/codex_verify.sh`
- Related docs:
  - `docs/component_packaging_architecture.md`
  - `docs/large_file_refactor_plan.md`
  - `docs/local_llm_agent_roadmap.md`
  - `docs/tools_mvp_roadmap.md`
- Reference implementation or pattern:
  - `packages/caverno_execution_runtime` is the existing one-way pure-Dart
    package boundary.
  - GitHub Spec Kit separates one distribution, internal code modules, and
    manifest-driven content packages instead of publishing every component as
    an independent code distribution.
- Known quirks, compatibility rules, or release gates:
  - Pub workspaces require Dart 3.6 or later. Keep explicit workspace paths so
    the repository remains compatible with its current `^3.10.8` SDK
    constraint; workspace glob syntax requires Dart 3.11 or later.
  - A workspace has one root lockfile and package configuration. Package-local
    dependency resolution must not be reintroduced.
  - `ContentParser` is a compatibility surface for multiple local-model tool
    call formats and incomplete streaming tags.

## Implementation Notes

- Preferred approach:
  1. Document the component taxonomy, dependency graph, security boundary, and
     migration criteria.
  2. Adopt an explicitly enumerated Pub workspace for the root application and
     internal packages.
  3. Replace the execution-runtime-specific boundary test with a generic,
     profile-aware package graph check.
  4. Update repository verification to use the shared workspace resolution and
     preserve package-specific analysis, tests, and optional code generation.
  5. Add `packages/caverno_content_protocol`, move `ContentParser` and its tests,
     and migrate every consumer to its public library.
- Constraints:
  - Dependency direction remains root application to internal packages only.
  - Pure-Dart packages must not import Flutter, Riverpod, storage, platform
    plugins, `dart:io`, `dart:ui`, `dart:ffi`, or `package:caverno`.
  - Packages must not import another package's `lib/src` implementation.
  - Package dependencies must remain acyclic.
  - The parser's public type names and method behavior must remain unchanged.
- Generated files needed: None for the pilot package. Verification must retain
  support for future package-local generators.
- Migration or data compatibility concerns: None. This slice changes imports
  and dependency resolution only; no persisted or wire schema may change.

## Similar-Pattern Search

- Search terms:
  - `core/utils/content_parser.dart`
  - `ContentParser`
  - `packages/*/pubspec.yaml`
  - `package:caverno_execution_runtime`
  - `lib/src/`
- Files or modules inspected:
  - Chat presentation, orchestration, and response normalization
  - Routine scheduling and execution
  - Settings live-LLM diagnostics
  - Internal-package verification and architecture tests
- Follow-up tasks found:
  - Extract `caverno_tool_contracts` after common approval and capability types
    are separated from application settings.
  - Extract `caverno_llm_contracts` after tool contracts stabilize.
  - Extract `caverno_workflow_core` after domain services stop importing
    presentation state.

## Acceptance Criteria

- Required behavior:
  - The root application and both internal packages share one Pub workspace
    resolution.
  - Every `ContentParser` consumer imports `package:caverno_content_protocol`.
  - Existing parser inputs produce unchanged segments, tool calls, sanitized
    arguments, incomplete-tag state, and stripped content.
  - Repository verification discovers, analyzes, and tests every internal
    package.
- Edge cases:
  - Complete, incomplete, malformed, XML, function, control-token, and bare tool
    call formats retain their coverage.
  - Tool calls inside thinking blocks remain non-executable.
  - An unregistered package or dependency cycle fails the architecture gate.
- Failure paths:
  - A pure-Dart package importing a forbidden platform or application library
    fails with the offending file and import URI.
  - A package importing another package's private `src` library fails.
  - Workspace membership and package policy drift fail before release.
- Accessibility, localization, or platform expectations: No UI, accessibility,
  localization, or platform behavior changes.

## Verification

```bash
fvm dart pub workspace list
tool/codex_verify.sh \
  --test test/quality/package_boundary_test.dart
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:

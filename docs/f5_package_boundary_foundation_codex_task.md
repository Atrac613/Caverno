# F5 Package Boundary Foundation

## Task

- Goal: Establish the first enforceable package boundary for Caverno by moving
  the shared execution runtime contract into a small pure-Dart package.
- User-visible behavior: None. GUI, headless, and terminal execution behavior,
  event schemas, exit codes, and approval semantics must remain unchanged.
- Non-goals:
  - Do not package `ChatNotifier`, `ChatPage`, `McpToolService`, terminal
    composition, persistence, or platform adapters.
  - Do not change CLI packaging, signing, or supported platforms.
  - Do not move the file-backed execution lease in this slice.
  - Do not combine the extraction with tool-loop, workflow, or UI behavior
    changes.

## Context

- Affected files or components:
  - `lib/features/chat/application/runtime/`
  - GUI and terminal runtime adapters
  - runtime-focused tests
  - `test/quality/file_size_ratchet_test.dart`
  - `tool/codex_verify.sh`
  - root and package `pubspec.yaml` files
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/local_llm_agent_roadmap.md`
  - `docs/roadmap.md`
  - `docs/caverno_cli_terminal_contract.md`
- Reference implementation or pattern: The CLI1 shared runtime ports already
  isolate event production from GUI and terminal presentation.
- Known quirks, compatibility rules, or release gates:
  - CLI4 may resume after this foundation is merged and the combined root and
    internal-package verification gate passes. A fresh signed macOS packaged
    doctor is a CLI4 promotion and release gate, not an F5 prerequisite.
  - Before this slice, the root Flutter application was the only package and
    the repository verifier had no internal `packages/` verification path.
  - Before this slice, runtime tests used `flutter_test` even though the runtime
    contract was pure Dart.

## Implementation Notes

- Preferred approach:
  1. Add `packages/caverno_execution_runtime` as an internal path dependency.
  2. Move the runtime event, ports, execution engine, and failure classifier
     into that package without changing public type names or wire values.
  3. Keep ownership lease IO, Riverpod adapters, persistence, and frontend
     composition in the root application.
  4. Move the pure runtime tests into the package and run them with `dart test`.
  5. Make the repository verification entrypoint analyze and test each declared
     internal package.
- Constraints:
  - The package must not import Flutter, Riverpod, root `package:caverno`,
    storage plugins, or platform plugins.
  - Dependencies must point from the root application to the package only.
  - Runtime JSON event schema and enum wire names are compatibility surfaces.
  - Package extraction must remain behavior-preserving.
- Generated files needed: None.
- Migration or data compatibility concerns: None. No persisted model or storage
  schema changes are allowed.

## Similar-Pattern Search

- Search terms:
  - `features/chat/application/runtime`
  - `caverno_execution_runtime`
  - `caverno_runtime_event`
  - `caverno_runtime_ports`
  - `caverno_runtime_failure_classifier`
- Files or modules inspected:
  - `lib/features/chat/application/runtime/`
  - `lib/features/terminal/`
  - `lib/features/chat/presentation/providers/`
  - `integration_test/plan_mode_scenario_test.dart`
- Follow-up tasks found:
  - Extract the ChatPage workflow task coordinator after characterization tests.
  - Split `McpToolService` into catalog, transport, normalization, and
    tool-family handlers before considering an MCP protocol package.
  - Evaluate a pure tool-contract package only after a second stable package
    consumer exists.

## Acceptance Criteria

- Required behavior:
  - GUI, headless, and terminal consumers import runtime contracts from
    `package:caverno_execution_runtime`.
  - The package has no dependency on Flutter or the root Caverno package.
  - Runtime events preserve schema name, schema version, type names, payload
    keys, and surface wire names.
  - Root application tests and package tests pass.
  - `tool/codex_verify.sh` analyzes and tests internal packages.
- Edge cases:
  - Runtime completion, failure, question, approval, and tool lifecycle events
    retain their current serialization.
  - The package verifier succeeds when no root focused test target is supplied.
  - Focused root test runs still execute package analysis and package tests.
- Failure paths:
  - Architecture tests reject package imports from Flutter, Riverpod, storage,
    platform plugins, or `package:caverno`.
  - Verification stops when an internal package fails dependency resolution,
    analysis, or tests.
- Accessibility, localization, or platform expectations: No UI or localized
  copy changes. The runtime package must remain platform-neutral.

## Verification

```bash
(cd packages/caverno_execution_runtime && fvm dart test)
tool/codex_verify.sh \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/features/chat/presentation/providers/caverno_execution_runtime_provider_test.dart \
  --test test/features/terminal/application/caverno_cli_application_test.dart \
  --test test/features/terminal/presentation/caverno_terminal_presenter_test.dart
```

## Handoff Notes

- Summary: Extracted the event, ports, execution engine, and failure classifier
  into `packages/caverno_execution_runtime`; migrated GUI, integration, and CLI
  consumers; added one-way boundary checks; and extended the repository verifier
  to analyze and test internal Dart packages.
- Tests run:
  - Package analysis completed with no findings.
  - All 13 package tests passed.
  - The focused root gate passed 32 tests covering file-size ratchets, package
    boundaries, runtime providers, terminal interaction, terminal presentation,
    and GUI-to-terminal resume.
  - Root Flutter analysis completed with no findings.
- Coverage or low-coverage notes: Coverage was not collected because this slice
  moves already-covered behavior without changing it. Focused runtime tests now
  run directly in the package.
- Risks or follow-ups:
  - Keep IO ownership leases, persistence, Riverpod adapters, and frontend
    composition in the application.
  - Merge this foundation and keep the combined root and internal-package gate
    green before resuming CLI4. Treat the signed packaged doctor as CLI4
    promotion evidence rather than a prerequisite for this extraction.
  - Add characterization tests before the ChatPage workflow task coordinator
    extraction.
  - Split MCP catalog, transport, normalization, and tool-family handlers before
    considering an MCP protocol package.

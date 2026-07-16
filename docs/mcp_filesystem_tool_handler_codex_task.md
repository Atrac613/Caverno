# MCP Built-in Filesystem Tool Handler Extraction

Status: completed on `feature/mcp-filesystem-tool-handler`.

## Task

- Goal: extract the built-in filesystem tool family and rollback checkpoint
  ownership from `McpToolService` into an independently testable
  application-internal handler.
- User-visible behavior: preserve existing schemas, definition placement,
  validation, normalization, platform gating, direct execution, result
  envelopes, and rollback behavior. Correct the existing `delete_file` remote
  collision reservation gap before extraction.
- Non-goals: changing `FilesystemTools`, normalizing legacy success envelopes,
  changing approval policy, moving LSP or dependency grounding, introducing an
  internal package, or adding unrestricted filesystem access.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - `lib/features/chat/data/datasources/mcp_tool_service_delete_file.dart`
  - `lib/features/chat/data/datasources/filesystem_tools.dart`
  - `lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart`
  - a new `built_in_filesystem_tool_handler.dart`
  - focused service, handler, checkpoint, filesystem, and line-ratchet tests
- Related docs: `docs/large_file_refactor_plan.md` Phase 3 and
  `docs/roadmap.md` milestone F5.
- Reference pattern: the independent `BuiltInNetworkToolHandler` boundary.
  Keep this handler in the root application and do not add another Dart
  `part`.
- Compatibility rules:
  - Preserve all nine names: `list_directory`, `read_file`, `inspect_file`,
    `find_files`, `search_files`, `write_file`, `edit_file`, `delete_file`,
    and `rollback_last_file_change`.
  - Read-only definitions remain available on every platform. Mutation
    definitions remain desktop-only.
  - Preserve global definition placement: the five read-only definitions,
    dependency grounding, LSP, then the four desktop mutation definitions.
  - Disabled or platform-hidden definitions remain directly executable by a
    known name, matching the current service contract.
  - All nine names reserve remote MCP collisions even when their definitions
    are disabled. A focused pre-extraction fix corrected the prior
    `delete_file` reservation gap.
  - Read operations and `write_file`/`edit_file` retain their legacy successful
    `McpToolResult` envelope even when a JSON payload reports an operation
    error. `delete_file` continues deriving success from its payload.
  - Only successful mutations add rollback snapshots. An `already_applied`
    edit does not add a snapshot.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition schemas, split placement, platform gating,
     disabled direct execution, result-envelope asymmetry, normalization, and
     checkpoint lifecycle behavior.
  2. Add `delete_file` to the reserved collision set and pin all nine remote
     collision names.
  3. Introduce `BuiltInFilesystemToolHandler` with explicit `toolNames`,
     `readOnlyDefinitions`, `mutationDefinitions`, `handles`, and `execute`
     surfaces.
  4. Inject a narrow operation runner and snapshot loader for deterministic
     normalization and mutation tests. Production delegates to
     `FilesystemTools`.
  5. Move `FileRollbackCheckpointStore` ownership into the handler. Keep the
     existing `McpToolService` preview, begin, end, and rollback methods as thin
     delegates.
  6. Remove `mcp_tool_service_delete_file.dart`, delegate definitions and
     execution to the handler, and lower primary plus aggregate ratchets.
- Constraints:
  - Do not place mutation definitions before dependency grounding or LSP.
  - Preserve exact required arguments, numeric defaults and clamps, optional
    filters, `create_parents`, `replace_all`, and payload error messages.
  - Preserve the first successful snapshot per path in turn checkpoints and
    the individual rollback stack's LIFO behavior.
  - Keep dependency grounding and LSP routing in `McpToolService`.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_reservedToolNames`, `_listDirectoryTool`,
  `_deleteFileToolDefinition`, `_isFilesystemPayloadSuccess`,
  `_fileRollbackCheckpointStore`, `beginFileTurnCheckpoint`, and remote tool
  name collisions.
- Files or modules inspected: `mcp_tool_service.dart`,
  `mcp_tool_service_delete_file.dart`, `mcp_tool_service_connection.dart`,
  `filesystem_tools.dart`, `file_rollback_checkpoint_store.dart`, their focused
  tests, and the file-size ratchet.
- Follow-up tasks found: local command/background process extraction, remote
  MCP connection and trust-state extraction, result normalization, and later
  decomposition of the IO-heavy `network_tools.dart` implementation.

## Acceptance Criteria

- Required behavior:
  - Exact definitions and full placement around dependency grounding and LSP
    remain unchanged.
  - `McpToolService.executeTool` delegates all nine names to one handler.
  - All non-filesystem tools keep their existing routing.
  - All nine filesystem names namespace remote MCP collisions.
  - Existing service checkpoint APIs use the same store owned by the handler.
- Edge cases:
  - Blank required arguments fail without invoking the operation runner.
  - Numeric defaults and clamps are preserved for list, read, inspect, find,
    and search operations.
  - Failed and already-applied mutations do not create rollback entries.
  - Repeated changes to one path retain the first turn snapshot.
- Failure paths:
  - Read and write/edit payload errors retain their legacy success envelope.
  - Delete and rollback failures retain their existing unsuccessful envelopes
    and retry behavior.
  - Unknown names are not handled.
- Platform expectations: direct tests cover both definition branches without
  requiring an Android/iOS runner; filesystem integration tests use isolated
  temporary directories only.

## Verification

Run focused checks after each implementation commit:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/built_in_filesystem_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/data/datasources/filesystem_tools_test.dart \
  --test test/features/chat/data/datasources/file_rollback_checkpoint_store_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInFilesystemToolHandler` now owns all nine ordered filesystem
  definitions, validation, normalization, execution, mutation snapshots, and
  rollback checkpoints. `McpToolService` delegates definitions, execution, and
  checkpoint APIs to the handler, and the former delete-file `part` was
  removed. The primary service fell from 4,096 to 3,621 lines, its same-library
  aggregate fell from 4,439 to 3,910 lines, and the handler is ratcheted at 622
  lines.
- Tests run: the focused verifier passed 97 root tests plus 13 internal-package
  tests with no analyzer findings. The full repository coverage gate passed
  3,445 root tests, regenerated committed outputs without drift, and reported
  no analyzer findings.
- Coverage or low-coverage notes: full-project line coverage was 72.27%
  (51,054/70,641). The new handler reached 99.20% line coverage (249/251)
  without live filesystem access outside isolated temporary directories.
- Risks or follow-ups: the legacy result-envelope asymmetry is intentionally
  preserved and should only be normalized in a separate behavior-change task.
  The next service-decomposition slice is the local command and background
  process handler.

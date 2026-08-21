# SEC4.4b Project Mutation Containment Task

Status: complete.

## Task

- Goal: authorize every write, edit, and delete against the same canonical,
  symlink-aware project root used by SEC4.4a reads. Canonicalize the target or
  its nearest existing parent immediately before any filesystem effect.
- User-visible behavior: in-project relative and absolute mutation paths still
  work. `~`, `..`, sibling/prefix collisions, and symlink escapes fail before
  preflight, approval preview, or execute.
- Non-goals: routine external MCP deny-by-default (SA-09, a follow-up SEC4.4b
  slice), host-wide mutation approvals, and git/shell write containment.

## Context

- Affected components:
  - `FileMutationToolHandler` effect boundary;
  - a mutation path fence next to `ProjectReadPathFence`.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-08 and P1-1;
  - `docs/sec4_4a_project_read_containment_task.md`.
- Release gate: P1. Do not combine with SA-09.

## Implementation Slices

1. Add a mutation fence that reuses canonical-root comparison, resolves an
   existing target like the read fence, and otherwise walks to the nearest
   existing parent.
2. Call it at the start of `FileMutationToolHandler.handle` so denied paths
   never reach preflight, fingerprint, or execute.
3. Keep handler tests on an injectable authorizer; cover symlink and
   nearest-parent cases on the real fence.

## Implementation Notes

- Preferred approach: fail closed with a stable `project_mutation_*` denial
  code. Rewrite the operation path to the authorized canonical form before
  later effects.
- Constraints:
  - Do not grow `file_mutation_tool_handler.dart` past its F1 budget.
  - Missing project root denies mutations.
  - Do not follow a non-existent path into a sibling via string prefix.
- Generated files needed: None.

## Similar-Pattern Search

- Search terms: `isInsideRoot`, `delete_path_outside_project`,
  `ProjectReadPathFence`, `FileMutationToolHandler`.
- Files or modules inspected:
  - `project_read_path_fence.dart`
  - `file_mutation_tool_handler.dart`
  - `file_mutation_tool_runtime_adapter.dart`
- Follow-up tasks found: deny unclassified external MCP tools in routines
  (SA-09).

## Acceptance Criteria

- Required behavior:
  - Existing in-root files can be edited or deleted.
  - New in-root files can be written via the nearest existing parent.
- Edge cases:
  - Reject `~`, `~/...`, `..`, siblings, prefix collisions, and symlink
    escapes, including an in-root link to a file outside the root.
- Failure paths:
  - Zero execution-port calls after denial.

## Verification

```bash
fvm flutter test test/features/chat/data/datasources/project_mutation_path_fence_test.dart
fvm flutter test test/features/chat/domain/services/file_mutation_tool_handler_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
```

## Handoff Notes

- Summary: Write, edit, and delete now go through `ProjectMutationPathFence`
  before preflight, fingerprint, or execute. Existing targets resolve like
  SEC4.4a reads; new files authorize via the nearest existing parent.
- Focused verification passed:
  - `project_mutation_path_fence_test.dart`
  - `file_mutation_tool_handler_test.dart`
  - `file_mutation_tool_runtime_adapter_test.dart`
  - `file_size_ratchet_test.dart`
- Risks or follow-ups: SA-09 / SEC4.4c is complete. Git and local-command
  writes are outside this handler. Re-check immediately before execute is still
  a TOCTOU follow-up if a symlink can be swapped after approval.

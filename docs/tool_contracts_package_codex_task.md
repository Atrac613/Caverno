# Tool Contracts Package

## Task

- Goal: Extract the stable tool approval and capability contracts into a
  reusable pure-Dart package without changing approval, classification,
  persistence, or execution behavior.
- User-visible behavior: None.
- Non-goals:
  - Do not move approval UI, auto-review orchestration, audit logging, taint
    policy, routine policy, browser policy, or Computer Use policy.
  - Do not change which tools require approval or how denials are escalated.
  - Do not rename persisted `ToolApprovalMode` values.
  - Do not introduce a runtime component registry or installable tool bundle.

## Measured Boundary

- `ToolApprovalMode` is currently declared in `AppSettings` even though it is
  also used by chat participants, approval handlers, widgets, tests, and live
  canaries.
- `ToolCapabilityClassifier` is a 519-line, dependency-free pure-Dart policy
  with 307 lines of direct tests. Its results feed security perimeter, taint,
  audit, tool-result, and coding command policy.
- `ToolApprovalGateDecision` is a 115-line dependency-free approval contract
  with 63 lines of direct tests. It is shared by the approval handlers and
  their tests.
- The three targets have no Flutter, Riverpod, persistence, platform, root
  package, or operating-system dependency.
- Application-specific settings, execution, presentation, and logging consume
  these contracts but are not dependencies of the proposed package.

## Intended Public API

The package exposes one public library:
`package:caverno_tool_contracts/caverno_tool_contracts.dart`.

It owns:

- `ToolApprovalMode`
- `ToolApprovalGateOutcome`
- `ToolApprovalGateDecision`
- `ToolCapabilityClass`
- `ToolRiskTier`
- `ToolCommandEffect`
- `ToolCapability`
- `ToolCapabilityClassifier`

Implementation helpers remain private under `lib/src`.

## Implementation Plan

1. Register `caverno_tool_contracts` as an explicit `pure_dart` workspace
   package with no production dependencies.
2. Move the capability classifier and approval gate into package-owned source
   files without behavioral edits.
3. Move `ToolApprovalMode` out of `AppSettings`; import it from the package in
   every direct consumer.
4. Move the classifier and approval gate unit tests into the package, retaining
   their assertions unchanged except for imports.
5. Regenerate Freezed and JSON serialization outputs so persisted settings and
   participant schemas continue to use the same enum values.
6. Extend the generic package boundary gate to reject the removed root import
   paths and any reintroduction of `ToolApprovalMode` in application settings.
7. Run focused settings, participant, approval, security, and canary compile
   coverage before the full repository gate.

## Compatibility Constraints

- `ToolApprovalMode` values remain `defaultPermissions`, `autoReview`, and
  `fullAccess`, in the existing order.
- JSON values remain `defaultPermissions`, `autoReview`, and `fullAccess`.
- Unknown persisted values continue to fall back to `defaultPermissions`.
- Every classifier input must produce the same capability class, risk tier,
  command effect, mutation flag, and network flag as before extraction.
- Every approval gate decision must preserve its outcome, rationale, bypass,
  escalation, and convenience getter behavior.
- Root application code imports only the package public library, never
  `package:caverno_tool_contracts/src/...`.

## Acceptance Criteria

- The package passes pure-Dart analysis and its complete direct test suite.
- `AppSettings` and `ConversationParticipant` generated serializers compile and
  preserve their existing enum maps.
- The package catalog, root workspace, and versioned root dependency agree.
- No legacy classifier, approval gate, or settings-owned approval enum remains.
- Security perimeter, taint, audit, settings, participant, approval handler,
  and tool policy tests pass unchanged.
- Repository analysis, generated-output verification, package tests, root
  tests, and merged coverage all pass.

## Verification

```bash
fvm dart pub workspace list
tool/codex_verify.sh \
  --test test/quality/package_boundary_test.dart \
  --test test/core/security/taint_policy_test.dart \
  --test test/core/security/tool_perimeter_context_test.dart \
  --test test/core/services/tool_approval_audit_log_test.dart \
  --test test/features/settings/domain/entities/app_settings_test.dart \
  --test test/features/chat/presentation/widgets/participant_roster_bar_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:

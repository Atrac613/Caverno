# SEC4.1 Approval-Free Execution Boundary Task

Status: complete on `feature/sec4-1-approval-free-execution-boundary`.

## Task

- Goal: ensure that every command allowed through the read-only shortcut uses
  Caverno's bounded internal argv executor and never reaches `sh -c` or
  Windows `cmd /C`. Remembered exact permissions remain a separate explicit
  authorization path.
- User-visible behavior: bounded inspection commands continue to run without a
  prompt; interpreter-like, shell-backed, or unsupported commands require the
  existing approval flow and are blocked in Plan Mode.
- Non-goals: redesign remembered permission rules, remove explicitly approved
  shell execution, or implement the SEC4.4 project-root filesystem boundary.

## Context

- Affected components:
  - `LocalShellTools` classification and internal execution;
  - foreground `local_execute_command` approval routing;
  - background `process_start` approval routing;
  - `PlanningToolPolicy` command admission.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-01;
  - `docs/local_llm_agent_roadmap.md` SEC4.1.
- Release gate: SEC4.1 is P0 and must close before an affected release.

## Implementation Tasks

1. **SEC4.1a — Classifier regression contract.** Add named regressions for
   `awk system()`, `sed w`, shell-backed read commands, option-extensible
   `find`/`rg` inputs, and the historical standalone-`&` separator defect.
2. **SEC4.1b — Internal-executor invariant.** Make the approval-free classifier
   return true only when the exact normalized command is accepted by the
   bounded internal executor. Keep unsupported options fail-closed.
3. **SEC4.1c — Consumer boundary tests.** Prove that foreground, remote-origin,
   background process, and Plan Mode consumers all use the shared invariant.
   Preserve the rule that Plan Mode cannot start a background process.
4. **SEC4.1d — Verification and audit evidence.** Run focused tests, the
   repository verifier, and a similar-pattern search before updating the audit
   evidence and milestone status.

## Similar-Pattern Search

- Search terms: `LocalShellTools.isReadOnly`, `requiresExplicitApproval`,
  `CommandPermissionRuleDecision.allow`, `process_start`,
  `PlanningToolPolicy`.
- Inspect all approval-free consumers before completing SEC4.1c.
- Record separately roadmapped findings instead of widening this slice into
  SEC4.2 configuration quarantine or SEC4.4 filesystem containment.

## Acceptance Criteria

- `LocalShellTools.isReadOnly(command)` implies that executing the same command
  reports `executed_internally: true`.
- `awk`, `sed`, `grep`, `stat`, `file`, and shell-backed `git` commands never
  take the read-only shortcut.
- Supported `pwd`, `echo`, `ls`, `cat`, `head`, `tail`, `wc`, `find`, and `rg`
  forms retain approval-free behavior through bounded Dart implementations.
- Unsupported `find` and `rg` expressions fail closed inside the bounded
  executor and never fall back to a native shell.
- Foreground, remote-origin, and background handlers request approval for
  semantic shell commands. Plan Mode rejects them.
- Existing separator, explicit-approval, timeout, and internal-execution tests
  remain green on supported platforms.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/data/datasources/local_shell_tools_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/local_command_tool_handler_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/background_process_tool_handler_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/planning_tool_policy_test.dart
tool/codex_verify.sh --no-codegen --no-tests
```

## Handoff Notes

- Implementation commits:
  - `da2e6b84` enforces the internal-executor invariant across foreground,
    background, remote-origin, saved-rule, and Plan Mode admission;
  - `e17d8eec` removes the duplicate ChatNotifier `process_start` shortcut and
    adds an active-runtime approval regression;
  - `1415da6f` shares background argument parsing, updates the adjacent mutation
    guard regression, and restores the 417-line handler ratchet.
- Focused command, process, Plan Mode, permission, active ChatNotifier, mutation
  guard, and file-size-ratchet tests pass. `tool/codex_verify.sh --no-codegen
  --no-tests` also passes.
- The full root test run completed with four baseline failures outside this
  slice: three pre-existing `mcp_tool_service.dart` /
  `chat_remote_datasource.dart` size-ratchet failures and the pre-existing model
  capability count expectation (`29` versus `32`). None of those files changed
  from the audit baseline in this branch.
- Residual risk: explicitly approved native-shell execution remains available
  by design; SEC4.2 and the remaining P0 slices are still release blockers.

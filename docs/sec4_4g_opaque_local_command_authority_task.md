# SEC4.4g Opaque Local-Command Authority

Status: completed 2026-08-24.

## Task

- Goal: prevent a native-shell command from silently escaping the selected
  project by computing a host path that is absent from the lexical path scan.
- User-visible behavior: commands that reach `sh -c` or `cmd /C` require a
  fresh, non-cacheable host-write approval even in Full Access or auto-review.
  Commands executed through Caverno's bounded internal argv implementation keep
  their existing fast path.
- Non-goals: parsing arbitrary shell, implementing an OS filesystem sandbox,
  changing commands when no project is selected, or changing Git tool policy.

## Context

- Affected components: local-command approval scope and contract, foreground
  and background handlers, approval-gate audit source, and focused tests.
- Related docs: `docs/security_followup_review_2026-08-24.md` SA-19,
  `docs/sec4_4f_local_command_write_containment_task.md`, and
  `docs/security_audit_2026-08-14.md`.
- Reference pattern: `requiredManualDecision` already runs before cached
  approval, Full Access, and auto-review for literal out-of-project paths.
- Release gate: P0 follow-up for unrestricted local commands.

## Implementation Notes

- Treat a command as opaque when it will reach a native shell. For
  `local_execute_command`, that means the command is not internally executable
  or `background:true`; every `process_start` command is opaque.
- Require fresh manual approval only when a non-empty project root establishes
  the boundary. Preserve general chat behavior without a selected project.
- Prefer the literal out-of-project prompt when both a path token and opaque
  shell execution are present; otherwise explain that computed effects cannot
  be proven project-contained.
- Record `opaque_host_write` as the audit decision source.
- Do not persist an allow rule or positive result cache for a mandatory fresh
  approval.
- No generated files, migrations, or new dependencies are required.

## Similar-Pattern Search

- Search terms: `requiredManualDecision`, `fullAccessEligible`,
  `LocalCommandApprovalScope`, `process_start`, `background`, `sh -c`, and
  `cmd /C`.
- Files inspected: foreground and extracted background handlers, the production
  ChatNotifier process-start path, local command runtime adapters, built-in
  mutation preflight, approval coordinator, and permission-rule service.
- Follow-up tasks found: OS-enforced filesystem containment remains the only way
  to describe an approved opaque command as project-contained. SA-20 remains a
  separate HTML Preview slice.

## Acceptance Criteria

- A computed-path interpreter command cannot use saved allow, approval cache,
  auto-review, or Full Access when a project is selected.
- `background:true` and `process_start` receive the same boundary even for a
  command such as `pwd` that foreground execution can run internally.
- Mandatory host-write approval is not offered as a remembered rule and does
  not write a positive approval-result cache.
- Literal outside paths retain their more specific approval copy and audit
  source.
- Internal in-project read commands preserve their approval-free path.
- Denial and expired-owner paths start zero processes.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/chat/domain/services/out_of_root_command_paths_test.dart \
  --test test/features/chat/domain/services/tool_approval_auto_review_service_test.dart \
  --test test/features/chat/domain/services/local_command_tool_handler_test.dart \
  --test test/features/chat/domain/services/background_process_tool_handler_test.dart
```

## Handoff Notes

- Summary: foreground shell execution, `background:true`, and every
  `process_start` now require fresh `opaque_host_write` authority when a project
  is selected. Saved denies remain effective, but saved allows, Full Access,
  auto-review, remembered allow rules, and positive result caches cannot satisfy
  this authority.
- Tests run: main and workspace-package static analysis passed. The four focused
  suites passed 133 tests with coverage enabled.
- Coverage or low-coverage notes: focused aggregate line coverage was 29.49%
  (2,079/7,050); this is expected because the handler suites import broad chat
  infrastructure. The new approval-scope branches and both foreground and
  background enforcement paths have direct regressions.
- Risks or follow-ups: native-shell approval is explicit authority, not an OS
  containment guarantee.

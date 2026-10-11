# F5 Incomplete Content Tool Recovery Extraction

## Task And Acceptance

Isolate incomplete-call eligibility, parsing, ordered candidate acceptance and
recovery feedback. Keep current-generation/owner guards, owner-rooted hash
construction, seen-call registration, stripping, pending-result registration and
execution queueing with ChatNotifier. Freeze accepted/rejected candidate paths,
including all-duplicate fallback, and owner lifecycle isolation. Run pre/post
notifier integration, focused policy/owner tests, analysis/coverage and boundary
ratchets; update both roadmap indexes and commit locally.

## Context And Plan

Baseline: local main `006e8eb32`; ChatNotifier 7,287 root/19,770 aggregate lines.
The parser returns recoverable incomplete calls. Candidate acceptance currently
registers each hash in the explicitly begun owner registry; duplicate/disposed
owners reject registration. An owner-bound acceptance callback retains that
responsibility in the notifier while a small plan handles parser/feedback
policy. No owner registry, transport or execution enters the domain boundary.
Similar-pattern search inspected artifact recovery plans, parser exemptions and
content-tool registry lifecycle. Recovery branch precedence remains in place.

## Verification

Three notifier integration cases passed before and after extraction using
`--name 'incomplete content tool|fenced tool-name continuation'`. They cover
parseable incomplete calls, fenced-name continuation and recovery before no-tool
finalization. Twelve policy tests cover role/null/complete gates, both tag
variants, exact recovered arguments and feedback, all-rejected fallback,
malformed/exempt/think-only input and acceptance exception propagation. The
think-only expectation was corrected to preserve the existing continuation
path rather than change shared parser behavior.

A separate acceptance contract uses the real content-tool registry and rooted
deduplication key builder to prove duplicate rejection within one owner,
isolation across conversations sharing a generation, disposed-owner refusal,
fresh-generation acceptance and no implicit queueing/pending registration.
The existing registry lifecycle suite is included in the final gate.
Current-generation/owner guards and recovery precedence are unchanged; exact
continuation notice fragments match the original. Stripping still precedes
pending registration or queueing, and the acceptance callback still marks each
candidate before those side effects.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/chat/domain/services/tool_loop/incomplete_content_tool_recovery_plan_test.dart \
  --test test/features/chat/presentation/providers/incomplete_content_tool_recovery_owner_test.dart \
  --test test/features/chat/presentation/providers/content_tool_turn_state_registry_test.dart \
  --test test/features/chat/domain/services/tool_loop/assistant_tool_artifact_recovery_plan_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 479 focused tests passed across seven suites, including twelve policy tests,
  the owner acceptance contract and existing registry lifecycle coverage.
  Three notifier integration cases passed separately.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Plan: 11/11 executable lines covered (100%). This focused gate does not
  establish full ChatNotifier coverage; notifier evidence is the separate
  incomplete-call integration run.
- ChatNotifier: 7,287 -> 7,261 root and 19,770 -> 19,744 aggregate lines.
  Plan: 48 lines. Root/module/aggregate budgets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or tool execution/acquisition port.

## Follow-Up

Inspect repeated content-call recovery and successful-result reuse contracts
before another move. Owner state, request retries, approval and execution
retain their owners. F5 remains `current`; RC1 signed-device verification stays
on hold. No full ChatNotifier/Flutter suite, live-model, live-tool,
signed-device, release or push run. The pre-existing `macos/Podfile.lock` change
remains outside this task.

# F5 Repeated Content Tool Recovery Extraction

## Task And Acceptance

Isolate ordered selection of the first repeated call with reusable successful
content evidence and its existing log/fallback text. Keep empty/current-generation
and provider-capability guards, owner-rooted matching, ledger failure/retention
policy and message mutation in ChatNotifier and its existing collaborators.
Freeze lookup order, early stopping and owner/evidence reuse conditions. Run
pre/post notifier integration, focused policy/ledger contracts, analysis/coverage
and boundary gates; update both roadmaps and commit locally.

## Context And Plan

Baseline: local main `814271249`; ChatNotifier 7,261 root/19,744 aggregate lines.
This suppression path is gated off for advanced-live-tool providers. Each repeat
searches the owning turn's content ledger for the newest successful result with
the same rooted deduplication key. The shared ledger owns failure classification
and retention; the new plan receives that owner-bound lookup, not ledger state.
Similar-pattern search inspected incomplete-call acceptance, result ledger and
provider capability gates. No failure classifier or execution policy is copied.

## Verification

The original Foundation Models repeat suppression integration passed before
and after extraction (one test), retaining one tool execution, two requests and
the previous-result fallback. Five policy tests cover ordered lookup, stopping
at the first reusable repeat, no evidence, exact log/fallback text and lookup
exception propagation. Three real-ledger contracts cover newest success despite
newer failure, relative/absolute rooted path equivalence, other path exclusion,
owner/generation isolation, completed-only exclusion, retention and disposal.
The plan leaves evidence counts unchanged.

Provider/generation guards and owner-bound successful lookup are byte-identical
to the original. Log/fallback string fragments match after local variable
substitution; log then owner-message replacement retains its original order.
No ledger retention, success classifier, provider capability or key policy is
copied or changed.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/chat/domain/services/tool_loop/repeated_content_tool_recovery_plan_test.dart \
  --test test/features/chat/presentation/providers/repeated_content_tool_recovery_owner_test.dart \
  --test test/features/chat/presentation/providers/turn_tool_result_ledger_test.dart \
  --test test/features/chat/domain/services/tool_loop/incomplete_content_tool_recovery_plan_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 476 focused tests passed across seven suites, including five policy tests,
  three owner/evidence contracts and existing result-ledger coverage.
  One notifier integration case passed separately.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Plan: 9/9 executable lines covered (100%). This focused gate does not
  establish full ChatNotifier coverage; notifier evidence is the separate
  Foundation Models suppression integration run.
- ChatNotifier: 7,261 -> 7,250 root and 19,744 -> 19,733 aggregate lines.
  Plan: 34 lines. Root/module/aggregate budgets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or tool execution/acquisition port.

## Follow-Up

Inspect fresh/repeated content-call partition and execution queue boundaries
before another move. Owner state, retries, approval and execution retain their
owners. F5 remains `current`; RC1 signed-device verification stays on hold.
No full ChatNotifier/Flutter suite, live-model, live-tool, signed-device,
release or push run. The pre-existing `macos/Podfile.lock` change remains
outside this task.

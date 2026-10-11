# F5 Assistant Tool Artifact Recovery Extraction

## Task And Acceptance

Extract immutable assessment of assistant-authored tool-result markers and
fenced tool-name blocks, including existing logs and recovery notices. Preserve
role gates, marker order, stripping rules and exact notice text. Keep owner
lookup/guards, recovery branch precedence, message mutation, pending-result
registration and execution with ChatNotifier. Run pre/post integration cases,
isolated assessment tests, analysis/coverage and size/package/layer gates;
update both roadmap indexes and commit locally.

## Context And Plan

Baseline: local main `508f293d3`; ChatNotifier 7,327 root/19,810 aggregate lines.
Incomplete-call recovery first marks owner-scoped seen calls, then the remaining
branches reject assistant-authored results and fenced names. The latter two
contain a bounded message-to-notice assessment, while owner state transitions
and incomplete-call deduplication remain orchestration. Similar-pattern search
inspected shared content parsing, fenced-name parsing and skipped-browser policy.
The planned move adds no state, execution port, IO or owner registry.

## Verification

Four existing notifier integration cases passed before and after extraction
with `--name 'assistant-authored tool|fenced tool-name continuation'`. They
cover incomplete-call continuation, ignored results, safe empty fallback and
recovery before no-tool finalization. Thirteen isolated assessment tests cover
role/null gates, marker order/duplicates, parser exemptions, malformed and
incomplete markers, fenced stripping with preserved thinking, empty/ordinary
fences and independent mixed-artifact assessment. Unverified marker values are
not copied into result feedback.

Recovery branch precedence is byte-identical to the original. Exact notice
string fragments match the original; owner guards and side-effect order were
inspected in both delegation methods. The plan has no notifier/data dependency,
owner state or execution/acquisition port.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/chat/domain/services/tool_loop/assistant_tool_artifact_recovery_plan_test.dart \
  --test test/features/chat/domain/services/claims/skipped_browser_action_recovery_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 471 focused tests passed across five suites, including thirteen isolated
  plan tests; four notifier integration cases passed separately.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Plan: 18/18 executable lines covered (100%). This domain-focused gate does
  not establish full ChatNotifier coverage; notifier evidence is the separate
  artifact-recovery integration run.
- ChatNotifier: 7,327 -> 7,287 root and 19,810 -> 19,770 aggregate lines.
  Plan: 62 lines. Root/module/aggregate budgets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity
  or dependency.

## Follow-Up

Inspect incomplete-call recovery and freeze parsing versus owner-scoped
deduplication before another move. Request retries, owner message mutation,
pending registration and tool execution retain their owners. F5 remains
`current`; RC1 signed-device verification stays on hold. No full
ChatNotifier/Flutter suite, live-model, live-tool, signed-device, release or push
run. The pre-existing `macos/Podfile.lock` change remains outside this task.

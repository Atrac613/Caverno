# F5 Skipped Browser Recovery Extraction

## Task And Acceptance

Isolate skipped browser snapshot recovery eligibility and post-snapshot repair
eligibility. Preserve guard precedence, browser intent detection, generated ID
and max-elements arguments, recovered-result recognition and repair behavior.
Keep owner lookup, request construction, context retry, approval and execution
with ChatNotifier. Run original integration cases, isolated policy tests and
focused analysis/coverage plus size/package/layer gates. Update both roadmaps
and commit locally; no live browser or device work.

## Ranking And Boundary Selection

Baseline: local main `6a2495635`. On 2026-10-11, root lines/commits since
2026-09-11 are ChatNotifier 7,344/82, diagnostic service 2,122/40, remote coding
server 3,261/15 and remote coding page 2,671/12. ChatNotifier has 34 parts and
19,827 aggregate lines; its existing aggregate ceiling is 19,882. The preceding
catalog-focused coverage is not comparable coverage for ChatNotifier. Existing
browser-action integration tests provide a narrow behavior contract instead.

The browser recovery predicates use tool availability, disabled tools, owner
user text and completed snapshot evidence. Their request orchestration is kept
in place. Session-memory update and workflow proposal request blocks remain
orchestration-heavy. Similar-pattern search inspected skipped skill recovery,
shared browser claim recognition and existing repair prompts.

## Verification

Four original ChatNotifier browser-action integration tests passed before and
after extraction using the quiet wrapper with `--name 'browser action'`. They
exercise successful recovery, failed recovery and final unexecuted-action
evidence through real notifier orchestration with fixture data sources/tools.
Twelve isolated policy tests cover English/Japanese intent, exact ID/arguments,
clock read only on recovery, all negative guards, malformed definitions behind
early guards and recovered-result recognition independent of result content.
Both predicate bodies match the original after owner-input/clock substitutions.
Owner text lookup is synchronous and remains in the notifier; no await or owner
transition is introduced. The new import order lint was corrected before the
final gate was rerun.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/chat/domain/services/claims/skipped_browser_action_recovery_test.dart \
  --test test/features/chat/domain/services/claims/final_answer_claim_detector_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 483 focused tests passed across five suites, including twelve isolated
  recovery policy tests; four notifier integration tests passed separately.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Policy: 13/13 executable lines covered (100%). This focused domain gate does
  not establish full ChatNotifier coverage; notifier evidence is the separate
  browser-action integration run.
- ChatNotifier: 7,344 -> 7,327 root and 19,827 -> 19,810 aggregate lines.
  Policy: 50 lines. Root/module/aggregate ratchets pass; aggregate budget also
  retires 55 lines of prior slack against the measured baseline.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or browser execution/acquisition port.

## Follow-Up

Inspect remaining ChatNotifier recovery branches and freeze a bounded
owner-aware contract before moving another concern. Request retries, approval,
execution and owner management retain their owners. F5 remains `current`;
RC1 signed-device verification remains on hold. No full ChatNotifier/Flutter
suite, live-browser, live-model, signed-device, release or push run.
The pre-existing `macos/Podfile.lock` change remains outside this task.

# F5 Content Tool Call Partition Extraction

## Task And Acceptance

Isolate completed/advertised printed-call extraction and ordered fresh/repeated
partition through owner-bound seen-call acceptance. Preserve tagged precedence,
all-or-nothing printed-name gating, each candidate's acceptance and relative
order within both outputs. Keep owner/advertisement lookup, rooted hashes,
repeat-before-fresh dispatch, queue guards, display-only exclusions, executed
keys, approval and owner-lifetime execution checks in ChatNotifier/registry.
Run pre/post integrations, focused partition/owner/registry tests, analysis and
coverage/boundary gates; update both roadmaps and commit locally.

## Context And Plan

Baseline: local main `a517a47d1`; ChatNotifier 7,250 root/19,733 aggregate lines.
Printed extraction is already a domain policy. The remaining inline loop marks
owner-bound seen keys and partitions the recovered calls. A batch object can
compose extraction with acceptance without owning any registry or queue.
The execution queue retains a different executed-key policy and display-only
exclusions; merging seen/execute keys would change behavior. Similar-pattern
search inspected printed-call policy, incomplete acceptance and registry queue
lifetime/serialization tests. This slice adds no execution/acquisition port.

## Verification

Five notifier integration cases passed before extraction (three queue/repeat
cases and two printed-call cases) and after extraction in a single focused run.
They cover sequential approval, repeat suppression, display-only print and
advertised/unoffered raw-object recovery. Twelve partition tests cover output
order, one acceptance per candidate, same-batch duplicates, tagged precedence,
all-or-nothing printed-name gating, no candidates and exception propagation.
One real-registry contract covers normalized rooted keys, owner/generation
isolation, disposed-owner classification and no implicit executed key, pending
execution or result registration. Existing queue lifecycle tests are gated.

Repeat handling, success lookup and queue/lifetime implementation are
byte-identical to the original. The notifier still handles repeated calls before
queueing fresh calls. Both seen-key acceptance and advertisement lookup remain
bound to the original owner. No execution or acquisition port is introduced.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/chat/domain/services/tool_loop/content_tool_call_partition_test.dart \
  --test test/features/chat/presentation/providers/content_tool_call_partition_owner_test.dart \
  --test test/features/chat/presentation/providers/content_tool_turn_state_registry_test.dart \
  --test test/features/chat/domain/services/tool_loop/repeated_content_tool_recovery_plan_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 473 focused tests passed across seven suites, including twelve partition
  tests, one owner contract and existing registry lifecycle/queue coverage.
  Five notifier integration cases passed separately.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Partition: 10/10 executable lines covered (100%). This focused gate does not
  establish full ChatNotifier coverage; notifier evidence is the separate
  five-case integration run.
- ChatNotifier: 7,250 -> 7,240 root and 19,733 -> 19,723 aggregate lines.
  Partition: 35 lines. Measured root/aggregate counts and all budgets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or tool execution/acquisition port.

## Follow-Up

Inspect owner-scoped content-tool message mutation and freeze attached/detached
behavior before another move. Queue lifecycle, owner state, approvals, retries
and execution retain their owners. F5 remains `current`; RC1 signed-device
verification stays on hold. No full ChatNotifier/Flutter suite, live-model,
live-tool, signed-device, release or push run. The pre-existing
`macos/Podfile.lock` change remains outside this task.

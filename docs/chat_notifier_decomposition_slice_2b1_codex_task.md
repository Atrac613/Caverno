# ChatNotifier Decomposition Slice 2b1: Exact Live-Canary Exit Accounting

## Task

- Goal: make every multi-thread live-canary scenario prove that each completed
  interaction generation records exactly one `turn_exit` entry and that no
  conversation remains busy.
- User-visible behavior: none. This slice strengthens a live regression gate.
- Destination API: add a test-only lifecycle assertion that accepts immutable
  expected completed-turn counts by conversation and validates the parsed
  `turnExit.turnId` multiset together with `busyConversationIds`.
- Non-goals:
  - changing `ChatNotifier`, runtime lifecycle, or session-log production code;
  - changing prompts, scenario workloads, or overlap requirements;
  - accepting a non-empty exit list as evidence of exact accounting;
  - adding another notifier part or production collaborator.

## Context

- Affected files:
  - `tool/canaries/multi_thread_plan_live_canary_test.dart`;
  - `integration_test/multi_thread_plan_live_canary_test.dart` only if its
    forwarding entrypoint needs a comment or command correction.
- Related docs:
  - `docs/chat_notifier_decomposition_codex_task.md`;
  - `docs/multi_thread_architecture_study.md`;
  - `docs/session_logs.md`.
- Existing source methods and call sites:
  - `_expectEveryThreadHandedBack` currently checks only
    `busyConversationIds`;
  - `_SessionLog.parse` retains all entries, including `turn_exit`, but exposes
    no exact per-generation assertion;
  - `two threads drafting at once keep their own project, log and plan` waits
    for and asserts only a non-empty exit list;
  - `two coding turns at once keep their own messages` also accepts any
    non-empty exit list;
  - `a message queued behind a running turn still runs` has no independent
    `turn_exit` assertion;
  - `a thread the user left mid-turn comes back finished` has no independent
    `turn_exit` assertion.
- Session-log contract:
  `LlmSessionLogStore.recordTurnExit` writes `operation == "turn_exit"` and the
  generation correlation key at `turnExit.turnId`.

## Implementation Notes

- Introduce one test-only immutable expectation shape, for example
  `Map<String, int> expectedCompletedTurnsByConversation`, copied with
  `Map.unmodifiable` before asynchronous polling.
- Add a `_SessionLog` helper that returns `turnExit.turnId` values without
  guessing from timestamps or request count.
- The shared lifecycle assertion must:
  1. poll until every expected conversation log exists;
  2. collect every `turn_exit` entry;
  3. require the exact expected count for that conversation;
  4. require every `turnId` to be non-empty and unique within the conversation;
  5. require each `turnId` count to equal one;
  6. require `busyConversationIds` to be empty.
- Expected completed turns are:
  - concurrent plan drafting: alpha `2`, beta `2` because each seed chat turn
    and each plan-draft turn completes;
  - concurrent coding: alpha `1`, beta `1`;
  - queued message: owning conversation `2`;
  - handback after navigation: alpha `1`; the beta conversation starts no turn.
- Keep overlap, project isolation, transcript isolation, and persisted-plan
  assertions unchanged.
- Include duplicate and missing IDs in failure diagnostics. Print conversation
  IDs, expected counts, actual IDs, and matching raw exit entries.
- Do not infer interaction generations from entry order. The logged `turnId` is
  the authoritative generation key.
- Generated files needed: none.
- Typed side-effect ports: none. The gate reads the existing
  `LlmSessionLogStore` output and observable `ChatState`; it must not mutate
  production state.

## Similar-Pattern Search

- Search terms:
  - `operation'] == 'turn_exit'`;
  - `_expectEveryThreadHandedBack`;
  - `busyConversationIds`;
  - `turnExit`;
  - `turnId`.
- Inspect both the tool canary and its integration-test forwarding entrypoint.
- If another live canary uses a non-empty exit assertion, record it as a
  follow-up; do not widen this slice beyond the four named scenarios.

## Measurement and Manifest

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Expected same-library aggregate delta: `0`; it remains `22,900` physical
  lines.
- Manifest status changes: none.
- Collaborator records and discovery markers: none.
- Target-file coverage expectation: numerical line coverage is not applicable
  because Dart coverage excludes test source. The checked target-file gate is
  stronger: all four non-skipped live scenarios must reach their exact lifecycle
  assertion and pass.

## Acceptance Criteria

1. Every scenario declares its expected completed turns explicitly.
2. Every expected conversation has exactly the declared number of distinct
   `turnExit.turnId` values.
3. Every expected interaction generation has exactly one exit entry; duplicate,
   missing, and empty IDs fail.
4. An unrelated exit cannot satisfy another conversation's expectation.
5. The queued and handback scenarios independently validate exit accounting.
6. Every scenario independently ends with no busy conversations.
7. Existing overlap, project, transcript, plan, queue, and handback assertions
   remain intact.
8. No production file, manifest entry, part declaration, or size budget changes.

## Verification

Format and run the non-live wrapper first:

```bash
fvm dart format \
  tool/canaries/multi_thread_plan_live_canary_test.dart \
  integration_test/multi_thread_plan_live_canary_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
  -d flutter-tester
```

Verify the endpoint, then run the corrected gate with the exact warmed model:

```bash
curl -fsS http://127.0.0.1:11434/v1/models
CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL=http://127.0.0.1:11434/v1 \
CAVERNO_LLM_API_KEY=no-key \
CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
  -d flutter-tester
tool/codex_verify.sh --coverage
git diff --check
```

Record the reachable base URL, exact model ID, all four expected-count maps, and
the observed turn IDs. Use a loopback relay on macOS when the Flutter test
process cannot reach the LAN endpoint.

## Stop Conditions

- Stop if a scenario cannot identify completed turns from logged
  `turnExit.turnId`; do not substitute request count or timestamp order.
- Stop and open a separate lifecycle-fix task if the strengthened gate exposes
  a production turn that truly emits zero or duplicate exits.
- Stop if passing the gate would require weakening overlap, project isolation,
  transcript isolation, or timeout assertions.
- Stop if production code, a provider schema, or session-log schema must change.

## Handoff Notes

- Exact model and base URL: loaded `qwen3.6-27b-vision` at
  `http://192.168.100.241:1234/v1`.
- The 2026-07-28 full run observed:
  - plan alpha `4ea11762-610b-4cf6-bb91-5b4ebb4c5c6e`:
    `[gen-2, gen-6]`;
  - plan beta `91cfdcbf-a551-4e63-b1cb-80269abd67f6`:
    `[gen-4, gen-7]`;
  - coding alpha `119cf724-98f9-42d5-bf84-8391a41ee2c4`: `[gen-2]`;
  - coding beta `83e28924-8fad-485c-ad6f-8c9f9edd2be0`: `[gen-3]`;
  - queued alpha `541533a4-e0b4-4366-b823-db12a871200b`:
    `[gen-1, gen-2]`;
  - handback alpha `7d8e20f5-64c4-4448-8d23-268a820a4043`: `[gen-2]`;
  - handback beta `0095ac7e-d1a9-41f9-9ff8-3758cd0ae8ee`: `[]`.
- All four scenarios reached the exact lifecycle assertion and ended with no
  busy conversation. The Flutter run completed `+4` with all tests passed.
- Keep this slice in one focused Conventional Commit.

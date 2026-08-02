# Chat Tool-Result Observation Join: Codex Task

Status: Implemented and live-verified on 2026-08-02 against the private
169-definition snapshot captured from clean build `739957a5`.

## Task

- Goal: Structurally count logged tool-result submissions in a validated
  private corpus and prove that each submitted result belongs to the effective
  catalogue snapshot joined to that record's configuration segment.
- User-visible behavior: `--check-corpus-manifest` reports path-free aggregate
  coverage counts and rejects malformed result submissions or tools absent from
  the joined full catalogue.
- Non-goals: Do not infer success from result payloads, count model-requested
  calls as executions, emit tool names, derive guard action states, implement
  the static tool manifest, or produce the final residency report.

## Context

- Affected files or components:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - Phase 1 inventory status documents
- Related docs:
  - `docs/chat_notifier_inventory_codex_task.md`
  - `docs/chat_tool_catalogue_snapshot_validation_codex_task.md`
  - `docs/session_logs.md`
- Reference implementation or pattern: `SessionLoggingChatDataSource` writes
  executed results into the next request as either singleton `toolCallId` /
  `toolName` fields or a `toolResults` list. The older
  `tool/analyze_tool_results.py` demonstrates why replayed message text and
  grep counts are not valid execution evidence.
- Known quirks, compatibility rules, or release gates: A model response's
  `response.toolCalls` records requests, not completed execution. Request
  messages and rendered result text are replayed across later records and must
  not be counted.

## Implementation Notes

- Preferred approach:
  1. Recognize only the session logger's singleton and batch tool-result
     submission operations.
  2. Validate their normalized request shapes, non-empty call IDs and names,
     and unique IDs within a batch.
  3. Join each record by timestamp to its already validated configuration
     segment and require every submitted tool name to exist in that snapshot.
  4. Add aggregate submission, observed definition, and unobserved definition
     counts to the deterministic corpus summary.
- Constraints: Count each structured result item once in the record that
  submits it. Do not inspect result prose or arguments. Do not expose tool
  names, call IDs, private paths, or payloads in output or errors.
- Generated files needed: None.
- Migration or data compatibility concerns: Schema-v2 marker and ordinary LLM
  records without result submissions remain valid and contribute zero events.

## Similar-Pattern Search

- Search terms: `toolResults`, `toolCallId`, `toolName`,
  `createChatCompletionWithToolResult`, `streamWithToolResult`,
  `split_tool_sections`.
- Files or modules inspected:
  - `lib/features/chat/data/datasources/llm_session_log_store.dart`
  - `lib/features/chat/data/datasources/session_logging_chat_datasource.dart`
  - `tool/analyze_tool_results.py`
- Follow-up tasks found: Write a private deterministic measurement artifact
  containing definition-level rows after the static tool manifest is ready.

## Acceptance Criteria

- Required behavior: Valid singleton and batch submissions are counted once,
  joined to the correct segment snapshot, and reflected in deterministic
  aggregate coverage counts. Zero-observation definitions remain represented
  by the validated catalogue denominator.
- Edge cases: Multiple calls of one tool increase submissions but not observed
  definition coverage. The same tool name in different snapshots is a distinct
  configuration-specific definition observation.
- Failure paths: Missing or malformed request objects, empty IDs or names,
  duplicate batch IDs, incompatible operation shapes, and names absent from the
  joined snapshot fail with a concise path-free `InventoryError`.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-corpus-manifest /path/to/private/corpus.json
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Corpus validation now reads only normalized singleton and batch
  tool-result submissions, joins every submission to the timestamp-selected
  catalogue snapshot, and rejects names absent from that full catalogue. The
  version-2 path-free summary reports total submissions plus observed and
  unobserved configuration-specific definition counts.
- Tests run:
  - `python3 test/python/analyze_chat_notifier_inventory_test.py`: 34 passed.
  - A private live fixture joined one normalized submission to the clean
    169-definition snapshot and reported one observed plus 168 unobserved
    definitions.
  - A payload-free structural compatibility scan recognized 1,936 normalized
    submissions in 5,773 local schema-v2 records. It rejected 69 historical
    `streamChatCompletion` records carrying accumulated `toolResults`, because
    those replayed lists cannot establish one execution per item.
  - `tool/codex_verify.sh`: dependency installation, generated-file check,
    project and package analysis, and package tests passed. The full Flutter
    suite reached 6,482 passing tests and failed the same unrelated stale
    assertion in
    `test/tool/run_coding_stalled_diagnostic_repair_live_canary_test.dart`,
    which still requires the removed source text `.where(_isTodoVerifierCall)`.
- Coverage or low-coverage notes: Focused tests cover zero observations,
  singleton and batch submissions, repeated tools without coverage inflation,
  requested-but-unexecuted model calls, malformed request shapes, empty and
  duplicate IDs, incompatible operations, unknown catalogue names, timestamp
  segment selection, and deterministic private-field-free output.
- Risks or follow-ups: Definition-level private output remains a later slice.
  The pinned measurement corpus must use normalized result-submission records;
  historical accumulated-result records require exclusion rather than an
  inferred replay correction.

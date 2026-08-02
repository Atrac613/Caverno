# ChatNotifier Matching-Build Guard Capture Task

## Task

- Goal: Produce and validate one private, hash-pinned, clean matching-build
  session corpus and its complete catalogue snapshot for the Phase 1 guard
  action-state analysis.
- User-visible behavior: None. This is a private measurement slice.
- Non-goals: Change production logging, instrument another guard, delete the
  two unreachable delegates, migrate handlers, or commit private logs and
  catalogue definitions.

## Context

- Affected files or components:
  - private session logs, catalogue snapshot, corpus manifest, and analyser
    output under Caverno's private temporary storage;
  - `docs/chat_notifier_guard_reachability_inventory.md`;
  - `docs/chat_notifier_renewal_candidate_ranking.md`.
- Related docs:
  - `docs/chat_notifier_inventory_codex_task.md`;
  - `docs/chat_notifier_pinned_corpus_contract_codex_task.md`;
  - `docs/chat_tool_catalogue_snapshot_codex_task.md`.
- Reference implementation or pattern: Use the existing live-canary session
  logging, `caverno catalogue snapshot`, and
  `tool/analyze_chat_notifier_inventory.py` contracts.
- Known quirks, compatibility rules, or release gates: The source must be
  committed and clean before capture. Unknown or dirty build provenance cannot
  establish an action state. Session logs and dynamic catalogue definitions
  are sensitive and must not be committed.

## Implementation Notes

- Preferred approach:
  1. Commit this contract so the capture revision can be clean.
  2. Select the smallest existing live path that emits a schema-v2 session log
     with the covered recovery decision.
  3. Capture the complete effective catalogue from the same revision and
     configuration.
  4. Pin the exact files, hashes, time bounds, configuration fingerprint,
     capture command, and exporter revision in a private corpus manifest.
  5. Validate the manifest and run the dynamic inventory analyser twice to
     prove deterministic output.
- Constraints: Do not print API keys, MCP environment values, dynamic tool
  names, private paths, session identifiers, prompts, arguments, or results in
  checked-in documentation. Record only path-free counts, digests, timestamps,
  revisions, dirty states, and derived guard action states.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `CAVERNO_BUILD_COMMIT`, `CAVERNO_BUILD_DIRTY`,
  `completedToolResultFinalAnswerRecovery`, `catalogue snapshot`,
  `corpus-manifest`, and `configurationFingerprint`.
- Files or modules inspected: Build-provenance wrapper, live-canary runners,
  CLI catalogue capture, session-log store, analyser, and pinned-corpus docs.
- Follow-up tasks found: Delete the two orphan delegates only if the analyser
  derives `dead` without a contradiction; otherwise repair the proof.

## Acceptance Criteria

- Required behavior: The private manifest validates, represents the exact
  clean source revision, joins every record to one complete schema-v1 catalogue
  snapshot, and produces byte-identical analysis on two runs.
- Edge cases: An unavailable LLM endpoint, incomplete MCP discovery, unknown or
  dirty provenance, missing telemetry, hash mismatch, or configuration mismatch
  stops the measurement without changing action states.
- Failure paths: Preserve diagnostics privately and report only the path-free
  blocker in checked-in documentation.
- Accessibility, localization, or platform expectations: Not applicable.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-corpus-manifest /path/to/private/corpus.json
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --corpus-manifest /path/to/private/corpus.json \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --tool-manifest tool/chat_notifier_tool_catalog_inventory.json \
  --output /path/to/private/output.json
git diff --check
```

## Handoff Notes

- Summary: Captured and hash-pinned one clean matching-build corpus and complete
  catalogue snapshot. Added deterministic guard action-state derivation, fixed
  offset-free session timestamps, and accepted structured final-stream replays
  without double-counting tool submissions. The measurement derives 2 `dead`
  and 63 `unresolved` candidates.
- Tests run: All 47 focused Python analyser tests and all 16 focused
  session-logging Flutter tests pass. The private manifest validates and two
  analyser runs produce byte-identical output. The standard verifier passes
  generation, project and package analysis, package tests, and 6,481 of 6,482
  Flutter tests; only the unrelated stale
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart` fixture fails.
- Coverage or low-coverage notes: Runtime evidence depends on one bounded live
  capture and is not a production-frequency sample.
- Risks or follow-ups: The separate focused slice removed the two dead
  proposal-parsing delegates. The remaining 63 guard candidates stay
  unresolved.

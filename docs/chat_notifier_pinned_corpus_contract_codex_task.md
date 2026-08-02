# ChatNotifier Pinned Corpus Contract: Codex Task

## Task

- Goal: Make a private session-log corpus reproducible by validating its exact
  files, SHA-256 pins, build provenance, and configuration segments before any
  dynamic ChatNotifier measurement runs.
- User-visible behavior: None. This is offline analysis tooling only.
- Non-goals: Deriving guard action states, parsing telemetry firing counts,
  validating the static tool catalogue, selecting a second telemetry event, or
  changing production logging.

## Context

- Affected files or components:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - Phase 1 inventory and renewal status documents
- Related docs:
  - `docs/chat_notifier_inventory_codex_task.md`
  - `docs/chat_notifier_guard_reachability_inventory.md`
  - `docs/session_logs.md`
- Reference implementation or pattern: Existing exact-schema guard and
  telemetry-selection validators in `analyze_chat_notifier_inventory.py`.
- Known quirks, compatibility rules, or release gates:
  - Corpus manifests and their outputs are private and must not be committed.
  - Session logs can contain sensitive prompts, arguments, and results.
  - Schema-v2 logs always contain `build.commit` and `build.dirty`; `unknown`
    commit provenance is not valid measurement input.
  - Dirty-build observations may be retained as historical evidence but cannot
    establish a matching-build action state.

## Implementation Notes

- Preferred approach:
  1. Add a versioned exact-field corpus-manifest schema and a
     `--check-corpus-manifest` command.
  2. Resolve every declared build revision to a full Git commit. Accept a short
     revision only when Git resolves it unambiguously and it prefixes that
     commit.
  3. Read only listed JSONL files, verify each SHA-256 before parsing, and
     reject blank, malformed, non-session-log, or missing-provenance records.
  4. Require each file to declare complete, ordered, non-overlapping timestamp
     segments. Join every record to exactly one segment using logged timestamps.
  5. Pin each segment's full catalogue snapshot by path and SHA-256, and require
     a non-secret configuration fingerprint, capture command, and exporter
     revision. Snapshot content analysis remains a follow-up.
  6. Return a deterministic summary containing the corpus-manifest digest,
     file and record counts, logged date range, represented full build commits,
     and dirty-state markers.
- Constraints:
  - Paths may be absolute or relative to the private manifest directory.
  - Reject duplicate file paths, duplicate snapshot pins, unexpected fields,
    invalid SHA-256 strings, non-boolean dirty markers, and invalid timestamps.
  - A file-level build declaration must match every JSONL record in that file.
  - Segment boundaries use `startTimestampInclusive` and
    `endTimestampExclusive`.
  - Do not expose private paths or session identifiers in standard output.
  - `--corpus-manifest` with `--output` remains blocked until the dynamic
    measurement slice is implemented.
- Generated files needed: None.
- Migration or data compatibility concerns: None. Older logs without reliable
  v2 build provenance are rejected rather than guessed.

## Similar-Pattern Search

- Search terms: `corpus-manifest`, `build.commit`, `build.dirty`, `sha256`,
  `timestamp`, `configurationFingerprint`, `catalogueSnapshotPath`.
- Files or modules inspected:
  - `tool/analyze_chat_notifier_inventory.py`
  - `tool/triage_session_logs.py`
  - `lib/features/chat/data/datasources/llm_session_log_store.dart`
  - `lib/core/constants/build_info.dart`
- Follow-up tasks found: Parse the validated corpus into per-build guard
  observations, then derive action states only for a clean source-matching
  partition.

## Acceptance Criteria

- Required behavior:
  - A valid hash-pinned manifest produces a path-free deterministic summary.
  - Re-running validation with unchanged inputs produces byte-identical JSON.
  - Logged short commits are canonicalized to full unambiguous commits.
  - Every JSONL record is covered by exactly one pinned configuration segment.
- Edge cases:
  - Empty files, unknown builds, dirty builds, mixed builds in one file, and
    multiple files representing one build are handled explicitly.
  - Timestamp equality at adjacent segment boundaries joins only the later
    segment.
- Failure paths:
  - Missing files, hash mismatches, malformed lines, schema mismatches, invalid
    provenance, segment gaps or overlaps, out-of-range records, and snapshot
    hash mismatches fail with a concise `InventoryError`.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-corpus-manifest /path/to/private/corpus.json
python3 tool/analyze_chat_notifier_inventory.py --help
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: Dynamic measurement and action-state derivation remain
  explicitly out of scope.

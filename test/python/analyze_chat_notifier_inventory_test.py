#!/usr/bin/env python3
"""Focused tests for ``tool/analyze_chat_notifier_inventory.py``."""

import contextlib
import importlib.util
import hashlib
import io
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "analyze_chat_notifier_inventory",
    ROOT / "tool" / "analyze_chat_notifier_inventory.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load ChatNotifier inventory analyser")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


class ChatNotifierInventoryTest(unittest.TestCase):
    def _fixture(self, directory):
        root = pathlib.Path(directory)
        domain = root / analyzer.DOMAIN_ROOT
        providers = root / analyzer.NOTIFIER_ROOT
        domain.mkdir(parents=True)
        providers.mkdir(parents=True)
        (domain / "sample_guard.dart").write_text(
            "final class SampleGuard {}\n"
            "class SampleRecovery {}\n"
            "abstract final class SamplePolicy {}\n"
        )
        (providers / "chat_notifier_sample.dart").write_text(
            "part of 'chat_notifier.dart';\n\n"
            "extension SampleChatNotifier on ChatNotifier {\n"
            "  Future<void> _requestSampleRecovery() async {}\n"
            "  String _buildSampleRepairPrompt() => '';\n"
            "  Future<void> _runSample() async {\n"
            "    await _requestSampleRecovery();\n"
            "    _buildSampleRepairPrompt();\n"
            "  }\n"
            "}\n"
        )
        (providers / "chat_notifier_turn_finalization_recovery.dart").write_text(
            "part of 'chat_notifier.dart';\n\n"
            "extension FinalizationChatNotifier on ChatNotifier {\n"
            "  bool _shouldSkipCompletedToolResultFinalAnswerRecovery() => false;\n"
            "  void _finalizeTurn() {\n"
            "    _shouldSkipCompletedToolResultFinalAnswerRecovery();\n"
            "  }\n"
            "}\n"
        )
        return root

    def _manifest(self, root, *, exclude_prompt=True):
        candidates = analyzer.discover_guard_candidates(root)
        entries = []
        exclusions = []
        for candidate in candidates:
            if exclude_prompt and candidate["symbol"] == "_buildSampleRepairPrompt":
                exclusions.append(
                    {
                        **candidate,
                        "reason": "Prompt formatting does not select a recovery path.",
                    }
                )
                continue
            entries.append(
                {
                    **candidate,
                    "selectionRoots": analyzer.discover_lexical_selection_roots(
                        root, candidate
                    ),
                    "staticEdges": [
                        f"{selection_root} -> {candidate['symbol']}"
                        for selection_root in analyzer.discover_lexical_selection_roots(
                            root, candidate
                        )
                    ],
                    "reachabilityImpact": "may suppress a feature or recovery path",
                    "telemetryEvent": None,
                    "currentStaticState": "unresolved",
                    "staticProof": None,
                    "unresolvedEdges": ["Runtime callback dispatch is not resolved."],
                }
            )
        return {
            "schemaName": analyzer.SCHEMA_NAME,
            "schemaVersion": analyzer.SCHEMA_VERSION,
            "sourceRevision": "HEAD",
            "auditedSourceRoots": [
                rule["root"] for rule in analyzer.DISCOVERY_RULES
            ],
            "discoveryRules": list(analyzer.DISCOVERY_RULES),
            "explicitExclusions": exclusions,
            "entries": entries,
        }

    def _write_manifest(self, root, manifest):
        path = root / "guard_inventory.json"
        path.write_text(json.dumps(manifest))
        return path

    def _selection(self, manifest):
        target_entries = [
            entry for entry in manifest["entries"] if entry["telemetryEvent"] is None
        ]
        instrument_id = next(
            entry["id"]
            for entry in target_entries
            if entry["symbol"]
            == "_shouldSkipCompletedToolResultFinalAnswerRecovery"
        )
        entries = []
        for entry in target_entries:
            if entry["id"] == instrument_id:
                entries.append(
                    {
                        "id": entry["id"],
                        "disposition": "instrument",
                        "question": "Which final-answer recovery branch ran?",
                        "reason": "The turn-exit boundary can carry the decision.",
                        "event": (
                            "turn_exit.guardDecisions."
                            "completedToolResultFinalAnswerRecovery"
                        ),
                        "recordedValues": [
                            "not_evaluated",
                            "skip_recovery",
                            "allow_recovery",
                        ],
                        "dataClassification": "metadata_only",
                        "verification": ["focused recovery test"],
                    }
                )
            else:
                entries.append(
                    {
                        "id": entry["id"],
                        "disposition": "defer",
                        "question": f"Was {entry['symbol']} evaluated?",
                        "reason": "Keep the first slice to one decision event.",
                        "prerequisite": "Re-rank after the first slice.",
                    }
                )
        return {
            "schemaName": analyzer.TELEMETRY_SELECTION_SCHEMA_NAME,
            "schemaVersion": analyzer.TELEMETRY_SELECTION_SCHEMA_VERSION,
            "sourceRevision": manifest["sourceRevision"],
            "guardManifest": "guard_inventory.json",
            "firstSliceLimit": 1,
            "entries": entries,
        }

    def _write_selection(self, root, selection):
        path = root / "telemetry_selection.json"
        path.write_text(json.dumps(selection))
        return path

    def _mark_first_slice_covered(self, manifest, selection):
        guard_entry = next(
            entry
            for entry in manifest["entries"]
            if entry["id"] == analyzer.FIRST_TELEMETRY_SLICE_ID
        )
        guard_entry["telemetryEvent"] = analyzer.FIRST_TELEMETRY_SLICE_EVENT
        selection_entry = next(
            entry
            for entry in selection["entries"]
            if entry["id"] == analyzer.FIRST_TELEMETRY_SLICE_ID
        )
        selection_entry["disposition"] = "covered"

    def _sha256(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _write_corpus_fixture(self, directory):
        root = pathlib.Path(directory)
        commit = analyzer.resolve_source_revision(ROOT, "HEAD")
        first_snapshot = root / "catalogue-a.json"
        second_snapshot = root / "catalogue-b.json"
        first_snapshot.write_text('{"tools":["first"]}\n')
        second_snapshot.write_text('{"tools":["second"]}\n')
        session_path = root / "session.jsonl"
        records = [
            {
                "schemaName": analyzer.SESSION_LOG_SCHEMA_NAME,
                "schemaVersion": 2,
                "timestamp": "2026-08-02T00:15:00Z",
                "build": {"commit": commit[:10], "dirty": False},
                "operation": "turn_exit",
            },
            {
                "schemaName": analyzer.SESSION_LOG_SCHEMA_NAME,
                "schemaVersion": 2,
                "timestamp": "2026-08-02T00:30:00+00:00",
                "build": {"commit": commit[:12], "dirty": False},
                "operation": "turn_exit",
            },
        ]
        session_path.write_text(
            "".join(f"{json.dumps(record)}\n" for record in records)
        )
        manifest = {
            "schemaName": analyzer.CORPUS_MANIFEST_SCHEMA_NAME,
            "schemaVersion": analyzer.CORPUS_MANIFEST_SCHEMA_VERSION,
            "files": [
                {
                    "path": session_path.name,
                    "sha256": self._sha256(session_path),
                    "buildRevision": commit[:8],
                    "dirty": False,
                    "segments": [
                        {
                            "startTimestampInclusive": "2026-08-02T00:00:00Z",
                            "endTimestampExclusive": "2026-08-02T00:30:00Z",
                            "configurationFingerprint": "config-a",
                            "catalogueSnapshotPath": first_snapshot.name,
                            "catalogueSnapshotSha256": self._sha256(first_snapshot),
                            "snapshotCaptureCommand": "capture catalogue a",
                            "exporterRevision": "exporter-v1",
                        },
                        {
                            "startTimestampInclusive": "2026-08-02T00:30:00Z",
                            "endTimestampExclusive": "2026-08-02T01:00:00Z",
                            "configurationFingerprint": "config-b",
                            "catalogueSnapshotPath": second_snapshot.name,
                            "catalogueSnapshotSha256": self._sha256(second_snapshot),
                            "snapshotCaptureCommand": "capture catalogue b",
                            "exporterRevision": "exporter-v1",
                        },
                    ],
                }
            ],
        }
        manifest_path = root / "corpus.json"
        self._write_corpus_manifest(manifest_path, manifest)
        return manifest_path, manifest, session_path, records, commit

    def _write_corpus_manifest(self, path, manifest):
        path.write_text(json.dumps(manifest, sort_keys=True))

    def _rewrite_session(self, path, records, manifest, manifest_path):
        path.write_text("".join(f"{json.dumps(record)}\n" for record in records))
        manifest["files"][0]["sha256"] = self._sha256(path)
        self._write_corpus_manifest(manifest_path, manifest)

    def test_discovers_types_and_notifier_members_deterministically(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            candidates = analyzer.discover_guard_candidates(root)

        self.assertEqual(
            [candidate["symbol"] for candidate in candidates],
            [
                "SampleGuard",
                "SamplePolicy",
                "SampleRecovery",
                "_buildSampleRepairPrompt",
                "_requestSampleRecovery",
                "_shouldSkipCompletedToolResultFinalAnswerRecovery",
            ],
        )

    def test_accepts_exact_entries_and_explicit_exclusions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            path = self._write_manifest(root, manifest)

            counts = analyzer.validate_guard_manifest(path, root)

        self.assertEqual(counts, {"discovered": 6, "entries": 5, "exclusions": 1})

    def test_rejects_unrepresented_discovery_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest["entries"].pop()
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(analyzer.InventoryError, "unrepresented"):
                analyzer.validate_guard_manifest(path, root)

    def test_rejects_stale_manifest_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest["entries"][0]["symbol"] = "RemovedGuard"
            manifest["entries"][0]["id"] = (
                f"{manifest['entries'][0]['path']}::RemovedGuard"
            )
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(analyzer.InventoryError, "stale"):
                analyzer.validate_guard_manifest(path, root)

    def test_rejects_incomplete_evidence_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            del manifest["entries"][0]["unresolvedEdges"]
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "missing fields: unresolvedEdges"
            ):
                analyzer.validate_guard_manifest(path, root)

    def test_rejects_identifier_that_does_not_match_path_and_symbol(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest["entries"][0]["id"] = "renamed-without-source-identity"
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(analyzer.InventoryError, "id must be"):
                analyzer.validate_guard_manifest(path, root)

    def test_rejects_stale_lexical_selection_roots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest["entries"][-1]["selectionRoots"] = []
            manifest["entries"][-1]["staticEdges"] = []
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "selectionRoots are stale"
            ):
                analyzer.validate_guard_manifest(path, root)

    def test_requires_closed_proof_for_unreachable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            candidate = next(
                entry
                for entry in manifest["entries"]
                if entry["symbol"] == "SampleGuard"
            )
            candidate["currentStaticState"] = "unreachable"
            candidate["staticProof"] = "No production selection root exists."
            path = self._write_manifest(root, manifest)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "unresolved edges"
            ):
                analyzer.validate_guard_manifest(path, root)

    def test_accepts_complete_telemetry_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection_path = self._write_selection(
                root, self._selection(manifest)
            )

            counts = analyzer.validate_telemetry_selection(
                selection_path, manifest_path, root
            )

        self.assertEqual(
            counts,
            {"selected": 5, "instrument": 1, "covered": 0, "defer": 4},
        )

    def test_accepts_completed_first_slice_telemetry_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            selection = self._selection(manifest)
            self._mark_first_slice_covered(manifest, selection)
            manifest_path = self._write_manifest(root, manifest)
            selection_path = self._write_selection(root, selection)

            counts = analyzer.validate_telemetry_selection(
                selection_path, manifest_path, root
            )

        self.assertEqual(
            counts,
            {"selected": 5, "instrument": 0, "covered": 1, "defer": 4},
        )

    def test_rejects_incomplete_telemetry_selection_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            selection["entries"].pop(0)
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(analyzer.InventoryError, "missing"):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_duplicate_telemetry_selection_id(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            selection["entries"].append(dict(selection["entries"][0]))
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(analyzer.InventoryError, "Duplicate"):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_deferred_selection_for_mapped_event(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            selection = self._selection(manifest)
            manifest["entries"][0]["telemetryEvent"] = "turn_exit.existing"
            manifest_path = self._write_manifest(root, manifest)
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "cannot defer an already mapped event"
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_non_metadata_instrument_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            instrument = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "instrument"
            )
            instrument["dataClassification"] = "payload"
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(analyzer.InventoryError, "metadata_only"):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_covered_selection_without_existing_event(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            deferred = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "defer"
            )
            deferred.clear()
            deferred.update(
                {
                    "id": manifest["entries"][0]["id"],
                    "disposition": "covered",
                    "question": "Was the decision covered?",
                    "reason": "An existing event may cover it.",
                    "verification": ["focused event test"],
                }
            )
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "missing fields: .*event"
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_deferred_selection_with_event(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            deferred = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "defer"
            )
            deferred["event"] = "turn_exit.unexpected"
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "unexpected fields: event"
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_deferred_selection_without_prerequisite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            deferred = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "defer"
            )
            del deferred["prerequisite"]
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "missing fields: prerequisite"
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_changed_first_slice_recorded_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            instrument = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "instrument"
            )
            instrument["recordedValues"] = ["skip_recovery", "allow_recovery"]
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError,
                "first bounded recordedValues",
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_more_than_one_instrument_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            manifest_path = self._write_manifest(root, manifest)
            selection = self._selection(manifest)
            deferred = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "defer"
            )
            identifier = deferred["id"]
            deferred.clear()
            deferred.update(
                {
                    "id": identifier,
                    "disposition": "instrument",
                    "question": "Which branch ran?",
                    "reason": "Instrument another decision.",
                    "event": "turn_exit.anotherDecision",
                    "recordedValues": ["not_evaluated", "selected"],
                    "dataClassification": "metadata_only",
                    "verification": ["focused test"],
                }
            )
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError, "exactly one instrument or covered"
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_rejects_covered_event_that_disagrees_with_guard_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            selection = self._selection(manifest)
            self._mark_first_slice_covered(manifest, selection)
            covered = next(
                entry
                for entry in selection["entries"]
                if entry["disposition"] == "covered"
            )
            covered["event"] = "turn_exit.guardDecisions.wrong"
            manifest_path = self._write_manifest(root, manifest)
            selection_path = self._write_selection(root, selection)

            with self.assertRaisesRegex(
                analyzer.InventoryError,
                "event must match the guard inventory mapping",
            ):
                analyzer.validate_telemetry_selection(
                    selection_path, manifest_path, root
                )

    def test_accepts_hash_pinned_corpus_with_exact_segment_join(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, _, _, _, commit = self._write_corpus_fixture(directory)

            first = analyzer.validate_corpus_manifest(manifest_path, ROOT)
            second = analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertEqual(first, second)
        self.assertEqual(first["fileCount"], 1)
        self.assertEqual(first["recordCount"], 2)
        self.assertEqual(first["configurationSegmentCount"], 2)
        self.assertEqual(first["catalogueSnapshotCount"], 2)
        self.assertEqual(
            first["loggedRange"],
            {
                "startTimestampInclusive": "2026-08-02T00:15:00Z",
                "endTimestampInclusive": "2026-08-02T00:30:00Z",
            },
        )
        self.assertEqual(
            first["representedBuilds"],
            [{"commit": commit, "dirty": False}],
        )
        self.assertNotIn(directory, json.dumps(first, sort_keys=True))

    def test_check_corpus_manifest_cli_prints_only_the_json_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, _, _, _, _ = self._write_corpus_fixture(directory)
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                exit_code = analyzer.main(
                    ["--check-corpus-manifest", str(manifest_path)]
                )

        self.assertEqual(exit_code, 0)
        decoded = json.loads(output.getvalue())
        self.assertEqual(decoded["fileCount"], 1)
        self.assertNotIn(directory, output.getvalue())

    def test_rejects_missing_mismatched_empty_and_malformed_corpus_files(self):
        scenarios = (
            ("missing", "does not exist or is not a file"),
            ("hash", "SHA-256 does not match"),
            ("empty", "at least one JSONL record"),
            ("malformed", "invalid JSON"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, session_path, _, _ = (
                    self._write_corpus_fixture(directory)
                )
                if scenario == "missing":
                    manifest["files"][0]["path"] = "missing.jsonl"
                    self._write_corpus_manifest(manifest_path, manifest)
                elif scenario == "hash":
                    manifest["files"][0]["sha256"] = "0" * 64
                    self._write_corpus_manifest(manifest_path, manifest)
                else:
                    session_path.write_text("" if scenario == "empty" else "not-json\n")
                    manifest["files"][0]["sha256"] = self._sha256(session_path)
                    self._write_corpus_manifest(manifest_path, manifest)

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

    def test_rejects_unreliable_or_mixed_build_provenance(self):
        scenarios = (
            ("unknown", "unambiguous Git commit hash"),
            ("dirty", "build.dirty does not match"),
            ("mixed", "build.commit does not match"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, session_path, records, _ = (
                    self._write_corpus_fixture(directory)
                )
                if scenario == "unknown":
                    records[0]["build"]["commit"] = "unknown"
                elif scenario == "dirty":
                    records[0]["build"]["dirty"] = True
                else:
                    records[0]["build"]["commit"] = analyzer.resolve_source_revision(
                        ROOT, "HEAD^"
                    )
                self._rewrite_session(
                    session_path, records, manifest, manifest_path
                )

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

    def test_rejects_segment_gaps_overlaps_and_uncovered_records(self):
        scenarios = (
            ("gap", "timestamp gap"),
            ("overlap", "timestamp overlap"),
            ("uncovered", "exactly one configuration segment"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, session_path, records, _ = (
                    self._write_corpus_fixture(directory)
                )
                if scenario == "gap":
                    manifest["files"][0]["segments"][1][
                        "startTimestampInclusive"
                    ] = "2026-08-02T00:31:00Z"
                    self._write_corpus_manifest(manifest_path, manifest)
                elif scenario == "overlap":
                    manifest["files"][0]["segments"][1][
                        "startTimestampInclusive"
                    ] = "2026-08-02T00:29:00Z"
                    self._write_corpus_manifest(manifest_path, manifest)
                else:
                    records[0]["timestamp"] = "2026-08-01T23:59:59Z"
                    self._rewrite_session(
                        session_path, records, manifest, manifest_path
                    )

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

    def test_rejects_unpinned_or_duplicate_catalogue_snapshots(self):
        scenarios = (
            ("hash", "SHA-256 does not match"),
            ("duplicate", "Duplicate catalogue snapshot pin"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, _, _, _ = self._write_corpus_fixture(
                    directory
                )
                segments = manifest["files"][0]["segments"]
                if scenario == "hash":
                    segments[0]["catalogueSnapshotSha256"] = "0" * 64
                else:
                    segments[1]["catalogueSnapshotPath"] = segments[0][
                        "catalogueSnapshotPath"
                    ]
                    segments[1]["catalogueSnapshotSha256"] = segments[0][
                        "catalogueSnapshotSha256"
                    ]
                self._write_corpus_manifest(manifest_path, manifest)

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

    def test_rejects_unexpected_corpus_fields_and_invalid_timestamps(self):
        scenarios = (
            ("field", "unexpected fields"),
            ("timezone", "must include a UTC offset"),
            ("range", "positive range"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, _, _, _ = self._write_corpus_fixture(
                    directory
                )
                segment = manifest["files"][0]["segments"][0]
                if scenario == "field":
                    manifest["files"][0]["sessionId"] = "private"
                elif scenario == "timezone":
                    segment["startTimestampInclusive"] = "2026-08-02T00:00:00"
                else:
                    segment["endTimestampExclusive"] = segment[
                        "startTimestampInclusive"
                    ]
                self._write_corpus_manifest(manifest_path, manifest)

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)


if __name__ == "__main__":
    unittest.main()

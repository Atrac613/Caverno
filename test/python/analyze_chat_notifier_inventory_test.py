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

    def _catalogue_snapshot(self, commit, *names):
        definitions = [
            {
                "type": "function",
                "x-caverno-fixture-source": "test",
                "function": {
                    "description": f"Fixture definition {index}",
                    "name": name,
                    "parameters": {"properties": {}, "type": "object"},
                },
            }
            for index, name in enumerate(sorted(names), 1)
        ]
        fingerprint_payload = json.dumps(
            {"toolDefinitions": definitions},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
        return {
            "schema": analyzer.CATALOGUE_SNAPSHOT_SCHEMA_NAME,
            "version": analyzer.CATALOGUE_SNAPSHOT_SCHEMA_VERSION,
            "exporterRevision": analyzer.CATALOGUE_SNAPSHOT_EXPORTER_REVISION,
            "capturedAt": "2026-08-01T23:55:00Z",
            "build": {
                "commit": commit[:10],
                "dirty": False,
                "builtAt": "2026-08-01T23:50:00Z",
            },
            "configurationFingerprint": "sha256:"
            + hashlib.sha256(fingerprint_payload).hexdigest(),
            "toolCount": len(definitions),
            "toolDefinitions": definitions,
        }

    def _write_snapshot(self, path, snapshot):
        path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")

    def _write_corpus_fixture(self, directory):
        root = pathlib.Path(directory)
        commit = analyzer.resolve_source_revision(ROOT, "HEAD")
        first_snapshot = root / "catalogue-a.json"
        second_snapshot = root / "catalogue-b.json"
        first_catalogue = self._catalogue_snapshot(commit, "first")
        second_catalogue = self._catalogue_snapshot(commit, "second", "shared")
        self._write_snapshot(first_snapshot, first_catalogue)
        self._write_snapshot(second_snapshot, second_catalogue)
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
                            "configurationFingerprint": first_catalogue[
                                "configurationFingerprint"
                            ],
                            "catalogueSnapshotPath": first_snapshot.name,
                            "catalogueSnapshotSha256": self._sha256(first_snapshot),
                            "snapshotCaptureCommand": "capture catalogue a",
                            "exporterRevision": first_catalogue[
                                "exporterRevision"
                            ],
                        },
                        {
                            "startTimestampInclusive": "2026-08-02T00:30:00Z",
                            "endTimestampExclusive": "2026-08-02T01:00:00Z",
                            "configurationFingerprint": second_catalogue[
                                "configurationFingerprint"
                            ],
                            "catalogueSnapshotPath": second_snapshot.name,
                            "catalogueSnapshotSha256": self._sha256(second_snapshot),
                            "snapshotCaptureCommand": "capture catalogue b",
                            "exporterRevision": second_catalogue[
                                "exporterRevision"
                            ],
                        },
                    ],
                }
            ],
        }
        manifest_path = root / "corpus.json"
        self._write_corpus_manifest(manifest_path, manifest)
        return manifest_path, manifest, session_path, records, commit

    def _rewrite_snapshot(self, manifest_path, manifest, index, snapshot):
        segment = manifest["files"][0]["segments"][index]
        snapshot_path = manifest_path.parent / segment["catalogueSnapshotPath"]
        self._write_snapshot(snapshot_path, snapshot)
        segment["catalogueSnapshotSha256"] = self._sha256(snapshot_path)
        self._write_corpus_manifest(manifest_path, manifest)

    def _write_corpus_manifest(self, path, manifest):
        path.write_text(json.dumps(manifest, sort_keys=True))

    def _rewrite_session(self, path, records, manifest, manifest_path):
        path.write_text("".join(f"{json.dumps(record)}\n" for record in records))
        manifest["files"][0]["sha256"] = self._sha256(path)
        self._write_corpus_manifest(manifest_path, manifest)

    def _tool_result_record(self, commit, timestamp, operation, request):
        return {
            "schemaName": analyzer.SESSION_LOG_SCHEMA_NAME,
            "schemaVersion": 2,
            "timestamp": timestamp,
            "build": {"commit": commit[:10], "dirty": False},
            "operation": operation,
            "request": request,
        }

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
            manifest_path, manifest, _, _, commit = self._write_corpus_fixture(
                directory
            )
            expected_fingerprints = sorted(
                segment["configurationFingerprint"]
                for segment in manifest["files"][0]["segments"]
            )

            first = analyzer.validate_corpus_manifest(manifest_path, ROOT)
            second = analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertEqual(first, second)
        self.assertEqual(first["schemaVersion"], 2)
        self.assertEqual(first["fileCount"], 1)
        self.assertEqual(first["recordCount"], 2)
        self.assertEqual(first["configurationSegmentCount"], 2)
        self.assertEqual(first["catalogueSnapshotCount"], 2)
        self.assertEqual(first["catalogueDefinitionCount"], 3)
        self.assertEqual(first["catalogueExporterRevisions"], ["1"])
        self.assertEqual(first["toolResultSubmissionCount"], 0)
        self.assertEqual(first["observedCatalogueDefinitionCount"], 0)
        self.assertEqual(first["unobservedCatalogueDefinitionCount"], 3)
        self.assertEqual(
            first["catalogueConfigurationFingerprints"],
            expected_fingerprints,
        )
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

    def test_counts_structured_tool_result_submissions_by_joined_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, manifest, session_path, records, commit = (
                self._write_corpus_fixture(directory)
            )
            records[:] = [
                self._tool_result_record(
                    commit,
                    "2026-08-02T00:15:00Z",
                    "streamWithToolResult",
                    {
                        "toolCallId": "call-first",
                        "toolName": "first",
                        "toolArguments": {},
                        "toolResult": {"ok": True},
                    },
                ),
                self._tool_result_record(
                    commit,
                    "2026-08-02T00:30:00Z",
                    "createChatCompletionWithToolResults",
                    {
                        "toolResults": [
                            {
                                "id": "call-second",
                                "name": "second",
                                "arguments": {},
                                "result": {"ok": True},
                            },
                            {
                                "id": "call-shared",
                                "name": "shared",
                                "arguments": {},
                                "result": {"ok": False},
                            },
                        ]
                    },
                ),
            ]
            self._rewrite_session(session_path, records, manifest, manifest_path)

            summary = analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertEqual(summary["toolResultSubmissionCount"], 3)
        self.assertEqual(summary["observedCatalogueDefinitionCount"], 3)
        self.assertEqual(summary["unobservedCatalogueDefinitionCount"], 0)

    def test_counts_repeated_results_without_inflating_definition_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, manifest, session_path, records, commit = (
                self._write_corpus_fixture(directory)
            )
            records[:] = [
                self._tool_result_record(
                    commit,
                    "2026-08-02T00:30:00Z",
                    "createChatCompletionWithToolResults",
                    {
                        "toolResults": [
                            {
                                "id": f"call-{index}",
                                "name": "second",
                                "arguments": {},
                                "result": {},
                            }
                            for index in range(2)
                        ]
                    },
                )
            ]
            self._rewrite_session(session_path, records, manifest, manifest_path)

            summary = analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertEqual(summary["toolResultSubmissionCount"], 2)
        self.assertEqual(summary["observedCatalogueDefinitionCount"], 1)
        self.assertEqual(summary["unobservedCatalogueDefinitionCount"], 2)

    def test_does_not_count_model_requested_tool_calls_as_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, manifest, session_path, records, commit = (
                self._write_corpus_fixture(directory)
            )
            records[:] = [
                {
                    **self._tool_result_record(
                        commit,
                        "2026-08-02T00:15:00Z",
                        "streamChatCompletionWithTools",
                        {"messages": [], "tools": []},
                    ),
                    "response": {
                        "content": "",
                        "toolCalls": [
                            {"id": "requested", "name": "absent", "arguments": {}}
                        ],
                    },
                }
            ]
            self._rewrite_session(session_path, records, manifest, manifest_path)

            summary = analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertEqual(summary["toolResultSubmissionCount"], 0)
        self.assertEqual(summary["observedCatalogueDefinitionCount"], 0)

    def test_rejects_malformed_or_unjoined_tool_result_submissions(self):
        scenarios = (
            ("unknown", "absent from its catalogue snapshot"),
            ("request", "request must be an object"),
            ("empty_id", "toolCallId must be non-empty"),
            ("duplicate", "toolResults has duplicate IDs"),
            ("batch_shape", "missing fields"),
            ("operation", "incompatible operation"),
            ("mixed", "incompatible batch result field"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, session_path, records, commit = (
                    self._write_corpus_fixture(directory)
                )
                operation = "streamWithToolResult"
                request = {
                    "toolCallId": "call-first",
                    "toolName": "first",
                    "toolArguments": {},
                    "toolResult": {},
                }
                timestamp = "2026-08-02T00:15:00Z"
                if scenario == "unknown":
                    request["toolName"] = "private_absent_tool"
                elif scenario == "request":
                    request = None
                elif scenario == "empty_id":
                    request["toolCallId"] = " "
                elif scenario in {"duplicate", "batch_shape"}:
                    operation = "createChatCompletionWithToolResults"
                    timestamp = "2026-08-02T00:30:00Z"
                    item = {
                        "id": "duplicate",
                        "name": "second",
                        "arguments": {},
                        "result": {},
                    }
                    request = {
                        "toolResults": [dict(item), dict(item)]
                    }
                    if scenario == "batch_shape":
                        request["toolResults"][0].pop("result")
                elif scenario == "operation":
                    operation = "streamChatCompletionWithTools"
                else:
                    request["toolResults"] = []
                records[:] = [
                    self._tool_result_record(
                        commit,
                        timestamp,
                        operation,
                        request,
                    )
                ]
                self._rewrite_session(
                    session_path, records, manifest, manifest_path
                )

                with self.assertRaisesRegex(
                    analyzer.InventoryError, expected
                ) as context:
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

                self.assertNotIn("private_absent_tool", str(context.exception))

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

    def test_rejects_malformed_catalogue_snapshot_schema_and_definitions(self):
        scenarios = (
            ("schema", "schema is unsupported"),
            ("field", "unexpected fields"),
            ("count", "toolCount must match"),
            ("unsorted", "must be sorted by name"),
            ("duplicate", "names must be unique"),
            ("definition", "missing fields"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, _, _, _ = self._write_corpus_fixture(
                    directory
                )
                segment = manifest["files"][0]["segments"][1]
                snapshot_path = (
                    manifest_path.parent / segment["catalogueSnapshotPath"]
                )
                snapshot = json.loads(snapshot_path.read_text())
                if scenario == "schema":
                    snapshot["schema"] = "unsupported"
                elif scenario == "field":
                    snapshot["privatePath"] = "/private/catalogue"
                elif scenario == "count":
                    snapshot["toolCount"] += 1
                elif scenario == "unsorted":
                    snapshot["toolDefinitions"].reverse()
                elif scenario == "duplicate":
                    snapshot["toolDefinitions"][1]["function"]["name"] = "second"
                else:
                    snapshot["toolDefinitions"][0].pop("function")
                self._rewrite_snapshot(manifest_path, manifest, 1, snapshot)

                with self.assertRaisesRegex(analyzer.InventoryError, expected):
                    analyzer.validate_corpus_manifest(manifest_path, ROOT)

    def test_rejects_invalid_catalogue_snapshot_json_without_exposing_path(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest_path, manifest, _, _, _ = self._write_corpus_fixture(
                directory
            )
            segment = manifest["files"][0]["segments"][0]
            snapshot_path = manifest_path.parent / segment["catalogueSnapshotPath"]
            snapshot_path.write_text("not-json\n")
            segment["catalogueSnapshotSha256"] = self._sha256(snapshot_path)
            self._write_corpus_manifest(manifest_path, manifest)

            with self.assertRaises(analyzer.InventoryError) as context:
                analyzer.validate_corpus_manifest(manifest_path, ROOT)

        self.assertIn("catalogueSnapshot is invalid JSON", str(context.exception))
        self.assertNotIn(directory, str(context.exception))

    def test_rejects_catalogue_fingerprint_and_segment_provenance_drift(self):
        scenarios = (
            ("fingerprint", "does not match its definitions"),
            ("segment", "does not match its segment declaration"),
            ("exporter", "exporterRevision does not match"),
            ("commit", "build.commit does not match"),
            ("dirty", "build.dirty does not match"),
            ("builtAt", "must include a UTC offset"),
        )
        for scenario, expected in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as directory:
                manifest_path, manifest, _, _, _ = self._write_corpus_fixture(
                    directory
                )
                segment = manifest["files"][0]["segments"][0]
                snapshot_path = (
                    manifest_path.parent / segment["catalogueSnapshotPath"]
                )
                snapshot = json.loads(snapshot_path.read_text())
                if scenario == "fingerprint":
                    snapshot["toolDefinitions"][0]["function"][
                        "description"
                    ] = "Changed after capture"
                    self._rewrite_snapshot(manifest_path, manifest, 0, snapshot)
                elif scenario == "segment":
                    segment["configurationFingerprint"] = "sha256:" + "0" * 64
                    self._write_corpus_manifest(manifest_path, manifest)
                elif scenario == "exporter":
                    segment["exporterRevision"] = "2"
                    self._write_corpus_manifest(manifest_path, manifest)
                elif scenario == "commit":
                    snapshot["build"]["commit"] = analyzer.resolve_source_revision(
                        ROOT, "HEAD^"
                    )
                    self._rewrite_snapshot(manifest_path, manifest, 0, snapshot)
                elif scenario == "dirty":
                    snapshot["build"]["dirty"] = True
                    self._rewrite_snapshot(manifest_path, manifest, 0, snapshot)
                else:
                    snapshot["build"]["builtAt"] = "2026-08-01T23:50:00"
                    self._rewrite_snapshot(manifest_path, manifest, 0, snapshot)

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

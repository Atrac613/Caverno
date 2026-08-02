#!/usr/bin/env python3
"""Focused tests for ``tool/analyze_chat_notifier_inventory.py``."""

import importlib.util
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


if __name__ == "__main__":
    unittest.main()

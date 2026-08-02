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
            ],
        )

    def test_accepts_exact_entries_and_explicit_exclusions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self._fixture(directory)
            manifest = self._manifest(root)
            path = self._write_manifest(root, manifest)

            counts = analyzer.validate_guard_manifest(path, root)

        self.assertEqual(counts, {"discovered": 5, "entries": 4, "exclusions": 1})

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


if __name__ == "__main__":
    unittest.main()

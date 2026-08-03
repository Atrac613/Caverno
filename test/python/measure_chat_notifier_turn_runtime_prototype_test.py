#!/usr/bin/env python3
"""Focused tests for the TurnRuntime prototype selector."""

import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "measure_chat_notifier_turn_runtime_prototype",
    ROOT / "tool" / "measure_chat_notifier_turn_runtime_prototype.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load the TurnRuntime prototype selector")
selector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(selector)


class TurnRuntimePrototypeSelectorTest(unittest.TestCase):
    def _git(self, root, *arguments):
        result = subprocess.run(
            ["git", *arguments],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            self.fail(result.stderr or result.stdout)
        return result.stdout.strip()

    def _part(
        self,
        name,
        *,
        identity_entrypoints=0,
        ambient_reads=0,
        production_lines=1,
    ):
        declarations = [
            {
                "name": f"_{name}Entry{index}",
                "identity": index < identity_entrypoints,
            }
            for index in range(max(1, identity_entrypoints))
        ]
        return {
            "partPath": f"chat_notifier_{name}.dart",
            "declarations": declarations,
            "ambientReads": ambient_reads,
            "productionLines": production_lines,
        }

    def _fixture(self, directory, parts=None):
        base = pathlib.Path(directory)
        root = base / "repo"
        provider_root = root / selector.PROVIDER_ROOT
        tool_root = root / "tool"
        provider_root.mkdir(parents=True)
        tool_root.mkdir()
        parts = parts or [self._part("alpha", identity_entrypoints=1)]

        audit_entrypoints = []
        audit_methods = []
        audit_reads = []
        manifest_parts = []
        for part in parts:
            part_path = part["partPath"]
            source_relative = (selector.PROVIDER_ROOT / part_path).as_posix()
            (root / source_relative).write_text(
                "// production line\n" * part["productionLines"]
            )
            declaration_names = [
                declaration["name"] for declaration in part["declarations"]
            ]
            audit_entrypoints.append(
                {"partPath": part_path, "declarations": declaration_names}
            )
            manifest_parts.append(
                {
                    "id": part_path.removeprefix("chat_notifier_").removesuffix(
                        ".dart"
                    ),
                    "partPath": part_path,
                    "entrypoints": declaration_names,
                    "status": "partial",
                    "collaborators": [],
                }
            )
            for declaration in part["declarations"]:
                audit_methods.append(
                    {
                        "path": source_relative,
                        "declaration": declaration["name"],
                        "entrypoint": True,
                        "turnReachable": True,
                        "turnIdentityParameters": (
                            ["required ChatTurnOwner owner"]
                            if declaration["identity"]
                            else []
                        ),
                    }
                )
            for index in range(part["ambientReads"]):
                audit_reads.append(
                    {
                        "id": f"{source_relative}::read#{index}",
                        "path": source_relative,
                        "declaration": declaration_names[0],
                        "turnReachable": True,
                    }
                )
            audit_reads.append(
                {
                    "id": f"{source_relative}::unreachable",
                    "path": source_relative,
                    "declaration": declaration_names[0],
                    "turnReachable": False,
                }
            )

        audit_path = tool_root / "audit.json"
        manifest_path = tool_root / "manifest.json"
        audit = {
            "schemaName": selector.AUDIT_SCHEMA_NAME,
            "schemaVersion": selector.AUDIT_SCHEMA_VERSION,
            "manifestPath": "tool/manifest.json",
            "entrypoints": audit_entrypoints,
            "methods": audit_methods,
            "reads": audit_reads,
        }
        manifest = {
            "schemaName": selector.MANIFEST_SCHEMA_NAME,
            "schemaVersion": selector.MANIFEST_SCHEMA_VERSION,
            "parts": manifest_parts,
        }
        audit_path.write_text(json.dumps(audit, indent=2) + "\n")
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

        self._git(root, "init", "-q")
        self._git(root, "config", "user.name", "Selector Test")
        self._git(root, "config", "user.email", "selector@example.invalid")
        self._git(root, "add", ".")
        self._git(root, "commit", "-qm", "fixture")
        return root, audit_path, manifest_path, audit, manifest

    def _select(
        self,
        root,
        audit_path,
        manifest_path,
        *,
        source_revision="HEAD",
        require_clean=False,
    ):
        return selector.build_selection(
            root=root,
            audit_path=audit_path,
            manifest_path=manifest_path,
            source_revision=source_revision,
            require_clean=require_clean,
        )

    def _verification_fixture(self, directory):
        root, audit_path, manifest_path, _, _ = self._fixture(directory)
        selected_source = (
            root / selector.PROVIDER_ROOT / "chat_notifier_alpha.dart"
        )
        selected_source.write_text("void _alphaEntry0(ChatTurnOwner owner) {}\n")
        focused_executable = root / "test/focused_test.dart"
        focused_declaration = root / "test/focused_part.dart"
        live_runner = root / "tool/run_live.sh"
        live_test = root / "tool/live_test.dart"
        focused_executable.parent.mkdir(parents=True)
        focused_executable.write_text("part 'focused_part.dart';\n")
        focused_declaration.write_text(
            "test('focused gate', () {});\nfocused evidence\n"
        )
        live_runner.write_text(
            "flutter test tool/live_test.dart --plain-name \"live gate\"\n"
        )
        live_test.write_text("test('live gate', () {});\nlive evidence\n")
        verification_path = root / "tool/verification.json"
        verification = {
            "schemaName": selector.VERIFICATION_SCHEMA_NAME,
            "schemaVersion": selector.VERIFICATION_SCHEMA_VERSION,
            "selectedPart": {
                "partPath": "chat_notifier_alpha.dart",
                "sourcePath": (
                    selector.PROVIDER_ROOT / "chat_notifier_alpha.dart"
                ).as_posix(),
                "migratedPathSymbols": ["_alphaEntry0"],
            },
            "focusedTest": {
                "command": (
                    "flutter test test/focused_test.dart "
                    '--plain-name "focused gate"'
                ),
                "executablePath": "test/focused_test.dart",
                "declarationPath": "test/focused_part.dart",
                "testName": "focused gate",
                "contract": "The focused path emits its expected evidence.",
                "expectedEvidence": [
                    {
                        "id": "focused",
                        "description": "Focused evidence is asserted.",
                        "sourcePath": "test/focused_part.dart",
                        "requiredText": ["focused evidence"],
                    }
                ],
            },
            "liveCanary": {
                "command": "tool/run_live.sh",
                "runnerPath": "tool/run_live.sh",
                "testPath": "tool/live_test.dart",
                "testName": "live gate",
                "contract": "The live path emits its expected evidence.",
                "expectedEvidence": [
                    {
                        "id": "live",
                        "description": "Live evidence is asserted.",
                        "sourcePath": "tool/live_test.dart",
                        "requiredText": ["live evidence"],
                    }
                ],
            },
        }
        verification_path.write_text(json.dumps(verification, indent=2) + "\n")
        self._git(root, "add", ".")
        self._git(root, "commit", "-qm", "verification fixture")
        selection_path = pathlib.Path(directory) / "selection.json"
        self._refresh_selection(
            root, audit_path, manifest_path, selection_path
        )
        return (
            root,
            audit_path,
            manifest_path,
            selection_path,
            verification_path,
            verification,
        )

    def _refresh_selection(
        self, root, audit_path, manifest_path, selection_path
    ):
        selection = self._select(
            root,
            audit_path,
            manifest_path,
            require_clean=True,
        )
        selector.write_json_atomic(selection_path, selection)
        return selection

    def _commit_verification_change(
        self,
        *,
        root,
        audit_path,
        manifest_path,
        selection_path,
        verification_path,
        verification,
    ):
        verification_path.write_text(json.dumps(verification, indent=2) + "\n")
        self._git(root, "add", str(verification_path.relative_to(root)))
        self._git(root, "commit", "-qm", "change verification")
        self._refresh_selection(root, audit_path, manifest_path, selection_path)

    def test_ranks_all_current_parts_by_the_four_required_keys(self):
        parts = [
            self._part("alpha", identity_entrypoints=2, production_lines=1),
            self._part(
                "beta",
                identity_entrypoints=1,
                ambient_reads=2,
                production_lines=1,
            ),
            self._part(
                "gamma",
                identity_entrypoints=1,
                ambient_reads=1,
                production_lines=10,
            ),
            self._part(
                "delta",
                identity_entrypoints=1,
                ambient_reads=1,
                production_lines=5,
            ),
            self._part("epsilon", production_lines=3),
            self._part("zeta", production_lines=3),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(
                directory, parts
            )
            selection = self._select(root, audit_path, manifest_path)

        self.assertEqual(
            [candidate["partPath"] for candidate in selection["candidates"]],
            [
                "chat_notifier_alpha.dart",
                "chat_notifier_beta.dart",
                "chat_notifier_gamma.dart",
                "chat_notifier_delta.dart",
                "chat_notifier_epsilon.dart",
                "chat_notifier_zeta.dart",
            ],
        )
        self.assertEqual(selection["selected"]["rank"], 1)
        self.assertEqual(
            selection["selected"]["turnReachableIdentityEntrypoints"]["count"],
            2,
        )
        self.assertEqual(
            selection["selected"]["turnReachableAmbientReads"]["count"], 0
        )

    def test_conversation_context_is_not_an_explicit_turn_identity(self):
        parts = [
            self._part("context", identity_entrypoints=1, production_lines=10),
            self._part("owner", identity_entrypoints=1, production_lines=1),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, audit, _ = self._fixture(
                directory, parts
            )
            audit["methods"][0]["turnIdentityParameters"] = [
                "Conversation conversation"
            ]
            audit_path.write_text(json.dumps(audit, indent=2) + "\n")

            selection = self._select(root, audit_path, manifest_path)

        self.assertEqual(
            selection["selected"]["partPath"], "chat_notifier_owner.dart"
        )
        context = next(
            candidate
            for candidate in selection["candidates"]
            if candidate["partPath"] == "chat_notifier_context.dart"
        )
        self.assertEqual(
            context["turnReachableIdentityEntrypoints"]["count"], 0
        )

    def test_explicit_turn_identity_parameter_contract(self):
        self.assertTrue(
            selector._is_explicit_turn_identity_parameter(
                "required ChatTurnOwner? owner"
            )
        )
        self.assertTrue(
            selector._is_explicit_turn_identity_parameter(
                "required int interactionGeneration"
            )
        )
        self.assertTrue(
            selector._is_explicit_turn_identity_parameter("int generation")
        )
        self.assertFalse(
            selector._is_explicit_turn_identity_parameter(
                "Conversation conversation"
            )
        )
        self.assertFalse(
            selector._is_explicit_turn_identity_parameter(
                "int generationBudget"
            )
        )

    def test_binds_inputs_and_resolves_head_to_a_full_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            selection = self._select(root, audit_path, manifest_path)
            head = self._git(root, "rev-parse", "HEAD")
            audit_sha256 = hashlib.sha256(audit_path.read_bytes()).hexdigest()
            manifest_sha256 = hashlib.sha256(
                manifest_path.read_bytes()
            ).hexdigest()

        self.assertEqual(selection["sourceRevision"], head)
        self.assertEqual(len(selection["sourceRevision"]), 40)
        self.assertEqual(selection["inputs"]["audit"]["path"], "tool/audit.json")
        self.assertEqual(
            selection["inputs"]["audit"]["sha256"], audit_sha256
        )
        self.assertEqual(
            selection["inputs"]["manifest"]["sha256"], manifest_sha256
        )

    def test_selection_is_deterministic(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            first = self._select(root, audit_path, manifest_path)
            second = self._select(root, audit_path, manifest_path)

        self.assertEqual(
            json.dumps(first, sort_keys=True), json.dumps(second, sort_keys=True)
        )

    def test_require_clean_rejects_changes_but_optional_mode_accepts_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            (root / "untracked.txt").write_text("dirty\n")

            with self.assertRaisesRegex(
                selector.SelectionError, "requires a clean worktree"
            ):
                self._select(
                    root,
                    audit_path,
                    manifest_path,
                    require_clean=True,
                )
            selection = self._select(
                root, audit_path, manifest_path, require_clean=False
            )

        self.assertEqual(selection["selected"]["partPath"], "chat_notifier_alpha.dart")

    def test_reports_worktree_only_changes_with_their_full_path(self):
        # Porcelain prints a leading space for a worktree-only change, and the
        # first such line is the one a trailing strip() would shorten, taking a
        # character off the reported path with it.
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            tracked = selector.PROVIDER_ROOT / "chat_notifier_alpha.dart"
            (root / tracked).write_text("// edited\n")

            with self.assertRaises(selector.SelectionError) as raised:
                self._select(
                    root,
                    audit_path,
                    manifest_path,
                    require_clean=True,
                )

        self.assertIn(tracked.as_posix(), str(raised.exception))

    def test_rejects_a_source_revision_other_than_checked_out_head(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            (root / "second.txt").write_text("second\n")
            self._git(root, "add", "second.txt")
            self._git(root, "commit", "-qm", "second")

            with self.assertRaisesRegex(
                selector.SelectionError, "checked-out HEAD commit"
            ):
                self._select(
                    root,
                    audit_path,
                    manifest_path,
                    source_revision="HEAD~1",
                )

    def test_rejects_duplicate_current_part_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, audit, _ = self._fixture(directory)
            audit["entrypoints"].append(dict(audit["entrypoints"][0]))
            audit_path.write_text(json.dumps(audit))

            with self.assertRaisesRegex(
                selector.SelectionError, "duplicate partPath"
            ):
                self._select(root, audit_path, manifest_path)

    def test_rejects_a_current_part_missing_from_the_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, manifest = self._fixture(directory)
            manifest["parts"] = []
            manifest_path.write_text(json.dumps(manifest))

            with self.assertRaisesRegex(
                selector.SelectionError, "missing from manifest"
            ):
                self._select(root, audit_path, manifest_path)

    def test_rejects_a_missing_current_source_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            source_path = (
                root / selector.PROVIDER_ROOT / "chat_notifier_alpha.dart"
            )
            source_path.unlink()

            with self.assertRaisesRegex(
                selector.SelectionError, "source does not exist"
            ):
                self._select(root, audit_path, manifest_path)

    def test_rejects_an_ambiguous_audited_entrypoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, audit, _ = self._fixture(directory)
            audit["methods"].append(dict(audit["methods"][0]))
            audit_path.write_text(json.dumps(audit))

            with self.assertRaisesRegex(
                selector.SelectionError, "exactly one audited method"
            ):
                self._select(root, audit_path, manifest_path)

    def test_records_an_unresolved_historical_entrypoint(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, audit, _ = self._fixture(directory)
            audit["methods"] = []
            audit_path.write_text(json.dumps(audit))

            selection = self._select(root, audit_path, manifest_path)

        self.assertEqual(selection["selected"]["declaredEntrypoints"], 1)
        self.assertEqual(selection["selected"]["resolvedEntrypoints"], 0)
        self.assertEqual(
            selection["selected"]["unresolvedEntrypoints"], ["_alphaEntry0"]
        )
        self.assertEqual(
            selection["selected"]["turnReachableIdentityEntrypoints"]["count"],
            0,
        )

    def test_cli_failure_does_not_write_a_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            output_path = pathlib.Path(directory) / "selection.json"
            (root / "dirty.txt").write_text("dirty\n")
            stderr = io.StringIO()

            with mock.patch.object(selector, "repository_root", return_value=root):
                with contextlib.redirect_stderr(stderr):
                    exit_code = selector.main(
                        [
                            "select",
                            "--audit",
                            str(audit_path),
                            "--manifest",
                            str(manifest_path),
                            "--source-revision",
                            "HEAD",
                            "--require-clean",
                            "--output",
                            str(output_path),
                        ]
                    )

        self.assertEqual(exit_code, 2)
        self.assertIn("error: Prototype selection requires", stderr.getvalue())
        self.assertFalse(output_path.exists())

    def test_cli_writes_the_selection_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            root, audit_path, manifest_path, _, _ = self._fixture(directory)
            output_path = pathlib.Path(directory) / "selection.json"
            stdout = io.StringIO()

            with mock.patch.object(selector, "repository_root", return_value=root):
                with contextlib.redirect_stdout(stdout):
                    exit_code = selector.main(
                        [
                            "select",
                            "--audit",
                            str(audit_path),
                            "--manifest",
                            str(manifest_path),
                            "--source-revision",
                            "HEAD",
                            "--require-clean",
                            "--output",
                            str(output_path),
                        ]
                    )
            output = json.loads(output_path.read_text())

        self.assertEqual(exit_code, 0)
        self.assertEqual(output["schemaName"], selector.SELECTION_SCHEMA_NAME)
        self.assertIn("chat_notifier_alpha.dart", stdout.getvalue())

    def test_validate_gates_binds_focused_and_live_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            (
                root,
                _,
                _,
                selection_path,
                verification_path,
                _,
            ) = self._verification_fixture(directory)

            validated = selector.validate_gates(
                root=root,
                selection_path=selection_path,
                verification_manifest_path=verification_path,
            )

        self.assertEqual(
            validated["schemaName"], selector.VALIDATED_SELECTION_SCHEMA_NAME
        )
        self.assertEqual(
            validated["selected"]["partPath"], "chat_notifier_alpha.dart"
        )
        self.assertEqual(
            validated["verification"]["selectedPart"]["migratedPathSymbols"],
            ["_alphaEntry0"],
        )
        self.assertFalse(validated["liveCanaryExecuted"])

    def test_validate_gates_rejects_a_selected_part_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._verification_fixture(directory)
            (
                root,
                audit_path,
                manifest_path,
                selection_path,
                verification_path,
                verification,
            ) = fixture
            verification["selectedPart"]["partPath"] = (
                "chat_notifier_other.dart"
            )
            self._commit_verification_change(
                root=root,
                audit_path=audit_path,
                manifest_path=manifest_path,
                selection_path=selection_path,
                verification_path=verification_path,
                verification=verification,
            )

            with self.assertRaisesRegex(
                selector.SelectionError, "does not match the selected part"
            ):
                selector.validate_gates(
                    root=root,
                    selection_path=selection_path,
                    verification_manifest_path=verification_path,
                )

    def test_validate_gates_rejects_a_tampered_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            (
                root,
                _,
                _,
                selection_path,
                verification_path,
                _,
            ) = self._verification_fixture(directory)
            selection = json.loads(selection_path.read_text())
            selection["selected"]["productionLines"] += 1
            selection_path.write_text(json.dumps(selection))

            with self.assertRaisesRegex(
                selector.SelectionError, "does not match the current audited ranking"
            ):
                selector.validate_gates(
                    root=root,
                    selection_path=selection_path,
                    verification_manifest_path=verification_path,
                )

    def test_validate_gates_rejects_a_missing_command(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._verification_fixture(directory)
            (
                root,
                audit_path,
                manifest_path,
                selection_path,
                verification_path,
                verification,
            ) = fixture
            verification["focusedTest"]["command"] = ""
            self._commit_verification_change(
                root=root,
                audit_path=audit_path,
                manifest_path=manifest_path,
                selection_path=selection_path,
                verification_path=verification_path,
                verification=verification,
            )

            with self.assertRaisesRegex(
                selector.SelectionError, "focusedTest.command"
            ):
                selector.validate_gates(
                    root=root,
                    selection_path=selection_path,
                    verification_manifest_path=verification_path,
                )

    def test_validate_gates_rejects_a_symbol_outside_the_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._verification_fixture(directory)
            (
                root,
                audit_path,
                manifest_path,
                selection_path,
                verification_path,
                verification,
            ) = fixture
            verification["selectedPart"]["migratedPathSymbols"] = [
                "_notSelected"
            ]
            self._commit_verification_change(
                root=root,
                audit_path=audit_path,
                manifest_path=manifest_path,
                selection_path=selection_path,
                verification_path=verification_path,
                verification=verification,
            )

            with self.assertRaisesRegex(
                selector.SelectionError, "not a selected identity entrypoint"
            ):
                selector.validate_gates(
                    root=root,
                    selection_path=selection_path,
                    verification_manifest_path=verification_path,
                )

    def test_validate_gates_rejects_missing_evidence_text(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._verification_fixture(directory)
            (
                root,
                audit_path,
                manifest_path,
                selection_path,
                verification_path,
                verification,
            ) = fixture
            verification["liveCanary"]["expectedEvidence"][0][
                "requiredText"
            ] = ["missing live evidence"]
            self._commit_verification_change(
                root=root,
                audit_path=audit_path,
                manifest_path=manifest_path,
                selection_path=selection_path,
                verification_path=verification_path,
                verification=verification,
            )

            with self.assertRaisesRegex(
                selector.SelectionError, "is missing from"
            ):
                selector.validate_gates(
                    root=root,
                    selection_path=selection_path,
                    verification_manifest_path=verification_path,
                )

    def test_validate_gates_cli_writes_an_atomic_output(self):
        with tempfile.TemporaryDirectory() as directory:
            (
                root,
                _,
                _,
                selection_path,
                verification_path,
                _,
            ) = self._verification_fixture(directory)
            output_path = pathlib.Path(directory) / "validated.json"
            stdout = io.StringIO()

            with mock.patch.object(selector, "repository_root", return_value=root):
                with contextlib.redirect_stdout(stdout):
                    exit_code = selector.main(
                        [
                            "validate-gates",
                            "--selection",
                            str(selection_path),
                            "--verification-manifest",
                            str(verification_path),
                            "--output",
                            str(output_path),
                        ]
                    )
            output = json.loads(output_path.read_text())

        self.assertEqual(exit_code, 0)
        self.assertEqual(
            output["schemaName"], selector.VALIDATED_SELECTION_SCHEMA_NAME
        )
        self.assertIn("live canary not executed", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()

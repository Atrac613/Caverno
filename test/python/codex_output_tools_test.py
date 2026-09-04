#!/usr/bin/env python3
"""Regression tests for repository-side bounded output tools."""

from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import tempfile
import textwrap
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
CODEX_RG = ROOT / "tool" / "codex_rg.sh"
AGENT_OUTPUT = ROOT / "tool" / "agent_output.sh"
FLUTTER_TEST_QUIET = ROOT / "tool" / "flutter_test_quiet.sh"
CODEX_VERIFY = ROOT / "tool" / "codex_verify.sh"


def _write_executable(path: Path, body: str) -> None:
    path.write_text(textwrap.dedent(body).lstrip(), encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class CodexRgTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)

    def tearDown(self) -> None:
        self.temp_directory.cleanup()

    def run_rg(
        self,
        *arguments: str,
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        merged_environment = os.environ.copy()
        if environment:
            merged_environment.update(environment)
        return subprocess.run(
            [str(CODEX_RG), *arguments],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
            env=merged_environment,
        )

    def test_reports_bounded_path_sorted_hits_and_keeps_complete_json(self) -> None:
        (self.root / "z.txt").write_text("needle three\n", encoding="utf-8")
        (self.root / "a.txt").write_text(
            "needle one\nneedle needle two\n",
            encoding="utf-8",
        )
        output = self.root / "reports" / "search.jsonl"

        result = self.run_rg(
            "--max-hits",
            "2",
            "--output",
            str(output),
            "--",
            "needle",
            ".",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MATCHES: 4 across 3 lines in 2 files", result.stdout)
        self.assertIn("First 2 matching lines", result.stdout)
        self.assertIn("a.txt:1", result.stdout)
        self.assertIn("a.txt:2", result.stdout)
        self.assertNotIn("z.txt:1", result.stdout)
        self.assertIn("1 more matching lines omitted", result.stdout)
        self.assertTrue(output.is_file())
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        events = [json.loads(line) for line in output.read_text().splitlines()]
        self.assertEqual(sum(event.get("type") == "match" for event in events), 3)

    def test_fails_closed_for_non_match_output_modes(self) -> None:
        output = self.root / "files.txt"

        result = self.run_rg("--output", str(output), "--", "--files", ".")

        self.assertEqual(result.returncode, 65)
        self.assertIn("non-JSON output", result.stderr)
        self.assertIn("rerun this mode with --raw", result.stderr)
        self.assertTrue(output.exists())
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_fails_closed_when_rg_returns_non_json_output(self) -> None:
        binary_directory = self.root / "bin"
        binary_directory.mkdir()
        _write_executable(
            binary_directory / "rg",
            """
            #!/usr/bin/env bash
            echo UNEXPECTED_OUTPUT
            exit 0
            """,
        )
        output = self.root / "unexpected.jsonl"

        result = self.run_rg(
            "--output",
            str(output),
            "--",
            "needle",
            ".",
            environment={"PATH": f"{binary_directory}:{os.environ.get('PATH', '')}"},
        )

        self.assertEqual(result.returncode, 65)
        self.assertIn("non-JSON output", result.stderr)
        self.assertIn("rerun this mode with --raw", result.stderr)
        self.assertEqual(output.read_text().strip(), "UNEXPECTED_OUTPUT")
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_preserves_no_match_status_and_artifact(self) -> None:
        (self.root / "input.txt").write_text("haystack\n", encoding="utf-8")
        output = self.root / "no-match.jsonl"

        result = self.run_rg("--output", str(output), "--", "needle", ".")

        self.assertEqual(result.returncode, 1)
        self.assertIn("NO MATCHES", result.stdout)
        self.assertTrue(output.is_file())

    def test_preserves_invalid_pattern_status_and_diagnostics(self) -> None:
        output = self.root / "invalid.jsonl"

        result = self.run_rg("--output", str(output), "--", "[", ".")

        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR: rg exited with status 2", result.stderr)
        self.assertIn("regex parse error", result.stdout)
        self.assertTrue(output.is_file())
        self.assertTrue(Path(f"{output}.stderr").is_file())

    def test_handles_unicode_paths_and_binary_text_mode(self) -> None:
        directory = self.root / "dir with space"
        directory.mkdir()
        binary = directory / "日本.bin"
        binary.write_bytes(b"needle\x00tail\n")
        output = self.root / "binary.jsonl"

        result = self.run_rg(
            "--output",
            str(output),
            "--",
            "--text",
            "needle",
            ".",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dir with space/日本.bin:1", result.stdout)
        self.assertIn("\\u0000", json.dumps(result.stdout))

    def test_clips_long_lines_and_raw_mode_remains_unbounded(self) -> None:
        (self.root / "long.txt").write_text(
            f"needle {'x' * 100}\n",
            encoding="utf-8",
        )
        output = self.root / "long.jsonl"
        bounded = self.run_rg(
            "--max-line-chars",
            "12",
            "--output",
            str(output),
            "--",
            "needle",
            ".",
        )
        raw = self.run_rg("--raw", "--", "needle", ".")

        self.assertEqual(bounded.returncode, 0, bounded.stderr)
        self.assertIn("chars omitted", bounded.stdout)
        self.assertEqual(raw.returncode, 0, raw.stderr)
        self.assertIn("x" * 80, raw.stdout)
        self.assertNotIn("Full JSON result", raw.stdout)


class AgentOutputTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self.harness = self.root / "run.sh"
        _write_executable(
            self.harness,
            f"""
            #!/usr/bin/env bash
            set -euo pipefail
            source {AGENT_OUTPUT!s}
            agent_output_run "$1" "fixture command" "$2" bash -c "$3"
            """,
        )

    def tearDown(self) -> None:
        self.temp_directory.cleanup()

    def run_output(
        self,
        mode: str,
        command: str,
        *,
        environment: dict[str, str] | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], Path]:
        log = self.root / f"{mode}.log"
        merged_environment = os.environ.copy()
        if environment:
            merged_environment.update(environment)
        result = subprocess.run(
            [str(self.harness), str(log), mode, command],
            text=True,
            capture_output=True,
            check=False,
            env=merged_environment,
        )
        return result, log

    def test_quiet_mode_keeps_success_output_only_in_log(self) -> None:
        result, log = self.run_output("quiet", "echo QUIET_SENTINEL")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("QUIET_SENTINEL", result.stdout)
        self.assertIn("Finished fixture command with status 0", result.stdout)
        self.assertEqual(log.read_text().strip(), "QUIET_SENTINEL")
        self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)

    def test_quiet_failure_preserves_status_and_bounded_tail(self) -> None:
        command = "echo BEGIN_SENTINEL; for i in $(seq 1 50); do echo row-$i; done; exit 7"
        result, log = self.run_output("quiet", command)

        self.assertEqual(result.returncode, 7)
        self.assertNotIn("BEGIN_SENTINEL", result.stdout)
        self.assertIn("row-50", result.stdout)
        self.assertIn("Diagnostic tail (40 lines maximum)", result.stdout)
        self.assertIn("BEGIN_SENTINEL", log.read_text())

    def test_quiet_mode_emits_heartbeats_for_long_commands(self) -> None:
        result, _ = self.run_output(
            "quiet",
            "sleep 0.15",
            environment={"CAVERNO_AGENT_OUTPUT_HEARTBEAT_SECONDS": "0.05"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Still running fixture command", result.stdout)

    def test_raw_mode_streams_and_saves_output(self) -> None:
        result, log = self.run_output("raw", "echo RAW_SENTINEL")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RAW_SENTINEL", result.stdout)
        self.assertEqual(log.read_text().strip(), "RAW_SENTINEL")
        self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)

    def test_raw_failure_preserves_command_status(self) -> None:
        result, log = self.run_output("raw", "echo RAW_FAILURE_SENTINEL; exit 9")

        self.assertEqual(result.returncode, 9)
        self.assertIn("RAW_FAILURE_SENTINEL", result.stdout)
        self.assertIn("RAW_FAILURE_SENTINEL", log.read_text())

    def test_quiet_mode_handles_signals_and_reaps_children(self) -> None:
        for sent_signal, expected_status in (
            (signal.SIGINT, 130),
            (signal.SIGTERM, 143),
        ):
            with self.subTest(signal=sent_signal):
                suffix = sent_signal.name.lower()
                log = self.root / f"interrupted-{suffix}.log"
                child_pid_path = self.root / f"child-{suffix}.pid"
                command = (
                    f'trap "exit 0" INT TERM; echo $$ > "{child_pid_path}"; '
                    "while true; do sleep 0.1; done"
                )
                process = subprocess.Popen(
                    [str(self.harness), str(log), "quiet", command],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    start_new_session=True,
                )
                deadline = time.monotonic() + 3
                while not child_pid_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(child_pid_path.exists(), "child process did not start")
                child_pid = int(child_pid_path.read_text().strip())

                try:
                    os.kill(process.pid, sent_signal)
                    stdout, stderr = process.communicate(timeout=5)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.communicate()

                self.assertEqual(process.returncode, expected_status, stderr)
                self.assertIn(
                    f"Finished fixture command with status {expected_status}",
                    stdout,
                )
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)


class ScriptIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.environment = os.environ.copy()
        self.environment["PATH"] = f"{self.bin}:{self.environment.get('PATH', '')}"

    def tearDown(self) -> None:
        self.temp_directory.cleanup()

    def run_script(
        self,
        script: str,
        arguments: list[str],
        environment: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        merged_environment = self.environment.copy()
        if environment:
            merged_environment.update(environment)
        return subprocess.run(
            ["bash", str(ROOT / "tool" / script), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
            env=merged_environment,
        )

    def test_flutter_verbose_streams_while_quiet_default_only_captures(self) -> None:
        _write_executable(
            self.bin / "fvm",
            r'''
            #!/usr/bin/env bash
            json_log=""
            for argument in "$@"; do
              case "${argument}" in
                json:*) json_log="${argument#json:}" ;;
              esac
            done
            printf '%s\n' \
              '{"type":"suite","suite":{"id":1,"path":"fixture_test.dart"}}' \
              '{"type":"allSuites","count":1}' \
              '{"type":"testStart","time":0,"test":{"id":1,"name":"fixture","suiteID":1}}' \
              '{"type":"testDone","time":1,"testID":1,"result":"success","hidden":false,"skipped":false}' \
              '{"type":"done","success":true}' >"${json_log}"
            echo FLUTTER_VERBOSE_SENTINEL
            ''',
        )
        report_directory = self.root / "flutter-report"
        environment = {"CAVERNO_TEST_REPORT_DIR": str(report_directory)}

        quiet = subprocess.run(
            [str(FLUTTER_TEST_QUIET)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
            env={**self.environment, **environment},
        )
        verbose = subprocess.run(
            [str(FLUTTER_TEST_QUIET), "--verbose"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
            env={**self.environment, **environment},
        )

        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertNotIn("FLUTTER_VERBOSE_SENTINEL", quiet.stdout)
        self.assertEqual(verbose.returncode, 0, verbose.stderr)
        self.assertIn("FLUTTER_VERBOSE_SENTINEL", verbose.stdout)
        self.assertIn(
            "FLUTTER_VERBOSE_SENTINEL",
            (report_directory / "flutter_test_stdout.txt").read_text(),
        )

    def test_release_quiet_output_preserves_complete_lane_log(self) -> None:
        _write_executable(
            self.bin / "fvm",
            """
            #!/usr/bin/env bash
            echo RELEASE_NOISE_SENTINEL
            exit 0
            """,
        )
        log_directory = self.root / "release-logs"
        result = self.run_script(
            "release_ios_macos.sh",
            [
                "--only",
                "ios",
                "--ios-signing-style",
                "automatic",
                "--no-pub-get",
                "--quiet-output",
                "--ios-export-root",
                str(self.root / "ios-export"),
                "--release-log-dir",
                str(log_directory),
            ],
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("RELEASE_NOISE_SENTINEL", result.stdout)
        logs = list(log_directory.glob("*.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("RELEASE_NOISE_SENTINEL", logs[0].read_text())

    def test_publish_quiet_output_preserves_complete_appcast_log(self) -> None:
        artifact = self.root / "Caverno-1.0.0-1.zip"
        artifact.write_bytes(b"artifact")
        generator = self.root / "generate_appcast"
        _write_executable(
            generator,
            """
            #!/usr/bin/env bash
            echo APPCAST_NOISE_SENTINEL
            exit 0
            """,
        )
        updates = self.root / "updates"
        result = self.run_script(
            "publish_macos_sparkle_release.sh",
            [
                "--artifact",
                str(artifact),
                "--download-url-prefix",
                "https://example.com/releases",
                "--skip-upload",
                "--quiet-output",
                "--updates-dir",
                str(updates),
                "--sparkle-generate-appcast",
                str(generator),
            ],
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("APPCAST_NOISE_SENTINEL", result.stdout)
        logs = list((updates / "logs").glob("*.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("APPCAST_NOISE_SENTINEL", logs[0].read_text())

    def test_turn_steering_quiet_and_raw_modes_preserve_snapshots(self) -> None:
        _write_executable(
            self.bin / "flutter",
            r'''
            #!/usr/bin/env bash
            for i in $(seq 1 20); do echo TURN_NOISE_$i; done
            echo 'TURN_STEERING_CANARY_SNAPSHOT {"arm":"steer","redirected":true,"steerCarriedInRequests":true,"directiveCarriedInRequests":true,"alphaCreated":false}'
            ''',
        )
        common_environment = {
            "CAVERNO_LLM_BASE_URL": "http://127.0.0.1:1234/v1",
            "CAVERNO_LLM_API_KEY": "fixture",
            "CAVERNO_LLM_MODEL": "fixture",
            "CAVERNO_TURN_STEERING_CANARY_REPORT_ROOT": str(self.root / "turn"),
        }

        quiet = self.run_script(
            "run_turn_steering_live_canary.sh",
            ["--quiet-output"],
            common_environment,
        )
        raw = self.run_script(
            "run_turn_steering_live_canary.sh",
            ["--raw-output"],
            {**common_environment, "CAVERNO_TURN_STEERING_CANARY_REPORT_ROOT": str(self.root / "turn-raw")},
        )

        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertNotIn("TURN_NOISE_1\n", quiet.stdout)
        self.assertIn("steer: 1/1 runs matched", quiet.stdout)
        self.assertEqual(raw.returncode, 0, raw.stderr)
        self.assertIn("TURN_NOISE_1\n", raw.stdout)

    def test_pro_reasoning_quiet_output_preserves_complete_log(self) -> None:
        _write_executable(
            self.bin / "fvm",
            """
            #!/usr/bin/env bash
            echo PRO_REASONING_NOISE_SENTINEL
            exit 0
            """,
        )
        report_root = self.root / "pro"
        result = self.run_script(
            "run_pro_reasoning_live_canary.sh",
            ["--quiet-output"],
            {
                "CAVERNO_LIVE_LLM_DATA_EXPORT_ACK": "1",
                "CAVERNO_LLM_BASE_URL": "http://127.0.0.1:1234/v1",
                "CAVERNO_LLM_API_KEY": "fixture",
                "CAVERNO_LLM_MODEL": "fixture-primary",
                "CAVERNO_PRO_REASONING_SECONDARY_BASE_URL": "http://127.0.0.1:1235/v1",
                "CAVERNO_PRO_REASONING_SECONDARY_API_KEY": "fixture",
                "CAVERNO_PRO_REASONING_SECONDARY_MODEL": "fixture-secondary",
                "CAVERNO_PRO_REASONING_LIVE_CANARY_REPORT_ROOT": str(report_root),
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("PRO_REASONING_NOISE_SENTINEL", result.stdout)
        logs = list(report_root.glob("*/flutter_test.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("PRO_REASONING_NOISE_SENTINEL", logs[0].read_text())


class CodexVerifyContractTest(unittest.TestCase):
    def test_focused_analysis_skips_notification_relay_check(self) -> None:
        source = CODEX_VERIFY.read_text(encoding="utf-8")

        self.assertIn(
            '[[ -f "$NOTIFICATION_RELAY_DIR/package.json" ]] && ! $FOCUSED',
            source,
        )


if __name__ == "__main__":
    unittest.main()

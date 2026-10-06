import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:caverno/features/chat/domain/services/command_verification_reconciliation.dart';
import 'package:caverno/features/chat/domain/services/project_task_step_completion_policy.dart';
import 'package:caverno/features/chat/domain/services/pytest_verification_identity.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno/features/chat/domain/services/unresolved_verification_failure.dart';
import 'package:caverno/features/chat/domain/services/verification_metadata_query_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final missing = command(
    'missing',
    'python3 -m pytest test_retry.py -v 2>&1 | tail -30',
    stdout: '/opt/python/bin/python3.14: No module named pytest',
  );
  final feedback = const CodingCommandOutputGuardrailService()
      .buildFeedbackToolResult(toolResults: [missing])!;
  final success = command(
    'success',
    '.venv/bin/python -m pytest test_retry.py -v 2>&1 | tail -40',
  );

  test('settles a cd-prefixed failure only in its effective directory', () {
    final prefixed = command(
      'prefixed',
      'cd /workspace && python3 -m pytest test_retry.py -v 2>&1 | tail -30',
      directory: '/parent',
      stdout: 'python3: No module named pytest',
    );
    final failed = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [prefixed])!;
    final passed = command(
      'passed',
      'cd /workspace && .venv/bin/python -m pytest test_retry.py -v 2>&1 | tail -40',
      directory: '/parent',
    );
    expect(
      ToolResultPromptBuilder.completionEvidence([
        prefixed,
        failed,
        passed,
      ]).unresolvedErrorCount,
      0,
    );
    expect(
      ToolResultPromptBuilder.completionEvidence([
        prefixed,
        failed,
        command(
          'other-root',
          passed.arguments['command'] as String,
          directory: '/parent',
          stdout: '2 failed, 4 passed in 0.1s',
        ),
      ]).unresolvedErrorCount,
      1,
    );
  });

  test(
    'settles a failed interpreter invocation with the matching venv verifier',
    () {
      final results = [missing, feedback, success];
      final evidence = ToolResultPromptBuilder.completionEvidence(results);
      expect(evidence.unresolvedErrorCount, 0);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(
        ToolResultPromptBuilder.completionBlockerInstructions(results),
        isEmpty,
      );
      expect(
        ToolResultPromptBuilder.formatToolResults(results),
        isNot(contains('No module named')),
      );
      expect(
        results,
        hasLength(3),
        reason: 'the raw audit results are preserved',
      );
    },
  );

  for (final variant in [
    'other target',
    'other directory',
    'other flags',
    'unknown shell',
    'unknown counts',
    'no tests',
    'failed tests',
    'timeout',
    'running',
    'missing typed exit',
    'diagnostic error',
  ]) {
    test('keeps the failure for $variant', () {
      final candidate = command(
        'candidate',
        switch (variant) {
          'other target' => '.venv/bin/python -m pytest other.py -v',
          'other flags' =>
            '.venv/bin/python -m pytest test_retry.py -v -k retry',
          'unknown shell' =>
            '.venv/bin/python -m pytest test_retry.py -v && echo done',
          _ => '.venv/bin/python -m pytest test_retry.py -v',
        },
        directory: variant == 'other directory' ? '/other' : '/workspace',
        stdout: switch (variant) {
          'unknown counts' => 'done',
          'no tests' => '================= 0 passed in 0.1s =================',
          'failed tests' =>
            '================= 2 failed, 4 passed in 0.1s =================',
          _ => '================= 6 passed in 0.1s =================',
        },
        typed: variant != 'missing typed exit',
        timedOut: variant == 'timeout',
        processState: variant == 'running' ? ToolProcessState.running : null,
        diagnosticErrors: variant == 'diagnostic error' ? 1 : 0,
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([
        missing,
        feedback,
        candidate,
      ]);
      expect(evidence.unresolvedErrorCount, 1);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
    });
  }

  test('a later failure stays blocking after an earlier success', () {
    final failure = command(
      'later-failure',
      success.arguments['command'] as String,
      stdout: '================= 2 failed, 4 passed in 0.1s =================',
    );
    final laterFeedback = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [failure])!;
    final evidence = ToolResultPromptBuilder.completionEvidence([
      missing,
      feedback,
      success,
      failure,
      laterFeedback,
    ]);
    expect(evidence.unresolvedErrorCount, 1);
    expect(evidence.hasFailedExecutionVerification, isTrue);
  });

  test('retains unrelated diagnostics in a mixed feedback batch', () {
    final other = command(
      'other',
      'python3 -m pytest other.py -v',
      stdout: 'No data found',
    );
    final mixed = const CodingCommandOutputGuardrailService()
        .buildFeedbackToolResult(toolResults: [missing, other])!;
    final evidence = ToolResultPromptBuilder.completionEvidence([
      missing,
      other,
      mixed,
      success,
    ]);
    expect(evidence.unresolvedErrorCount, 1);
    expect(
      evidence.unresolvedErrorDiagnostics.single.message,
      contains('No data found'),
    );
  });

  test('resolves old log feedback using its nearest preceding command', () {
    ToolResultInfo legacy(ToolResultInfo source) {
      final generated = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(toolResults: [source])!;
      final payload = jsonDecode(generated.result) as Map<String, dynamic>;
      (payload['issues'] as List).single.remove('tool_call_id');
      return ToolResultInfo(
        id: 'legacy-${source.id}',
        name: generated.name,
        arguments: generated.arguments,
        result: jsonEncode(payload),
      );
    }

    final repeat = command(
      'repeat',
      missing.arguments['command'] as String,
      stdout: '/opt/python/bin/python3.14: No module named pytest',
    );
    final results = CommandVerificationReconciliation.currentResults([
      missing,
      legacy(missing),
      success,
      repeat,
      legacy(repeat),
    ]);
    expect(results.map((result) => result.id), [
      success.id,
      repeat.id,
      'legacy-repeat',
    ]);
  });

  test('runner counts reject prose and report failures and skips', () {
    final identity = PytestVerificationIdentity.parse(
      'pytest test.py',
      '/workspace',
    )!;
    expect(identity.counts('I confirmed 6 tests passed.'), isNull);
    final counts = identity.counts(
      '=== 2 failed, 4 passed, 1 skipped, 1 error in 0.1s ===',
    )!;
    expect(counts.failedCount, 3);
    expect(counts.skippedCount, 1);
  });

  group('guardrail feedback on commands that verify nothing', () {
    // Session 17398f84: an import probe and a venv setup command each got an
    // Error diagnostic that no later pass could settle, so a subtask whose
    // pytest run passed kept being rejected for "2 unresolved errors".
    const guardrail = CodingCommandOutputGuardrailService();
    final probe = command(
      'probe',
      'python3 -c "import pytest; print(pytest.__version__)" 2>&1; '
          'python3 -m venv --help >/dev/null 2>&1 && echo venv-ok',
      stdout:
          'Traceback (most recent call last):\n'
          "ModuleNotFoundError: No module named 'pytest'\nvenv-ok\n",
    );
    final setup = command(
      'setup',
      'python3 -m venv .venv && .venv/bin/python -m pip install --quiet '
          'pytest 2>&1 | tail -20; echo "exit=\$?"',
      stdout: 'exit=1\n',
    );
    final passed = command(
      'passed',
      'python3 -m pytest -q 2>&1 | tail -5',
      stdout: '61 passed in 3.09s',
    );

    test('stays visible to the model but never blocks completion', () {
      final probeFeedback = guardrail.buildFeedbackToolResult(
        toolResults: [probe],
      );
      final setupFeedback = guardrail.buildFeedbackToolResult(
        toolResults: [setup],
      );
      expect(probeFeedback, isNotNull);
      expect(setupFeedback, isNotNull);
      expect(CommandVerificationReconciliation.isVerification(probe), isFalse);
      expect(CommandVerificationReconciliation.isVerification(setup), isFalse);
      final results = [probe, probeFeedback!, setup, setupFeedback!, passed];

      final evidence = ToolResultPromptBuilder.completionEvidence(results);
      expect(evidence.unresolvedErrorCount, 0);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(
        ToolResultPromptBuilder.completionBlockerInstructions(results),
        isEmpty,
      );
      expect(
        const ProjectTaskStepCompletionPolicy()
            .status(
              response: 'Verified.\nPROJECT_TASK_SUBTASK_DONE',
              results: results,
              goal: ConversationGoal(
                id: 'g',
                objective: 'Implement',
                projectTaskAutoReview: true,
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
              ),
            )
            .completionAccepted,
        isTrue,
      );
    });

    test('a flagged verification still blocks until it passes', () {
      final masked = command(
        'masked',
        'python3 verify_logging.py 2>&1 | tail -5; echo done',
        stdout: 'Traceback (most recent call last):\nAssertionError\ndone\n',
      );
      final feedback = guardrail.buildFeedbackToolResult(
        toolResults: [masked],
      )!;
      final results = [masked, feedback, passed];

      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).unresolvedErrorCount,
        1,
      );
      final blockers = ToolResultPromptBuilder.completionBlockerInstructions(
        results,
      ).join('\n');
      expect(blockers, contains('flagged by the command output guardrail'));
      expect(blockers, isNot(contains('does not pass analysis')));
    });
  });

  group('pytest runs whose tests never started', () {
    // Session 016d4d5e: three failed attempts in which pytest never ran kept
    // the subtask rejected after the same tests had passed (61 passed), and
    // the model deleted and rebuilt the venv to replay their setup.
    final passed = command(
      'passed',
      'cd /workspace && /opt/homebrew/bin/pytest -q 2>&1 | tail -5',
      stdout: '61 passed in 3.19s',
    );
    const versionProbeChain =
        'cd /workspace && rm -rf .venv && python3 -m venv --without-pip .venv '
        '&& .venv/bin/python -c "import sys; print(sys.version)" '
        '&& .venv/bin/python -m pytest -q 2>&1 | tail -3';
    final launchFailure = command(
      'launch',
      versionProbeChain,
      exitCode: 1,
      stdout:
          '3.14.6 (main)\n'
          '/workspace/.venv/bin/python: No module named pytest\n',
    );

    test('an environment query before pytest is not part of the check', () {
      final missingVenv = command(
        'missing-venv',
        'cd /workspace && ls -d .venv 2>/dev/null && '
            '.venv/bin/python -m pytest -q 2>&1 | tail -5',
        exitCode: 1,
        stdout: '',
      );
      expect(
        CommandVerificationReconciliation.currentResults([
          missingVenv,
          passed,
        ]).map((result) => result.id),
        ['passed'],
      );
    });

    test('a pytest that could not import owes only the pytest run', () {
      final results = [launchFailure, passed];
      expect(
        CommandVerificationReconciliation.currentResults(
          results,
        ).map((result) => result.id),
        ['passed'],
      );
      expect(const UnresolvedVerificationFailure().describe(results), isNull);
      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasSuccessfulExecutionVerification,
        isTrue,
      );
    });

    test('names the pytest run instead of the setup to replay', () {
      final gap = const UnresolvedVerificationFailure().describe([
        launchFailure,
      ])!;
      expect(gap, contains('A passing run of the same tests'));
      expect(gap, contains('.venv/bin/python -m pytest -q'));
      expect(gap, contains('need not be repeated'));
      expect(gap, isNot(contains('a different command passing')));
    });

    test('a check before pytest still has to pass itself', () {
      final checked = command(
        'checked',
        'cd /workspace && grep -q WEBHOOK watcher.py && '
            '.venv/bin/python -m pytest -q 2>&1 | tail -5',
        exitCode: 1,
        stdout: '',
      );
      expect(
        CommandVerificationReconciliation.currentResults([checked, passed]),
        contains(checked),
      );
    });

    test('tests that ran and failed keep the whole chain', () {
      final failedTests = command(
        'failed-tests',
        versionProbeChain,
        exitCode: 1,
        stdout: '3.14.6 (main)\n2 failed, 59 passed in 3.1s\n',
      );
      expect(
        CommandVerificationReconciliation.currentResults([failedTests, passed]),
        contains(failedTests),
      );
    });

    test('a launch failure after a pass still blocks', () {
      expect(
        CommandVerificationReconciliation.currentResults([
          passed,
          launchFailure,
        ]),
        contains(launchFailure),
      );
    });
  });

  test('a command -v probe that finds no venv is not a check', () {
    // Session 64bbc516: this probe's missing `venv` was the check the
    // recovery asked the model to make pass, until it reported blocked.
    final probe = command(
      'probe',
      'ls -a; command -v python3.12 python3.11 python3.13; ls .venv venv',
      exitCode: 1,
      stdout: '.venv\n/opt/homebrew/bin/python3.12\n',
    );
    expect(CommandVerificationReconciliation.isVerification(probe), isFalse);
    expect(const UnresolvedVerificationFailure().describe([probe]), isNull);
  });

  group('setup output and package probes', () {
    // Session d27e7528: a passing `ensurepip | tail && pip install | tail &&
    // pytest -q` (61 passed) settled nothing, and a package probe was the
    // check the recovery asked the model to make pass.
    const probe =
        '.venv/bin/python -m pip list 2>/dev/null | grep -i pytest; '
        'echo "---"; .venv/bin/python -c "import pytest; '
        "print('pytest', pytest.__version__)\" 2>&1 | head -1";
    final launchFailure = command(
      'venv-pytest',
      '.venv/bin/python -m pytest -q',
      exitCode: 1,
      stdout: '',
    );
    final installedAndPassed = command(
      'host-chain',
      '.venv/bin/python -m ensurepip --upgrade 2>&1 | tail -2 && '
          '.venv/bin/python -m pip install pytest 2>&1 | tail -3 && '
          '.venv/bin/python -m pytest -q',
      stdout: 'Successfully installed pip-26.1.2\n61 passed in 3.09s\n',
    );

    test('a package probe is a query, not a check', () {
      expect(VerificationMetadataQueryPolicy.applies(probe), isTrue);
      final failedProbe = command(
        'probe',
        probe,
        exitCode: 1,
        stdout: '---\nTraceback (most recent call last):\n',
      );
      expect(
        CommandVerificationReconciliation.isVerification(failedProbe),
        isFalse,
      );
      expect(
        const UnresolvedVerificationFailure().describe([
          failedProbe,
          installedAndPassed,
        ]),
        isNull,
      );
    });

    test('trimmed setup output still lets the chain settle pytest', () {
      expect(
        CommandVerificationReconciliation.currentResults([
          launchFailure,
          installedAndPassed,
        ]).map((result) => result.id),
        ['host-chain'],
      );
    });

    for (final command in [
      'echo ok > out.txt; python3 -m pytest --version',
      '.venv/bin/python -m pip list | grep -i pytest && python3 -m pytest -q',
    ]) {
      test('a write or a real run is not a probe: $command', () {
        expect(VerificationMetadataQueryPolicy.applies(command), isFalse);
      });
    }

    test('a step whose failure is swallowed settles nothing', () {
      final masked = command(
        'masked',
        'python3 check.py || true && .venv/bin/python -m pytest -q',
        stdout: '61 passed in 3.09s',
      );
      expect(
        CommandVerificationReconciliation.currentResults([
          launchFailure,
          masked,
        ]),
        contains(launchFailure),
      );
    });
  });

  group('non-pytest verification', () {
    // Session d0c0462c: only pytest runs were ever reconciled, so a failed
    // `watcher.py --dry-run` stayed failed for the rest of the turn even when
    // the very same command later passed.
    ToolResultInfo run(String id, String command, int exitCode) =>
        ToolResultInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': '/w'},
          result: jsonEncode({
            'command': command,
            'working_directory': '/w',
            'exit_code': exitCode,
            'stdout': exitCode == 0 ? 'All 22 checks passed.' : 'failed',
          }),
          outcome: ToolOutcome(exitCode: exitCode),
        );
    const verifier = '.venv/bin/python verify_logging.py';

    test('the same command passing later settles its failure', () {
      final current = CommandVerificationReconciliation.currentResults([
        run('fail', verifier, 1),
        run('pass', verifier, 0),
      ]);
      expect(current.map((result) => result.id), ['pass']);
    });

    // Session 17398f84: the chain passed, yet the standalone check it
    // contains stayed failed and kept the subtask rejected.
    const lint = 'python3 -m ruff check watcher.py';
    const chain = '$lint && python3 -m pytest -q 2>&1 | tail -3';
    ToolResultInfo chainRun(String id, String command, {String dir = '/w'}) =>
        ToolResultInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': dir},
          result: jsonEncode({
            'command': command,
            'working_directory': dir,
            'exit_code': 0,
            'stdout': 'All checks passed!\n61 passed in 3.09s\n',
          }),
          outcome: const ToolOutcome(exitCode: 0),
        );

    test('a passing && chain settles a failed run of each plain step', () {
      final results = [run('lint', lint, 1), chainRun('chain', chain)];
      expect(
        CommandVerificationReconciliation.currentResults(
          results,
        ).map((result) => result.id),
        ['chain'],
      );
      expect(const UnresolvedVerificationFailure().describe(results), isNull);
    });

    for (final (label, other) in [
      ('another directory', chainRun('chain', chain, dir: '/elsewhere')),
      (
        'another file',
        chainRun(
          'chain',
          'python3 -m ruff check other.py && python3 -m pytest -q 2>&1 '
              '| tail -3',
        ),
      ),
      ('a ; list', chainRun('chain', '$lint; python3 -m pytest -q')),
    ]) {
      test('a passing chain in $label does not settle it', () {
        final current = CommandVerificationReconciliation.currentResults([
          run('lint', lint, 1),
          other,
        ]);
        expect(current.map((result) => result.id), contains('lint'));
      });
    }

    test('a different command passing does not', () {
      final current = CommandVerificationReconciliation.currentResults([
        run('fail', verifier, 1),
        run('other', 'python3 -m pytest -q', 0),
      ]);
      expect(current.map((result) => result.id), contains('fail'));
    });
  });

  group('verification failures across later mutations', () {
    const dryRun =
        '.venv/bin/python app.py --dry-run 2>&1 | head -20; '
        'echo "--- app.log tail ---"; tail -8 app.log';
    for (final exitCode in [0, 1]) {
      for (final withFeedback in [false, true]) {
        if (exitCode != 0 && withFeedback) continue;
        for (final rerunPasses in [false, true]) {
          test(
            'requires the failed check after an edit '
            '(exit: $exitCode, feedback: $withFeedback, rerun: $rerunPasses)',
            () {
              final failed = command(
                'dry-run-failed',
                dryRun,
                exitCode: exitCode,
                stdout:
                    'Traceback (most recent call last):\n'
                    'RuntimeError: fixture verification failed\n',
              );
              final results = [
                failed,
                if (withFeedback)
                  const CodingCommandOutputGuardrailService()
                      .buildFeedbackToolResult(toolResults: [failed])!,
                ToolResultInfo(
                  id: 'ignore-log',
                  name: 'edit_file',
                  arguments: const {'path': '/workspace/.gitignore'},
                  result: jsonEncode({
                    'path': '/workspace/.gitignore',
                    'changed': true,
                  }),
                  outcome: const ToolOutcome(
                    fileMutations: [
                      ToolFileMutation(
                        path: '/workspace/.gitignore',
                        changed: true,
                        contentHash: 'ignore-generated-log',
                      ),
                    ],
                  ),
                ),
                command('unit-tests', '.venv/bin/python -m pytest -q'),
                if (rerunPasses)
                  command('dry-run-passed', dryRun, stdout: 'Dry-run passed.'),
              ];
              final evidence = ToolResultPromptBuilder.completionEvidence(
                results,
              );
              expect(evidence.hasExecutionVerification, isTrue);
              expect(evidence.hasFailedExecutionVerification, !rerunPasses);
              expect(evidence.hasSuccessfulExecutionVerification, rerunPasses);
              final settled = evidence.settleForExecutionGenerations(
                mutationGeneration: 2,
                verificationGeneration: 2,
              );
              expect(settled.hasFailedExecutionVerification, !rerunPasses);
              expect(settled.hasSuccessfulExecutionVerification, rerunPasses);
              expect(
                const UnresolvedVerificationFailure().describe(results),
                rerunPasses ? isNull : contains('app.py --dry-run'),
              );
            },
          );
        }
      }
    }
  });

  group('reported command exit status', () {
    const invocation = '.venv/bin/python app.py --dry-run 2>&1 | head -40';
    const reporter = r'; echo "PIPELINE_EXIT=${PIPESTATUS[0]:-n/a}"';
    final initialFailure = command('initial-failure', invocation, exitCode: 2);

    test('a failed command remains failed without a side feedback result', () {
      final failed = command(
        'masked-failure',
        '$invocation$reporter',
        stdout: 'usage error\nPIPELINE_EXIT=2\n',
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([failed]);
      expect(evidence.hasFailedExecutionVerification, isTrue);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
      expect(
        const UnresolvedVerificationFailure().describe([failed]),
        contains('reported exit 2; shell exit 0'),
      );
    });

    test('another passing check cannot clear a reported network failure', () {
      final failed = command(
        'network-failure',
        '$invocation$reporter',
        stdout: 'Traceback (most recent call last)\nPIPELINE_EXIT=120\n',
      );
      final results = [
        initialFailure,
        failed,
        command('unit-tests', 'python3 -m pytest -q'),
      ];
      expect(
        CommandVerificationReconciliation.currentResults(results),
        contains(initialFailure),
      );
      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasSuccessfulExecutionVerification,
        isFalse,
      );
      expect(
        const UnresolvedVerificationFailure().describe(results),
        contains('reported exit 120'),
      );
    });

    test(
      'a proven successful rerun settles the invocation and its feedback',
      () {
        final failed = command(
          'masked-failure',
          '$invocation$reporter',
          stdout: 'PIPELINE_EXIT=2\n',
        );
        final outputFeedback = const CodingCommandOutputGuardrailService()
            .buildFeedbackToolResult(toolResults: [failed])!;
        final passed = command(
          'passed',
          '$invocation$reporter',
          stdout: 'dry run completed\nPIPELINE_EXIT=0\n',
        );
        final results = [initialFailure, failed, outputFeedback, passed];
        expect(
          CommandVerificationReconciliation.currentResults(
            results,
          ).map((r) => r.id),
          ['passed'],
        );
        final evidence = ToolResultPromptBuilder.completionEvidence(results);
        expect(evidence.hasFailedExecutionVerification, isFalse);
        expect(evidence.hasSuccessfulExecutionVerification, isTrue);
        expect(evidence.unresolvedErrorCount, 0);
        expect(const UnresolvedVerificationFailure().describe(results), isNull);
      },
    );

    for (final variant in [
      'missing report',
      'different directory',
      'different arguments',
      'missing typed exit',
    ]) {
      test('cannot settle the original failure with $variant', () {
        final passed = command(
          'unproven',
          variant == 'different arguments'
              ? '.venv/bin/python app.py --other 2>&1 | head -40$reporter'
              : '$invocation$reporter',
          directory: variant == 'different directory' ? '/other' : '/workspace',
          stdout: variant == 'missing report' ? 'done' : 'PIPELINE_EXIT=0\n',
          typed: variant != 'missing typed exit',
        );
        expect(
          CommandVerificationReconciliation.currentResults([
            initialFailure,
            passed,
          ]),
          contains(initialFailure),
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            initialFailure,
            passed,
          ]).hasFailedExecutionVerification,
          isTrue,
        );
      });
    }

    test('pytest reruns still need positive runner counts with a report', () {
      final failed = command(
        'pytest-failed',
        'python3 -m pytest test_app.py -q',
        exitCode: 1,
      );
      for (final output in [
        'done\nPIPELINE_EXIT=0',
        '2 passed in 0.1s\nPIPELINE_EXIT=0',
      ]) {
        final passed = command(
          'pytest-rerun',
          r'python3 -m pytest test_app.py -q; echo "PIPELINE_EXIT=${PIPESTATUS[0]}"',
          stdout: output,
        );
        expect(
          CommandVerificationReconciliation.currentResults([
            failed,
            passed,
          ]).contains(failed),
          !output.startsWith('2 passed'),
        );
      }
    });

    test('terminal background tails retain the reported command failure', () {
      final failed = ToolResultInfo(
        id: 'background-report',
        name: 'process_wait',
        arguments: const {'job_id': 'reported-job'},
        result: jsonEncode({
          'job_id': 'reported-job',
          'status': 'exited',
          'command': '$invocation$reporter',
          'working_directory': '/workspace',
          'exit_code': 0,
          'stdout_tail': 'PIPELINE_EXIT=120\n',
        }),
        outcome: const ToolOutcome(
          exitCode: 0,
          processState: ToolProcessState.exited,
        ),
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([failed]);
      expect(evidence.hasFailedExecutionVerification, isTrue);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
      expect(
        const UnresolvedVerificationFailure().describe([failed]),
        contains('reported exit 120'),
      );
    });
  });

  group('compound verification evidence', () {
    const verifier =
        '.venv/bin/python verify_logging.py && .venv/bin/python -m pytest -q';
    const cleaned = 'rm -f test_verify_log.log watcher.log && $verifier';

    test('pytest metadata is not a check or a failed verification scope', () {
      final lookup = command(
        'pytest-location',
        'ls -d /workspace/.venv /workspace/venv 2>/dev/null; which pytest 2>/dev/null; '
            'python3 -c "import pytest; print(pytest.__file__)" 2>&1',
        exitCode: 1,
        stdout:
            'Traceback (most recent call last):\nModuleNotFoundError: No module named \'pytest\'',
      );
      expect(CommandVerificationReconciliation.isVerification(lookup), isFalse);
      final inspectionOnly = ToolResultPromptBuilder.completionEvidence([
        lookup,
      ]);
      expect(inspectionOnly.hasExecutionVerification, isFalse);
      expect(inspectionOnly.hasFailedExecutionVerification, isFalse);
      expect(const UnresolvedVerificationFailure().describe([lookup]), isNull);
      final failed = command(
        'failed',
        'python3 verify_logging.py && python3 -m pytest -q',
        exitCode: 1,
      );
      final partial = command('partial', '.venv/bin/python -m pytest -q');
      expect(
        const UnresolvedVerificationFailure().describe([
          failed,
          lookup,
          partial,
        ]),
        isNotNull,
      );
      final passed = command(
        'passed',
        'python3 verify_logging.py && .venv/bin/python -m pytest -q',
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([
        failed,
        lookup,
        partial,
        passed,
      ]);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(evidence.unresolvedErrorCount, 0);
    });

    for (final prefix in [
      '',
      'cd /workspace && ',
      'cd /workspace && python3 verify_logging.py && ',
    ]) {
      test('settles the same checks after a reporting change: $prefix', () {
        const targets = 'test_a.py test_b.py';
        final failed = command(
          'system-runner',
          '${prefix}python3 -m pytest $targets -v 2>&1 | tail -20',
          exitCode: 1,
          stdout: 'python3: No module named pytest',
        );
        final passed = command(
          'project-runner',
          '$prefix.venv/bin/python -m pytest $targets -q 2>&1 | tail -15',
          stdout: '53 passed in 3.08s',
        );
        final results = [failed, passed];
        expect(
          CommandVerificationReconciliation.currentResults(
            results,
          ).map((r) => r.id),
          ['project-runner'],
        );
        final evidence = ToolResultPromptBuilder.completionEvidence(results);
        expect(evidence.hasSuccessfulExecutionVerification, isTrue);
        expect(evidence.hasFailedExecutionVerification, isFalse);
        expect(evidence.unresolvedErrorCount, 0);
        expect(const UnresolvedVerificationFailure().describe(results), isNull);
        expect(
          results,
          hasLength(2),
          reason: 'the raw audit ledger is retained',
        );
      });
    }

    test('a failed multi-runtime lookup neither verifies nor blocks work', () {
      final lookup = command(
        'runtime-lookup',
        'cd /workspace && ls -a && which -a python3 python3.12 python3.13',
        exitCode: 1,
        stdout: '.venv\n/usr/bin/python3\n',
      );
      expect(CommandVerificationReconciliation.isVerification(lookup), isFalse);
      final onlyLookup = ToolResultPromptBuilder.completionEvidence([lookup]);
      expect(onlyLookup.hasExecutionVerification, isFalse);
      expect(onlyLookup.hasSuccessfulExecutionVerification, isFalse);
      expect(onlyLookup.hasFailedExecutionVerification, isFalse);
      expect(const UnresolvedVerificationFailure().describe([lookup]), isNull);
      final failed = command('failed', 'python3 -m pytest -q', exitCode: 1);
      expect(
        const UnresolvedVerificationFailure().describe([failed, lookup]),
        contains('python3 -m pytest'),
      );
      final passed = command('passed', '.venv/bin/python -m pytest -q');
      final evidence = ToolResultPromptBuilder.completionEvidence([
        failed,
        lookup,
        passed,
      ]);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(evidence.unresolvedErrorCount, 0);
    });

    test('a missing optional package is inspection rather than verification', () {
      final lookup = command(
        'environment',
        'cd /workspace && ls -d .venv venv 2>/dev/null; which pytest 2>/dev/null; '
            'python3 -m pip show pytest 2>/dev/null | head -3',
        exitCode: 1,
        stdout: '.venv\n/usr/local/bin/pytest\n',
      );
      expect(CommandVerificationReconciliation.isVerification(lookup), isFalse);
      expect(
        const ToolCapabilityClassifier()
            .classify(lookup.name, arguments: lookup.arguments)
            .commandEffect,
        ToolCommandEffect.verification,
        reason: 'completion evidence does not change approval classification',
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([lookup]);
      expect(evidence.hasExecutionVerification, isFalse);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(const UnresolvedVerificationFailure().describe([lookup]), isNull);
    });

    const failedChain =
        'cd /workspace && python3 verify_logging.py && echo "TESTS" && '
        'python3 -m pytest -q 2>&1 | tail -20';
    const workingChain =
        'cd /workspace && python3 verify_logging.py && '
        '.venv/bin/python -m pytest -q 2>&1 | tail -10';

    test(
      'a full passing chain settles its failed runner in the project runtime',
      () {
        final failed = command('chain-failure', failedChain, exitCode: 1);
        final passed = command(
          'chain-passed',
          workingChain,
          stdout: '53 passed in 0.1s',
        );
        expect(
          CommandVerificationReconciliation.currentResults([
            failed,
            passed,
          ]).map((r) => r.id),
          ['chain-passed'],
        );
        expect(
          const UnresolvedVerificationFailure().describe([failed, passed]),
          isNull,
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            failed,
            passed,
          ]).hasSuccessfulExecutionVerification,
          isTrue,
        );
      },
    );

    test('passing only pytest does not settle failed prerequisite checks', () {
      final failed = command('chain-failure', failedChain, exitCode: 1);
      final passed = command(
        'runner-passed',
        '.venv/bin/python -m pytest -q',
        stdout: '53 passed in 0.1s',
      );
      expect(
        CommandVerificationReconciliation.currentResults([failed, passed]),
        contains(failed),
      );
      expect(
        const UnresolvedVerificationFailure().describe([failed, passed]),
        contains('verify_logging.py'),
      );
    });

    const systemScripts =
        'cd /workspace && python3 verify_logging.py && '
        'python3 -m pytest test_state.py test_watcher.py -v 2>&1';
    const venvScripts =
        'cd /workspace && .venv/bin/python verify_logging.py && '
        '.venv/bin/python -m pytest test_state.py test_watcher.py -v 2>&1';

    test(
      'settles a full chain after switching every Python script runtime',
      () {
        final failed = command(
          'system-chain',
          systemScripts,
          exitCode: 1,
          stdout: 'All 24 checks passed.\npython3: No module named pytest',
        );
        final passed = command(
          'venv-chain',
          venvScripts,
          stdout: 'All 24 checks passed.\n53 passed in 3.09s',
        );
        expect(
          CommandVerificationReconciliation.currentResults([
            failed,
            passed,
          ]).map((result) => result.id),
          ['venv-chain'],
        );
        expect(
          const UnresolvedVerificationFailure().describe([failed, passed]),
          isNull,
        );
        final evidence = ToolResultPromptBuilder.completionEvidence([
          failed,
          passed,
        ]);
        expect(evidence.hasSuccessfulExecutionVerification, isTrue);
        expect(evidence.hasFailedExecutionVerification, isFalse);
      },
    );

    for (final variant in [
      'different script',
      'different script arguments',
      'interpreter options',
      'module prerequisite',
      'missing prerequisite',
      'different targets',
      'different flags',
      'different directory',
      'trailing mutation',
      'output file',
      'no counts',
      'failed tests',
      'missing typed exit',
      'timeout',
    ]) {
      test('keeps the original Python chain failure for $variant', () {
        final failed = command('system-chain', systemScripts, exitCode: 1);
        final candidate = command(
          'venv-chain',
          switch (variant) {
            'different script' => venvScripts.replaceFirst(
              'verify_logging.py',
              'verify_other.py',
            ),
            'different script arguments' => venvScripts.replaceFirst(
              'verify_logging.py',
              'verify_logging.py --skip-console',
            ),
            'interpreter options' => venvScripts.replaceFirst(
              '.venv/bin/python verify_logging.py',
              '.venv/bin/python -O verify_logging.py',
            ),
            'module prerequisite' => venvScripts.replaceFirst(
              'verify_logging.py',
              '-m logging_check',
            ),
            'missing prerequisite' => venvScripts.replaceFirst(
              '.venv/bin/python verify_logging.py && ',
              '',
            ),
            'different targets' => venvScripts.replaceFirst(
              'test_watcher.py',
              'test_other.py',
            ),
            'different flags' => venvScripts.replaceFirst('-v', '-v -k state'),
            'different directory' => venvScripts.replaceFirst(
              '/workspace',
              '/other',
            ),
            'trailing mutation' => '$venvScripts && rm -f state.json',
            'output file' => '$venvScripts > tests.txt',
            _ => venvScripts,
          },
          typed: variant != 'missing typed exit',
          timedOut: variant == 'timeout',
          stdout: switch (variant) {
            'no counts' => 'All 24 checks passed.\nDone.',
            'failed tests' => '1 failed, 53 passed in 3.09s',
            _ => 'All 24 checks passed.\n53 passed in 3.09s',
          },
        );
        expect(
          CommandVerificationReconciliation.currentResults([failed, candidate]),
          contains(failed),
        );
      });
    }

    test(
      'a full chain also covers an earlier failure of its terminal runner',
      () {
        final failed = command(
          'runner-failure',
          'python3 -m pytest -q',
          exitCode: 1,
        );
        final passed = command(
          'chain-passed',
          workingChain,
          stdout: '53 passed in 0.1s',
        );
        expect(
          CommandVerificationReconciliation.currentResults([
            failed,
            passed,
          ]).map((r) => r.id),
          ['chain-passed'],
        );
      },
    );

    for (final variant in [
      'different prerequisite',
      'different directory',
      'different runner flags',
      'timeout',
      'missing counts',
      'failed tests',
    ]) {
      test('compound failure remains for $variant', () {
        final failed = command('chain-failure', failedChain, exitCode: 1);
        final candidateCommand = switch (variant) {
          'different prerequisite' => workingChain.replaceFirst(
            'verify_logging.py',
            'verify_other.py',
          ),
          'different directory' => workingChain.replaceAll(
            '/workspace',
            '/other',
          ),
          'different runner flags' => workingChain.replaceFirst('-q', '-q -x'),
          _ => workingChain,
        };
        final candidate = command(
          'candidate',
          candidateCommand,
          directory: variant == 'different directory' ? '/other' : '/workspace',
          timedOut: variant == 'timeout',
          stdout: switch (variant) {
            'missing counts' => 'done',
            'failed tests' => '1 failed, 53 passed in 0.1s',
            _ => '53 passed in 0.1s',
          },
        );
        expect(
          CommandVerificationReconciliation.currentResults([failed, candidate]),
          contains(failed),
        );
      });
    }

    test(
      'counts post-deletion verification without relaxing command authority',
      () {
        final result = command(
          'verified',
          cleaned,
          stdout: 'All 24 checks passed.\n53 passed in 0.1s',
        );
        final deletion = ToolResultInfo(
          id: 'delete-fixture',
          name: 'delete_file',
          arguments: const {},
          result: jsonEncode({
            'path': '/workspace/verify_fixture.py',
            'deleted': true,
          }),
          outcome: const ToolOutcome(
            fileMutations: [
              ToolFileMutation(
                path: '/workspace/verify_fixture.py',
                changed: true,
                byteSize: 0,
              ),
            ],
          ),
        );
        final evidence = ToolResultPromptBuilder.completionEvidence([
          deletion,
          result,
        ]);
        expect(evidence.hasSuccessfulExecutionVerification, isTrue);
        expect(evidence.mutatedWithoutExecutionVerification, isFalse);
        expect(evidence.unverifiedChangePaths, isEmpty);
        expect(
          const ToolCapabilityClassifier()
              .classify(result.name, arguments: result.arguments)
              .commandEffect,
          ToolCommandEffect.workspaceMutation,
        );
      },
    );

    test('settles the same verification after cleanup', () {
      final failure = command('failed', verifier, exitCode: 1);
      final passed = command('passed', cleaned, stdout: '53 passed in 0.1s');
      expect(
        CommandVerificationReconciliation.currentResults([
          failure,
          passed,
        ]).map((r) => r.id),
        ['passed'],
      );
    });

    for (final stdout in ['done', '0 passed in 0.1s', '53 passed in 0.1s']) {
      test('requires completed positive runner counts: $stdout', () {
        final result = command(
          'incomplete',
          cleaned,
          stdout: stdout,
          timedOut: stdout.startsWith('53'),
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            result,
          ]).hasSuccessfulExecutionVerification,
          isFalse,
        );
      });
    }

    for (final suffix in [
      ' || true',
      '; true',
      ' && touch source.py',
      ' &',
      ' >result.txt',
    ]) {
      test('does not credit a masked or post-mutation command: $suffix', () {
        final result = command(
          'masked',
          'rm -f scratch.log && python3 -m pytest -q$suffix',
        );
        expect(
          CommandVerificationReconciliation.isVerification(result),
          isFalse,
        );
      });
    }

    test(
      'retains failure diagnostics from a nominally successful compound run',
      () {
        final result = command(
          'bad-output',
          cleaned,
          stdout: '2 failed, 3 passed in 0.1s',
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            result,
          ]).hasSuccessfulExecutionVerification,
          isFalse,
        );
        expect(
          ToolResultPromptBuilder.completionEvidence([
            result,
          ]).hasFailedExecutionVerification,
          isTrue,
        );
      },
    );
  });

  group('background verification identity', () {
    const verifier = '.venv/bin/python verify_logging.py';
    ToolResultInfo wait({
      String directory = '/workspace',
      String? originalCommand = verifier,
      String? jobId = 'job-1',
      int exitCode = 1,
    }) => ToolResultInfo(
      id: 'wait',
      name: 'process_wait',
      arguments: const {'job_id': 'job-1'},
      result: jsonEncode({
        'job_id': jobId,
        'command': ?originalCommand,
        'working_directory': directory,
        'exit_code': exitCode,
      }),
      outcome: ToolOutcome(
        exitCode: exitCode,
        processState: ToolProcessState.exited,
      ),
    );

    test('settles a failed monitor with the matching foreground verifier', () {
      final failed = wait();
      final passed = command(
        'passed',
        verifier,
        stdout: 'All 24 checks passed.',
      );
      final evidence = ToolResultPromptBuilder.completionEvidence([
        failed,
        passed,
      ]);
      expect(evidence.hasFailedExecutionVerification, isFalse);
      expect(evidence.hasSuccessfulExecutionVerification, isTrue);
      expect(
        CommandVerificationReconciliation.currentResults([
          failed,
          passed,
        ]).map((r) => r.id),
        ['passed'],
      );
      expect(
        const UnresolvedVerificationFailure().describe([failed]),
        contains('`$verifier` failed'),
      );
    });

    for (final failure in [
      wait(directory: '/other'),
      wait(originalCommand: null),
      wait(originalCommand: 'python3 verify_other.py'),
      wait(jobId: null),
      wait(jobId: ''),
    ]) {
      test('keeps unmatched origin ${failure.result}', () {
        final passed = command('passed', verifier);
        expect(
          ToolResultPromptBuilder.completionEvidence([
            failure,
            passed,
          ]).hasFailedExecutionVerification,
          isTrue,
        );
      });
    }

    test('a later terminal background failure remains blocking', () {
      final passed = command('passed', verifier);
      expect(
        ToolResultPromptBuilder.completionEvidence([
          passed,
          wait(),
        ]).hasFailedExecutionVerification,
        isTrue,
      );
    });

    final mutation = ToolResultInfo(
      id: 'edit',
      name: 'edit_file',
      arguments: const {'path': '/workspace/source.py'},
      result: jsonEncode({'path': '/workspace/source.py', 'replacements': 1}),
    );
    final start = ToolResultInfo(
      id: 'start',
      name: 'process_start',
      arguments: const {'command': verifier, 'working_directory': '/workspace'},
      result: jsonEncode({
        'job_id': 'job-1',
        'command': verifier,
        'working_directory': '/workspace',
        'status': 'running',
      }),
      outcome: const ToolOutcome(processState: ToolProcessState.running),
    );

    test('credits only a job dispatched after the latest mutation', () {
      final fresh = ToolResultPromptBuilder.completionEvidence([
        mutation,
        start,
        wait(exitCode: 0),
      ]);
      final stale = ToolResultPromptBuilder.completionEvidence([
        start,
        mutation,
        wait(exitCode: 0),
      ]);
      final unknown = ToolResultPromptBuilder.completionEvidence([
        mutation,
        wait(exitCode: 0),
      ]);
      expect(fresh.hasSuccessfulExecutionVerification, isTrue);
      expect(stale.hasSuccessfulExecutionVerification, isFalse);
      expect(unknown.hasSuccessfulExecutionVerification, isFalse);
    });

    test('an older job success cannot settle a post-mutation failure', () {
      final failed = command('fresh-failure', verifier, exitCode: 1);
      final results = [start, mutation, failed, wait(exitCode: 0)];
      expect(
        CommandVerificationReconciliation.currentResults(
          results,
        ).map((result) => result.id),
        contains(failed.id),
      );
      expect(
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasFailedExecutionVerification,
        isTrue,
      );
    });

    test('legacy running monitor results cannot verify execution', () {
      for (final name in ['process_status', 'process_wait']) {
        final evidence = ToolResultPromptBuilder.completionEvidence([
          ToolResultInfo(
            id: 'legacy-poll',
            name: name,
            arguments: const {'job_id': 'job-1'},
            result: jsonEncode({
              'job_id': 'job-1',
              'command': verifier,
              'working_directory': '/workspace',
              'status': 'running',
              'exit_code': 0,
              'ok': true,
            }),
          ),
        ]);
        expect(evidence.hasSuccessfulExecutionVerification, isFalse);
      }
    });
  });
}

ToolResultInfo command(
  String id,
  String command, {
  String stdout = '================= 6 passed in 0.1s =================',
  String directory = '/workspace',
  bool typed = true,
  bool timedOut = false,
  ToolProcessState? processState,
  int diagnosticErrors = 0,
  int exitCode = 0,
}) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command, 'working_directory': directory},
  result: jsonEncode({
    'command': command,
    'working_directory': directory,
    'exit_code': exitCode,
    'stdout': stdout,
    'timed_out': timedOut,
  }),
  outcome: typed
      ? ToolOutcome(
          exitCode: exitCode,
          processState: processState,
          diagnosticErrorCount: diagnosticErrors,
        )
      : null,
);

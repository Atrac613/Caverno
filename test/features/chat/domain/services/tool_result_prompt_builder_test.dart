import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';

void main() {
  group('ToolResultPromptBuilder', () {
    test('dedupes tool definitions by name', () {
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'web_search',
            'description': 'Search the web',
            'parameters': const <String, dynamic>{},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'web_search',
            'description': 'Duplicate entry',
            'parameters': const <String, dynamic>{},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description': 'Read a file',
            'parameters': const <String, dynamic>{},
          },
        },
      ];

      final deduped = ToolResultPromptBuilder.dedupeToolsByName(tools);

      expect(deduped, hasLength(2));
      expect(
        deduped
            .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
            .toList(),
        ['web_search', 'read_file'],
      );
    });

    test('builds an answer prompt with tool descriptions and arguments', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt(
        [
          ToolResultInfo(
            id: 'tool-1',
            name: 'wifi_scan',
            arguments: const {'interface': 'wlan0'},
            result: '{"ssid":"Office"}',
          ),
        ],
        descriptionsByName: const {'wifi_scan': 'Scan nearby Wi-Fi networks.'},
      );

      expect(prompt, contains('Please answer the user\'s question'));
      expect(prompt, contains('[Tool: wifi_scan]'));
      expect(prompt, contains('Description: Scan nearby Wi-Fi networks.'));
      expect(prompt, contains('Arguments: {"interface":"wlan0"}'));
      expect(prompt, contains('Result:'));
      expect(prompt, contains('Scope note:'));
    });

    test('adds exact preservation guidance for raw tool result values', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'diagnostic_exact_value',
          arguments: const {'field': 'product_label'},
          result: 'Raw result:\n{"product_label":"ZX-900_\\u03b1 2026-06-12"}',
        ),
      ]);

      expect(prompt, contains('TOOL RESULT EXACT PRESERVATION:'));
      expect(prompt, contains('copy those values character-for-character'));
      expect(prompt, contains('Do not summarize, translate, normalize'));
      expect(prompt, contains('If a tool result includes "Raw result:"'));
      expect(prompt, contains('source of truth'));
      expect(prompt, contains('ZX-900_\\u03b1 2026-06-12'));
    });

    test(
      'blocks completion claims when the bounded tool loop dropped a tool call',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'edit_file',
            arguments: const {
              'path': '/tmp/prime_numbers.dart',
              'old_text': "import 'dart:math';",
              'new_text': "import 'dart:math' show sqrt;",
            },
            result: jsonEncode({
              'code': 'tool_call_not_executed',
              'error':
                  'Tool call was requested after the bounded tool loop stopped '
                  'and was not executed before the final answer.',
              'reason': 'bounded_tool_loop_exhausted',
              'tool_name': 'edit_file',
            }),
          ),
        ]);

        expect(prompt, contains('TASK NOT COMPLETE:'));
        expect(prompt, contains('the bounded tool loop stopped'));
        expect(prompt, contains('edit_file'));
        expect(prompt, contains('remains unexecuted'));
        // The guardrail must precede the tool-result payload so a weak model
        // sees it before the dropped call.
        expect(
          prompt.indexOf('TASK NOT COMPLETE:'),
          lessThan(prompt.indexOf('[Tool: edit_file]')),
        );
      },
    );

    test('blocks completion claims when analyzer errors remain unresolved', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'dart_analyze_feedback',
          arguments: const {
            'project_root': '/tmp',
            'changed_paths': ['prime_numbers.dart'],
          },
          result: jsonEncode({
            'schema': 'caverno_dart_analyze_feedback',
            'current_diagnostic_count': 3,
            'diagnostics': [
              {
                'relative_path': 'prime_numbers.dart',
                'severity': 'Error',
                'code': 'UNDEFINED_METHOD',
                'message':
                    "The method 'sqrt' isn't defined for the type "
                    "'double'.",
              },
              {
                'relative_path': 'prime_numbers.dart',
                'severity': 'Error',
                'code': 'NOT_ENOUGH_POSITIONAL_ARGUMENTS',
                'message':
                    "1 positional argument expected by 'print', but 0 found.",
              },
              {
                'relative_path': 'prime_numbers.dart',
                'severity': 'Warning',
                'code': 'UNUSED_IMPORT',
                'message': "Unused import: 'dart:math'.",
              },
            ],
          }),
        ),
      ]);

      expect(prompt, contains('TASK NOT COMPLETE:'));
      expect(prompt, contains('2 unresolved Error-severity diagnostic(s)'));
      expect(prompt, contains('prime_numbers.dart'));
      expect(prompt, contains('does not pass analysis'));
    });

    test('surfaces completion evidence for goal auto-continuation', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'tool-1',
          name: 'edit_file',
          arguments: const {},
          result: jsonEncode({
            'code': 'tool_call_not_executed',
            'reason': 'bounded_tool_loop_exhausted',
            'tool_name': 'edit_file',
          }),
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'dart_analyze_feedback',
          arguments: const {},
          result: jsonEncode({
            'diagnostics': [
              {
                'relative_path': 'lib/main.dart',
                'path': '/tmp/app/lib/main.dart',
                'severity': 'Error',
                'code': 'UNDEFINED_IDENTIFIER',
                'message': 'Undefined name.',
              },
              {
                'relative_path': 'lib/main.dart',
                'path': '/tmp/app/lib/main.dart',
                'severity': 'Warning',
                'code': 'UNUSED_IMPORT',
                'message': 'Unused import.',
              },
            ],
          }),
        ),
      ]);

      expect(evidence.hasIncompleteEvidence, isTrue);
      expect(evidence.hasBlockingEvidence, isTrue);
      expect(evidence.boundedToolLoopExhausted, isTrue);
      expect(evidence.unexecutedToolNames, ['edit_file']);
      expect(evidence.unresolvedErrorCount, 1);
      expect(evidence.unresolvedErrorPaths, ['lib/main.dart']);
      expect(evidence.unresolvedErrorDiagnostics, hasLength(1));
      expect(evidence.unresolvedErrorDiagnostics.single.path, 'lib/main.dart');
      expect(
        evidence.unresolvedErrorDiagnostics.single.code,
        'UNDEFINED_IDENTIFIER',
      );
      expect(
        evidence.unresolvedErrorDiagnostics.single.message,
        'Undefined name.',
      );
      expect(evidence.summary, contains('1 unresolved Error diagnostic'));
    });

    test('surfaces unverified file changes as incomplete evidence', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {},
          result: jsonEncode({
            'path': '/tmp/app/bin/todo_cli.dart',
            'bytes_written': 120,
            'created': true,
          }),
        ),
      ]);

      expect(evidence.hasIncompleteEvidence, isTrue);
      expect(evidence.hasBlockingEvidence, isFalse);
      expect(evidence.unverifiedChangePaths, ['/tmp/app/bin/todo_cli.dart']);
      expect(evidence.mutatedWithoutExecutionVerification, isTrue);
      expect(evidence.summary, contains('unverified file change'));
      expect(
        evidence.summary,
        contains('without execution-class verification'),
      );
    });

    test('surfaces unexecuted completion claims as incomplete evidence', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'unexecuted-command',
          name: 'local_execute_command',
          arguments: const {},
          result: jsonEncode({
            'ok': false,
            'code': 'unexecuted_command_action',
          }),
        ),
      ]);

      expect(evidence.hasIncompleteEvidence, isTrue);
      expect(evidence.hasUnexecutedActionClaim, isTrue);
      expect(evidence.summary, contains('actions were not executed'));
    });

    test(
      'keeps exit-zero command output failures after later command success',
      () {
        final failedCommandResult = ToolResultInfo(
          id: 'verify-runtime-behavior',
          name: 'local_execute_command',
          arguments: const {
            'command': 'dart run bin/todo.dart done 999',
            'working_directory': '/tmp/todo',
          },
          result: jsonEncode({
            'command': 'dart run bin/todo.dart done 999',
            'working_directory': '/tmp/todo',
            'exit_code': 0,
            'stdout': '',
            'stderr': 'Unhandled exception: Bad state: task not found.',
          }),
        );
        final feedback = const CodingCommandOutputGuardrailService()
            .buildFeedbackToolResult(
              toolResults: [failedCommandResult],
              now: DateTime(2026, 7, 15),
            );
        final evidence = ToolResultPromptBuilder.completionEvidence([
          failedCommandResult,
          feedback!,
          ToolResultInfo(
            id: 'later-analysis',
            name: 'local_execute_command',
            arguments: const {'command': 'dart analyze'},
            result: jsonEncode({
              'command': 'dart analyze',
              'exit_code': 0,
              'stdout': 'No issues found.',
              'stderr': '',
            }),
          ),
        ]);

        expect(evidence.hasExecutionVerification, isTrue);
        expect(evidence.hasSuccessfulExecutionVerification, isFalse);
        expect(evidence.hasIncompleteEvidence, isTrue);
        expect(evidence.hasBlockingEvidence, isTrue);
        expect(evidence.unresolvedErrorCount, 1);
        expect(evidence.unresolvedErrorDiagnostics, hasLength(1));
        expect(
          evidence.unresolvedErrorDiagnostics.single.code,
          'command_output_failure',
        );
        expect(
          evidence.unresolvedErrorDiagnostics.single.message,
          contains('runtime failure signal'),
        );
      },
    );

    test('keeps mixed verifier failures blocking in either result order', () {
      final analyzeSuccess = ToolResultInfo(
        id: 'analyze-success',
        name: 'local_execute_command',
        arguments: const {'command': 'dart analyze'},
        result: jsonEncode({
          'command': 'dart analyze',
          'exit_code': 0,
          'stdout': 'No errors found.',
          'stderr': '',
        }),
      );
      final testFailure = ToolResultInfo(
        id: 'test-failure',
        name: 'run_tests',
        arguments: const {
          'runner': 'dart',
          'test_path': 'test',
          'working_directory': '/tmp/todo',
        },
        result: jsonEncode({
          'command': "dart test 'test'",
          'exit_code': 65,
          'stdout': 'Could not find package `test`.',
          'stderr': '',
        }),
      );

      for (final toolResults in [
        [analyzeSuccess, testFailure],
        [testFailure, analyzeSuccess],
      ]) {
        final evidence = ToolResultPromptBuilder.completionEvidence(
          toolResults,
        );

        expect(evidence.hasExecutionVerification, isTrue);
        expect(evidence.hasSuccessfulExecutionVerification, isFalse);
        expect(evidence.hasFailedExecutionVerification, isTrue);
        expect(evidence.hasIncompleteEvidence, isTrue);
        expect(evidence.hasBlockingEvidence, isTrue);
        expect(evidence.summary, contains('execution verification failed'));
      }
    });

    test('does not count local inspection as execution verification', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'inspect-state',
          name: 'local_execute_command',
          arguments: const {'command': 'cat .todo.json'},
          result: jsonEncode({
            'command': 'cat .todo.json',
            'exit_code': 0,
            'stdout': '[]',
            'stderr': '',
          }),
        ),
      ]);

      expect(evidence.hasExecutionVerification, isFalse);
      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
    });

    test('does not settle current blocking evidence by generation alone', () {
      const evidence = ToolResultCompletionEvidence(
        unresolvedErrorCount: 1,
        unresolvedErrorDiagnostics: [
          UnresolvedErrorDiagnostic(
            path: '',
            code: 'command_output_failure',
            message: 'Runtime behavior failed.',
          ),
        ],
        hasExecutionVerification: true,
        hasFailedExecutionVerification: true,
      );

      final settled = evidence.settleForExecutionGenerations(
        mutationGeneration: 4,
        verificationGeneration: 4,
      );

      expect(settled.hasIncompleteEvidence, isTrue);
      expect(settled.hasSuccessfulExecutionVerification, isFalse);
      expect(settled.unresolvedErrorCount, 1);
    });

    test('does not treat an already-applied edit as a new mutation', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'tool-1',
          name: 'edit_file',
          arguments: const {},
          result: jsonEncode({
            'path': '/tmp/app/pubspec.yaml',
            'replacements': 0,
            'already_applied': true,
          }),
        ),
      ]);

      expect(evidence.hasIncompleteEvidence, isFalse);
      expect(evidence.unverifiedChangePaths, isEmpty);
      expect(evidence.mutatedWithoutExecutionVerification, isFalse);
    });

    test(
      'classifies goal evidence progress without path churn false positives',
      () {
        expect(
          const ToolResultCompletionEvidence(
            unresolvedErrorCount: 1,
            unresolvedErrorPaths: ['bin/todo_cli.dart'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              unresolvedErrorCount: 2,
              unresolvedErrorPaths: ['bin/todo_cli.dart'],
            ),
          ),
          GoalEvidenceProgress.improved,
        );
        expect(
          const ToolResultCompletionEvidence(
            unresolvedErrorCount: 3,
            unresolvedErrorPaths: ['bin/todo_cli.dart', 'lib/main.dart'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              unresolvedErrorCount: 2,
              unresolvedErrorPaths: ['bin/todo_cli.dart'],
            ),
          ),
          GoalEvidenceProgress.noProgress,
        );
        expect(
          const ToolResultCompletionEvidence(
            unresolvedErrorCount: 2,
            unresolvedErrorPaths: ['lib/main.dart'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              unresolvedErrorCount: 2,
              unresolvedErrorPaths: ['bin/todo_cli.dart'],
            ),
          ),
          GoalEvidenceProgress.noProgress,
        );
        expect(
          const ToolResultCompletionEvidence(
            unverifiedChangePaths: ['README.md'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              unverifiedChangePaths: ['docs/README.md'],
            ),
          ),
          GoalEvidenceProgress.improved,
        );
        expect(
          const ToolResultCompletionEvidence(
            unverifiedChangePaths: ['README.md'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              boundedToolLoopExhausted: true,
              unexecutedToolNames: ['read_file'],
            ),
          ),
          GoalEvidenceProgress.noProgress,
        );
        expect(
          const ToolResultCompletionEvidence(
            boundedToolLoopExhausted: true,
            unexecutedToolNames: ['read_file'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              unverifiedChangePaths: ['README.md'],
            ),
          ),
          GoalEvidenceProgress.noProgress,
        );
        expect(
          const ToolResultCompletionEvidence(
            boundedToolLoopExhausted: true,
            unexecutedToolNames: ['read_file'],
          ).compareProgress(
            const ToolResultCompletionEvidence(
              boundedToolLoopExhausted: true,
              unexecutedToolNames: ['read_file'],
            ),
          ),
          GoalEvidenceProgress.noProgress,
        );
      },
    );

    test('carries unresolved diagnostics across read-only evidence', () {
      const previous = ToolResultCompletionEvidence(
        unresolvedErrorCount: 2,
        unresolvedErrorPaths: ['lib/main.dart'],
        unresolvedErrorDiagnostics: [
          UnresolvedErrorDiagnostic(
            path: 'lib/main.dart',
            code: 'undefined_identifier',
            message: 'Undefined name store.',
          ),
        ],
        hasExecutionVerification: true,
      );

      final carried = const ToolResultCompletionEvidence()
          .carryForwardIncompleteFrom(previous);

      expect(carried.unresolvedErrorCount, 2);
      expect(carried.unresolvedErrorPaths, ['lib/main.dart']);
      expect(carried.unresolvedErrorDiagnostics, hasLength(1));
      expect(
        carried.unresolvedErrorDiagnostics.single.message,
        'Undefined name store.',
      );
      expect(carried.hasIncompleteEvidence, isTrue);
    });

    test('keeps prior diagnostics after a failed execution verification', () {
      const previous = ToolResultCompletionEvidence(
        unresolvedErrorCount: 2,
        unresolvedErrorPaths: ['lib/main.dart'],
        hasExecutionVerification: true,
      );

      final carried = const ToolResultCompletionEvidence(
        hasExecutionVerification: true,
      ).carryForwardIncompleteFrom(previous);

      expect(carried.unresolvedErrorCount, 2);
      expect(carried.hasIncompleteEvidence, isTrue);
    });

    test(
      'settles prior mutation evidence after failed execution verification',
      () {
        const previous = ToolResultCompletionEvidence(
          mutatedWithoutExecutionVerification: true,
          unverifiedChangePaths: ['bin/app.dart'],
        );
        const current = ToolResultCompletionEvidence(
          hasExecutionVerification: true,
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: ['bin/app.dart'],
        );

        final carried = current.carryForwardIncompleteFrom(previous);

        expect(carried.hasExecutionVerification, isTrue);
        expect(carried.mutatedWithoutExecutionVerification, isFalse);
        expect(carried.unverifiedChangePaths, isEmpty);
        expect(carried.unresolvedErrorCount, 1);
        expect(carried.requiresValidationContinuation, isFalse);
      },
    );

    test('replaces prior errors with an authoritative clean snapshot', () {
      const previous = ToolResultCompletionEvidence(
        unresolvedErrorCount: 13,
        unresolvedErrorPaths: ['lib/expense.dart'],
      );

      final carried = const ToolResultCompletionEvidence(
        hasExecutionVerification: true,
        hasAuthoritativeDiagnosticSnapshot: true,
      ).carryForwardIncompleteFrom(previous);

      expect(carried.unresolvedErrorCount, 0);
      expect(carried.unresolvedErrorPaths, isEmpty);
    });

    test(
      'clears prior diagnostics after successful execution verification',
      () {
        const previous = ToolResultCompletionEvidence(
          unresolvedErrorCount: 2,
          unresolvedErrorPaths: ['lib/main.dart'],
          hasExecutionVerification: true,
        );

        final carried = const ToolResultCompletionEvidence(
          hasExecutionVerification: true,
          hasSuccessfulExecutionVerification: true,
        ).carryForwardIncompleteFrom(previous);

        expect(carried.unresolvedErrorCount, 0);
        expect(carried.hasIncompleteEvidence, isFalse);
      },
    );

    test('settles stale evidence when the current mutation is verified', () {
      const evidence = ToolResultCompletionEvidence(
        boundedToolLoopExhausted: true,
        unresolvedErrorCount: 1,
        unresolvedErrorPaths: ['lib/main.dart'],
        unverifiedChangePaths: ['lib/main.dart'],
        mutatedWithoutExecutionVerification: true,
      );

      final settled = evidence.settleForExecutionGenerations(
        mutationGeneration: 3,
        verificationGeneration: 3,
      );

      expect(settled.hasIncompleteEvidence, isFalse);
      expect(settled.hasSuccessfulExecutionVerification, isTrue);
    });

    test(
      'keeps a later unexecuted tool request after generation settlement',
      () {
        const evidence = ToolResultCompletionEvidence(
          boundedToolLoopExhausted: true,
          unexecutedToolNames: ['local_execute_command'],
          hasUnexecutedActionClaim: true,
          mutatedWithoutExecutionVerification: true,
        );

        final settled = evidence.settleForExecutionGenerations(
          mutationGeneration: 1,
          verificationGeneration: 1,
        );

        expect(settled.hasSuccessfulExecutionVerification, isTrue);
        expect(settled.boundedToolLoopExhausted, isTrue);
        expect(settled.unexecutedToolNames, ['local_execute_command']);
        expect(settled.hasUnexecutedActionClaim, isTrue);
        expect(settled.mutatedWithoutExecutionVerification, isFalse);
      },
    );

    test('recognizes an unexecuted verifier as validation evidence', () {
      const evidence = ToolResultCompletionEvidence(
        boundedToolLoopExhausted: true,
        unexecutedToolNames: ['local_execute_command'],
        unresolvedErrorCount: 3,
      );

      expect(evidence.hasPendingExecutionVerification, isTrue);
      expect(evidence.requiresValidationContinuation, isTrue);
    });

    test('keeps evidence when verification predates the latest mutation', () {
      const evidence = ToolResultCompletionEvidence(
        unresolvedErrorCount: 1,
        unresolvedErrorPaths: ['lib/main.dart'],
      );

      final unsettled = evidence.settleForExecutionGenerations(
        mutationGeneration: 4,
        verificationGeneration: 3,
      );

      expect(unsettled, same(evidence));
      expect(unsettled.hasIncompleteEvidence, isTrue);
    });

    test(
      'keeps authoritative success when content evidence is also present',
      () {
        const authoritative = ToolResultCompletionEvidence(
          hasExecutionVerification: true,
          hasSuccessfulExecutionVerification: true,
        );
        final staleContentDiagnostic = ToolResultInfo(
          id: 'content-diagnostic',
          name: 'dart_analyze_feedback',
          arguments: const {},
          result: jsonEncode({
            'diagnostics': [
              {
                'severity': 'Error',
                'path': '/tmp/app/lib/main.dart',
                'relative_path': 'lib/main.dart',
                'code': 'undefined_identifier',
                'message': 'Undefined name.',
              },
            ],
          }),
        );

        final evidence = ToolResultPromptBuilder.reconcileFinalizationEvidence(
          authoritativeEvidence: authoritative,
          completedToolResults: [
            ToolResultInfo(
              id: 'verification',
              name: 'local_execute_command',
              arguments: const {},
              result: jsonEncode({'exit_code': 0}),
            ),
          ],
          contentToolResults: [staleContentDiagnostic],
        );

        expect(evidence, same(authoritative));
        expect(evidence.hasIncompleteEvidence, isFalse);
      },
    );

    test('uses content evidence when no tool-aware results completed', () {
      final contentDiagnostic = ToolResultInfo(
        id: 'content-diagnostic',
        name: 'dart_analyze_feedback',
        arguments: const {},
        result: jsonEncode({
          'diagnostics': [
            {
              'severity': 'Error',
              'path': '/tmp/app/lib/main.dart',
              'relative_path': 'lib/main.dart',
              'code': 'undefined_identifier',
              'message': 'Undefined name.',
            },
          ],
        }),
      );

      final evidence = ToolResultPromptBuilder.reconcileFinalizationEvidence(
        authoritativeEvidence: const ToolResultCompletionEvidence(),
        completedToolResults: const [],
        contentToolResults: [contentDiagnostic],
      );

      expect(evidence.unresolvedErrorCount, 1);
      expect(evidence.hasIncompleteEvidence, isTrue);
    });

    test(
      'does not surface unverified file changes after a verification run',
      () {
        final evidence = ToolResultPromptBuilder.completionEvidence([
          ToolResultInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {},
            result: jsonEncode({
              'path': '/tmp/app/bin/todo_cli.dart',
              'bytes_written': 120,
              'created': true,
            }),
          ),
          ToolResultInfo(
            id: 'tool-2',
            name: 'local_execute_command',
            arguments: const {'command': 'dart test'},
            result: jsonEncode({'exit_code': 0, 'stdout': 'ok'}),
          ),
        ]);

        expect(evidence.hasIncompleteEvidence, isFalse);
        expect(evidence.unverifiedChangePaths, isEmpty);
        expect(evidence.mutatedWithoutExecutionVerification, isFalse);
      },
    );

    test('invalidates verification when a later mutation lands', () {
      final evidence = ToolResultPromptBuilder.completionEvidence([
        ToolResultInfo(
          id: 'verify-1',
          name: 'local_execute_command',
          arguments: const {'command': 'dart test'},
          result: jsonEncode({'exit_code': 0}),
        ),
        ToolResultInfo(
          id: 'edit-1',
          name: 'edit_file',
          arguments: const {},
          result: jsonEncode({
            'path': '/tmp/app/lib/main.dart',
            'replacements': 1,
          }),
        ),
      ]);

      expect(evidence.hasSuccessfulExecutionVerification, isFalse);
      expect(evidence.hasExecutionVerification, isFalse);
      expect(evidence.mutatedWithoutExecutionVerification, isTrue);
      expect(evidence.unverifiedChangePaths, ['/tmp/app/lib/main.dart']);
    });

    test('recognizes every execution-class verification tool', () {
      for (final toolName in const [
        'local_execute_command',
        'run_tests',
        'git_execute_command',
        'process_start',
        'process_wait',
      ]) {
        final evidence = ToolResultPromptBuilder.completionEvidence([
          ToolResultInfo(
            id: 'mutation',
            name: 'write_file',
            arguments: const {},
            result: jsonEncode({'path': '/tmp/app/lib/main.dart'}),
          ),
          ToolResultInfo(
            id: 'execution',
            name: toolName,
            arguments: toolName == 'local_execute_command'
                ? const {'command': 'dart test'}
                : const {},
            result: jsonEncode(
              toolName.startsWith('process_') ? {'ok': true} : {'exit_code': 0},
            ),
          ),
        ]);

        expect(
          evidence.mutatedWithoutExecutionVerification,
          isFalse,
          reason: toolName,
        );
      }
    });

    test('separates memory extraction errors from chat-turn stop causes', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {'command': 'inspect session log'},
          result: jsonEncode({
            'stdout':
                'L49 request messages: memory_extractor_system, memory_extractor_user\n'
                'L49 error: Failed to load model qwen/qwen3-coder-next\n'
                'L53 finishReason: stop; toolCalls: 0',
            'exit_code': 0,
          }),
        ),
      ]);

      expect(prompt, contains('separate the user-facing chat turn'));
      expect(prompt, contains('background secondary calls'));
      expect(prompt, contains('memory_extractor_system'));
      expect(prompt, contains('post-response memory extraction calls'));
      expect(
        prompt,
        contains('Do not cite their model-load, transport, or JSON errors'),
      );
      expect(prompt, contains('latest non-memory-extraction chat entry'));
      expect(prompt, contains('code=tool_call_not_executed'));
      expect(prompt, contains('harness diagnostic'));
      expect(prompt, contains('target log evidence'));
      expect(
        prompt.indexOf('separate the user-facing chat turn'),
        lessThan(prompt.indexOf('[Tool: local_execute_command]')),
      );
    });

    test(
      'does not flag analyzer errors superseded by a later edit on same file',
      () {
        const dartPath = '/Users/dev/tmp/primes.dart';
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {'path': dartPath},
            result: jsonEncode({
              'path': dartPath,
              'bytes_written': 1354,
              'created': true,
            }),
          ),
          ToolResultInfo(
            id: 'tool-2',
            name: 'dart_analyze_feedback',
            arguments: const {
              'project_root': '/Users/dev/tmp',
              'changed_paths': ['primes.dart'],
            },
            result: jsonEncode({
              'schema': 'caverno_dart_analyze_feedback',
              'current_diagnostic_count': 1,
              'diagnostics': [
                {
                  'path': dartPath,
                  'relative_path': 'primes.dart',
                  'severity': 'Error',
                  'code': 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
                  'message':
                      "The argument type 'String' can't be assigned to "
                      "the parameter type 'num'.",
                },
              ],
            }),
          ),
          // The fix lands AFTER the analyzer ran; the analyzer is not re-run,
          // so its diagnostic is stale and must not block completion.
          ToolResultInfo(
            id: 'tool-3',
            name: 'edit_file',
            arguments: const {'path': dartPath},
            result: jsonEncode({
              'path': dartPath,
              'replacements': 1,
              'replace_all': false,
            }),
          ),
        ]);

        expect(prompt, isNot(contains('TASK NOT COMPLETE:')));
      },
    );

    test(
      'still flags analyzer errors when a later edit failed on the same file',
      () {
        const dartPath = '/Users/dev/tmp/primes.dart';
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'dart_analyze_feedback',
            arguments: const {'project_root': '/Users/dev/tmp'},
            result: jsonEncode({
              'schema': 'caverno_dart_analyze_feedback',
              'diagnostics': [
                {
                  'path': dartPath,
                  'relative_path': 'primes.dart',
                  'severity': 'Error',
                  'code': 'UNDEFINED_METHOD',
                  'message': "The method 'sqrt' isn't defined.",
                },
              ],
            }),
          ),
          // A dropped/failed edit does not resolve the diagnostic.
          ToolResultInfo(
            id: 'tool-2',
            name: 'edit_file',
            arguments: const {'path': dartPath},
            result: jsonEncode({
              'code': 'tool_call_not_executed',
              'reason': 'bounded_tool_loop_exhausted',
              'tool_name': 'edit_file',
            }),
          ),
        ]);

        expect(prompt, contains('TASK NOT COMPLETE:'));
        expect(prompt, contains('1 unresolved Error-severity diagnostic(s)'));
      },
    );

    test(
      'counts a persistent error once across stale and fresh analyzer passes',
      () {
        const dartPath = '/Users/dev/tmp/primes.dart';
        final diagnostic = {
          'path': dartPath,
          'relative_path': 'primes.dart',
          'severity': 'Error',
          'line': 46,
          'column': 50,
          'code': 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
          'message':
              "The argument type 'String' can't be assigned to the "
              "parameter type 'num'.",
        };
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          // Stale per-batch feedback (before the unrelated edit).
          ToolResultInfo(
            id: 'tool-1',
            name: 'dart_analyze_feedback',
            arguments: const {'project_root': '/Users/dev/tmp'},
            result: jsonEncode({
              'schema': 'caverno_dart_analyze_feedback',
              'diagnostics': [diagnostic],
            }),
          ),
          // A dropped edit does not resolve it, so the stale result is not
          // superseded.
          ToolResultInfo(
            id: 'tool-2',
            name: 'edit_file',
            arguments: const {'path': dartPath},
            result: jsonEncode({
              'code': 'tool_call_not_executed',
              'reason': 'bounded_tool_loop_exhausted',
              'tool_name': 'edit_file',
            }),
          ),
          // Fresh authoritative final pass reports the same persistent error.
          ToolResultInfo(
            id: 'tool-3',
            name: 'dart_analyze_feedback',
            arguments: const {'project_root': '/Users/dev/tmp'},
            result: jsonEncode({
              'schema': 'caverno_dart_analyze_feedback',
              'diagnostics': [diagnostic],
            }),
          ),
        ]);

        expect(prompt, contains('TASK NOT COMPLETE:'));
        expect(prompt, contains('1 unresolved Error-severity diagnostic(s)'));
        expect(
          prompt,
          isNot(contains('2 unresolved Error-severity diagnostic(s)')),
        );
      },
    );

    test(
      'does not inject completion blockers for an edited-then-run change',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {'path': '/tmp/ok.py'},
            result: '{"path":"/tmp/ok.py","bytes_written":12,"created":true}',
          ),
          // Running the change after the edit verifies it.
          ToolResultInfo(
            id: 'tool-2',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 /tmp/ok.py'},
            result: jsonEncode({
              'command': 'python3 /tmp/ok.py',
              'exit_code': 0,
              'stdout': 'ok\n',
              'stderr': '',
            }),
          ),
        ]);

        expect(prompt, isNot(contains('TASK NOT COMPLETE:')));
        expect(prompt, isNot(contains('UNVERIFIED CHANGE:')));
      },
    );

    test(
      'flags an edit that was never run or tested in the turn as unverified',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          // Mirrors the prime-benchmark log: a turn of read/edit cycles with no
          // execution, yet the model claims it fixed the bug.
          ToolResultInfo(
            id: 'tool-1',
            name: 'edit_file',
            arguments: const {'path': '/tmp/prime_benchmark.py'},
            result: jsonEncode({
              'path': '/tmp/prime_benchmark.py',
              'replacements': 1,
              'replace_all': false,
            }),
          ),
          ToolResultInfo(
            id: 'tool-2',
            name: 'read_file',
            arguments: const {'path': '/tmp/prime_benchmark.py'},
            result: jsonEncode({
              'path': '/tmp/prime_benchmark.py',
              'content': 'def f(): ...',
            }),
          ),
        ]);

        expect(prompt, contains('UNVERIFIED CHANGE:'));
        expect(prompt, contains('nothing was run or tested in this turn'));
      },
    );

    test('flags a mutation that lands after the last verification', () {
      // Even a cosmetic edit advances the mutation generation, so the earlier
      // run cannot verify the final artifact.
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {'command': 'dart run bin/benchmark.dart'},
          result: jsonEncode({
            'command': 'dart run bin/benchmark.dart',
            'exit_code': 0,
            'stdout': '78498 primes\n',
          }),
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'edit_file',
          arguments: const {'path': '/tmp/benchmark.dart'},
          result: jsonEncode({
            'path': '/tmp/benchmark.dart',
            'replacements': 1,
          }),
        ),
      ]);

      expect(prompt, contains('UNVERIFIED CHANGE:'));
    });

    test('guards against unverified local file side-effect claims', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'http_get',
          arguments: const {'url': 'https://example.com/weather'},
          result: '{"status_code":200,"body":"Weather data"}',
        ),
      ]);

      expect(prompt, contains('Only claim that a local file was created'));
      expect(prompt, contains('code=unexecuted_file_save'));
      expect(prompt, contains('If the user requested local file changes'));
      expect(prompt, contains('the files were not created yet'));
      expect(prompt, contains('When a write_file result includes'));
      expect(prompt, contains('existing file was updated or overwritten'));
      expect(prompt, contains('new file was created'));
      expect(prompt, contains('instead of emitting tool-call tags'));
      expect(prompt, contains('This final answer request cannot call tools'));
      expect(prompt, contains('Do not output JSON command arrays'));
      expect(prompt, contains('state that it remains unexecuted'));
      expect(prompt, contains('When browser_snapshot returns page elements'));
      expect(
        prompt,
        contains('refs are valid only for the current page snapshot'),
      );
      expect(prompt, contains('Do not invent or renumber browser refs'));
      expect(prompt, contains('element_not_found or a stale target'));
      expect(prompt, contains('fresh browser_snapshot before retrying'));
      expect(prompt, contains('Only say a browser action'));
      expect(prompt, contains('corresponding browser tool result succeeded'));
      expect(prompt, contains('code=unexecuted_browser_action'));
      expect(prompt, contains('For browser_click results'));
      expect(prompt, contains('target label, name'));
      expect(prompt, contains('navigated fields'));
      expect(prompt, contains('what was actually clicked'));
      expect(prompt, contains('browser_submit retry'));
      expect(prompt, contains('When browser_save_data succeeds'));
      expect(prompt, contains('tool result path field exactly'));
      expect(prompt, contains('trust the result path'));
      expect(prompt, contains('Do not restate an investigation plan'));
      expect(prompt, contains('answer from the executed tool results'));
      expect(
        prompt,
        contains(
          'When the provided tool results already satisfy the user\'s requested local action or saved coding goal',
        ),
      );
      expect(prompt, contains('end after the concise completion evidence'));
      expect(
        prompt,
        contains(
          'Do not add optional follow-up questions, offers, or suggestions',
        ),
      );
      expect(prompt, contains('When a load_skill result contains explicit'));
      expect(prompt, contains('Do not add optional follow-up questions'));
      expect(prompt, contains('Do not convert a missing source file'));
      expect(prompt, contains('preserve that blocker'));
      expect(prompt, contains('Treat search_past_conversations'));
      expect(prompt, contains('historical context'));
      expect(prompt, contains('not verified evidence'));
      expect(prompt, contains('current application-executed tool results'));
      expect(prompt, contains('Do not treat finishReason=stream_end'));
      expect(prompt, contains('unfinished tool-call tag'));
      expect(prompt, contains('concrete transport error'));
      expect(prompt, isNot(contains('<tool_use>')));
    });

    test('marks write_file created false as an existing file update', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': '/tmp/tokyo_weather_2026-06-02.md'},
          result: jsonEncode({
            'path': '/tmp/tokyo_weather_2026-06-02.md',
            'bytes_written': 504,
            'created': false,
          }),
        ),
      ]);

      expect(prompt, contains('[Tool: write_file]'));
      expect(prompt, contains('Arguments:'));
      expect(
        prompt,
        contains(
          'Operation note: write_file updated or overwrote an existing file',
        ),
      );
      expect(prompt, contains('/tmp/tokyo_weather_2026-06-02.md'));
      expect(
        prompt,
        contains('mention this existing-file update in the final answer'),
      );
      expect(prompt, contains('"created":false'));
    });

    test('marks write_file created true as a new file creation', () {
      final note = ToolResultPromptBuilder.buildToolOperationNote(
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': '/tmp/weather.md'},
          result: jsonEncode({
            'path': '/tmp/weather.md',
            'bytes_written': 128,
            'created': true,
          }),
        ),
      );

      expect(note, 'write_file created a new file at /tmp/weather.md.');
    });

    test('adds Open-Meteo WMO weather code interpretation notes', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'http_get',
          arguments: const {'url': 'https://api.open-meteo.com/v1/forecast'},
          result: jsonEncode({
            'url': 'https://api.open-meteo.com/v1/forecast',
            'status_code': 200,
            'content_type': 'application/json; charset=utf-8',
            'body': jsonEncode({
              'daily_units': {'weathercode': 'wmo code'},
              'daily': {
                'time': ['2026-06-03'],
                'weathercode': [65],
              },
            }),
          }),
        ),
      ]);

      expect(prompt, contains('Interpretation note:'));
      expect(
        prompt,
        contains(
          'Open-Meteo daily 2026-06-03 weather code 65 = Rain: Heavy intensity.',
        ),
      );
      expect(
        prompt,
        contains(
          'drizzle codes are 51, 53, and 55, while rain codes are 61, 63, and 65',
        ),
      );
    });

    test('marks recalled conversation results as unverified context', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'search_past_conversations',
          arguments: const {'query': 'Android BLE data corruption'},
          result: 'assistant: The root cause is native-side byte conversion.',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'list_directory',
          arguments: const {'path': 'packages/universal_ble'},
          result:
              '{"error":"Directory does not exist: /workspace/packages/universal_ble"}',
        ),
      ]);

      expect(prompt, contains('[Tool: search_past_conversations]'));
      expect(
        prompt,
        contains('Scope note: This is recalled historical context'),
      );
      expect(prompt, contains('prior assistant hypotheses'));
      expect(prompt, contains('treat it as unverified'));
      expect(prompt, contains('Directory does not exist'));
    });

    test('marks zero-match discovery results as inconclusive', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'find-1',
          name: 'find_files',
          arguments: const {'pattern': '*release*note*'},
          result: jsonEncode({
            'path': '/workspace',
            'pattern': '*release*note*',
            'matches': const <String>[],
            'match_count': 0,
          }),
        ),
        ToolResultInfo(
          id: 'search-1',
          name: 'search_files',
          arguments: const {'query': 'Release notes'},
          result: jsonEncode({
            'path': '/workspace',
            'query': 'Release notes',
            'matches': const <String>[],
            'match_count': 0,
            'scanned_files': 42,
          }),
        ),
      ]);

      final findDecoded =
          jsonDecode(budgeted.first.result) as Map<String, dynamic>;
      final searchDecoded =
          jsonDecode(budgeted.last.result) as Map<String, dynamic>;

      expect(findDecoded['discovery_hint'], contains('exact filename glob'));
      expect(findDecoded['discovery_hint'], contains('list_directory'));
      expect(searchDecoded['discovery_hint'], contains('exact content query'));
      expect(searchDecoded['discovery_hint'], contains('filename search'));

      final prompt = ToolResultPromptBuilder.buildAnswerPrompt(budgeted);
      expect(prompt, contains('zero matches only proves'));
      expect(prompt, contains('Before saying a requested file or content'));
    });

    test('does not mark non-empty discovery results as inconclusive', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'find-1',
          name: 'find_files',
          arguments: const {'pattern': '*.md'},
          result: jsonEncode({
            'path': '/workspace',
            'pattern': '*.md',
            'matches': const ['docs/releases/caverno-1.3.8.md'],
            'match_count': 1,
          }),
        ),
      ]);

      final decoded =
          jsonDecode(budgeted.single.result) as Map<String, dynamic>;

      expect(decoded, isNot(contains('discovery_hint')));
    });

    test('redacts screenshot base64 from answer prompts', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'computer_screenshot',
          arguments: const {},
          result:
              '{"imageBase64":"large-payload","imageMimeType":"image/png","width":800,"height":600}',
        ),
      ]);

      expect(prompt, isNot(contains('large-payload')));
      expect(prompt, contains('[attached as image content]'));
      expect(prompt, contains('"width":800'));
    });

    test('reduces oversized read_file content for prompt budget', () {
      final largeContent = '${'A' * 9000}\nneedle\n${'B' * 9000}';
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: jsonEncode({
            'path': '/workspace/lib/main.dart',
            'content': largeContent,
            'size_bytes': largeContent.length,
            'start_line': 1,
            'line_count': 400,
            'total_lines': 800,
          }),
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final decoded =
          jsonDecode(budgeted.single.result) as Map<String, dynamic>;

      expect(decoded['content'], isNot(contains('needle')));
      expect(decoded['content_reduced_for_prompt_budget'], isTrue);
      expect(decoded['read_more_hint'], contains('read_file'));
      expect(
        (decoded['content'] as String).length,
        lessThan(largeContent.length),
      );
    });

    test('does not stub stale tool results in normal budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'read-old',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'old content',
        ),
        ToolResultInfo(
          id: 'read-new',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'new content',
        ),
      ]);

      expect(budgeted.first.result, 'old content');
      expect(budgeted.last.result, 'new content');
    });

    test('stubs stale tool results in compact budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'read-old',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'old content',
        ),
        ToolResultInfo(
          id: 'read-new',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'new content',
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      expect(budgeted.first.result, contains('stale tool result omitted'));
      expect(budgeted.first.result, contains('newer read_file'));
      expect(budgeted.last.result, 'new content');
    });

    test('keeps protected stale tool results in compact budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults(
        [
          ToolResultInfo(
            id: 'read-old',
            name: 'read_file',
            arguments: const {'path': '/workspace/lib/main.dart'},
            result: 'old content',
          ),
          ToolResultInfo(
            id: 'read-new',
            name: 'read_file',
            arguments: const {'path': '/workspace/lib/main.dart'},
            result: 'new content',
          ),
        ],
        mode: ToolResultPromptBudgetMode.compact,
        protectedPaths: const {'lib/main.dart'},
      );

      expect(budgeted.first.result, 'old content');
      expect(budgeted.last.result, 'new content');
    });

    test('reduces search result lists and exposes the next offset', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'search_files',
          arguments: const {'query': 'TODO'},
          result: jsonEncode({
            'path': '/workspace',
            'query': 'TODO',
            'matches': List<String>.generate(
              60,
              (index) => 'lib/file_$index.dart:${index + 1}: TODO',
            ),
            'match_count': 60,
            'offset': 20,
          }),
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final decoded =
          jsonDecode(budgeted.single.result) as Map<String, dynamic>;

      expect(decoded['matches'], hasLength(40));
      expect(decoded['matches_reduced_for_prompt_budget'], isTrue);
      expect(decoded['omitted_matches_count'], 20);
      expect(decoded['next_offset'], 60);
    });

    test('keeps only the latest compact image attachment payload', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'computer_screenshot',
          arguments: const {},
          result:
              '{"imageBase64":"first-image","imageMimeType":"image/png","width":800}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'computer_screenshot_window',
          arguments: const {},
          result:
              '{"imageBase64":"latest-image","imageMimeType":"image/png","width":600}',
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final first = jsonDecode(budgeted.first.result) as Map<String, dynamic>;
      final second = jsonDecode(budgeted.last.result) as Map<String, dynamic>;

      expect(first['imageBase64'], isNot('first-image'));
      expect(first['image_omitted_for_prompt_budget'], isTrue);
      expect(second['imageBase64'], 'latest-image');
    });
  });
}

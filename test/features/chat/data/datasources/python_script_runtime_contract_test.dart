import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:test/test.dart';

import 'python_script_runtime_test_support.dart';

void main() {
  group('PythonScriptRuntimeInput', () {
    test('freezes strict JSON and computes an order-independent digest', () {
      final nested = <String, dynamic>{
        'paths': <Object?>['input.png'],
      };
      final arguments = <String, dynamic>{
        'code': 'print("ok")',
        'metadata': nested,
      };
      final first = PythonScriptRuntimeInput(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(arguments: arguments),
      );
      final reordered = PythonScriptRuntimeInput(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(
          arguments: const {
            'metadata': {
              'paths': ['input.png'],
            },
            'code': 'print("ok")',
          },
        ),
      );

      (nested['paths'] as List<Object?>).add('poison.png');
      nested['late'] = true;
      arguments['code'] = 'print("poison")';

      expect(first.identity, reordered.identity);
      expect(first.arguments, {
        'code': 'print("ok")',
        'metadata': {
          'paths': ['input.png'],
        },
      });
      expect(
        () => (first.arguments['metadata'] as Map)['late'] = true,
        throwsUnsupportedError,
      );
    });

    test('rejects ambiguous invocation and non-JSON argument identities', () {
      for (final call in [
        testPythonToolCall(id: ' python-call'),
        testPythonToolCall(name: 'run_python_script '),
        testPythonToolCall(name: 'read_file'),
      ]) {
        expect(
          () =>
              PythonScriptRuntimeInput(owner: testPythonOwner, toolCall: call),
          throwsArgumentError,
        );
      }
      for (final invalid in <Object?>[
        <String>{'mutable'},
        <Object?, Object?>{7: 'not-a-string-key'},
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => PythonScriptRuntimeInput(
            owner: testPythonOwner,
            toolCall: testPythonToolCall(
              arguments: {'code': 'print(1)', 'invalid': invalid},
            ),
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('Python runtime identities', () {
    test('binds the full immutable owner message snapshot', () {
      final invocation = PythonScriptRuntimeInput(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(),
      ).identity;
      final firstMessage = testPythonMessage();
      final first = PythonScriptRuntimeIdentity(
        invocation: invocation,
        ownerMessages: [firstMessage],
      );
      final same = PythonScriptRuntimeIdentity(
        invocation: invocation,
        ownerMessages: [firstMessage],
      );
      final changedContent = PythonScriptRuntimeIdentity(
        invocation: invocation,
        ownerMessages: [
          firstMessage.copyWith(content: 'Different owner content'),
        ],
      );
      final changedAttachment = PythonScriptRuntimeIdentity(
        invocation: invocation,
        ownerMessages: [
          firstMessage.copyWith(originalImagePath: '/other/input.png'),
        ],
      );

      expect(first, same);
      expect(first, isNot(changedContent));
      expect(first, isNot(changedAttachment));
    });

    test('chains cache, directory, and execution argument identities', () {
      final input = PythonScriptRuntimeInput(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(),
      );
      final runtime = PythonScriptRuntimeIdentity(
        invocation: input.identity,
        ownerMessages: [testPythonMessage()],
      );
      final cache = PythonApprovalRuntimeIdentity(
        runtime: runtime,
        cacheArguments: const {'code': 'print("ok")'},
      );
      final changedCache = PythonApprovalRuntimeIdentity(
        runtime: runtime,
        cacheArguments: const {'code': 'print("changed")'},
      );
      final directory = PythonStagingDirectoryIdentity(
        canonicalPath: '/tmp/caverno_python_identity',
        markerNonce: 'marker',
      );
      final execution = PythonExecutionRuntimeIdentity(
        runtime: runtime,
        directoryIdentity: directory,
        arguments: const {'code': 'print("ok")', 'timeout_seconds': 7},
      );
      final reordered = PythonExecutionRuntimeIdentity(
        runtime: runtime,
        directoryIdentity: directory,
        arguments: const {'timeout_seconds': 7, 'code': 'print("ok")'},
      );

      expect(cache, isNot(changedCache));
      expect(execution, reordered);
      expect(
        execution,
        isNot(
          PythonExecutionRuntimeIdentity(
            runtime: runtime,
            directoryIdentity: directory,
            arguments: const {'code': 'print("ok")', 'timeout_seconds': 8},
          ),
        ),
      );
    });

    test('execution request rejects arguments outside its digest', () {
      final input = PythonScriptRuntimeInput(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(),
      );
      final runtime = PythonScriptRuntimeIdentity(
        invocation: input.identity,
        ownerMessages: const <Message>[],
      );
      final identity = PythonExecutionRuntimeIdentity(
        runtime: runtime,
        directoryIdentity: PythonStagingDirectoryIdentity(
          canonicalPath: '/tmp/caverno_python_execution',
          markerNonce: 'marker',
        ),
        arguments: const {'code': 'print(1)'},
      );
      final authority = PythonScriptExecutionAuthority();
      final permit = authority
          .reserve(
            owner: testPythonOwner,
            identity: identity,
            ownerIsCurrent: () => true,
          )
          .permit!;

      expect(
        () => PythonRuntimeExecutionRequest(
          identity: identity,
          arguments: const {'code': 'print(2)'},
          effectPermit: permit,
        ),
        throwsArgumentError,
      );
    });
  });
}

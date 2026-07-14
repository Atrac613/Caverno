import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultCompletionEvidence evidence(List<Map<String, Object?>> items) {
    return ToolResultPromptBuilder.completionEvidence([
      ToolResultInfo(
        id: 'diagnostics',
        name: 'local_execute_command',
        arguments: const {'command': 'dart analyze'},
        result: jsonEncode({'diagnostics': items}),
      ),
    ]);
  }

  Map<String, Object?> diagnostic({
    required String path,
    required String relativePath,
    required String code,
    required String message,
    int line = 10,
  }) => {
    'severity': 'Error',
    'path': path,
    'relative_path': relativePath,
    'line': line,
    'column': 4,
    'code': code,
    'message': message,
  };

  test('is stable across diagnostic ordering and location changes', () {
    final first = diagnostic(
      path: '/tmp/run-a/lib/main.dart',
      relativePath: 'lib/main.dart',
      code: 'undefined_identifier',
      message: 'Undefined name at /tmp/run-a/lib/main.dart:10:4',
    );
    final second = diagnostic(
      path: '/tmp/run-a/lib/store.dart',
      relativePath: 'lib/store.dart',
      code: 'missing_method',
      message: 'Missing method at line 20 column 3',
    );
    final signatureA = evidence([first, second]).diagnosticSignature;
    final signatureB = evidence([
      diagnostic(
        path: '/tmp/run-b/lib/store.dart',
        relativePath: 'lib/store.dart',
        code: 'missing_method',
        message: 'Missing method at line 99 column 8',
        line: 99,
      ),
      diagnostic(
        path: '/tmp/run-b/lib/main.dart',
        relativePath: 'lib/main.dart',
        code: 'undefined_identifier',
        message: 'Undefined name at /tmp/run-b/lib/main.dart:44:9',
        line: 44,
      ),
    ]).diagnosticSignature;

    expect(signatureB, signatureA);
  });

  test('changes for substantive code, path, or message changes', () {
    final original = evidence([
      diagnostic(
        path: '/tmp/lib/main.dart',
        relativePath: 'lib/main.dart',
        code: 'undefined_identifier',
        message: 'Undefined name store',
      ),
    ]).diagnosticSignature;
    final changed = evidence([
      diagnostic(
        path: '/tmp/lib/main.dart',
        relativePath: 'lib/main.dart',
        code: 'missing_method',
        message: 'Missing method save',
      ),
    ]).diagnosticSignature;

    expect(changed, isNot(original));
  });
}

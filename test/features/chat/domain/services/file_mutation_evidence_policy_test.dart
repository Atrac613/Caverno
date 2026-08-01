import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_evidence_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = FileMutationEvidencePolicy();

  ToolResultInfo result(String value, {Object? path = 'lib/main.dart'}) {
    return ToolResultInfo(
      id: 'result-1',
      name: 'write_file',
      arguments: path == null ? const {} : {'path': path},
      result: value,
    );
  }

  group('mutation tool classification', () {
    test('accepts every supported mutation tool name', () {
      for (final name in [
        'write_file',
        'edit_file',
        'delete_file',
        'rollback_last_file_change',
        '  WRITE_FILE  ',
      ]) {
        expect(policy.isMutationToolName(name), isTrue, reason: name);
      }
    });

    test('rejects non-mutation and empty tool names', () {
      for (final name in [
        '',
        'read_file',
        'browser_save_data',
        'write_file_v2',
        'edit_directory',
      ]) {
        expect(policy.isMutationToolName(name), isFalse, reason: name);
      }
    });
  });

  group('successful result classification', () {
    test('accepts plain, malformed, and non-object success payloads', () {
      for (final value in [
        'Saved lib/main.dart',
        '{not-json',
        '[]',
        'true',
        'null',
        '{"error":null,"already_applied":false,"code":"ok"}',
        '{"already_applied":"true"}',
        '{"ok":false}',
        '{"code":"edit_mismatch"}',
      ]) {
        expect(policy.isSuccessfulResult(result(value)), isTrue, reason: value);
      }
    });

    test('rejects empty and explicit textual failures', () {
      for (final value in [
        '',
        '   ',
        'Error: write failed',
        '  AUTO-REVIEW DENIED: unsafe target',
      ]) {
        expect(
          policy.isSuccessfulResult(result(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('rejects structured errors and already-applied results', () {
      for (final value in [
        '{"error":"write failed"}',
        '{"error":false}',
        '{"already_applied":true}',
      ]) {
        expect(
          policy.isSuccessfulResult(result(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('rejects every structured failure code after normalization', () {
      for (final code in [
        'permission_denied',
        ' BOOKMARK_RESTORE_FAILED ',
        'tool_execution_failed',
      ]) {
        final value = '{"code":"$code"}';
        expect(policy.isSuccessfulResult(result(value)), isFalse, reason: code);
      }
    });
  });

  group('path extraction', () {
    test('trims a non-empty result payload path', () {
      expect(
        policy.resultPayloadPath('{"path":"  lib/result.dart  "}'),
        'lib/result.dart',
      );
      expect(
        policy.resultPayloadPath(
          '{"error":"write failed","path":"lib/failed.dart"}',
        ),
        'lib/failed.dart',
      );
    });

    test('rejects invalid result payload paths', () {
      for (final value in [
        'not-json',
        '[]',
        'null',
        '{}',
        '{"path":1}',
        '{"path":"  "}',
        '{"Path":"lib/wrong-case.dart"}',
        '{"meta":{"path":"lib/nested.dart"}}',
      ]) {
        expect(policy.resultPayloadPath(value), isNull, reason: value);
      }
    });

    test('trims a non-empty argument path from any map', () {
      expect(
        policy.argumentPath(const <Object, Object>{
          'path': '  lib/argument.dart  ',
        }),
        'lib/argument.dart',
      );
    });

    test('rejects missing, non-map, non-string, and empty arguments', () {
      for (final arguments in <Object?>[
        null,
        const [],
        '{"path":"lib/string.dart"}',
        const {},
        const {'path': 1},
        const {'path': '  '},
        const {'Path': 'lib/wrong-case.dart'},
        const {
          'meta': {'path': 'lib/nested.dart'},
        },
      ]) {
        expect(policy.argumentPath(arguments), isNull, reason: '$arguments');
      }
    });

    test('prefers the result payload path over the argument path', () {
      expect(
        policy.pathForResult(
          result('{"path":"lib/result.dart"}', path: 'lib/argument.dart'),
        ),
        'lib/result.dart',
      );
    });

    test('falls back to arguments when the result has no valid path', () {
      expect(
        policy.pathForResult(result('saved', path: ' lib/argument.dart ')),
        'lib/argument.dart',
      );
      expect(policy.pathForResult(result('saved', path: null)), isNull);
    });
  });
}

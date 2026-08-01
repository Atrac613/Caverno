import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_mutation_signature.dart';
import 'package:test/test.dart';

const _signature = CodingVerificationMutationSignature();

ToolResultInfo _result({
  required String id,
  String name = 'write_file',
  String? argumentPath = 'lib/main.dart',
  String result = 'saved',
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: argumentPath == null ? const {} : {'path': argumentPath},
    result: result,
  );
}

CodingVerificationMutationSignatureInput _input(
  List<ToolResultInfo> toolResults, {
  String? projectRoot = '/workspace/project',
}) {
  return CodingVerificationMutationSignatureInput(
    toolResults: toolResults,
    projectRoot: projectRoot,
  );
}

List<Map<String, dynamic>> _decode(String signature) {
  return (jsonDecode(signature) as List).cast<Map<String, dynamic>>().toList(
    growable: false,
  );
}

void main() {
  group('CodingVerificationMutationSignatureInput', () {
    test('freezes the exact owner tool-result snapshot', () {
      final owners = <Object?>['owner-a'];
      final metadata = <String, dynamic>{
        'paths': <Object?>['lib/main.dart'],
        'owners': owners,
        'labels': <String, Object?>{'7': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'path': 'lib/main.dart',
        'metadata': metadata,
      };
      final ownerResults = [
        ToolResultInfo(
          id: 'owner-a',
          name: 'write_file',
          arguments: arguments,
          result: 'saved',
        ),
      ];
      final input = _input(ownerResults);

      ownerResults.clear();
      arguments['path'] = 'lib/visible.dart';
      (metadata['paths']! as List<Object?>).add('lib/visible.dart');
      owners.add('owner-b');
      (metadata['labels']! as Map)['7'] = 'owner-b';

      expect(input.toolResults.map((result) => result.id), ['owner-a']);
      expect(input.toolResults.single.arguments['path'], 'lib/main.dart');
      expect(
        (input.toolResults.single.arguments['metadata']
            as Map<String, dynamic>)['paths'],
        ['lib/main.dart'],
      );
      expect(
        (input.toolResults.single.arguments['metadata']
            as Map<String, dynamic>)['owners'],
        ['owner-a'],
      );
      final frozenLabels =
          (input.toolResults.single.arguments['metadata']
                  as Map<String, dynamic>)['labels']
              as Map;
      expect(frozenLabels, {'7': 'owner-a'});
      expect(
        () => input.toolResults.add(_result(id: 'owner-b')),
        throwsUnsupportedError,
      );
      expect(
        () => input.toolResults.single.arguments['path'] = 'lib/other.dart',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.toolResults.single.arguments['metadata']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('lib/other.dart'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.toolResults.single.arguments['metadata']
                        as Map<String, dynamic>)['owners']
                    as List<Object?>)
                .add('owner-b'),
        throwsUnsupportedError,
      );
      expect(() => frozenLabels['7'] = 'late', throwsUnsupportedError);
    });

    test('rejects every non-JSON argument shape', () {
      final invalidValues = <Object?>[
        _MutableArgument(),
        <Object?, Object?>{7: 'owner-a'},
        <Object?>{'not-json'},
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => _input([
            ToolResultInfo(
              id: 'invalid',
              name: 'write_file',
              arguments: {'metadata': invalidValue},
              result: 'saved',
            ),
          ]),
          throwsArgumentError,
          reason: invalidValue.toString(),
        );
      }
    });
  });

  group('compute', () {
    test('returns null for empty or ineligible evidence', () {
      expect(_signature.compute(_input(const [])), isNull);
      expect(
        _signature.compute(
          _input([
            _result(id: 'read', name: 'read_file'),
            _result(
              id: 'failed',
              result: '{"error":"write failed","path":"lib/failed.dart"}',
            ),
            _result(
              id: 'already-applied',
              result: '{"already_applied":true,"path":"lib/existing.dart"}',
            ),
            _result(id: 'non-dart', argumentPath: 'README.md'),
            _result(id: 'missing-path', argumentPath: null),
          ]),
        ),
        isNull,
      );
    });

    test('prefers a result path and resolves relative paths by owner root', () {
      final signature = _signature.compute(
        _input([
          _result(
            id: 'edit-result-path',
            name: 'edit_file',
            argumentPath: 'lib/from_arguments.dart',
            result: '{"path":"lib/from_result.dart"}',
          ),
        ]),
      );

      expect(_decode(signature!), [
        {
          'id': 'edit-result-path',
          'name': 'edit_file',
          'path': '/workspace/project/lib/from_result.dart',
        },
      ]);
    });

    test('trims result paths and owner roots before resolution', () {
      final signature = _signature.compute(
        _input([
          _result(
            id: 'trimmed',
            argumentPath: 'lib/from_arguments.dart',
            result: '{"path":"  lib/from_result.dart  "}',
          ),
        ], projectRoot: '  /workspace/project  '),
      );

      expect(_decode(signature!), [
        {
          'id': 'trimmed',
          'name': 'write_file',
          'path': '/workspace/project/lib/from_result.dart',
        },
      ]);
    });

    test('preserves absolute paths and case-insensitive Dart suffixes', () {
      final signature = _signature.compute(
        _input([
          _result(
            id: 'absolute',
            name: 'rollback_last_file_change',
            argumentPath: '/tmp/project/lib/MAIN.DART',
          ),
        ]),
      );

      expect(_decode(signature!), [
        {
          'id': 'absolute',
          'name': 'rollback_last_file_change',
          'path': '/tmp/project/lib/MAIN.DART',
        },
      ]);
    });

    test('keeps a relative path when no project root is available', () {
      final signature = _signature.compute(
        _input([
          _result(id: 'relative', name: 'delete_file'),
        ], projectRoot: null),
      );

      expect(_decode(signature!), [
        {'id': 'relative', 'name': 'delete_file', 'path': 'lib/main.dart'},
      ]);
    });

    test('preserves source order and duplicate mutation entries', () {
      final duplicate = _result(
        id: 'duplicate',
        name: 'write_file',
        argumentPath: 'lib/shared.dart',
      );
      final signature = _signature.compute(
        _input([
          _result(
            id: 'first',
            name: 'edit_file',
            argumentPath: 'lib/first.dart',
          ),
          duplicate,
          duplicate,
          _result(
            id: 'last',
            name: 'delete_file',
            argumentPath: 'lib/last.dart',
          ),
        ]),
      );

      expect(_decode(signature!).map((entry) => entry['id']).toList(), [
        'first',
        'duplicate',
        'duplicate',
        'last',
      ]);
      expect(_decode(signature).map((entry) => entry['name']).toList(), [
        'edit_file',
        'write_file',
        'write_file',
        'delete_file',
      ]);
      expect(_decode(signature).map((entry) => entry['path']).toList(), [
        '/workspace/project/lib/first.dart',
        '/workspace/project/lib/shared.dart',
        '/workspace/project/lib/shared.dart',
        '/workspace/project/lib/last.dart',
      ]);
    });

    test('uses the supplied owner root in a poison-thread case', () {
      final evidence = [_result(id: 'shared', argumentPath: 'lib/shared.dart')];

      final ownerASignature = _signature.compute(
        _input(evidence, projectRoot: '/workspace/owner-a'),
      );
      final visibleOwnerBSignature = _signature.compute(
        _input(evidence, projectRoot: '/workspace/owner-b'),
      );

      expect(ownerASignature, isNot(visibleOwnerBSignature));
      expect(
        _decode(ownerASignature!).single['path'],
        '/workspace/owner-a/lib/shared.dart',
      );
      expect(
        _decode(visibleOwnerBSignature!).single['path'],
        '/workspace/owner-b/lib/shared.dart',
      );
    });
  });
}

final class _MutableArgument {
  var value = 0;
}

import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/services/chat_tool_catalogue_snapshot.dart';
import 'package:caverno/features/chat/data/datasources/chat_tool_catalogue_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ChatToolCatalogueSnapshotService();
  const cleanBuild = <String, Object?>{
    'commit': 'abcdef123456',
    'dirty': false,
    'builtAt': '2026-08-02T00:00:00Z',
  };

  Map<String, dynamic> definition(String name, {String description = ''}) {
    return <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        },
        'description': description,
        'name': name,
      },
    };
  }

  test('builds a canonical redacted snapshot with stable fingerprint', () {
    final first = service.build(
      toolDefinitions: <Map<String, dynamic>>[
        definition('zeta'),
        definition('alpha', description: 'Never reveal catalogue-secret.'),
      ],
      capturedAt: DateTime.parse('2026-08-02T12:34:56+09:00'),
      buildProvenance: cleanBuild,
      secrets: const <String>['catalogue-secret'],
    );
    final second = service.build(
      toolDefinitions: <Map<String, dynamic>>[
        definition('alpha', description: 'Never reveal catalogue-secret.'),
        definition('zeta'),
      ],
      capturedAt: DateTime.parse('2026-08-03T00:00:00Z'),
      buildProvenance: cleanBuild,
      secrets: const <String>['catalogue-secret'],
    );

    expect(first['schema'], ChatToolCatalogueSnapshotService.schema);
    expect(first['version'], 1);
    expect(first['exporterRevision'], '1');
    expect(first['capturedAt'], '2026-08-02T03:34:56.000Z');
    expect(first['toolCount'], 2);
    expect(
      first['configurationFingerprint'],
      second['configurationFingerprint'],
    );
    final definitions = first['toolDefinitions']! as List<Object?>;
    expect(
      definitions.map((item) {
        final tool = item! as Map<String, Object?>;
        final function = tool['function']! as Map<String, Object?>;
        return function['name'];
      }),
      <String>['alpha', 'zeta'],
    );
    final encoded = service.encode(first);
    expect(encoded, isNot(contains('catalogue-secret')));
    expect(encoded, contains('[REDACTED]'));
    expect(jsonDecode(encoded), first);
  });

  test('rejects unknown or dirty build provenance', () {
    for (final build in <Map<String, Object?>>[
      const <String, Object?>{'commit': 'unknown', 'dirty': false},
      const <String, Object?>{'commit': 'abcdef1', 'dirty': true},
    ]) {
      expect(
        () => service.build(
          toolDefinitions: <Map<String, dynamic>>[definition('one')],
          capturedAt: DateTime.utc(2026, 8, 2),
          buildProvenance: build,
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects malformed and duplicate tool definitions', () {
    expect(
      () => service.build(
        toolDefinitions: <Map<String, dynamic>>[
          definition('duplicate'),
          definition('duplicate'),
        ],
        capturedAt: DateTime.utc(2026, 8, 2),
        buildProvenance: cleanBuild,
      ),
      throwsFormatException,
    );
    expect(
      () => service.build(
        toolDefinitions: const <Map<String, dynamic>>[
          <String, dynamic>{'type': 'function'},
        ],
        capturedAt: DateTime.utc(2026, 8, 2),
        buildProvenance: cleanBuild,
      ),
      throwsFormatException,
    );
  });

  test('writes a new snapshot and refuses to overwrite it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'caverno_catalogue_snapshot_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final output = File('${directory.path}/nested/catalogue.json');
    final snapshot = service.build(
      toolDefinitions: <Map<String, dynamic>>[definition('one')],
      capturedAt: DateTime.utc(2026, 8, 2),
      buildProvenance: cleanBuild,
    );

    await const ChatToolCatalogueSnapshotStore().writeNew(output, snapshot);
    final original = await output.readAsString();
    expect(jsonDecode(original), snapshot);

    await expectLater(
      const ChatToolCatalogueSnapshotStore().writeNew(output, snapshot),
      throwsA(isA<FileSystemException>()),
    );
    expect(await output.readAsString(), original);
    expect(
      output.parent.listSync().whereType<File>().where(
        (file) => file.path.contains('.tmp-'),
      ),
      isEmpty,
    );
  });
}

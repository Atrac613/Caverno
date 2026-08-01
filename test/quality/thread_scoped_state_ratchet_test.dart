import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/audit_chat_notifier_turn_scope.dart' as turn_scope_audit;

const String _baselinePath = 'tool/chat_notifier_turn_scope_baseline.json';

/// Baseline migration from the pre-Slice 2a3 lexical ratchet:
///
/// `chat_notifier.dart::_trackActiveResponse::state.messages`
///
/// maps to:
///
/// `lib/features/chat/presentation/providers/chat_notifier.dart`
/// `::_trackActiveResponse::state.messages#1`.
///
/// Every other initial ID was a pre-existing read newly exposed by complete
/// signatures, per-occurrence identities, and removal of the whole-method
/// accessor skip. The canonical Slice 2a1 report is the reviewed source of
/// truth; this test does not maintain a second hand-written allowlist.
void main() {
  test('reviewed turn-scoped ambient reads do not grow or drift', () {
    final manifest = turn_scope_audit.ChatNotifierDecompositionManifest.load(
      File(turn_scope_audit.defaultDecompositionManifestPath),
      expectedPartCount: 43,
    );
    final currentReport = turn_scope_audit.auditChatNotifierTurnScope(
      root: Directory.current,
      manifest: manifest,
    );
    final reviewedReport = _readReport(File(_baselinePath));

    final difference = _compareReadInventories(
      current: _turnScopedReadInventory(currentReport.data),
      reviewed: _turnScopedReadInventory(reviewedReport),
    );

    expect(difference.isEmpty, isTrue, reason: difference.describe());
  });

  group('AST-backed fixture coverage', () {
    late Directory root;
    late turn_scope_audit.ChatNotifierDecompositionManifest manifest;

    setUp(() {
      root = Directory.systemTemp.createTempSync('thread-scope-ratchet-');
      manifest = turn_scope_audit.ChatNotifierDecompositionManifest.decode(
        jsonEncode(_fixtureManifest()),
      );
      _writeFixture(root);
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test(
      'keeps multiline signatures, repeated reads, and mixed accessors visible',
      () {
        final report = turn_scope_audit.auditChatNotifierTurnScope(
          root: root,
          manifest: manifest,
        );
        final methods = _mapList(report.data['methods']);
        final method = methods.singleWhere(
          (entry) => entry['declaration'] == '_inspectTurn',
        );
        final ownerMethod = methods.singleWhere(
          (entry) => entry['declaration'] == '_inspectOwnedTurn',
        );
        final reads = _turnScopedReadInventory(report.data);

        expect(method['signature'], contains('int interactionGeneration'));
        expect(method['turnIdentityParameters'], ['int interactionGeneration']);
        expect(ownerMethod['turnIdentityParameters'], ['ChatTurnOwner owner']);
        expect(reads, hasLength(3));
        expect(reads.keys, [
          endsWith('::_inspectOwnedTurn::state.messages#1'),
          endsWith('::_inspectTurn::state.messages#1'),
          endsWith('::_inspectTurn::state.messages#2'),
        ]);
        expect(
          reads.values.every((metadata) => metadata.accessorBearing),
          isTrue,
        );
      },
    );

    test('baseline growth fails', () {
      final reviewed = _turnScopedReadInventory({
        'reads': [_fixtureRead('sample.dart::_inspect::state.messages#1')],
      });
      final current = _turnScopedReadInventory({
        'reads': [
          _fixtureRead('sample.dart::_inspect::state.messages#1'),
          _fixtureRead('sample.dart::_inspect::state.messages#2'),
        ],
      });

      final difference = _compareReadInventories(
        current: current,
        reviewed: reviewed,
      );

      expect(difference.added, ['sample.dart::_inspect::state.messages#2']);
      expect(difference.describe(), contains('New production read IDs'));
    });

    test('baseline shrink fails until the reviewed baseline is lowered', () {
      final reviewed = _turnScopedReadInventory({
        'reads': [
          _fixtureRead('sample.dart::_inspect::state.messages#1'),
          _fixtureRead('sample.dart::_inspect::state.messages#2'),
        ],
      });
      final current = _turnScopedReadInventory({
        'reads': [_fixtureRead('sample.dart::_inspect::state.messages#1')],
      });

      final difference = _compareReadInventories(
        current: current,
        reviewed: reviewed,
      );

      expect(difference.removed, ['sample.dart::_inspect::state.messages#2']);
      expect(difference.describe(), contains('Removed production read IDs'));
      expect(
        difference.describe(),
        contains('regenerate and lower the reviewed baseline'),
      );
    });

    test('baseline metadata reclassification fails', () {
      final id = 'sample.dart::_inspect::state.messages#1';
      final reviewed = _turnScopedReadInventory({
        'reads': [_fixtureRead(id, accessorBearing: false)],
      });
      final current = _turnScopedReadInventory({
        'reads': [_fixtureRead(id, accessorBearing: true)],
      });

      final difference = _compareReadInventories(
        current: current,
        reviewed: reviewed,
      );

      expect(difference.changed, [id]);
      expect(
        difference.describe(),
        contains('Reclassified production read IDs'),
      );
    });
  });
}

typedef _ReadMetadata = ({
  String path,
  String declaration,
  String kind,
  bool methodHasTurnIdentity,
  bool turnReachable,
  bool accessorBearing,
});

final class _ReadInventoryDifference {
  const _ReadInventoryDifference({
    required this.added,
    required this.removed,
    required this.changed,
    required this.current,
    required this.reviewed,
  });

  final List<String> added;
  final List<String> removed;
  final List<String> changed;
  final Map<String, _ReadMetadata> current;
  final Map<String, _ReadMetadata> reviewed;

  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;

  String describe() {
    if (isEmpty) {
      return 'The current turn-scoped read inventory matches the reviewed '
          'Slice 2a1 baseline.';
    }
    final sections = <String>[
      if (added.isNotEmpty)
        _formatSection(
          'New production read IDs',
          added,
          'Do not add these IDs to the baseline. Pass explicit turn-owned '
              'state instead.',
        ),
      if (removed.isNotEmpty)
        _formatSection(
          'Removed production read IDs',
          removed,
          'In the same extraction slice, regenerate and lower the reviewed '
              'baseline.',
        ),
      if (changed.isNotEmpty) _formatChangedSection(),
    ];
    return sections.join('\n\n');
  }

  String _formatChangedSection() {
    final details = <String>[];
    for (final id in changed) {
      details
        ..add(id)
        ..add('  reviewed: ${reviewed[id]}')
        ..add('  current:  ${current[id]}');
    }
    return _formatSection(
      'Reclassified production read IDs',
      details,
      'Review the classification change and regenerate the baseline only when '
          'the production change is intentional.',
    );
  }
}

_ReadInventoryDifference _compareReadInventories({
  required Map<String, _ReadMetadata> current,
  required Map<String, _ReadMetadata> reviewed,
}) {
  final added = current.keys.where((id) => !reviewed.containsKey(id)).toList()
    ..sort();
  final removed = reviewed.keys.where((id) => !current.containsKey(id)).toList()
    ..sort();
  final changed =
      current.keys
          .where(
            (id) => reviewed.containsKey(id) && current[id] != reviewed[id],
          )
          .toList()
        ..sort();
  return _ReadInventoryDifference(
    added: added,
    removed: removed,
    changed: changed,
    current: current,
    reviewed: reviewed,
  );
}

Map<String, _ReadMetadata> _turnScopedReadInventory(
  Map<String, Object?> report,
) {
  final inventory = <String, _ReadMetadata>{};
  for (final read in _mapList(report['reads'])) {
    if (read['methodHasTurnIdentity'] != true) {
      continue;
    }
    final id = _stringField(read, 'id');
    final previous = inventory[id];
    if (previous != null) {
      throw StateError('Duplicate turn-scope read ID: $id');
    }
    inventory[id] = (
      path: _stringField(read, 'path'),
      declaration: _stringField(read, 'declaration'),
      kind: _stringField(read, 'kind'),
      methodHasTurnIdentity: _boolField(read, 'methodHasTurnIdentity'),
      turnReachable: _boolField(read, 'turnReachable'),
      accessorBearing: _boolField(read, 'accessorBearing'),
    );
  }
  return Map.unmodifiable(
    Map.fromEntries(
      inventory.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    ),
  );
}

Map<String, Object?> _readReport(File file) {
  if (!file.existsSync()) {
    throw StateError('Turn-scope baseline does not exist: ${file.path}');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw StateError('Turn-scope baseline must contain a JSON object');
  }
  return decoded.cast<String, Object?>();
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) {
    throw StateError('Expected an array in the turn-scope audit report');
  }
  return value
      .map((entry) {
        if (entry is! Map) {
          throw StateError(
            'Expected an object in the turn-scope audit report array',
          );
        }
        return entry.cast<String, Object?>();
      })
      .toList(growable: false);
}

String _stringField(Map<String, Object?> value, String field) {
  final result = value[field];
  if (result is! String || result.isEmpty) {
    throw StateError('Expected non-empty string field "$field"');
  }
  return result;
}

bool _boolField(Map<String, Object?> value, String field) {
  final result = value[field];
  if (result is! bool) {
    throw StateError('Expected boolean field "$field"');
  }
  return result;
}

String _formatSection(
  String heading,
  Iterable<String> lines,
  String instruction,
) {
  return '$heading:\n${lines.map((line) => '- $line').join('\n')}\n'
      '$instruction';
}

Map<String, Object?> _fixtureManifest() => {
  'schemaName': 'caverno_chat_notifier_decomposition_manifest',
  'schemaVersion': 1,
  'baselineRevision': 'fixture',
  'notifierLibraryPath':
      'lib/features/chat/presentation/providers/chat_notifier.dart',
  'entrypointSemantics':
      'All ChatNotifier extension declarations in source order.',
  'parts': [
    {
      'id': 'fixture',
      'partPath': 'chat_notifier_fixture.dart',
      'entrypoints': ['_inspectTurn'],
      'status': 'remaining',
      'collaborators': <Object?>[],
    },
  ],
};

Map<String, Object?> _fixtureRead(String id, {bool accessorBearing = false}) {
  final segments = id.split('::');
  return {
    'id': id,
    'path': segments[0],
    'declaration': segments[1],
    'kind': segments[2].split('#').first,
    'line': 1,
    'column': 1,
    'methodHasTurnIdentity': true,
    'turnReachable': true,
    'accessorBearing': accessorBearing,
  };
}

void _writeFixture(Directory root) {
  _write(
    root,
    'lib/features/chat/presentation/providers/chat_notifier.dart',
    '''
part 'chat_notifier_fixture.dart';

class ChatNotifier {}
''',
  );
  _write(
    root,
    'lib/features/chat/presentation/providers/chat_notifier_fixture.dart',
    '''
part of 'chat_notifier.dart';

extension FixtureTurnScope on ChatNotifier {
  void _inspectTurn(
    int first,
    int second,
    int third,
    int fourth,
    int fifth,
    int sixth,
    int interactionGeneration,
  ) {
    final firstMessages = state.messages;
    TurnThread.currentId;
    final secondMessages = state.messages;
  }

  void _inspectOwnedTurn(ChatTurnOwner owner) {
    final messages = state.messages;
    TurnThread.currentId;
  }
}
''',
  );
}

void _write(Directory root, String relativePath, String source) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}

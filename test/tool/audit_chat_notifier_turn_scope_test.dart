import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/audit_chat_notifier_turn_scope.dart' as audit;

void main() {
  group('manifest validation', () {
    test('loads the checked-in inventory and status distribution', () {
      final manifest = audit.ChatNotifierDecompositionManifest.load(
        File(audit.defaultDecompositionManifestPath),
        expectedPartCount: 43,
      );

      expect(manifest.parts.map((part) => part.id).toSet(), hasLength(43));
      expect(
        manifest.parts.map((part) => part.partPath).toSet(),
        hasLength(43),
      );
      expect(_statusCounts(manifest), {
        'partial': 25,
        // execution_runtime moved keep -> partial on 2026-08-04 when the
        // destructor slice extracted the turn's releases from it.
        'keep': 4,
        // proposal_option_extraction and proposal_parsing moved
        // deferred -> extracted when their part-files became domain services.
        'deferred': 4,
        'extracted': 8,
        'remaining': 2,
      });
      audit.validateProgramManifest(manifest);
      expect(
        manifest.parts
            .singleWhere(
              (part) =>
                  part.partPath ==
                  'chat_notifier_content_tool_result_format.dart',
            )
            .collaborators
            .single
            .id,
        'content-tool-result-formatter',
      );
      expect(
        manifest.parts
            .singleWhere(
              (part) =>
                  part.partPath ==
                  'chat_notifier_coding_verification_feedback.dart',
            )
            .collaborators
            .map((collaborator) => collaborator.id)
            .toSet(),
        {
          'coding-verification-feedback-presentation',
          'coding-verification-mutation-signature',
        },
      );
      expect(
        manifest.parts
            .singleWhere(
              (part) =>
                  part.partPath == 'chat_notifier_duplicate_recovery.dart',
            )
            .collaborators
            .single
            .id,
        'duplicate-tool-result-recovery',
      );
      expect(manifest.toJson()['parts'], hasLength(43));
      expect(const audit.AuditException('message').toString(), 'message');
    });

    test('rejects malformed schemas and duplicate stable identifiers', () {
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode('{'),
        throwsA(isA<audit.AuditException>()),
      );
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode({..._manifestJson(), 'schemaName': 'wrong'}),
        ),
        throwsA(isA<audit.AuditException>()),
      );
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode({..._manifestJson(), 'schemaVersion': 2}),
        ),
        throwsA(isA<audit.AuditException>()),
      );

      final duplicateParts = _manifestJson();
      duplicateParts['parts'] = [
        _partJson(
          id: 'same',
          partPath: 'chat_notifier_one.dart',
          entrypoints: ['one'],
        ),
        _partJson(
          id: 'same',
          partPath: 'chat_notifier_two.dart',
          entrypoints: ['two'],
        ),
      ];
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(duplicateParts),
        ),
        throwsA(
          isA<audit.AuditException>().having(
            (error) => error.message,
            'message',
            contains('part ids must be unique'),
          ),
        ),
      );
    });

    test('rejects invalid statuses and collaborator ownership', () {
      final invalidStatus = _manifestJson();
      invalidStatus['parts'] = [
        _partJson(
          id: 'one',
          partPath: 'chat_notifier_one.dart',
          entrypoints: ['one'],
          status: 'done',
        ),
      ];
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(invalidStatus),
        ),
        throwsA(isA<audit.AuditException>()),
      );

      final unexpectedCollaborator = _manifestJson();
      unexpectedCollaborator['parts'] = [
        _partJson(
          id: 'one',
          partPath: 'chat_notifier_one.dart',
          entrypoints: ['one'],
          collaborators: [_collaboratorJson()],
        ),
      ];
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(unexpectedCollaborator),
        ),
        throwsA(isA<audit.AuditException>()),
      );

      final missingCollaborator = _manifestJson();
      missingCollaborator['parts'] = [
        _partJson(
          id: 'one',
          partPath: 'chat_notifier_one.dart',
          entrypoints: ['one'],
          status: 'extracted',
        ),
      ];
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(missingCollaborator),
        ),
        throwsA(isA<audit.AuditException>()),
      );
    });

    test('rejects missing files and an unexpected part count', () {
      expect(
        () => audit.ChatNotifierDecompositionManifest.load(
          File('does-not-exist.json'),
        ),
        throwsA(isA<audit.AuditException>()),
      );
      expect(
        () => audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(_manifestJson()),
          expectedPartCount: 2,
        ),
        throwsA(isA<audit.AuditException>()),
      );
    });

    test('allows extraction progress while preserving fixed boundaries', () {
      final manifest = audit.ChatNotifierDecompositionManifest.load(
        File(audit.defaultDecompositionManifestPath),
      );
      final evolvedJson =
          jsonDecode(jsonEncode(manifest.toJson())) as Map<String, dynamic>;
      final parts = (evolvedJson['parts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final evolvingPart = parts.firstWhere(
        (part) => part['status'] == 'remaining',
      );
      evolvingPart
        ..['status'] = 'partial'
        ..['collaborators'] = [
          {
            'id': 'future-collaborator',
            'path': 'lib/features/chat/domain/services/future.dart',
            'sizeBudgetKey': 'lib/features/chat/domain/services/future.dart',
          },
        ];

      final evolved = audit.ChatNotifierDecompositionManifest.decode(
        jsonEncode(evolvedJson),
      );
      expect(() => audit.validateProgramManifest(evolved), returnsNormally);
      expect(
        () => audit.validateProgramManifest(
          audit.ChatNotifierDecompositionManifest.decode(
            jsonEncode(_historicalManifestJson()),
          ),
        ),
        throwsA(isA<audit.AuditException>()),
      );
    });
  });

  group('historical inventory', () {
    test(
      'uses all ChatNotifier extension methods and getters in source order',
      () {
        final manifest = audit.ChatNotifierDecompositionManifest.decode(
          jsonEncode(_historicalManifestJson()),
        );
        final sources = _historicalSources();

        final inventory = audit.readHistoricalPartInventory(
          revision: 'origin',
          notifierLibraryPath: manifest.notifierLibraryPath,
          loadSource: (revision, sourcePath) {
            expect(revision, 'origin');
            return sources[sourcePath]!;
          },
        );

        expect(inventory.map((part) => part.partPath), [
          'chat_notifier_sample.dart',
          'chat_notifier_old.dart',
        ]);
        expect(inventory.first.entrypoints, [
          'visibleValue',
          '_entry',
          'helper',
        ]);
        audit.verifyManifestAgainstOrigin(
          manifest: manifest,
          revision: 'origin',
          loadSource: (_, sourcePath) => sources[sourcePath]!,
        );
      },
    );

    test('reports historical entrypoint drift', () {
      final json = _historicalManifestJson();
      final parts = json['parts']! as List<Object?>;
      final first = parts.first! as Map<String, Object?>;
      first['entrypoints'] = ['wrong'];
      final manifest = audit.ChatNotifierDecompositionManifest.decode(
        jsonEncode(json),
      );

      expect(
        () => audit.verifyManifestAgainstOrigin(
          manifest: manifest,
          revision: 'origin',
          loadSource: (_, sourcePath) => _historicalSources()[sourcePath]!,
        ),
        throwsA(
          isA<audit.AuditException>().having(
            (error) => error.message,
            'message',
            contains('Historical entrypoints do not match'),
          ),
        ),
      );
    });
  });

  group('AST audit', () {
    late Directory root;
    late audit.ChatNotifierDecompositionManifest manifest;

    setUp(() {
      root = Directory.systemTemp.createTempSync('turn-scope-audit-');
      manifest = audit.ChatNotifierDecompositionManifest.decode(
        jsonEncode(_historicalManifestJson()),
      );
      _writeFixture(root);
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('uses complete signatures and records every ambient occurrence', () {
      final report = audit.auditChatNotifierTurnScope(
        root: root,
        manifest: manifest,
      );
      final methods = _objectList(report.data['methods']);
      final entry = methods.singleWhere(
        (method) => method['declaration'] == '_entry',
      );
      final reads = _objectList(
        report.data['reads'],
      ).where((read) => read['declaration'] == '_entry').toList();

      expect(entry['signature'], contains('Conversation conversation'));
      expect(entry['turnIdentityParameters'], hasLength(2));
      expect(entry['turnScopedAccessors'], contains('TurnThread'));
      expect(
        reads.where((read) => read['kind'] == 'state.messages'),
        hasLength(2),
      );
      expect(
        reads
            .where((read) => read['kind'] == 'state.messages')
            .map((read) => read['id']),
        [contains('state.messages#1'), contains('state.messages#2')],
      );
      expect(reads.map((read) => read['kind']).toSet(), {
        'state.messages',
        'currentConversation',
        'effectiveCodingProject',
        'activeProjectRootPath',
      });
      expect(reads.every((read) => read['accessorBearing'] == true), isTrue);
      expect(
        reads.every((read) => read['methodHasTurnIdentity'] == true),
        isTrue,
      );
    });

    test('scans extracted collaborators and emits deterministic JSON', () {
      final first = audit.auditChatNotifierTurnScope(
        root: root,
        manifest: manifest,
      );
      final second = audit.auditChatNotifierTurnScope(
        root: root,
        manifest: manifest,
      );
      final reads = _objectList(first.data['reads']);

      expect(first.encode(), second.encode());
      expect(first.data['scannedPaths'], [
        'lib/features/chat/domain/services/sample_formatter.dart',
        'lib/features/chat/presentation/providers/chat_notifier.dart',
        'lib/features/chat/presentation/providers/chat_notifier_sample.dart',
      ]);
      expect(
        reads.any(
          (read) =>
              read['path'] ==
                  'lib/features/chat/domain/services/sample_formatter.dart' &&
              read['declaration'] == 'SampleFormatter.format',
        ),
        isTrue,
      );
    });

    test(
      'rejects unexpected current parts and missing collaborator markers',
      () {
        _write(
          root,
          'lib/features/chat/presentation/providers/chat_notifier.dart',
          '''
part 'chat_notifier_unexpected.dart';
class ChatNotifier {}
''',
        );
        expect(
          () =>
              audit.auditChatNotifierTurnScope(root: root, manifest: manifest),
          throwsA(
            isA<audit.AuditException>().having(
              (error) => error.message,
              'message',
              contains('part directives do not match'),
            ),
          ),
        );

        _writeFixture(root);
        _write(
          root,
          'lib/features/chat/domain/services/sample_formatter.dart',
          'abstract final class SampleFormatter {}\n',
        );
        expect(
          () =>
              audit.auditChatNotifierTurnScope(root: root, manifest: manifest),
          throwsA(
            isA<audit.AuditException>().having(
              (error) => error.message,
              'message',
              contains('Missing collaborator marker'),
            ),
          ),
        );
      },
    );

    test('rejects missing and malformed scanned sources', () {
      File(
        '${root.path}/lib/features/chat/presentation/providers/'
        'chat_notifier_sample.dart',
      ).deleteSync();
      expect(
        () => audit.auditChatNotifierTurnScope(root: root, manifest: manifest),
        throwsA(
          isA<audit.AuditException>().having(
            (error) => error.message,
            'message',
            contains('Required source does not exist'),
          ),
        ),
      );

      _writeFixture(root);
      _write(
        root,
        'lib/features/chat/presentation/providers/chat_notifier_sample.dart',
        'extension Broken on ChatNotifier {',
      );
      expect(
        () => audit.auditChatNotifierTurnScope(root: root, manifest: manifest),
        throwsA(
          isA<audit.AuditException>().having(
            (error) => error.message,
            'message',
            contains('Unable to parse'),
          ),
        ),
      );
    });

    test('checks a stable baseline while ignoring diagnostic line shifts', () {
      final report = audit.auditChatNotifierTurnScope(
        root: root,
        manifest: manifest,
      );
      final baseline = File('${root.path}/baseline.json');

      audit.writeBaseline(report, baseline);
      audit.checkBaseline(report, baseline);

      final decoded = jsonDecode(baseline.readAsStringSync()) as Map;
      final reads = decoded['reads']! as List;
      final firstRead = reads.first as Map;
      firstRead['line'] = 999;
      firstRead['column'] = 999;
      baseline.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
      );
      audit.checkBaseline(report, baseline);

      firstRead['kind'] = 'changed-kind';
      baseline.writeAsStringSync(jsonEncode(decoded));
      expect(
        () => audit.checkBaseline(report, baseline),
        throwsA(isA<audit.AuditException>()),
      );
    });

    test('reports missing and malformed baselines', () {
      final report = audit.auditChatNotifierTurnScope(
        root: root,
        manifest: manifest,
      );
      final baseline = File('${root.path}/baseline.json');
      expect(
        () => audit.checkBaseline(report, baseline),
        throwsA(isA<audit.AuditException>()),
      );
      baseline.writeAsStringSync('{');
      expect(
        () => audit.checkBaseline(report, baseline),
        throwsA(isA<audit.AuditException>()),
      );
    });

    test(
      'supports read-only, origin, baseline, and diagnostics CLI modes',
      () async {
        final manifestFile = File('${root.path}/manifest.json');
        manifestFile.writeAsStringSync(jsonEncode(_historicalManifestJson()));
        final stdoutBuffer = StringBuffer();
        final stderrBuffer = StringBuffer();
        String loader(String _, String sourcePath) =>
            _historicalSources()[sourcePath]!;

        expect(
          await audit.runAuditCli(
            ['--manifest', 'manifest.json'],
            workingDirectory: root,
            stdoutSink: stdoutBuffer,
            stderrSink: stderrBuffer,
            expectedPartCount: 2,
            enforceProgramManifest: false,
          ),
          0,
        );
        expect(stdoutBuffer.toString(), contains('"ambientReads"'));
        expect(stderrBuffer.toString(), isEmpty);

        stdoutBuffer.clear();
        expect(
          await audit.runAuditCli(
            [
              '--manifest',
              'manifest.json',
              '--verify-origin',
              'origin',
              '--write-baseline',
              'baseline.json',
            ],
            workingDirectory: root,
            stdoutSink: stdoutBuffer,
            stderrSink: stderrBuffer,
            originSourceLoader: loader,
            expectedPartCount: 2,
            enforceProgramManifest: false,
          ),
          0,
        );
        expect(File('${root.path}/baseline.json').existsSync(), isTrue);

        stdoutBuffer.clear();
        expect(
          await audit.runAuditCli(
            [
              '--manifest',
              'manifest.json',
              '--check-baseline',
              'baseline.json',
            ],
            workingDirectory: root,
            stdoutSink: stdoutBuffer,
            stderrSink: stderrBuffer,
            expectedPartCount: 2,
            enforceProgramManifest: false,
          ),
          0,
        );

        stdoutBuffer.clear();
        expect(
          await audit.runAuditCli(
            ['--manifest', 'manifest.json', '--describe-origin', 'origin'],
            workingDirectory: root,
            stdoutSink: stdoutBuffer,
            stderrSink: stderrBuffer,
            originSourceLoader: loader,
            expectedPartCount: 2,
            enforceProgramManifest: false,
          ),
          0,
        );
        expect(stdoutBuffer.toString(), contains('"visibleValue"'));
      },
    );

    test(
      'returns CLI diagnostics for invalid flags and missing inputs',
      () async {
        final errors = StringBuffer();
        expect(
          await audit.runAuditCli(
            ['--unknown', 'value'],
            workingDirectory: root,
            stderrSink: errors,
            expectedPartCount: null,
            enforceProgramManifest: false,
          ),
          1,
        );
        expect(errors.toString(), contains('Unknown argument'));

        errors.clear();
        expect(
          await audit.runAuditCli(
            ['--manifest'],
            workingDirectory: root,
            stderrSink: errors,
            expectedPartCount: null,
            enforceProgramManifest: false,
          ),
          1,
        );
        expect(errors.toString(), contains('requires a value'));

        errors.clear();
        expect(
          await audit.runAuditCli(
            ['--check-baseline', 'one', '--write-baseline', 'two'],
            workingDirectory: root,
            stderrSink: errors,
            expectedPartCount: null,
            enforceProgramManifest: false,
          ),
          1,
        );
        expect(errors.toString(), contains('mutually exclusive'));

        errors.clear();
        expect(
          await audit.runAuditCli(
            ['--describe-origin', 'origin', '--verify-origin', 'origin'],
            workingDirectory: root,
            stderrSink: errors,
            expectedPartCount: null,
            enforceProgramManifest: false,
          ),
          1,
        );
        expect(errors.toString(), contains('cannot be combined'));
      },
    );
  });
}

Map<String, int> _statusCounts(
  audit.ChatNotifierDecompositionManifest manifest,
) {
  final counts = <String, int>{};
  for (final part in manifest.parts) {
    counts.update(part.status, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, Object?> _manifestJson() => {
  'schemaName': 'caverno_chat_notifier_decomposition_manifest',
  'schemaVersion': 1,
  'baselineRevision': 'origin',
  'notifierLibraryPath':
      'lib/features/chat/presentation/providers/chat_notifier.dart',
  'entrypointSemantics':
      'All ChatNotifier extension declarations in source order.',
  'parts': <Object?>[],
};

Map<String, Object?> _historicalManifestJson() {
  final json = _manifestJson();
  json['parts'] = [
    _partJson(
      id: 'sample',
      partPath: 'chat_notifier_sample.dart',
      entrypoints: ['visibleValue', '_entry', 'helper'],
    ),
    _partJson(
      id: 'old',
      partPath: 'chat_notifier_old.dart',
      entrypoints: ['_oldFormat'],
      status: 'extracted',
      collaborators: [_collaboratorJson()],
    ),
  ];
  return json;
}

Map<String, Object?> _partJson({
  required String id,
  required String partPath,
  required List<String> entrypoints,
  String status = 'remaining',
  List<Map<String, Object?>> collaborators = const [],
}) => {
  'id': id,
  'partPath': partPath,
  'entrypoints': entrypoints,
  'status': status,
  'collaborators': collaborators,
};

Map<String, Object?> _collaboratorJson() => {
  'id': 'sample-formatter',
  'path': 'lib/features/chat/domain/services/sample_formatter.dart',
  'sizeBudgetKey': 'lib/features/chat/domain/services/sample_formatter.dart',
};

Map<String, String> _historicalSources() => {
  'lib/features/chat/presentation/providers/chat_notifier.dart': '''
part 'chat_notifier_sample.dart';
part 'chat_notifier_old.dart';
class ChatNotifier {}
''',
  'lib/features/chat/presentation/providers/chat_notifier_sample.dart': '''
part of 'chat_notifier.dart';
extension Sample on ChatNotifier {
  String get visibleValue => 'visible';

  void _entry(
    int first,
    int second,
    int third,
    int fourth,
    int fifth,
    int generation,
    Conversation conversation,
  ) {}

  void helper() {}
}
''',
  'lib/features/chat/presentation/providers/chat_notifier_old.dart': '''
part of 'chat_notifier.dart';
extension Old on ChatNotifier {
  String _oldFormat(String value) => value;
}
''',
};

void _writeFixture(Directory root) {
  _write(
    root,
    'lib/features/chat/presentation/providers/chat_notifier.dart',
    '''
part 'chat_notifier_sample.dart';

class Conversation {}

class ChatNotifier {
  void start(int generation) {
    _entry(1, 2, 3, 4, 5, generation, Conversation());
  }
}
''',
  );
  _write(
    root,
    'lib/features/chat/presentation/providers/chat_notifier_sample.dart',
    '''
part of 'chat_notifier.dart';

extension Sample on ChatNotifier {
  String get visibleValue => holder.currentConversation;

  void _entry(
    int first,
    int second,
    int third,
    int fourth,
    int fifth,
    int generation,
    Conversation conversation,
  ) {
    final firstMessages = state.messages;
    final secondMessages = state.messages;
    final visibleConversation = holder.currentConversation;
    _getEffectiveCodingProject();
    _getActiveProjectRootPath();
    TurnThread.currentId;
    helper();
  }

  void helper() {
    final visibleConversation = holder.currentConversation;
  }
}
''',
  );
  _write(root, 'lib/features/chat/domain/services/sample_formatter.dart', '''
// ChatNotifier decomposition collaborator: sample-formatter
abstract final class SampleFormatter {
  static String format(int generation) {
    return state.messages.toString();
  }
}

extension SampleStringExtension on String {
  String normalized() => trim();
}

mixin SampleFormatterMixin {
  String mixinValue() => state.messages.toString();
}

String topLevelFormat() => state.messages.toString();
''');
}

void _write(Directory root, String relativePath, String source) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}

List<Map<String, Object?>> _objectList(Object? value) {
  return (value! as List)
      .map((entry) => (entry! as Map).cast<String, Object?>())
      .toList(growable: false);
}

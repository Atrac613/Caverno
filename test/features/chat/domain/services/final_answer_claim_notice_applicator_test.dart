import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_evidence_contract.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_notice_applicator.dart';
import 'package:test/test.dart';

void main() {
  const applicator = FinalAnswerClaimNoticeApplicator();
  late Directory ownerRoot;
  late Directory visibleRoot;

  setUp(() async {
    ownerRoot = await Directory.systemTemp.createTemp(
      'final_answer_claim_owner_',
    );
    visibleRoot = await Directory.systemTemp.createTemp(
      'final_answer_claim_visible_',
    );
  });

  tearDown(() async {
    await ownerRoot.delete(recursive: true);
    await visibleRoot.delete(recursive: true);
  });

  test('returns non-coding content unchanged', () {
    const content = 'Created: `lib/new.dart`.\n\nAll 5 tests passed.';

    final result = applicator.apply(
      _input(
        candidateContent: content,
        isCodingWorkspaceOrMode: false,
        projectRoot: ownerRoot.path,
        toolResults: [_verificationEvidence(passed: 1)],
      ),
    );

    expect(result.content, content);
    expect(result.transformIds, isEmpty);
  });

  test('applies the unwritten-file notice independently', () {
    const content = 'Created: `lib/new.dart`.';

    final result = applicator.apply(
      _input(candidateContent: content, projectRoot: ownerRoot.path),
    );

    expect(
      result.content,
      '$content\n\n'
      'Deliverable claim check: `lib/new.dart` was listed as created or '
      'updated but does not exist.',
    );
    expect(result.transformIds, [
      FinalAnswerClaimNoticeApplicator.unwrittenFileTransformId,
    ]);
  });

  test('applies the narrated-transcript notice independently', () {
    const content = '''
Verification:

```text
\$ dart test
All tests passed.
```''';

    final result = applicator.apply(
      _input(candidateContent: content, projectRoot: null),
    );

    expect(
      result.content,
      '$content\n\n'
      'Transcript claim check: the response presents a terminal transcript, '
      'but the following command(s) have no execution record in this turn: '
      '`dart test`. Treat the transcript output shown for them as unverified.',
    );
    expect(result.transformIds, [
      FinalAnswerClaimNoticeApplicator.narratedTranscriptTransformId,
    ]);
  });

  test('applies the verification notice independently', () {
    const content = 'All 5 tests passed.';

    final result = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: null,
        toolResults: [_verificationEvidence(passed: 2, failed: 1)],
      ),
    );

    expect(
      result.content,
      '$content\n\n'
      'Verification claim check: The response reports 5 passing tests, but '
      'the recorded verification observed 2 passed, 1 failed, and 0 skipped '
      'test(s). The recorded command was `dart test`.',
    );
    expect(result.transformIds, [
      FinalAnswerClaimNoticeApplicator.verificationTransformId,
    ]);
  });

  test('applies all notices in the established order', () {
    const content = '''
Created: `lib/new.dart`.

```text
\$ dart test
All tests passed.
```

All 5 tests passed.''';

    final result = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: ownerRoot.path,
        toolResults: [_verificationEvidence(passed: 2)],
      ),
    );

    expect(result.transformIds, [
      FinalAnswerClaimNoticeApplicator.unwrittenFileTransformId,
      FinalAnswerClaimNoticeApplicator.narratedTranscriptTransformId,
      FinalAnswerClaimNoticeApplicator.verificationTransformId,
    ]);
    final unwrittenIndex = result.content.indexOf('Deliverable claim check:');
    final narratedIndex = result.content.indexOf('Transcript claim check:');
    final verificationIndex = result.content.indexOf(
      'Verification claim check:',
    );
    expect(unwrittenIndex, greaterThan(content.length));
    expect(narratedIndex, greaterThan(unwrittenIndex));
    expect(verificationIndex, greaterThan(narratedIndex));
  });

  test('does not reapply already-present notices', () {
    const content = '''
Created: `lib/new.dart`.

```text
\$ dart test
All tests passed.
```

All 5 tests passed.''';
    final evidence = [_verificationEvidence(passed: 2)];
    final first = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: ownerRoot.path,
        toolResults: evidence,
      ),
    );

    final second = applicator.apply(
      _input(
        candidateContent: first.content,
        projectRoot: ownerRoot.path,
        toolResults: evidence,
      ),
    );

    expect(second.content, first.content);
    expect(second.transformIds, isEmpty);
  });

  test('accepts successful owner evidence for all three claims', () {
    const content = '''
Created: `lib/new.dart`.

```text
\$ dart test
All 5 tests passed.
```

All 5 tests passed.''';

    final result = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: ownerRoot.path,
        toolResults: [
          _successfulWrite(ownerRoot.path, 'lib/new.dart'),
          _verificationEvidence(passed: 5),
        ],
        executedCommands: const ['dart test'],
      ),
    );

    expect(result.content, content);
    expect(result.transformIds, isEmpty);
  });

  test('checks file claims against the explicit owning project root', () {
    final visibleFile = File('${visibleRoot.path}/lib/owner.dart');
    visibleFile.createSync(recursive: true);
    visibleFile.writeAsStringSync('void main() {}');

    final result = applicator.apply(
      _input(
        candidateContent: 'Created: `lib/owner.dart`.',
        projectRoot: ownerRoot.path,
      ),
    );

    expect(result.content, contains('does not exist'));
    expect(result.content, contains('`lib/owner.dart`'));
  });

  test('keeps owner and visible-turn claim evidence independent', () {
    final visibleFile = File('${visibleRoot.path}/lib/owner.dart');
    visibleFile.createSync(recursive: true);
    visibleFile.writeAsStringSync('void main() {}');
    const content = '''
Created: `lib/owner.dart`.

```text
\$ dart test
All tests passed.
```

All 5 tests passed.''';

    final ownerResult = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: ownerRoot.path,
        toolResults: [_verificationEvidence(passed: 2)],
      ),
    );
    final visibleResult = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: visibleRoot.path,
        toolResults: [
          _successfulWrite(visibleRoot.path, 'lib/owner.dart'),
          _verificationEvidence(passed: 5),
        ],
        executedCommands: const ['dart test'],
      ),
    );

    expect(ownerResult.transformIds, [
      FinalAnswerClaimNoticeApplicator.unwrittenFileTransformId,
      FinalAnswerClaimNoticeApplicator.narratedTranscriptTransformId,
      FinalAnswerClaimNoticeApplicator.verificationTransformId,
    ]);
    expect(visibleResult.content, content);
    expect(visibleResult.transformIds, isEmpty);
  });

  test('skips transcript notices without command capability', () {
    const content = '''
```text
\$ dart test
All tests passed.
```''';

    final result = applicator.apply(
      _input(
        candidateContent: content,
        projectRoot: null,
        offersCommandExecution: false,
      ),
    );

    expect(result.content, content);
    expect(result.transformIds, isEmpty);
  });

  test('freezes owner evidence and returned transform IDs', () {
    final nestedArguments = <String, dynamic>{
      'commands': <Object?>['dart test'],
      'owners': <Object?>['owner-a'],
      'labels': <String, dynamic>{'primary': 'owner-a'},
    };
    final sourceResults = [
      ToolResultInfo(
        id: 'verification-evidence',
        name: CodingVerificationEvidenceContract.toolName,
        arguments: {'metadata': nestedArguments},
        result: _verificationEvidence(passed: 5).result,
      ),
    ];
    final sourceCommands = <String>['dart test'];
    final input = _input(
      candidateContent: 'All 5 tests passed.',
      projectRoot: null,
      toolResults: sourceResults,
      executedCommands: sourceCommands,
    );
    sourceResults.clear();
    sourceCommands.clear();
    (nestedArguments['commands']! as List<Object?>).add('dart analyze');
    (nestedArguments['owners']! as List<Object?>).add('owner-b');
    (nestedArguments['labels']! as Map)['primary'] = 'owner-b';

    final result = applicator.apply(input);

    expect(input.toolResults, hasLength(1));
    expect(input.executedCommands, ['dart test']);
    expect(
      (input.toolResults.single.arguments['metadata']
          as Map<String, dynamic>)['owners'],
      ['owner-a'],
    );
    final frozenLabels =
        (input.toolResults.single.arguments['metadata']
                as Map<String, dynamic>)['labels']
            as Map;
    expect(frozenLabels, {'primary': 'owner-a'});
    expect(
      () => input.toolResults.single.arguments['command'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.toolResults.single.arguments['metadata']
                      as Map<String, dynamic>)['commands']
                  as List<Object?>)
              .add('dart format'),
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.toolResults.single.arguments['metadata']
                      as Map<String, dynamic>)['owners']
                  as List<Object?>)
              .add('owner-c'),
      throwsUnsupportedError,
    );
    expect(() => frozenLabels['primary'] = 'late', throwsUnsupportedError);
    expect(() => result.transformIds.add('unexpected'), throwsUnsupportedError);
  });

  test('rejects non-JSON owner evidence arguments', () {
    for (final invalidValue in <Object?>[
      <Object?>{'owner-a'},
      <Object?, Object?>{7: 'owner-a'},
    ]) {
      expect(
        () => _input(
          candidateContent: 'Done.',
          projectRoot: null,
          toolResults: [
            ToolResultInfo(
              id: 'invalid',
              name: 'read_file',
              arguments: {'invalid': invalidValue},
              result: '{"ok":true}',
            ),
          ],
        ),
        throwsArgumentError,
        reason: invalidValue.runtimeType.toString(),
      );
    }
  });
}

FinalAnswerClaimNoticeInput _input({
  required String candidateContent,
  required String? projectRoot,
  bool isCodingWorkspaceOrMode = true,
  List<ToolResultInfo> toolResults = const [],
  List<String> executedCommands = const [],
  bool offersCommandExecution = true,
}) {
  return FinalAnswerClaimNoticeInput(
    isCodingWorkspaceOrMode: isCodingWorkspaceOrMode,
    candidateContent: candidateContent,
    toolResults: toolResults,
    executedCommands: executedCommands,
    projectRoot: projectRoot,
    offersCommandExecution: offersCommandExecution,
  );
}

ToolResultInfo _verificationEvidence({
  required int passed,
  int failed = 0,
  int skipped = 0,
}) {
  return ToolResultInfo(
    id: 'verification-evidence',
    name: CodingVerificationEvidenceContract.toolName,
    arguments: const {},
    result: jsonEncode({
      'schema': CodingVerificationEvidenceContract.schemaName,
      'counts': {'passed': passed, 'failed': failed, 'skipped': skipped},
      'verification': {
        'executable': 'dart',
        'arguments': ['test'],
      },
    }),
  );
}

ToolResultInfo _successfulWrite(String root, String path) {
  return ToolResultInfo(
    id: 'write-$path',
    name: 'write_file',
    arguments: {'path': path},
    result: jsonEncode({'path': '$root/$path', 'bytes_written': 12}),
  );
}

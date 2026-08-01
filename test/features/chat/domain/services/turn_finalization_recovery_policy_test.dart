import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/turn_finalization_recovery_policy.dart';
import 'package:test/test.dart';

const _policy = TurnFinalizationRecoveryPolicy();

ToolResultInfo _result(String id) {
  return ToolResultInfo(
    id: id,
    name: 'read_file',
    arguments: const {'path': 'lib/main.dart'},
    result: '{"ok":true}',
  );
}

TurnFinalizationRecoveryInput _input({
  String candidateResponse = 'The Dart implementation completed.',
  String? streamedFinalAnswer,
  List<ToolResultInfo>? toolResults,
  bool hasTimedOutCommandResult = false,
  bool hasFailedCommandValidation = false,
  bool hasUnexecutedCommandActionResult = false,
  bool hasUnexecutedFileSideEffectResult = false,
  bool hasSuccessfulCurrentSavedValidation = false,
  bool hasSuccessfulFileMutationEvidence = true,
  bool hasSuccessfulCommandExecutionEvidence = false,
}) {
  return TurnFinalizationRecoveryInput(
    candidateResponse: candidateResponse,
    streamedFinalAnswer: streamedFinalAnswer,
    toolResults: toolResults ?? [_result('owner-result')],
    hasTimedOutCommandResult: hasTimedOutCommandResult,
    hasFailedCommandValidation: hasFailedCommandValidation,
    hasUnexecutedCommandActionResult: hasUnexecutedCommandActionResult,
    hasUnexecutedFileSideEffectResult: hasUnexecutedFileSideEffectResult,
    hasSuccessfulCurrentSavedValidation: hasSuccessfulCurrentSavedValidation,
    hasSuccessfulFileMutationEvidence: hasSuccessfulFileMutationEvidence,
    hasSuccessfulCommandExecutionEvidence:
        hasSuccessfulCommandExecutionEvidence,
  );
}

void main() {
  group('TurnFinalizationRecoveryInput', () {
    test('freezes the exact owner tool-result snapshot', () {
      final ownerMetadata = <String, dynamic>{
        'primary': <Object?>['owner-a'],
      };
      final tags = <Object?>['owner-a'];
      final metadata = <String, dynamic>{
        'paths': <Object?>['lib/main.dart'],
        'owners': ownerMetadata,
        'tags': tags,
      };
      final arguments = <String, dynamic>{
        'path': 'lib/main.dart',
        'metadata': metadata,
      };
      final ownerResults = [
        ToolResultInfo(
          id: 'owner-a',
          name: 'read_file',
          arguments: arguments,
          result: '{"ok":true}',
        ),
      ];
      final input = _input(toolResults: ownerResults);

      ownerResults.clear();
      arguments['path'] = 'lib/visible.dart';
      (metadata['paths']! as List<Object?>).add('lib/visible.dart');
      (ownerMetadata['primary']! as List<Object?>).add('visible-owner-b');
      tags.add('visible-owner-b');

      expect(input.toolResults.map((result) => result.id), ['owner-a']);
      expect(input.toolResults.single.arguments['path'], 'lib/main.dart');
      final frozenMetadata =
          input.toolResults.single.arguments['metadata']!
              as Map<String, dynamic>;
      expect(frozenMetadata['paths'], ['lib/main.dart']);
      final frozenOwners = frozenMetadata['owners']! as Map<String, dynamic>;
      final frozenTags = frozenMetadata['tags']! as List<Object?>;
      expect(frozenOwners['primary'], ['owner-a']);
      expect(frozenTags, ['owner-a']);
      expect(
        () => input.toolResults.add(_result('owner-b')),
        throwsUnsupportedError,
      );
      expect(
        () => input.toolResults.single.arguments['path'] = 'lib/other.dart',
        throwsUnsupportedError,
      );
      expect(
        () => (frozenMetadata['paths'] as List<Object?>).add('lib/other.dart'),
        throwsUnsupportedError,
      );
      expect(
        () => (frozenOwners['primary']! as List<Object?>).add('later poison'),
        throwsUnsupportedError,
      );
      expect(() => frozenTags.add('later poison'), throwsUnsupportedError);
    });

    test('rejects non-JSON owner tool-result arguments', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
      ]) {
        expect(
          () => _input(
            toolResults: [
              ToolResultInfo(
                id: 'owner-a',
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
  });

  group('completed tool-result final-answer recovery', () {
    test('rejects a non-empty streamed-answer mismatch', () {
      expect(
        _policy.shouldSkipCompletedToolResultFinalAnswerRecovery(
          _input(
            streamedFinalAnswer: 'A different streamed answer.',
            hasSuccessfulCurrentSavedValidation: true,
          ),
        ),
        isFalse,
      );
    });

    test('accepts null, empty, and matching streamed answers', () {
      for (final streamedAnswer in <String?>[
        null,
        '',
        '  The Dart implementation completed.  ',
      ]) {
        expect(
          _policy.shouldSkipCompletedToolResultFinalAnswerRecovery(
            _input(streamedFinalAnswer: streamedAnswer),
          ),
          isTrue,
          reason: '$streamedAnswer',
        );
      }
    });

    test('rejects empty candidates and every blocking evidence fact', () {
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(candidateResponse: '   '),
        ),
        isFalse,
      );
      for (final blocked in [
        _input(
          hasTimedOutCommandResult: true,
          hasSuccessfulCurrentSavedValidation: true,
        ),
        _input(
          hasFailedCommandValidation: true,
          hasSuccessfulCurrentSavedValidation: true,
        ),
        _input(
          hasUnexecutedCommandActionResult: true,
          hasSuccessfulCurrentSavedValidation: true,
        ),
        _input(
          hasUnexecutedFileSideEffectResult: true,
          hasSuccessfulCurrentSavedValidation: true,
        ),
      ]) {
        expect(
          _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
            blocked,
          ),
          isFalse,
        );
      }
    });

    test('accepts current saved validation without other success evidence', () {
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(
            candidateResponse:
                'I will inspect the Dart source after saved validation.',
            hasSuccessfulCurrentSavedValidation: true,
            hasSuccessfulFileMutationEvidence: false,
          ),
        ),
        isTrue,
      );
    });

    test('requires successful mutation or command evidence', () {
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(hasSuccessfulFileMutationEvidence: false),
        ),
        isFalse,
      );
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(
            hasSuccessfulFileMutationEvidence: false,
            hasSuccessfulCommandExecutionEvidence: true,
          ),
        ),
        isTrue,
      );
    });

    test('requires completed prose without a future coding action', () {
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(candidateResponse: 'The Dart source is ready for review.'),
        ),
        isFalse,
      );
      expect(
        _policy.shouldSkipCompletedToolResultCodingContinuationRecovery(
          _input(
            candidateResponse:
                'The Dart implementation completed. Next I will update the source.',
          ),
        ),
        isFalse,
      );
    });

    test('keeps owner snapshots isolated in a poison-thread case', () {
      final ownerA = _input(
        streamedFinalAnswer: 'The Dart implementation completed.',
        toolResults: [_result('owner-a')],
      );
      final visibleOwnerB = _input(
        candidateResponse: 'I will inspect the Python source.',
        streamedFinalAnswer: 'I will inspect the Python source.',
        toolResults: [_result('owner-b')],
        hasTimedOutCommandResult: true,
        hasSuccessfulFileMutationEvidence: false,
      );

      expect(
        _policy.shouldSkipCompletedToolResultFinalAnswerRecovery(ownerA),
        isTrue,
      );
      expect(
        _policy.shouldSkipCompletedToolResultFinalAnswerRecovery(visibleOwnerB),
        isFalse,
      );
      expect(ownerA.toolResults.single.id, 'owner-a');
      expect(visibleOwnerB.toolResults.single.id, 'owner-b');
    });
  });

  group('successful final-answer evidence', () {
    test('accepts either mutation or command execution evidence', () {
      expect(
        _policy.hasSuccessfulFinalAnswerToolEvidence(
          _input(hasSuccessfulFileMutationEvidence: true),
        ),
        isTrue,
      );
      expect(
        _policy.hasSuccessfulFinalAnswerToolEvidence(
          _input(
            hasSuccessfulFileMutationEvidence: false,
            hasSuccessfulCommandExecutionEvidence: true,
          ),
        ),
        isTrue,
      );
      expect(
        _policy.hasSuccessfulFinalAnswerToolEvidence(
          _input(
            hasSuccessfulFileMutationEvidence: false,
            hasSuccessfulCommandExecutionEvidence: false,
          ),
        ),
        isFalse,
      );
    });
  });

  group('completed coding final-answer detection', () {
    test('recognizes English and CJK completion markers', () {
      expect(
        _policy.looksLikeCompletedCodingFinalAnswer(
          'The Python script was implemented and verified.',
        ),
        isTrue,
      );
      expect(
        _policy.looksLikeCompletedCodingFinalAnswer(
          String.fromCharCodes([
            0x30b3,
            0x30fc,
            0x30c9,
            0x3092,
            0x5b9f,
            0x88c5,
            0x3057,
            0x307e,
            0x3057,
            0x305f,
          ]),
        ),
        isTrue,
      );
    });

    test('preserves the exact completed-answer length limit', () {
      const lead = 'The Dart implementation completed. ';
      final atLimit = '$lead${'x' * (1600 - lead.length)}';
      final overLimit = '$lead${'x' * (1601 - lead.length)}';

      expect(atLimit.length, 1600);
      expect(overLimit.length, 1601);
      expect(_policy.looksLikeCompletedCodingFinalAnswer(atLimit), isTrue);
      expect(_policy.looksLikeCompletedCodingFinalAnswer(overLimit), isFalse);
    });

    test('rejects empty, oversized, targetless, and incomplete answers', () {
      expect(_policy.looksLikeCompletedCodingFinalAnswer(''), isFalse);
      expect(
        _policy.looksLikeCompletedCodingFinalAnswer(
          'The code completed. ${'x' * 1600}',
        ),
        isFalse,
      );
      expect(
        _policy.looksLikeCompletedCodingFinalAnswer(
          'The requested work completed successfully.',
        ),
        isFalse,
      );
      expect(
        _policy.looksLikeCompletedCodingFinalAnswer(
          'The Dart implementation remains in progress.',
        ),
        isFalse,
      );
    });
  });

  group('future coding action detection', () {
    test('recognizes English and CJK future actions', () {
      expect(
        _policy.looksLikeCodingFutureAction(
          'Now I will inspect the Dart source.',
        ),
        isTrue,
      );
      expect(
        _policy.looksLikeCodingFutureAction(
          String.fromCharCodes([0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059]),
        ),
        isTrue,
      );
    });

    test('rejects empty and terminal prose', () {
      expect(_policy.looksLikeCodingFutureAction(''), isFalse);
      expect(
        _policy.looksLikeCodingFutureAction(
          'The Dart implementation completed.',
        ),
        isFalse,
      );
    });
  });

  group('turn finalization candidate text', () {
    test('prefers a non-empty streamed final answer', () {
      expect(
        _policy.turnFinalizationCandidateText(
          content: 'Visible fallback.',
          streamedFinalAnswer: '  Streamed final answer.  ',
        ),
        'Streamed final answer.',
      );
    });

    test('strips tool artifacts when the streamed answer is absent', () {
      const content = '''
Checking the source.
<tool_use>{"name":"read_file","arguments":{"path":"lib/main.dart"}}</tool_use>
The Dart implementation completed.
''';

      for (final streamedAnswer in <String?>[null, '   ']) {
        final candidate = _policy.turnFinalizationCandidateText(
          content: content,
          streamedFinalAnswer: streamedAnswer,
        );
        expect(candidate, contains('Checking the source.'));
        expect(candidate, contains('The Dart implementation completed.'));
        expect(candidate, isNot(contains('<tool_use>')));
      }
    });
  });

  group('content before finalization candidate', () {
    test('keeps trimmed content for an empty candidate', () {
      expect(
        _policy.contentBeforeFinalizationCandidate(
          currentContent: 'Prefix content.   ',
          candidateResponse: ' ',
        ),
        'Prefix content.',
      );
    });

    test('returns empty content when the candidate is absent', () {
      expect(
        _policy.contentBeforeFinalizationCandidate(
          currentContent: 'Prefix content.',
          candidateResponse: 'Missing candidate.',
        ),
        isEmpty,
      );
    });

    test('extracts the prefix before the last candidate occurrence', () {
      expect(
        _policy.contentBeforeFinalizationCandidate(
          currentContent:
              'Repeated candidate.\nEvidence.\nRepeated candidate.  ',
          candidateResponse: '  Repeated candidate. ',
        ),
        'Repeated candidate.\nEvidence.',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/proposal_parsing_text_utils.dart';
import 'package:caverno/features/chat/domain/services/runtime_sampler_feedback_recorder.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  group('ProposalJsonExtractor', () {
    test('repairs truncated JSON objects', () {
      final feedback = _RecordingFeedbackSink();
      final extractor = ProposalJsonExtractor(
        jsonRepairFeedback: _feedbackBinding(feedback),
      );

      final decoded = extractor.extractJsonMap('{"taskCount":1');

      expect(decoded, {'taskCount': 1});
      expect(feedback.events, hasLength(1));
    });

    test('calls the repair hook only when a repair succeeds', () {
      final feedback = _RecordingFeedbackSink();
      final extractor = ProposalJsonExtractor(
        jsonRepairFeedback: _feedbackBinding(feedback),
      );

      expect(extractor.extractJsonMap('{"goal":"Direct"}'), {'goal': 'Direct'});
      expect(feedback.events, isEmpty);

      expect(extractor.extractJsonMap('prefix {"goal":"Sliced"} suffix'), {
        'goal': 'Sliced',
      });
      expect(feedback.events, isEmpty);

      expect(extractor.extractJsonMap('```json\n{"taskCount":1\n```'), {
        'taskCount': 1,
      });
      expect(feedback.events, hasLength(1));

      expect(extractor.extractJsonMap('prefix {"taskCount":2'), {
        'taskCount': 2,
      });
      expect(feedback.events, hasLength(2));
    });
  });

  group('ProposalParsingTextUtils', () {
    test('collects proposal sections from markdown labels', () {
      final sections = ProposalParsingTextUtils.collectProposalSections('''
Goal: Add persisted planning state
Constraints:
- Keep existing conversations compatible
Acceptance Criteria:
- Planning state survives reload
Open Questions: Should drafts sync across devices?
''');

      expect(sections['goal'], ['Add persisted planning state']);
      expect(sections['constraints'], [
        'Keep existing conversations compatible',
      ]);
      expect(sections['acceptanceCriteria'], [
        'Planning state survives reload',
      ]);
      expect(sections['openQuestions'], ['Should drafts sync across devices?']);
    });

    test('detects truncation finish reasons', () {
      expect(ProposalParsingTextUtils.isCompletionTruncated('length'), isTrue);
      expect(
        ProposalParsingTextUtils.isCompletionTruncated(' LENGTH '),
        isTrue,
      );
      expect(ProposalParsingTextUtils.isCompletionTruncated('stop'), isFalse);
      expect(ProposalParsingTextUtils.isCompletionTruncated(''), isFalse);
    });
  });
}

final class _RecordingFeedbackSink implements RuntimeSamplerFeedbackEventSink {
  final List<RuntimeSamplerFeedbackEvent> events = [];

  @override
  Future<bool> recordEvent(RuntimeSamplerFeedbackEvent event) async {
    events.add(event);
    return true;
  }
}

RuntimeSamplerFeedbackEventBinding _feedbackBinding(
  RuntimeSamplerFeedbackEventSink sink,
) {
  return RuntimeSamplerFeedbackEventBinding(
    sink: sink,
    event: RuntimeSamplerToolLoopRepetitionEvent(
      owner: ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      ),
      baselineProfile: ModelCapabilityProfile(
        id: '',
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://localhost:1234/v1',
        model: 'test-model',
      ),
    ),
  );
}

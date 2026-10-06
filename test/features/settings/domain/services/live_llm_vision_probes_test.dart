import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_vision_probes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The diagnostic's image probes, moved out of the service (F5) and driven
/// here by scripted replies. Defended: the no-image control outranks the
/// score, a rejected image request is its own verdict, and each arm carries
/// the image only when it should, at the budget it should.
void main() {
  late List<({bool hasImage, int maxTokens})> sent;

  LiveLlmVisionProbes probes({
    required String Function(bool hasImage) reply,
    bool rejectImage = false,
  }) {
    return LiveLlmVisionProbes(
      complete: ({required messages, required maxTokens}) async {
        final hasImage = messages.last.imageBase64 != null;
        sent.add((hasImage: hasImage, maxTokens: maxTokens));
        if (rejectImage && hasImage) throw Exception('400 image not allowed');
        return ChatCompletionResult(
          content: reply(hasImage),
          finishReason: 'stop',
        );
      },
      completeWithToolResults:
          ({required messages, required toolResults}) async {
            expect(toolResults.single.result, contains('imageBase64'));
            return ChatCompletionResult(
              content: reply(true),
              finishReason: 'stop',
            );
          },
      messages: (user) => [
        Message(
          id: 'u',
          content: user,
          role: MessageRole.user,
          timestamp: DateTime.utc(2026),
        ),
      ],
      answerMaxTokens: 512,
      reasoningMaxTokens: 2048,
    );
  }

  setUp(() => sent = []);

  group('quadrant attachment', () {
    test('reading the image and not the control passes', () async {
      final result = await probes(
        reply: (hasImage) => hasImage ? 'yellow, blue, red, green' : 'red',
      ).attachment();
      expect(result.id, LiveLlmVisionProbes.attachmentProbeId);
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(sent.map((s) => s.hasImage), [true, false]);
      expect(sent.map((s) => s.maxTokens), [512, 512]);
    });

    test('a control that scores as well means the image was ignored', () async {
      final result = await probes(
        reply: (_) => 'yellow, blue, red, green',
      ).attachment();
      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.details, contains('model_ignored_the_image'));
    });

    test(
      'a rejected image request is reported as the endpoint rejecting it',
      () async {
        final result = await probes(
          reply: (_) => 'green',
          rejectImage: true,
        ).attachment();
        expect(result.status, LiveLlmDiagnosticStatus.failed);
        expect(result.details, contains('endpoint_rejected'));
      },
    );
  });

  group('chart reading', () {
    test('uses the reasoning budget and passes a correct reading', () async {
      final result = await probes(
        reply: (hasImage) =>
            hasImage ? '78, 41, Dune, Cobalt' : '50, 50, Aster, Briar',
      ).chartReading();
      expect(result.id, LiveLlmVisionProbes.chartReadingProbeId);
      expect(result.status, LiveLlmDiagnosticStatus.passed);
      expect(sent.map((s) => s.maxTokens), [2048, 2048]);
    });

    test('an answer lost to reasoning is a warning, not blindness', () async {
      final result = await probes(
        reply: (hasImage) => hasImage ? '<think>the axis runs to 100' : 'x',
      ).chartReading();
      expect(result.status, LiveLlmDiagnosticStatus.warning);
      expect(result.details, contains('no_answer_within_budget'));
    });
  });

  test('the tool-observation image is read through a tool result', () async {
    final result = await probes(
      reply: (_) => 'yellow, blue, red, green',
    ).toolObservation();
    expect(result.id, LiveLlmVisionProbes.toolObservationProbeId);
    expect(result.status, LiveLlmDiagnosticStatus.passed);
    expect(result.passedChecks, 4);
  });
}

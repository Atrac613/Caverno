import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_response_scoring.dart';
import 'llm_sampler_preset_profile.dart';

/// Sends one sampler-calibration request and returns the model's reply.
///
/// The service binds the diagnostic model, token cap, and thinking observer;
/// a trial chooses only the prompt, the tools, and the temperature.
typedef SamplerCalibrationCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      List<Map<String, dynamic>>? tools,
      required double temperature,
    });

/// The four sampler-calibration trials of the live LLM diagnostic.
///
/// Moved out of `LiveLlmDiagnosticService` unchanged (F5): each trial sends
/// one request at one temperature and grades the reply into a
/// [LiveLlmDiagnosticSamplerTrial]. Deciding which trials run and folding
/// them into the report stays with the service.
class LiveLlmSamplerCalibrationTrials {
  const LiveLlmSamplerCalibrationTrials({
    required SamplerCalibrationCompletion complete,
    required List<Message> Function(String user) messages,
  }) : _complete = complete,
       _messages = messages;

  final SamplerCalibrationCompletion _complete;
  final List<Message> Function(String user) _messages;

  static const _routineSamplerMarker = 'CAVERNO_ROUTINE_SAMPLER_OK';
  static const _codingSamplerMarker = 'CAVERNO_CODING_SAMPLER_OK';
  static const _planSamplerMarker = 'CAVERNO_PLAN_SAMPLER_OK';
  static const _codingSamplerEditBlock = <String>[
    '<<<<<<< SEARCH',
    'return oldValue;',
    '=======',
    'return newValue;',
    '>>>>>>> REPLACE',
  ];
  static const _planSamplerTasks = <String>['inspect', 'edit', 'verify'];

  Future<LiveLlmDiagnosticSamplerTrial> toolLoop({
    required Map<String, dynamic> dateTool,
    required double temperature,
  }) async {
    try {
      final result = await _complete(
        messages: _messages(
          'Call the get_current_datetime tool now. Do not answer in text '
          'before using the tool.',
        ),
        tools: [dateTool],
        temperature: temperature,
      );
      final toolCalls = LiveLlmResponseScoring.toolCallsFrom(result);
      final passed = toolCalls.any(
        (call) => call.name == 'get_current_datetime',
      );
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.toolLoop.metadataName,
        temperature: temperature,
        passed: passed,
        malformedToolCallCount: passed ? 0 : 1,
        repetitionDetected: LiveLlmResponseScoring.looksRepetitive(
          result.content,
        ),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.toolLoop.metadataName,
        temperature: temperature,
        passed: false,
        malformedToolCallCount: 1,
      );
    }
  }

  Future<LiveLlmDiagnosticSamplerTrial> routine({
    required double temperature,
  }) async {
    try {
      final result = await _complete(
        messages: _messages(
          'Return exactly this routine sampler JSON object and no markdown:\n'
          '{"routine":"sampler_calibration","status":"ok","marker":"$_routineSamplerMarker","nextAction":"post_summary"}',
        ),
        temperature: temperature,
      );
      final content = result.content.trim();
      final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
      final passed =
          decoded?['routine'] == 'sampler_calibration' &&
          decoded?['status'] == 'ok' &&
          decoded?['marker'] == _routineSamplerMarker &&
          decoded?['nextAction'] == 'post_summary';
      final hasUnexpectedToolCalls = LiveLlmResponseScoring.toolCallsFrom(
        result,
      ).isNotEmpty;
      final hasMarker = content.contains(_routineSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.routine.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: !passed && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        repetitionDetected: LiveLlmResponseScoring.looksRepetitive(
          result.content,
        ),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.routine.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
      );
    }
  }

  Future<LiveLlmDiagnosticSamplerTrial> coding({
    required double temperature,
  }) async {
    try {
      final result = await _complete(
        messages: _messages(
          'Return exactly this coding sampler JSON object and no markdown:\n'
          '{"coding":"sampler_calibration","status":"ok","marker":"$_codingSamplerMarker","edit":["<<<<<<< SEARCH","return oldValue;","=======","return newValue;",">>>>>>> REPLACE"]}',
        ),
        temperature: temperature,
      );
      final content = result.content.trim();
      final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
      final editBlockMatches = LiveLlmResponseScoring.stringListEquals(
        decoded?['edit'],
        _codingSamplerEditBlock,
      );
      final hasCodingEnvelope =
          decoded?['coding'] == 'sampler_calibration' &&
          decoded?['marker'] == _codingSamplerMarker;
      final passed =
          hasCodingEnvelope && decoded?['status'] == 'ok' && editBlockMatches;
      final hasUnexpectedToolCalls = LiveLlmResponseScoring.toolCallsFrom(
        result,
      ).isNotEmpty;
      final hasMarker = content.contains(_codingSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.coding.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: decoded == null && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        editApplyFailureCount: hasCodingEnvelope && !editBlockMatches ? 1 : 0,
        repetitionDetected: LiveLlmResponseScoring.looksRepetitive(
          result.content,
        ),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.coding.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
        editApplyFailureCount: 1,
      );
    }
  }

  Future<LiveLlmDiagnosticSamplerTrial> plan({
    required double temperature,
  }) async {
    try {
      final result = await _complete(
        messages: _messages(
          'Return exactly this plan sampler JSON object and no markdown:\n'
          '{"plan":"sampler_calibration","status":"ok","marker":"$_planSamplerMarker","tasks":["inspect","edit","verify"]}',
        ),
        temperature: temperature,
      );
      final content = result.content.trim();
      final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(content);
      final passed =
          decoded?['plan'] == 'sampler_calibration' &&
          decoded?['status'] == 'ok' &&
          decoded?['marker'] == _planSamplerMarker &&
          LiveLlmResponseScoring.stringListEquals(
            decoded?['tasks'],
            _planSamplerTasks,
          );
      final hasUnexpectedToolCalls = LiveLlmResponseScoring.toolCallsFrom(
        result,
      ).isNotEmpty;
      final hasMarker = content.contains(_planSamplerMarker);
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.plan.metadataName,
        temperature: temperature,
        passed: passed && !hasUnexpectedToolCalls,
        jsonRepairEventCount: decoded == null && hasMarker ? 1 : 0,
        malformedToolCallCount: hasUnexpectedToolCalls ? 1 : 0,
        repetitionDetected: LiveLlmResponseScoring.looksRepetitive(
          result.content,
        ),
      );
    } catch (_) {
      return LiveLlmDiagnosticSamplerTrial(
        requestClass: LlmSamplerRequestClass.plan.metadataName,
        temperature: temperature,
        passed: false,
        jsonRepairEventCount: 1,
      );
    }
  }
}

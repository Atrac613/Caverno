import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/data/datasources/openai_parameter_support_probe.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

/// Sends one structured-output arm with the requested response format and cap.
typedef StructuredOutputProbeCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required StructuredOutputRequest responseFormat,
      required int maxTokens,
    });

/// The diagnostic's JSON Schema arm and JSON object fallback. The service owns
/// selection, endpoint IO, request settings, thinking observation, and reports.
class LiveLlmStructuredOutputProbe {
  const LiveLlmStructuredOutputProbe({
    required StructuredOutputProbeCompletion complete,
    required Future<EndpointParameterSupport> Function() responseFormatSupport,
    required List<Message> Function(String user) messages,
    required int answerMaxTokens,
    required int reasoningMaxTokens,
    DateTime Function() now = DateTime.now,
  }) : _complete = complete,
       _responseFormatSupport = responseFormatSupport,
       _messages = messages,
       _answerMaxTokens = answerMaxTokens,
       _reasoningMaxTokens = reasoningMaxTokens,
       _now = now;

  static const probeId = 'structured_output';
  static const supportMetadataKey = 'structuredOutputSupport';
  static const _schemaMarker = 'CAVERNO_SCHEMA_LOCKED_47';
  static const _objectMarker = 'CAVERNO_JSON_OBJECT_OK';
  static const _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'marker': <String, dynamic>{'type': 'string', 'const': _schemaMarker},
      'count': <String, dynamic>{'type': 'integer', 'const': 47},
    },
    'required': <String>['marker', 'count'],
    'additionalProperties': false,
  };

  final StructuredOutputProbeCompletion _complete;
  final Future<EndpointParameterSupport> Function() _responseFormatSupport;
  final List<Message> Function(String user) _messages;
  final int _answerMaxTokens;
  final int _reasoningMaxTokens;
  final DateTime Function() _now;

  /// [startedAt] precedes the service's running update, so elapsed time includes
  /// report publication, the metadata lookup, and every attempted arm.
  Future<LiveLlmDiagnosticProbeResult> run({
    required DateTime startedAt,
    void Function(LiveLlmDiagnosticProbeResult result)? onResult,
  }) async {
    final completed = <ChatCompletionResult>[];
    String schemaDetail;

    // Only an explicit endpoint denial skips the schema generation. Most
    // servers do not advertise parameters; unknown support keeps both arms.
    if (await _responseFormatSupport() ==
        EndpointParameterSupport.unsupported) {
      return _runObjectArm(
        completed: completed,
        schemaDetail:
            'json_schema: not attempted -- the endpoint does not list '
            'response_format among its supported_parameters',
        startedAt: startedAt,
        onResult: onResult,
      );
    }

    try {
      final schemaResult = await _complete(
        messages: _messages(
          // Name the values in both arms: an endpoint that drops response_format
          // must still receive an answerable prompt rather than reason to its cap.
          'Return one JSON object with exactly these two fields and no '
          'markdown, matching the supplied response schema: '
          '{"marker":"$_schemaMarker","count":47}',
        ),
        responseFormat: const StructuredOutputRequest.jsonSchema(
          name: 'caverno_live_diagnostic',
          schema: _schema,
        ),
        maxTokens: _reasoningMaxTokens,
      );
      completed.add(schemaResult);
      final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(
        schemaResult.content,
      );
      final schemaPassed =
          decoded?.length == 2 &&
          decoded?['marker'] == _schemaMarker &&
          decoded?['count'] == 47;
      if (schemaPassed) {
        final result = LiveLlmDiagnosticProbeResult(
          id: probeId,
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'The endpoint and model enforced the supplied JSON schema.',
          details: 'json_schema: passed\njson_object fallback: not needed',
          modelContent: LiveLlmDiagnosticEvidence.preview(schemaResult.content),
          usage: LiveLlmDiagnosticEvidence.usage(schemaResult),
          passedChecks: 2,
          totalChecks: 2,
          metadata: const {supportMetadataKey: 'jsonSchema'},
          elapsed: _now().difference(startedAt),
        );
        // Schema publication was inside the original arm's failure boundary.
        // Keep that scope while the service owns the report update itself.
        onResult?.call(result);
        return result;
      }
      schemaDetail = _schemaArmDetail(schemaResult);
    } catch (error) {
      schemaDetail =
          'json_schema: request failed (${LiveLlmDiagnosticEvidence.preview('$error')})';
    }

    return _runObjectArm(
      completed: completed,
      schemaDetail: schemaDetail,
      startedAt: startedAt,
      onResult: onResult,
    );
  }

  String _schemaArmDetail(ChatCompletionResult result) {
    final visible = LiveLlmResponseScoring.visibleContent(result.content);
    // A truncated answer describes the harness budget, not a schema violation.
    if (result.finishReason == 'length') {
      return visible.isEmpty
          ? 'json_schema: the model reasoned to the token cap and returned no '
                'answer (finish_reason: length)'
          : 'json_schema: the answer was truncated at the token cap '
                '(finish_reason: length)';
    }
    if (visible.isEmpty) {
      return 'json_schema: the request completed but returned no content';
    }
    return 'json_schema: request completed but the response violated the schema';
  }

  Future<LiveLlmDiagnosticProbeResult> _runObjectArm({
    required List<ChatCompletionResult> completed,
    required String schemaDetail,
    required DateTime startedAt,
    required void Function(LiveLlmDiagnosticProbeResult result)? onResult,
  }) async {
    LiveLlmDiagnosticProbeResult result;
    try {
      final objectResult = await _complete(
        messages: _messages(
          'Return one JSON object with exactly these two fields and no '
          'markdown: {"marker":"$_objectMarker","count":47}',
        ),
        responseFormat: const StructuredOutputRequest.jsonObject(),
        maxTokens: _answerMaxTokens,
      );
      completed.add(objectResult);
      final decoded = LiveLlmResponseScoring.tryDecodeJsonObject(
        objectResult.content,
      );
      final objectPassed =
          decoded?.length == 2 &&
          decoded?['marker'] == _objectMarker &&
          decoded?['count'] == 47;
      result = LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: objectPassed
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
        summary: objectPassed
            ? 'JSON object mode worked, but JSON Schema mode did not.'
            : 'Neither structured-output mode preserved its contract.',
        details: [
          schemaDetail,
          'json_object: ${objectPassed ? 'passed' : 'response violated the contract'}',
        ].join('\n'),
        modelContent: LiveLlmDiagnosticEvidence.preview(objectResult.content),
        usage: LiveLlmDiagnosticEvidence.totalUsage(completed),
        passedChecks: objectPassed ? 1 : 0,
        totalChecks: 2,
        metadata: {supportMetadataKey: objectPassed ? 'jsonObject' : 'none'},
        elapsed: _now().difference(startedAt),
      );
    } catch (error) {
      result = LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'Neither structured-output request mode was usable.',
        details: [
          schemaDetail,
          'json_object: request failed (${LiveLlmDiagnosticEvidence.preview('$error')})',
        ].join('\n'),
        usage: LiveLlmDiagnosticEvidence.totalUsage(completed),
        passedChecks: 0,
        totalChecks: 2,
        metadata: const {supportMetadataKey: 'none'},
        elapsed: _now().difference(startedAt),
      );
    }
    onResult?.call(result);
    return result;
  }
}

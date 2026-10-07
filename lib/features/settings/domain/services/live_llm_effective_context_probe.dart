import 'dart:math' as math;

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

typedef EffectiveContextProbeCompletion =
    Future<ChatCompletionResult> Function(int target, List<Message> messages);

/// One bounded context-ladder measurement, published by the service.
class LiveLlmEffectiveContextProbeMeasurement {
  const LiveLlmEffectiveContextProbeMeasurement({
    required this.result,
    required this.metrics,
  });

  final LiveLlmDiagnosticProbeResult result;
  final LiveLlmDiagnosticEffectiveContextMetrics metrics;
}

/// Measures boundary-marker recall. Selection, opt-in, provider skips,
/// request settings, thinking observation and publication stay with the service.
class LiveLlmEffectiveContextProbe {
  const LiveLlmEffectiveContextProbe({
    required EffectiveContextProbeCompletion complete,
    required List<Message> Function(String user) messages,
    required Future<int> Function() advertisedContextTokens,
    DateTime Function() now = DateTime.now,
  }) : _complete = complete,
       _messages = messages,
       _advertisedContextTokens = advertisedContextTokens,
       _now = now;

  static const probeId = 'effective_context';
  static const hardMaximumTokens = 1048576;
  static const _initialTokens = 2048;

  final EffectiveContextProbeCompletion _complete;
  final List<Message> Function(String user) _messages;
  final Future<int> Function() _advertisedContextTokens;
  final DateTime Function() _now;

  /// [startedAt] precedes running publication, preserving its elapsed time.
  /// The service calls this only after a positive maximum was explicitly set.
  Future<LiveLlmEffectiveContextProbeMeasurement> run({
    required int requestedMaximumTokens,
    required DateTime startedAt,
  }) async {
    final maximum = math.min(requestedMaximumTokens, hardMaximumTokens);
    final trials = <LiveLlmDiagnosticContextTrial>[];
    final completed = <ChatCompletionResult>[];
    for (final target in _effectiveContextTargets(maximum)) {
      final stopwatch = Stopwatch()..start();
      try {
        final result = await _complete(
          target,
          _effectiveContextMessages(target),
        );
        completed.add(result);
        stopwatch.stop();
        final expected = _effectiveContextExpectedReply(target);
        final visibleContent = LiveLlmResponseScoring.visibleContent(
          result.content,
        );
        final recallPassed = visibleContent == expected;
        final usageReported = result.usage.promptTokens > 0;
        final failureKind = !recallPassed
            ? _effectiveContextResponseFailureKind(target, visibleContent)
            : !usageReported
            ? 'prompt_usage_missing'
            : '';
        trials.add(
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: target,
            elapsed: stopwatch.elapsed,
            passed: recallPassed && usageReported,
            promptTokens: result.usage.promptTokens,
            failure: !recallPassed
                ? 'The response did not reproduce both boundary markers.'
                : !usageReported
                ? 'The endpoint omitted prompt token usage.'
                : '',
            failureKind: failureKind,
            finishReason: result.finishReason,
            responsePreview: recallPassed
                ? ''
                : LiveLlmDiagnosticEvidence.preview(
                    result.content,
                    maxChars: 240,
                  ),
          ),
        );
      } catch (error) {
        stopwatch.stop();
        trials.add(
          LiveLlmDiagnosticContextTrial(
            requestedApproximateTokens: target,
            elapsed: stopwatch.elapsed,
            passed: false,
            failure: LiveLlmDiagnosticEvidence.preview('$error', maxChars: 300),
            failureKind: 'request_error',
          ),
        );
      }
      if (!trials.last.passed) break;
    }

    final metrics = LiveLlmDiagnosticEffectiveContextMetrics(
      configuredMaximumTokens: maximum,
      trials: List.unmodifiable(trials),
      // Recorded so the ladder can tell a rung the model failed from one that
      // never fit this endpoint's window.
      advertisedContextTokens: await _advertisedContextTokens(),
    );
    final measured = metrics.maxSuccessfulPromptTokens;
    final status = measured == 0
        ? LiveLlmDiagnosticStatus.failed
        : metrics.reachedConfiguredMaximum
        ? LiveLlmDiagnosticStatus.passed
        : LiveLlmDiagnosticStatus.warning;
    final summary = measured == 0
        ? 'The context ladder could not produce a measured successful request.'
        : metrics.reachedConfiguredMaximum
        ? 'The model preserved both boundary markers through the configured maximum.'
        : 'The context ladder found a boundary above the last successful request.';
    return LiveLlmEffectiveContextProbeMeasurement(
      metrics: metrics,
      result: LiveLlmDiagnosticProbeResult(
        id: probeId,
        status: status,
        summary: summary,
        details: [
          'Measured prompt tokens: $measured',
          'Configured approximate maximum: $maximum',
          if (requestedMaximumTokens > maximum)
            'Requested maximum was clamped to $hardMaximumTokens tokens.',
          for (final trial in trials)
            '${trial.requestedApproximateTokens}: '
                '${trial.passed ? 'passed' : 'failed'}'
                '${trial.promptTokens > 0 ? ' (${trial.promptTokens} prompt tokens)' : ''}'
                '${trial.failureKind.isNotEmpty ? ' [${trial.failureKind}]' : ''}'
                '${trial.finishReason.isNotEmpty ? ' finish=${trial.finishReason}' : ''}'
                '${trial.failure.isNotEmpty ? ' - ${trial.failure}' : ''}',
        ].join('\n'),
        passedChecks: trials.where((trial) => trial.passed).length,
        totalChecks: trials.length,
        metadata: {'maxSuccessfulPromptTokens': '$measured'},
        modelContent: trials
            .map((trial) => trial.responsePreview)
            .firstWhere((preview) => preview.isNotEmpty, orElse: () => ''),
        usage: LiveLlmDiagnosticEvidence.totalUsage(completed),
        elapsed: _now().difference(startedAt),
      ),
    );
  }

  List<int> _effectiveContextTargets(int maximum) {
    if (maximum <= _initialTokens) return [maximum];
    final targets = <int>[];
    var target = _initialTokens;
    while (target < maximum) {
      targets.add(target);
      target *= 2;
    }
    if (targets.isEmpty || targets.last != maximum) targets.add(maximum);
    return targets;
  }

  List<Message> _effectiveContextMessages(int target) {
    final begin = _effectiveContextBeginMarker(target);
    final end = _effectiveContextEndMarker(target);
    final fillerCount = math.max(1, target - 128);
    final content = StringBuffer()
      ..writeln(
        'Read the DATA block. Return the exact line beginning CTX_BEGIN_ and '
        'the exact line beginning CTX_END_, separated by |, with no spaces or '
        'other text.',
      )
      ..writeln('DATA')
      ..writeln(begin)
      ..write(List.filled(fillerCount, 'pad').join(' '))
      ..writeln()
      ..writeln(end)
      ..write('END DATA');
    return _messages(content.toString());
  }

  String _effectiveContextExpectedReply(int target) =>
      '${_effectiveContextBeginMarker(target)}|${_effectiveContextEndMarker(target)}';

  String _effectiveContextResponseFailureKind(int target, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return 'response_empty';
    final hasBegin = trimmed.contains(_effectiveContextBeginMarker(target));
    final hasEnd = trimmed.contains(_effectiveContextEndMarker(target));
    if (hasBegin && hasEnd) return 'response_both_markers_non_exact';
    if (hasBegin) return 'response_begin_marker_only';
    if (hasEnd) return 'response_end_marker_only';
    return 'response_mismatch';
  }

  String _effectiveContextBeginMarker(int target) => 'CTX_BEGIN_$target';
  String _effectiveContextEndMarker(int target) => 'CTX_END_$target';
}

import 'dart:convert';

import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/tool_call_info.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_chart_probe_image.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

/// Sends one vision-probe request with the given completion budget.
typedef VisionProbeCompletion =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required int maxTokens,
    });

/// Sends a request whose image arrives as a tool observation.
typedef VisionProbeToolObservation =
    Future<ChatCompletionResult> Function({
      required List<Message> messages,
      required List<ToolResultInfo> toolResults,
    });

/// The live LLM diagnostic's image probes: quadrant colours from an attached
/// image, readings off a chart, and the same image delivered as a tool
/// observation. Each image arm runs against a no-image control, so a model
/// that answers as well blind is reported as not having read the image.
///
/// Moved out of `LiveLlmDiagnosticService` unchanged (F5). The service binds
/// the ports to its model, temperature, and thinking observer, and decides
/// which probes run for which provider.
class LiveLlmVisionProbes {
  const LiveLlmVisionProbes({
    required VisionProbeCompletion complete,
    required VisionProbeToolObservation completeWithToolResults,
    required List<Message> Function(String user) messages,
    required int answerMaxTokens,
    required int reasoningMaxTokens,
  }) : _complete = complete,
       _completeWithToolResults = completeWithToolResults,
       _messages = messages,
       _answerMaxTokens = answerMaxTokens,
       _reasoningMaxTokens = reasoningMaxTokens;

  static const attachmentProbeId = 'vision_attachment';
  static const chartReadingProbeId = 'chart_reading';
  static const toolObservationProbeId = 'vision_tool_observation';

  /// The quadrant test image; see the service's `visionProbeImageBase64` for
  /// why its size is load-bearing.
  static const imageBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAYAAAAGACAIAAAArpSLoAAAEpElEQVR42u3UwQkAMAwDMe'
      '+/tLtD8glFoAkMvrSBsaQw50IIEAKEACFAIEAIEAKEAIEAIUAIEAIEAoQAIUAIEAIEAoQA'
      'IUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAhQAgQAgQChAAhQAgQCBAChAAhQCBACB'
      'AChAAhQCBACBAChACBACFACBACBAKEACFACBC4EAKEACFACBAIEAKEACFAIEAIEAKEAIEA'
      'IUAIEAKEAHkRAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAhQAgQAgQChAAhQA'
      'gQCBAChAAhQCBACBAChAAhQCBACBAChACBACFACBACBAKEACFACBAIEAKEACFACBAIEAKE'
      'ACFAIEAIEAKEAIEAIUAIEAIELoQAIUAIEAIEAoQAIUAIEAgQAoQAIUAgQAgQAoQAIUAgQA'
      'gQAoQAgQAhQAgQAgQChAAhQAgQCBAChAAhQAgQCBAChAAhQCBACBAChACBACFACBACBAKE'
      'ACFACBACBAKEACFACBAIEAKEACFAIEAIEAKEAIEAIUAIEAKEAIEAIUAIEAIEAoQAIUAIEA'
      'gQAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAgQChAAhQAgQAgQChAAhQAgQCBAChAAh'
      'QCBACBAChACBACFACBAChACBACFACBACBAKEACFACBAIEAKEACFAIEAIEAKEACFAIEAIEA'
      'KEAIEAIUAIEAIEAoQAIUAIELgQAoQAIUAIEAgQAoQAIUAgQAgQAoQAgQAhQAgQAoQAgQAh'
      'QAgQAgQChAAhQAgQCBAChAAhQCBACBAChAAhQCBACBAChACBACFACBACBAKEACFACBAIEA'
      'KEACFACBAIEAKEACFAIEAIEAKEAIEAIUAIEAIEAoQAIUAIEAIEAoQAIUAIEAgQAoQAIUAg'
      'QAgQAoQAIUAuhAAhQAgQAgQChAAhQAgQCBACxM0A2YAFEwACBAgQgAABAgQgQIAAAQgQIE'
      'AAAgQIEIAAAQIEIECAAAEIECBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIEAAAgQIEIAA'
      'AQIEIECAAAECBCBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIEAAAgQIECBAAAIECBCAAA'
      'ECBCBAgAABCBAgQAACBAgQgAABAgQgQIAAAQgQIECAAAEIECBAAAIECBCAAAECBCBAgAAB'
      'CBAgQAACBAgQgAABAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABCBAgQAACBA'
      'gQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABAmQCQIAAAQIQIECAAAQI'
      'ECAAAQIECECAAAECECBAgAAECBAgAAECBAgQIAABAgQIQIAAAQIQIECAAAQIECAAAQIECE'
      'CAAAECECBAgABMAAgQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBCBAgAABAgQg'
      'QIAAAQgQIEAAAgQIEIAAAQIEIECAAAEIECBAAAIECBCAAAECBAgQgAABAgQgQIAAAQgQIE'
      'AAAgQIEIAAAQIEIECAAPGdB+I3WgSaUHuyAAAAAElFTkSuQmCC';

  static const _imageMimeType = 'image/png';
  static const _visionProbeExpectedColors = <String>[
    'yellow',
    'blue',
    'red',
    'green',
  ];
  static const _visionProbePrompt =
      'The attached image is split into four equal quadrants, each a single '
      'solid color. Reply with exactly the four color names in reading order '
      '(top-left, top-right, bottom-left, bottom-right), lowercase, separated '
      'by commas, and no other text.';

  /// Asks for all four readings in one turn.
  ///
  /// One request per arm rather than one per question: the probe runs on every
  /// diagnostic pass and a chart image is not cheap, and asking separately
  /// measured nothing extra when it was tried against a live endpoint.
  static const _chartProbePrompt =
      'The attached image is a bar chart with a labelled y axis. Reply with '
      'exactly four comma-separated items and no other text: the numeric '
      'height of the bar labelled Briar, the numeric height of the bar '
      'labelled Aster, the label of the tallest bar, the label of the '
      'shortest bar.';

  static const _chartClassificationRejected = 'endpoint_rejected';
  static const _chartClassificationNoAnswer = 'no_answer_within_budget';
  static const _chartClassificationGuessed = 'model_guessed_without_reading';
  static const _chartClassificationPartial = 'partially_read';
  static const _chartClassificationRead = 'read_correctly';

  static const _visionClassificationRejected = 'endpoint_rejected';
  static const _visionClassificationIgnored = 'model_ignored_the_image';
  static const _visionClassificationPartial = 'partially_read';
  static const _visionClassificationRead = 'read_correctly';

  final VisionProbeCompletion _complete;
  final VisionProbeToolObservation _completeWithToolResults;
  final List<Message> Function(String user) _messages;
  final int _answerMaxTokens;
  final int _reasoningMaxTokens;

  /// Reads the image through the user-attachment path: a user message carrying
  /// `imageBase64`, which `_formatMessages` turns into an image content part.
  ///
  /// Runs a no-image control arm as well. Without it a model that ignores image
  /// content but guesses a plausible color list is indistinguishable from one
  /// that actually looked; with it, "the control scored the same" is direct
  /// evidence the image did not inform the answer.
  Future<LiveLlmDiagnosticProbeResult> attachment() async {
    final withImage = await _colorArm(attachImage: true);
    final control = await _colorArm(attachImage: false);

    if (withImage.rejected) {
      return LiveLlmDiagnosticProbeResult(
        id: attachmentProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected a request carrying image content.',
        details:
            'Classification: $_visionClassificationRejected\n${withImage.error}',
        modelContent: LiveLlmDiagnosticEvidence.preview(
          withImage.content,
          maxChars: 400,
        ),
      );
    }

    final matched = withImage.matchedColors;
    final controlMatched = control.matchedColors;
    // The control arm outranks the score. A model that answers just as well
    // with no image did not read one, and a correct answer it could produce
    // blind is not evidence of vision -- so this is checked before the
    // all-four-colors pass.
    final ignored = controlMatched >= matched;
    final passed = !ignored && matched == _visionProbeExpectedColors.length;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : ignored
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;

    return LiveLlmDiagnosticProbeResult(
      id: attachmentProbeId,
      status: status,
      summary: passed
          ? 'The model read every quadrant color from the attached image.'
          : ignored
          ? 'The no-image control arm scored the same, so the image was not used.'
          : 'The model read the image only partially.',
      details: [
        'Classification: ${passed
            ? _visionClassificationRead
            : ignored
            ? _visionClassificationIgnored
            : _visionClassificationPartial}',
        'Expected: ${_visionProbeExpectedColors.join(', ')}',
        'With image: $matched/${_visionProbeExpectedColors.length} colors in order',
        'No-image control: $controlMatched/${_visionProbeExpectedColors.length}',
      ].join('\n'),
      modelContent: [
        // The visible answer, not the reasoning: a think block filled the whole
        // preview and left the actual reading -- the evidence for the verdict
        // above -- invisible in the report.
        'with_image: ${LiveLlmDiagnosticEvidence.preview(LiveLlmResponseScoring.visibleContent(withImage.content), maxChars: 240)}',
        'control: ${LiveLlmDiagnosticEvidence.preview(LiveLlmResponseScoring.visibleContent(control.content), maxChars: 240)}',
      ].join('\n'),
      usage: LiveLlmDiagnosticEvidence.totalUsage([
        if (withImage.result != null) withImage.result!,
        if (control.result != null) control.result!,
      ]),
      passedChecks: matched,
      totalChecks: _visionProbeExpectedColors.length,
    );
  }

  Future<_VisionArm> _colorArm({required bool attachImage}) async {
    final now = DateTime.now();
    final messages = _messages(_visionProbePrompt);
    if (attachImage) {
      messages[messages.length - 1] = messages.last.copyWith(
        imageBase64: imageBase64,
        imageMimeType: _imageMimeType,
      );
    } else {
      // The control arm must ask the same question with no image, so a model
      // that guesses is measured on the guess.
      messages[messages.length - 1] = messages.last.copyWith(
        content:
            '$_visionProbePrompt\n'
            '(No image is attached in this control request. Answer with your '
            'best guess and no explanation.)',
        timestamp: now,
      );
    }

    try {
      final result = await _complete(
        messages: messages,
        maxTokens: _answerMaxTokens,
      );
      return _VisionArm(
        result: result,
        content: result.content.trim(),
        matchedColors: LiveLlmResponseScoring.matchedQuadrantColors(
          result.content,
          _visionProbeExpectedColors,
        ),
      );
    } catch (error) {
      return _VisionArm(
        rejected: attachImage,
        error: error.toString(),
        content: '',
        matchedColors: 0,
      );
    }
  }

  /// Reads quantitative detail off a chart, which is what a document with a
  /// figure in it actually asks of a model.
  ///
  /// Separate from the quadrant probe on purpose: four solid colors say the
  /// vision path is wired, not that the model can read a value off an axis.
  /// Whether a chart is legible decides whether rendering PDF pages is worth
  /// building at all, so it is measured rather than assumed.
  Future<LiveLlmDiagnosticProbeResult> chartReading() async {
    final withImage = await _chartArm(attachImage: true);
    final control = await _chartArm(attachImage: false);

    if (withImage.rejected) {
      return LiveLlmDiagnosticProbeResult(
        id: chartReadingProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected a request carrying image content.',
        details:
            'Classification: $_chartClassificationRejected\n${withImage.error}',
        modelContent: LiveLlmDiagnosticEvidence.preview(
          withImage.content,
          maxChars: 400,
        ),
      );
    }

    // An answer that never arrived is not a reading the model got wrong. A
    // reasoning model can spend the whole budget narrating the axis, and
    // scoring that as blindness would report the harness's limit as the
    // model's -- the same mistake the quadrant probe's image size once made.
    if (LiveLlmResponseScoring.visibleContent(withImage.content).isEmpty) {
      return LiveLlmDiagnosticProbeResult(
        id: chartReadingProbeId,
        status: LiveLlmDiagnosticStatus.warning,
        summary: 'The model did not finish reasoning within the token budget.',
        details:
            'Classification: $_chartClassificationNoAnswer\n'
            'Nothing was measured: the response carried reasoning and no '
            'readings. Raising the budget was tried on 2026-09-18 and changed '
            'nothing -- the reasoning grew to fill it. Read a repeat as the '
            'model failing to bound itself, not as a probe that needs room.',
        modelContent: LiveLlmDiagnosticEvidence.preview(
          withImage.content,
          maxChars: 400,
        ),
        usage: LiveLlmDiagnosticEvidence.totalUsage([
          if (withImage.result != null) withImage.result!,
        ]),
        totalChecks: LiveLlmChartProbeImage.expectedAnswers.length,
      );
    }

    final expected = LiveLlmChartProbeImage.expectedAnswers;
    final matched = withImage.matchedColors;
    final controlMatched = control.matchedColors;
    // Same rule the quadrant probe follows: a model that scores as well with
    // no chart in front of it did not read one. Chart questions are guessable
    // enough that this outranks the score.
    final guessed = controlMatched >= matched;
    final passed = !guessed && matched == expected.length;
    final status = passed
        ? LiveLlmDiagnosticStatus.passed
        : guessed
        ? LiveLlmDiagnosticStatus.failed
        : LiveLlmDiagnosticStatus.warning;

    return LiveLlmDiagnosticProbeResult(
      id: chartReadingProbeId,
      status: status,
      summary: passed
          ? 'The model read every value off the chart.'
          : guessed
          ? 'The no-image control arm scored the same, so the chart was not read.'
          : 'The model read the chart only partially.',
      details: [
        'Classification: ${passed
            ? _chartClassificationRead
            : guessed
            ? _chartClassificationGuessed
            : _chartClassificationPartial}',
        'Expected: ${expected.join(', ')}',
        'With chart: $matched/${expected.length}',
        'No-image control: $controlMatched/${expected.length}',
      ].join('\n'),
      modelContent: [
        // The visible answer, not the reasoning: a think block filled the
        // whole preview and left the actual reading invisible in the report.
        'with_chart: ${LiveLlmDiagnosticEvidence.preview(LiveLlmResponseScoring.visibleContent(withImage.content), maxChars: 240)}',
        'control: ${LiveLlmDiagnosticEvidence.preview(LiveLlmResponseScoring.visibleContent(control.content), maxChars: 240)}',
      ].join('\n'),
      usage: LiveLlmDiagnosticEvidence.totalUsage([
        if (withImage.result != null) withImage.result!,
        if (control.result != null) control.result!,
      ]),
      passedChecks: matched,
      totalChecks: expected.length,
    );
  }

  Future<_VisionArm> _chartArm({required bool attachImage}) async {
    final messages = _messages(_chartProbePrompt);
    messages[messages.length - 1] = attachImage
        ? messages.last.copyWith(
            imageBase64: LiveLlmChartProbeImage.base64,
            imageMimeType: LiveLlmChartProbeImage.mimeType,
          )
        : messages.last.copyWith(
            content:
                '$_chartProbePrompt\n'
                '(No image is attached in this control request. Answer with '
                'your best guess and no explanation.)',
          );

    try {
      final result = await _complete(
        messages: messages,
        maxTokens: _reasoningMaxTokens,
      );
      return _VisionArm(
        result: result,
        content: result.content.trim(),
        matchedColors: LiveLlmResponseScoring.matchedChartAnswers(
          result.content,
        ),
      );
    } catch (error) {
      return _VisionArm(
        rejected: attachImage,
        error: error.toString(),
        content: '',
        matchedColors: 0,
      );
    }
  }

  /// Reads the image through the computer-use path: a tool result whose JSON
  /// carries `imageBase64`, which the datasource lifts into its own observation
  /// message. Same picture, different message shape — an endpoint can support
  /// one and not the other.
  Future<LiveLlmDiagnosticProbeResult> toolObservation() async {
    final messages = _messages(
      'A screen observation tool returned an image. $_visionProbePrompt',
    );
    try {
      final result = await _completeWithToolResults(
        messages: messages,
        toolResults: [
          ToolResultInfo(
            id: 'diagnostic-vision-observe-call',
            name: 'diagnostic_vision_observe',
            arguments: const {'region': 'full'},
            result: jsonEncode({
              'ok': true,
              'coordinateSpace': 'screenshot_pixels',
              'imageMimeType': _imageMimeType,
              'imageBase64': imageBase64,
            }),
          ),
        ],
      );
      final matched = LiveLlmResponseScoring.matchedQuadrantColors(
        result.content,
        _visionProbeExpectedColors,
      );
      final passed = matched == _visionProbeExpectedColors.length;
      return LiveLlmDiagnosticProbeResult(
        id: toolObservationProbeId,
        status: passed
            ? LiveLlmDiagnosticStatus.passed
            : matched > 0
            ? LiveLlmDiagnosticStatus.warning
            : LiveLlmDiagnosticStatus.failed,
        summary: passed
            ? 'The model read the image delivered as a tool observation.'
            : 'The model did not read the tool-observation image correctly.',
        details:
            'Expected: ${_visionProbeExpectedColors.join(', ')}\n'
            'Matched in order: $matched/${_visionProbeExpectedColors.length}',
        modelContent: LiveLlmDiagnosticEvidence.preview(
          result.content,
          maxChars: 400,
        ),
        usage: LiveLlmDiagnosticEvidence.usage(result),
        passedChecks: matched,
        totalChecks: _visionProbeExpectedColors.length,
      );
    } catch (error) {
      return LiveLlmDiagnosticProbeResult(
        id: toolObservationProbeId,
        status: LiveLlmDiagnosticStatus.failed,
        summary: 'The endpoint rejected the tool-observation image request.',
        details: 'Classification: $_visionClassificationRejected\n$error',
      );
    }
  }
}

class _VisionArm {
  const _VisionArm({
    required this.content,
    required this.matchedColors,
    this.result,
    this.rejected = false,
    this.error = '',
  });

  final ChatCompletionResult? result;
  final String content;
  final int matchedColors;
  final bool rejected;
  final String error;
}

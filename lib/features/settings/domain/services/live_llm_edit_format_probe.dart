import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';
import 'live_llm_diagnostic_response_scoring.dart';

typedef EditFormatProbeCompletion =
    Future<ChatCompletionResult> Function({required List<Message> messages});

/// Measures exact edit-format fidelity. Selection, request settings, thinking,
/// exception handling, elapsed time and publication stay with the service.
class LiveLlmEditFormatProbe {
  const LiveLlmEditFormatProbe({
    required EditFormatProbeCompletion complete,
    required List<Message> Function(String user) messages,
  }) : _complete = complete,
       _messages = messages;

  static const probeId = 'edit_format_fidelity';
  static const preferenceMetadataKey = 'editFormatPreference';
  static const _editFormatPath = 'lib/greeting.dart';
  static const _editFormatOriginal = '''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Hello, \$trimmed!';
}''';
  static const _editFormatUpdated = '''String buildLabel(String name) {
  final trimmed = name.trim();
  return 'Welcome, \$trimmed!';
}''';
  static final _editFormatSearchReplace = [
    '<<<<<<< SEARCH',
    "  return 'Hello, \$trimmed!';",
    '=======',
    "  return 'Welcome, \$trimmed!';",
    '>>>>>>> REPLACE',
  ].join('\n');
  static const _editFormatUnifiedDiff = '''--- a/lib/greeting.dart
+++ b/lib/greeting.dart
@@ -1,4 +1,4 @@
 String buildLabel(String name) {
   final trimmed = name.trim();
-  return 'Hello, \$trimmed!';
+  return 'Welcome, \$trimmed!';
 }''';

  final EditFormatProbeCompletion _complete;
  final List<Message> Function(String user) _messages;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final cases = <_EditFormatProbeCase>[
      const _EditFormatProbeCase(
        preference: ModelEditFormatPreference.wholeFile,
        instruction:
            'Return the complete updated file contents with no markdown fence.',
        expected: _editFormatUpdated,
      ),
      _EditFormatProbeCase(
        preference: ModelEditFormatPreference.searchReplace,
        instruction:
            'Return one exact SEARCH/REPLACE block using the markers '
            '<<<<<<< SEARCH, =======, and >>>>>>> REPLACE. Include only the '
            'changed line in each side and no markdown fence.',
        expected: _editFormatSearchReplace,
      ),
      _EditFormatProbeCase(
        preference: ModelEditFormatPreference.unifiedDiff,
        instruction:
            'Return one syntactically valid unified diff that can be applied '
            'to lib/greeting.dart. Include every available unchanged line as '
            'context, and ensure each hunk header count matches the old and '
            'new lines in that hunk. Return no markdown fence or explanation.',
        expected: _editFormatUnifiedDiff,
        normalize: LiveLlmResponseScoring.normalizeUnifiedDiffFileHeaders,
      ),
    ];
    final outcomes = <_EditFormatProbeOutcome>[];
    for (final testCase in cases) {
      final result = await _complete(
        messages: _messages(
          'Update the greeting from Hello to Welcome without changing any '
          'other text. The current $_editFormatPath contents are:\n\n'
          '$_editFormatOriginal\n\n${testCase.instruction}',
        ),
      );
      final normalized = LiveLlmResponseScoring.stripSingleCodeFence(
        LiveLlmResponseScoring.visibleContent(result.content),
      );
      final mismatch = LiveLlmResponseScoring.firstEditFormatMismatch(
        expected: testCase.prepare(testCase.expected),
        actual: testCase.prepare(normalized),
      );
      // A cap the answer never got past reads as "received end of output",
      // which names the symptom and hides the cause.
      final failureDetail = mismatch == null || result.finishReason != 'length'
          ? mismatch
          : '$mismatch -- the response hit the token cap '
                '(finish_reason: length)';
      outcomes.add(
        _EditFormatProbeOutcome(
          preference: testCase.preference,
          passed: failureDetail == null,
          failureDetail: failureDetail,
          content: result.content,
          usage: LiveLlmDiagnosticEvidence.usage(result),
        ),
      );
    }

    final passed = outcomes.where((outcome) => outcome.passed).toList();
    final preference = _preferredEditFormat(passed);
    final status = passed.length == outcomes.length
        ? LiveLlmDiagnosticStatus.passed
        : passed.isNotEmpty
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: status,
      summary: preference == ModelEditFormatPreference.unknown
          ? 'The model did not reproduce any supported edit format exactly.'
          : 'The model reliably produced ${preference.name} edits.',
      details: outcomes
          .map(
            (outcome) => outcome.passed
                ? '${outcome.preference.name}: passed'
                : '${outcome.preference.name}: failed'
                      '${outcome.failureDetail == null ? '' : ' (${outcome.failureDetail})'}',
          )
          .join('\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.preference.name}: ${LiveLlmDiagnosticEvidence.preview(outcome.content, maxChars: 360)}',
          )
          .join('\n\n'),
      usage: LiveLlmDiagnosticEvidence.sumUsage(
        outcomes.map((outcome) => outcome.usage),
      ),
      passedChecks: passed.length,
      totalChecks: outcomes.length,
      metadata: {preferenceMetadataKey: preference.name},
    );
  }

  ModelEditFormatPreference _preferredEditFormat(
    List<_EditFormatProbeOutcome> passed,
  ) {
    for (final preference in const [
      ModelEditFormatPreference.unifiedDiff,
      ModelEditFormatPreference.searchReplace,
      ModelEditFormatPreference.wholeFile,
    ]) {
      if (passed.any((outcome) => outcome.preference == preference)) {
        return preference;
      }
    }
    return ModelEditFormatPreference.unknown;
  }
}

class _EditFormatProbeCase {
  const _EditFormatProbeCase({
    required this.preference,
    required this.instruction,
    required this.expected,
    this.normalize,
  });

  final ModelEditFormatPreference preference;
  final String instruction;
  final String expected;

  /// Applied to both sides before comparison, to drop spelling differences the
  /// format permits. Null compares the text verbatim.
  final String Function(String value)? normalize;

  String prepare(String value) => normalize?.call(value) ?? value;
}

class _EditFormatProbeOutcome {
  const _EditFormatProbeOutcome({
    required this.preference,
    required this.passed,
    required this.failureDetail,
    required this.content,
    required this.usage,
  });

  final ModelEditFormatPreference preference;
  final bool passed;
  final String? failureDetail;
  final String content;
  final LiveLlmDiagnosticTokenUsage usage;
}

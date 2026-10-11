import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_evidence.dart';

/// Runs the language matrix through a provider-owned completion boundary.
class LiveLlmFoundationModelsLanguageMatrixProbe {
  const LiveLlmFoundationModelsLanguageMatrixProbe({
    required Future<FoundationModelsLanguageProbeOutcome> Function(
      FoundationModelsLanguageProbeCase testCase,
    )
    complete,
  }) : _complete = complete;

  static const probeId = 'foundation_models_language_matrix';
  static const _foundationModelsEnglishMarker = 'CAVERNO_FM_LANG_EN';
  static const _foundationModelsJapaneseMarker = 'CAVERNO_FM_LANG_JA';
  static const _foundationModelsToolBridgeMarker = 'CAVERNO_FM_LANG_TOOL';
  final Future<FoundationModelsLanguageProbeOutcome> Function(
    FoundationModelsLanguageProbeCase testCase,
  )
  _complete;

  Future<LiveLlmDiagnosticProbeResult> run() async {
    final cases = [
      const FoundationModelsLanguageProbeCase(
        label: 'english_text',
        marker: _foundationModelsEnglishMarker,
        userPrompt:
            'Reply with exactly $_foundationModelsEnglishMarker and no extra text.',
      ),
      const FoundationModelsLanguageProbeCase(
        label: 'japanese_text',
        marker: _foundationModelsJapaneseMarker,
        userPrompt:
            '\u6b21\u306e\u6587\u5b57\u5217\u3060\u3051\u3092\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044: $_foundationModelsJapaneseMarker',
      ),
      FoundationModelsLanguageProbeCase(
        label: 'english_tool_bridge',
        marker: _foundationModelsToolBridgeMarker,
        userPrompt:
            'A diagnostic tool is listed, but do not call it. Reply with '
            'exactly $_foundationModelsToolBridgeMarker and no extra text.',
        withToolBridge: true,
      ),
    ];
    final outcomes = <FoundationModelsLanguageProbeOutcome>[];
    for (final testCase in cases) {
      outcomes.add(await _complete(testCase));
    }

    final failed = outcomes.where((outcome) => !outcome.passed).toList();
    final englishBaseline = outcomes.first;
    final status = failed.isEmpty
        ? LiveLlmDiagnosticStatus.passed
        : englishBaseline.passed
        ? LiveLlmDiagnosticStatus.warning
        : LiveLlmDiagnosticStatus.failed;
    final summary = failed.isEmpty
        ? 'Foundation Models accepted English, Japanese, and tool-bridge prompts.'
        : englishBaseline.passed
        ? 'English baseline passed, but at least one language matrix case was rejected.'
        : 'Foundation Models rejected the English baseline prompt.';

    return LiveLlmDiagnosticProbeResult(
      id: probeId,
      status: status,
      summary: summary,
      details: outcomes.map((outcome) => outcome.toDetailLine()).join('\n'),
      modelContent: outcomes
          .map(
            (outcome) =>
                '${outcome.label}: ${LiveLlmDiagnosticEvidence.preview(outcome.preview, maxChars: 240)}',
          )
          .join('\n'),
      passedChecks: outcomes.length - failed.length,
      totalChecks: outcomes.length,
    );
  }
}

class FoundationModelsLanguageProbeCase {
  const FoundationModelsLanguageProbeCase({
    required this.label,
    required this.marker,
    required this.userPrompt,
    this.withToolBridge = false,
  });

  final String label;
  final String marker;
  final String userPrompt;
  final bool withToolBridge;
}

class FoundationModelsLanguageProbeOutcome {
  const FoundationModelsLanguageProbeOutcome({
    required this.label,
    required this.passed,
    required this.classification,
    required this.preview,
  });

  final String label;
  final bool passed;
  final String classification;
  final String preview;

  String toDetailLine() {
    return '$label: ${passed ? 'passed' : 'failed'} ($classification)';
  }
}

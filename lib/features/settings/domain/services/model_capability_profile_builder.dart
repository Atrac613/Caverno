import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'llm_sampler_calibration_service.dart';
import 'llm_sampler_preset_profile.dart';

class ModelCapabilityProfileBuilder {
  const ModelCapabilityProfileBuilder._();

  static ModelCapabilityProfile fromLiveDiagnosticReport({
    required LiveLlmDiagnosticReport report,
    required LlmProvider provider,
    Iterable<LlmSamplerCalibrationTrial> samplerTrials = const [],
  }) {
    final effectiveSamplerTrials = [
      ...report.samplerCalibrationTrials
          .map(_samplerTrialFromDiagnostic)
          .whereType<LlmSamplerCalibrationTrial>(),
      ...samplerTrials,
    ];
    final metadata = <String, String>{
      'overallStatus': report.overallStatus.name,
      'score': report.score.toStringAsFixed(3),
      'passedProbeCount': report.passedProbeCount.toString(),
      'scoredProbeCount': report.scoredProbeCount.toString(),
      'totalToolCount': report.toolCatalog.totalToolCount.toString(),
      'toolSearchEnabled': report.toolCatalog.toolSearchEnabled.toString(),
      for (final result in report.results)
        'probe.${result.id}.status': result.status.name,
    };
    final profile = ModelCapabilityProfile(
      id: '',
      provider: provider,
      baseUrl: report.baseUrl,
      model: report.model,
      toolCallStyle: _toolCallStyle(report, provider),
      structuredOutputSupport: _structuredOutputSupport(report),
      editFormatPreference: ModelEditFormatPreference.unknown,
      usableContextTokens: 0,
      probedAt: report.finishedAt ?? report.startedAt,
      probeSummary:
          '${report.overallStatus.label}: '
          '${report.passedProbeCount}/${report.scoredProbeCount} probes passed.',
      probeMetadata: metadata,
    );
    return _applySamplerCalibration(
      profile.normalizedForPersistence(),
      effectiveSamplerTrials,
    );
  }

  static ModelCapabilityProfile _applySamplerCalibration(
    ModelCapabilityProfile profile,
    Iterable<LlmSamplerCalibrationTrial> samplerTrials,
  ) {
    final trials = samplerTrials.toList(growable: false);
    if (trials.isEmpty) {
      return profile;
    }
    const calibrationService = LlmSamplerCalibrationService();
    var updatedProfile = profile;
    for (final requestClass in LlmSamplerRequestClass.values) {
      final selection = calibrationService.selectTemperature(
        requestClass: requestClass,
        trials: trials,
      );
      if (selection == null) {
        continue;
      }
      updatedProfile = calibrationService.applySelectionToProfile(
        profile: updatedProfile,
        selection: selection,
      );
    }
    return updatedProfile;
  }

  static LlmSamplerCalibrationTrial? _samplerTrialFromDiagnostic(
    LiveLlmDiagnosticSamplerTrial trial,
  ) {
    final requestClass = _samplerRequestClassByMetadataName(trial.requestClass);
    if (requestClass == null) {
      return null;
    }
    return LlmSamplerCalibrationTrial(
      requestClass: requestClass,
      temperature: trial.temperature,
      passed: trial.passed,
      jsonRepairEventCount: trial.jsonRepairEventCount,
      malformedToolCallCount: trial.malformedToolCallCount,
      editApplyFailureCount: trial.editApplyFailureCount,
      repetitionDetected: trial.repetitionDetected,
    );
  }

  static LlmSamplerRequestClass? _samplerRequestClassByMetadataName(
    String value,
  ) {
    final normalized = value.trim();
    for (final requestClass in LlmSamplerRequestClass.values) {
      if (requestClass.metadataName == normalized ||
          requestClass.name == normalized) {
        return requestClass;
      }
    }
    return null;
  }

  static ModelToolCallStyle _toolCallStyle(
    LiveLlmDiagnosticReport report,
    LlmProvider provider,
  ) {
    final narrowToolCall = _result(report, 'narrow_tool_call');
    if (narrowToolCall == null ||
        narrowToolCall.status == LiveLlmDiagnosticStatus.skipped) {
      return ModelToolCallStyle.unknown;
    }
    if (narrowToolCall.status == LiveLlmDiagnosticStatus.passed) {
      return provider == LlmProvider.appleFoundationModels
          ? ModelToolCallStyle.embeddedToolTags
          : ModelToolCallStyle.nativeToolCalls;
    }
    if (narrowToolCall.status == LiveLlmDiagnosticStatus.failed) {
      return ModelToolCallStyle.none;
    }
    return ModelToolCallStyle.unknown;
  }

  static ModelStructuredOutputSupport _structuredOutputSupport(
    LiveLlmDiagnosticReport report,
  ) {
    final instruction = _result(report, 'instruction_echo');
    if (instruction == null ||
        instruction.status == LiveLlmDiagnosticStatus.skipped) {
      return ModelStructuredOutputSupport.unknown;
    }
    if (instruction.status == LiveLlmDiagnosticStatus.passed) {
      return ModelStructuredOutputSupport.jsonObject;
    }
    if (instruction.status == LiveLlmDiagnosticStatus.failed) {
      return ModelStructuredOutputSupport.none;
    }
    return ModelStructuredOutputSupport.unknown;
  }

  static LiveLlmDiagnosticProbeResult? _result(
    LiveLlmDiagnosticReport report,
    String id,
  ) {
    for (final result in report.results) {
      if (result.id == id) {
        return result;
      }
    }
    return null;
  }
}

import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';
import 'live_llm_diagnostic_scoring.dart';
import 'llm_sampler_calibration_service.dart';
import 'llm_sampler_preset_profile.dart';

class ModelCapabilityProfileBuilder {
  const ModelCapabilityProfileBuilder._();

  /// [usableContextTokens] is the endpoint-reported context window for the
  /// probed model (llama.cpp `n_ctx`, LM Studio loaded context, Ollama
  /// `num_ctx`, OpenAI `context_length`). Zero means the endpoint advertised
  /// none; consumers must treat it as unmeasured rather than assume a default.
  static ModelCapabilityProfile fromLiveDiagnosticReport({
    required LiveLlmDiagnosticReport report,
    required LlmProvider provider,
    int usableContextTokens = 0,
    Iterable<LlmSamplerCalibrationTrial> samplerTrials = const [],
  }) {
    final effectiveSamplerTrials = [
      ...report.samplerCalibrationTrials
          .map(_samplerTrialFromDiagnostic)
          .whereType<LlmSamplerCalibrationTrial>(),
      ...samplerTrials,
    ];
    final score = LiveLlmDiagnosticScore.fromReport(report);
    final metadata = <String, String>{
      'overallStatus': report.overallStatus.name,
      'score': report.score.toStringAsFixed(3),
      // LL39 absolute score. Recorded alongside the legacy ratio so a stored
      // revision can be compared across models; the suite version is part of
      // the record because two versions must never be diffed.
      'benchmarkSuite':
          '${LiveLlmDiagnosticSuite.id}-v${LiveLlmDiagnosticSuite.version}',
      'benchmarkPoints': score.earnedPoints.toString(),
      'benchmarkMaxPoints': score.maxPoints.toString(),
      'benchmarkAttemptedPoints': score.attemptedPoints.toString(),
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
      goalUpdateFidelity: _goalUpdateFidelity(report),
      editFormatPreference: ModelEditFormatPreference.unknown,
      visionSupport: _visionSupport(report),
      usableContextTokens: usableContextTokens,
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

  static ModelGoalUpdateFidelity _goalUpdateFidelity(
    LiveLlmDiagnosticReport report,
  ) {
    final result = _result(report, 'update_goal_fidelity');
    return switch (result?.status) {
      LiveLlmDiagnosticStatus.passed => ModelGoalUpdateFidelity.reliable,
      LiveLlmDiagnosticStatus.failed => ModelGoalUpdateFidelity.unreliable,
      _ => ModelGoalUpdateFidelity.unknown,
    };
  }

  /// LL39 vision axis, derived from the two production message shapes.
  ///
  /// The attachment probe is the gate: it carries the no-image control arm, so
  /// it is the only one that can tell "read the image" from "guessed well". The
  /// observation probe then decides whether the model also handles the
  /// computer-use shape.
  static ModelVisionSupport _visionSupport(LiveLlmDiagnosticReport report) {
    final attachment = _result(report, 'vision_attachment');
    if (attachment == null ||
        attachment.status == LiveLlmDiagnosticStatus.skipped) {
      return ModelVisionSupport.unknown;
    }
    if (attachment.status == LiveLlmDiagnosticStatus.failed) {
      if (attachment.details.contains('endpoint_rejected')) {
        return ModelVisionSupport.rejected;
      }
      return ModelVisionSupport.ignored;
    }

    final observation = _result(report, 'vision_tool_observation');
    final observationPassed =
        observation?.status == LiveLlmDiagnosticStatus.passed;
    if (attachment.status == LiveLlmDiagnosticStatus.passed &&
        observationPassed) {
      return ModelVisionSupport.reliable;
    }
    return ModelVisionSupport.basic;
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

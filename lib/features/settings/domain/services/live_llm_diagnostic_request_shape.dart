import '../../../chat/domain/services/qwen38_request_thinking_policy.dart';
import '../entities/app_settings.dart';
import '../entities/live_llm_diagnostic.dart';

export '../entities/live_llm_diagnostic.dart'
    show LiveLlmDiagnosticThinkingMode;

/// The reasoning controls a diagnostic run sends, fixed rather than read from
/// the chat composer.
///
/// The diagnostic used to share the chat datasource, so whatever thinking and
/// effort the person last picked for chat decided what the probes measured.
/// On 2026-09-23 the same qwen3.8-27b-exl3 scored 980/980 with thinking on and
/// 952 with it off, losing the unified-diff and chart probes deterministically
/// -- and the capability profile then recommended a different edit format
/// depending on which mode happened to run last. A measurement has to hold its
/// own conditions still.
///
/// Only the reasoning controls are pinned. Endpoint, model and key still come
/// from the chat settings, because which model to measure is the one thing the
/// diagnostic must agree with chat on.
abstract final class LiveLlmDiagnosticRequestShape {
  static const defaultMode = LiveLlmDiagnosticThinkingMode.on;

  /// Whether a request to this endpoint and model can carry `enable_thinking`.
  ///
  /// Qwen3.8 builds always accept it; any other model only behind an endpoint
  /// the person opted into `chat_template_kwargs`, because a hosted endpoint
  /// that has never heard of the field may reject the request. When this is
  /// false both modes leave thinking to the server, so there is only one mode
  /// to measure.
  static bool canControlThinking(AppSettings settings) =>
      Qwen38RequestThinkingPolicy.isQwen38Model(settings.effectiveModel) ||
      settings.acceptsChatTemplateKwargsFor(settings.baseUrl);

  /// The effort a run in [mode] sends when the person has not picked one.
  ///
  /// Qwen3.8 thinking runs at medium effort, which is also what raises the
  /// policy's token floor to [Qwen38RequestThinkingPolicy.mediumMinimumMaxTokens]
  /// so a 512-token probe is not cut off inside its own reasoning. Every other
  /// case sends no effort at all, so a hosted model is measured at its default
  /// rather than at whatever the chat composer last asked for.
  static ReasoningEffortPreference defaultEffortFor(
    AppSettings settings,
    LiveLlmDiagnosticThinkingMode mode,
  ) {
    final qwen38 = Qwen38RequestThinkingPolicy.isQwen38Model(
      settings.effectiveModel,
    );
    return canControlThinking(settings) &&
            mode == LiveLlmDiagnosticThinkingMode.on &&
            qwen38
        ? ReasoningEffortPreference.medium
        : ReasoningEffortPreference.automatic;
  }

  /// [settings] with the chat reasoning controls replaced by [mode]'s.
  ///
  /// [effort] is the person's explicit pick on the diagnostic page; null
  /// falls back to [defaultEffortFor]. Either way the chat composer's effort
  /// never reaches the run. An explicit effort is still subject to the request
  /// policy, which drops it on Qwen3.8 when thinking is off.
  static AppSettings settingsFor(
    AppSettings settings,
    LiveLlmDiagnosticThinkingMode mode, {
    ReasoningEffortPreference? effort,
  }) {
    final controllable = canControlThinking(settings);
    return settings.copyWith(
      reasoningEffort: effort ?? defaultEffortFor(settings, mode),
      enableThinking: controllable
          ? mode == LiveLlmDiagnosticThinkingMode.on
          : null,
    );
  }
}

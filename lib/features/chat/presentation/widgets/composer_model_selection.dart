import 'dart:async';

import '../../../settings/domain/entities/app_settings.dart';

typedef ComposerModelListLoader = Future<List<String>> Function();
typedef ComposerModelSelectionChanged =
    FutureOr<void> Function(ComposerModelSelection selection);

/// The model-related values shown by the composer chip.
///
/// A normal chat composer reads these values from local settings. Remote Coding
/// supplies the desktop's values instead, while keeping the same menu and
/// visual control on the phone.
class ComposerModelSelection {
  const ComposerModelSelection({
    required this.model,
    required this.reasoningEffort,
    required this.enableThinking,
    this.supportedReasoningEfforts,
  });

  /// The local composer's values.
  factory ComposerModelSelection.fromSettings(AppSettings settings) =>
      ComposerModelSelection(
        model: settings.effectiveModel,
        reasoningEffort: settings.reasoningEffort,
        enableThinking: settings.enableThinking,
        supportedReasoningEfforts:
            settings.effectiveModelCapabilityProfile?.supportedReasoningEfforts,
      );

  final String model;
  final ReasoningEffortPreference reasoningEffort;
  final bool? enableThinking;

  /// The efforts [model]'s endpoint accepted when probed, or null when that is
  /// unknown. Remote Coding leaves it null: the desktop's endpoint is not one
  /// this device has probed.
  final List<String>? supportedReasoningEfforts;

  /// The efforts the menu offers: every one while support is unknown,
  /// otherwise the accepted ones plus automatic, plus the current choice so a
  /// setting made before the probe stays visible rather than vanishing.
  List<ReasoningEffortPreference> get reasoningEffortChoices {
    final supported = supportedReasoningEfforts;
    if (supported == null) return ReasoningEffortPreference.values;
    return [
      for (final effort in ReasoningEffortPreference.values)
        if (effort.apiValue == null ||
            supported.contains(effort.apiValue) ||
            effort == reasoningEffort)
          effort,
    ];
  }

  ComposerModelSelection copyWith({
    String? model,
    ReasoningEffortPreference? reasoningEffort,
    bool? enableThinking,
    bool clearEnableThinking = false,
  }) {
    return ComposerModelSelection(
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      enableThinking: clearEnableThinking
          ? null
          : enableThinking ?? this.enableThinking,
      // Measured for one model; another model's support is unknown until the
      // settings it is read from catch up.
      supportedReasoningEfforts: model == null || model == this.model
          ? supportedReasoningEfforts
          : null,
    );
  }
}

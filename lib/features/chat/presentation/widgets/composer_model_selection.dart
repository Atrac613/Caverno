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
  });

  /// The local composer's values.
  factory ComposerModelSelection.fromSettings(AppSettings settings) =>
      ComposerModelSelection(
        model: settings.effectiveModel,
        reasoningEffort: settings.reasoningEffort,
        enableThinking: settings.enableThinking,
      );

  final String model;
  final ReasoningEffortPreference reasoningEffort;
  final bool? enableThinking;

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
    );
  }
}

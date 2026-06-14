import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import 'model_edit_apply_telemetry_service.dart';

class WeakModelEditHarnessService {
  WeakModelEditHarnessService._();

  static String buildPromptContext({
    required ModelCapabilityProfile? profile,
    required Iterable<String> toolNames,
    required AssistantMode assistantMode,
  }) {
    if (!shouldInject(
      profile: profile,
      toolNames: toolNames,
      assistantMode: assistantMode,
    )) {
      return '';
    }

    final hasWriteFileTool = _hasWriteFileTool(toolNames);
    final lines = [
      'LL15 WEAK-MODEL EDIT HARNESS:',
      'When editing existing files, use edit_file with one valid JSON tool call.',
      'Required edit_file arguments: path, old_text, new_text. Optional arguments: replace_all, reason.',
      'Use JSON with double-quoted keys and strings, no comments, and no trailing commas.',
      'Set old_text to exact current text copied from the latest read_file or inspect_file result; include enough surrounding context to match one location.',
      'Set replace_all=false unless every occurrence should change.',
      'After edit_file or write_file succeeds, read_file the edited path and verify the exact changed text before running tests or claiming completion.',
      'If old_text was not found, is stale, or matches multiple locations, read the current file again and retry once with exact current content; do not guess.',
      'Example edit_file arguments: {"path":"lib/example.dart","old_text":"final enabled = false;","new_text":"final enabled = true;","replace_all":false,"reason":"Enable the feature flag."}',
    ];
    if (hasWriteFileTool) {
      lines.add(
        'If a retry still cannot target a small fixture file safely, use write_file with the complete current file content plus the minimal intended change; do not use write_file for large or uninspected files.',
      );
    }
    final failureRateLine =
        ModelEditApplyTelemetryService.promptFailureRateLine(profile);
    if (failureRateLine != null) {
      lines.add(failureRateLine);
    }
    return lines.join('\n');
  }

  static bool shouldInject({
    required ModelCapabilityProfile? profile,
    required Iterable<String> toolNames,
    required AssistantMode assistantMode,
  }) {
    if (!_isCodingAssistantMode(assistantMode)) {
      return false;
    }
    if (!_hasEditFileTool(toolNames)) {
      return false;
    }
    return _isWeakOrUncertainProfile(profile);
  }

  static bool _isCodingAssistantMode(AssistantMode assistantMode) {
    return assistantMode == AssistantMode.coding ||
        assistantMode == AssistantMode.plan;
  }

  static bool _hasEditFileTool(Iterable<String> toolNames) {
    return toolNames.any((name) => name.trim() == 'edit_file');
  }

  static bool _hasWriteFileTool(Iterable<String> toolNames) {
    return toolNames.any((name) => name.trim() == 'write_file');
  }

  static bool _isWeakOrUncertainProfile(ModelCapabilityProfile? profile) {
    if (profile == null) {
      return true;
    }
    if (_isStrongStructuredProfile(profile)) {
      return false;
    }
    return profile.toolCallStyle == ModelToolCallStyle.unknown ||
        profile.toolCallStyle == ModelToolCallStyle.embeddedToolTags ||
        profile.toolCallStyle == ModelToolCallStyle.none ||
        profile.structuredOutputSupport ==
            ModelStructuredOutputSupport.unknown ||
        profile.structuredOutputSupport == ModelStructuredOutputSupport.none ||
        profile.editFormatPreference == ModelEditFormatPreference.unknown ||
        profile.editFormatPreference == ModelEditFormatPreference.searchReplace;
  }

  static bool _isStrongStructuredProfile(ModelCapabilityProfile profile) {
    return profile.toolCallStyle == ModelToolCallStyle.nativeToolCalls &&
        (profile.structuredOutputSupport ==
                ModelStructuredOutputSupport.jsonSchema ||
            profile.structuredOutputSupport ==
                ModelStructuredOutputSupport.jsonObject);
  }
}

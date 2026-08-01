import 'ask_user_question_policy.dart';

// ChatNotifier decomposition collaborator: ask-user-question-option-parser

/// Turns the `options` a model wrote into domain options.
///
/// The model supplies them as loose JSON — bare strings, or maps that may omit
/// an id, carry an unusable one, or repeat a label — so this normalizes rather
/// than validates: anything unusable is dropped and everything kept is given a
/// unique id and a bounded length. A duplicate id would make two rows resolve
/// to the same answer, and an unbounded description would push the sheet off
/// screen.
final class AskUserQuestionOptionParser {
  const AskUserQuestionOptionParser();

  /// The largest number of options a question may present.
  static const int maxOptions = 8;

  static const int _maxLabelLength = 120;
  static const int _maxDescriptionLength = 500;
  static const int _maxPreviewLength = 2000;

  List<AskUserQuestionOption> parse(dynamic rawOptions) {
    if (rawOptions is! List) {
      return const [];
    }

    final options = <AskUserQuestionOption>[];
    final usedIds = <String>{};
    for (
      var index = 0;
      index < rawOptions.length && options.length < maxOptions;
      index++
    ) {
      final rawOption = rawOptions[index];
      String label;
      String id;
      String description = '';
      String preview = '';

      if (rawOption is String) {
        label = rawOption.trim();
        id = optionId(label, index);
      } else if (rawOption is Map) {
        label = (rawOption['label'] as String?)?.trim() ?? '';
        id = (rawOption['id'] as String?)?.trim().isNotEmpty == true
            ? (rawOption['id'] as String).trim()
            : optionId(label, index);
        description = (rawOption['description'] as String?)?.trim() ?? '';
        preview = (rawOption['preview'] as String?)?.trim() ?? '';
      } else {
        continue;
      }

      if (label.isEmpty) {
        continue;
      }
      var uniqueId = id;
      var suffix = 2;
      while (!usedIds.add(uniqueId)) {
        uniqueId = '$id-$suffix';
        suffix++;
      }
      options.add(
        AskUserQuestionOption(
          id: uniqueId,
          label: clip(label, _maxLabelLength),
          description: clip(description, _maxDescriptionLength),
          preview: clip(preview, _maxPreviewLength),
        ),
      );
    }
    return options;
  }

  /// A slug derived from [label], falling back to the 1-based position when
  /// the label carries nothing sluggable.
  String optionId(String label, int index) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isNotEmpty) {
      return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
    }
    return 'option-${index + 1}';
  }

  String clip(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}

/// Parsing holds no state, so callers share one instance.
const askUserQuestionOptionParser = AskUserQuestionOptionParser();

import '../../../../core/utils/attachment_format.dart';
import 'composer_file_picker.dart';

/// The visible transcript and model-only context for one composer submission.
class ComposerFileSubmission {
  const ComposerFileSubmission({
    required this.visibleContent,
    this.modelContent,
  });

  final String visibleContent;
  final String? modelContent;

  static ComposerFileSubmission compose({
    required ComposerFileAttachment? file,
    required String userText,
  }) {
    if (file == null) return ComposerFileSubmission(visibleContent: userText);
    final human = formatAttachmentSize(file.sizeBytes);
    final displayBlock = file.isPdf || file.pdfPageCount != null
        ? '[File: ${file.name} (PDF'
              '${file.pdfPageCount == null ? '' : ', ${file.pdfPageCount} pages'}, '
              '$human)]'
        : '[File: ${file.name} ($human)]';
    final modelBlock = ComposerFilePicker.composeMessageBlock(file);
    return ComposerFileSubmission(
      visibleContent: _joinVisible(displayBlock, userText),
      modelContent: _joinForModel(modelBlock, userText),
    );
  }

  /// The person's own words lead the bubble, and the attachment follows as the
  /// note it is. The conversation title is taken from the first user message's
  /// visible content, so a header in front named every thread after its file
  /// instead of after the question that was asked.
  static String _joinVisible(String block, String userText) =>
      userText.isEmpty ? block : '$userText\n\n$block';

  /// The model keeps document-then-question: the request reads better with the
  /// material first and the instruction last.
  static String _joinForModel(String block, String userText) =>
      userText.isEmpty ? block : '$block\n\n$userText';
}

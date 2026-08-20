import 'package:caverno_content_protocol/caverno_content_protocol.dart';

/// What one stream segment added to the visible answer.
///
/// Strips first and slices second. The other order cut a `<think>` open tag off
/// whenever the offset landed inside one -- it is a raw character index taken
/// from whichever message was last when streaming began -- and left reasoning
/// that no parser can recognise as reasoning. Session ae491799 handed exactly
/// that to the unexecuted-command guard, which read "released" out of the
/// model's private deliberation about a product release and spent three calls
/// and ninety seconds demanding the command run.
///
/// Reasoning is excluded on purpose: this feeds checks that ask what the reader
/// was told, and deliberation is not an assertion to anyone.
final class AssistantStreamDelta {
  const AssistantStreamDelta();

  String since({required String content, required int startingLength}) {
    if (startingLength >= content.length) return '';
    final visible = ContentParser.stripModelHistoryArtifacts(content);
    final before = ContentParser.stripModelHistoryArtifacts(
      content.substring(0, startingLength.clamp(0, content.length).toInt()),
    );
    return visible.startsWith(before)
        ? visible.substring(before.length).trim()
        : visible.trim();
  }
}

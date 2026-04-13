import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/voice_providers.dart';
import '../../../../core/utils/content_parser.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/message.dart';
import 'parsed_content_view.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onReselectProject,
  });

  final Message message;
  final VoidCallback? onReselectProject;

  /// Extracts text for TTS playback by removing tags such as `<think>`.
  String _extractReadableText(String content) {
    final result = ContentParser.parse(content);
    final buffer = StringBuffer();

    for (final segment in result.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
      // Skip thinking and tool-call segments for TTS.
    }

    return buffer.toString().trim();
  }

  _ProjectAccessIssue? _extractProjectAccessIssue(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('{') && line.endsWith('}'));

    for (final line in lines.toList().reversed) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final code = decoded['code'] as String?;
        if (code != 'permission_denied' && code != 'bookmark_restore_failed') {
          continue;
        }

        return _ProjectAccessIssue(
          code: code!,
          path: decoded['path'] as String?,
        );
      } catch (_) {
        // Ignore non-JSON lines.
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final tts = ref.read(ttsServiceProvider);
    final projectAccessIssue = !isUser
        ? _extractProjectAccessIssue(message.content)
        : null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'message.error'.tr(),
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      message.error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            // Image preview
            if (message.imageBase64 != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(message.imageBase64!),
                    fit: BoxFit.cover,
                    width: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 200,
                        height: 100,
                        color: theme.colorScheme.errorContainer,
                        child: Center(
                          child: Icon(
                            Icons.broken_image,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            // Render text when available.
            if (message.content.isNotEmpty || message.isStreaming)
              isUser
                  ? _UserMessageContent(
                      content: message.content.isEmpty && message.isStreaming
                          ? '...'
                          : message.content,
                      textColor: theme.colorScheme.onPrimary,
                    )
                  : ParsedContentView(
                      content: message.content.isEmpty && message.isStreaming
                          ? '...'
                          : message.content,
                      textColor: theme.colorScheme.onSurface,
                      isStreaming: message.isStreaming,
                    ),
            // Streaming indicator
            if (message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            // TTS button for completed assistant messages when TTS is enabled.
            if (!isUser &&
                settings.ttsEnabled &&
                !message.isStreaming &&
                message.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        if (tts.isSpeaking) {
                          tts.stop();
                        } else {
                          final readableText = _extractReadableText(
                            message.content,
                          );
                          if (readableText.isNotEmpty) {
                            tts.setSpeechRate(settings.speechRate);
                            tts.speak(readableText);
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tts.isSpeaking ? Icons.stop : Icons.volume_up,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tts.isSpeaking
                                  ? 'message.tts_stop'.tr()
                                  : 'message.tts_play'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isUser &&
                projectAccessIssue != null &&
                onReselectProject != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ProjectAccessErrorCard(
                  issue: projectAccessIssue,
                  onReselectProject: onReselectProject!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectAccessIssue {
  const _ProjectAccessIssue({required this.code, this.path});

  final String code;
  final String? path;
}

class _ProjectAccessErrorCard extends StatelessWidget {
  const _ProjectAccessErrorCard({
    required this.issue,
    required this.onReselectProject,
  });

  final _ProjectAccessIssue issue;
  final VoidCallback onReselectProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBookmarkRestoreFailure = issue.code == 'bookmark_restore_failed';
    final titleKey = isBookmarkRestoreFailure
        ? 'message.project_access_restore_failed'
        : 'message.project_access_permission_denied';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titleKey.tr(),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'message.project_access_reselect_help'.tr(),
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (issue.path != null && issue.path!.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              issue.path!,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onReselectProject,
            icon: const Icon(Icons.folder_open),
            label: Text('message.project_access_reselect'.tr()),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Regex that matches a `[File: name]` header followed by its content block.
final _fileBlockPattern = RegExp(r'^\[File: (.+?)\]\n([\s\S]*?)(?:\n\n|$)');

/// Renders user message content, collapsing embedded file blocks.
class _UserMessageContent extends StatefulWidget {
  const _UserMessageContent({required this.content, required this.textColor});

  final String content;
  final Color textColor;

  @override
  State<_UserMessageContent> createState() => _UserMessageContentState();
}

class _UserMessageContentState extends State<_UserMessageContent> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final match = _fileBlockPattern.firstMatch(widget.content);
    if (match == null) {
      return SelectableText(
        widget.content,
        style: TextStyle(color: widget.textColor),
      );
    }

    final fileName = match.group(1)!;
    final fileContent = match.group(2)!;
    final userText = widget.content.substring(match.end).trim();
    final lineCount = '\n'.allMatches(fileContent).length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible file block
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description,
                  size: 16,
                  color: widget.textColor.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$fileName ($lineCount lines)',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: widget.textColor.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  fileContent,
                  style: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        // User's own message text
        if (userText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
              userText,
              style: TextStyle(color: widget.textColor),
            ),
          ),
      ],
    );
  }
}

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
  const MessageBubble({super.key, required this.message});

  final Message message;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final tts = ref.read(ttsServiceProvider);

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
                  ? SelectableText(
                      message.content.isEmpty && message.isStreaming
                          ? '...'
                          : message.content,
                      style: TextStyle(color: theme.colorScheme.onPrimary),
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
          ],
        ),
      ),
    );
  }
}

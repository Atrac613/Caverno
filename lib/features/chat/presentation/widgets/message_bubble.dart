import 'anabasis_speaker_header.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/tts_service.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/utils/attachment_format.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../../settings/presentation/pages/chat_settings_page.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/turn_diff.dart';
import '../providers/coding_projects_notifier.dart';
import 'file_workspace_viewer_sheet.dart';
import 'message_image_io.dart';
import 'message_attachment_io.dart';
import 'message_image_viewer.dart';
import 'message_video_poster.dart';
import 'message_video_viewer.dart';
import 'parsed_content_view.dart';
import '../../../../core/theme/app_tokens.dart';

const double _messageImagePreviewWidth = 200;
const double _messageImagePreviewHeight = 140;

class MessageBubble extends ConsumerStatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onReselectProject,
    this.onRewindToHere,
    this.turnDiff,
    this.onOpenTurnDiff,
    this.onOpenFileWorkspaceViewer,
    this.canRewind = false,
  });

  final Message message;
  final VoidCallback? onReselectProject;
  final VoidCallback? onRewindToHere;
  final TurnDiff? turnDiff;
  final VoidCallback? onOpenTurnDiff;
  final ValueChanged<FileWorkspaceViewerRequest>? onOpenFileWorkspaceViewer;
  final bool canRewind;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _isHovering = false;
  bool _isActionRowPinned = false;
  bool _suppressActionRowToggle = false;
  bool _copied = false;
  int _copyFeedbackToken = 0;
  String? _cachedImageBase64;
  Uint8List? _cachedImageBytes;

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

  String _formatTimestamp(BuildContext context) {
    final locale = context.locale.toLanguageTag();
    return DateFormat.jm(locale).format(widget.message.timestamp.toLocal());
  }

  Future<void> _copyMessageContent() async {
    final content = widget.message.content.trim();
    if (content.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!mounted) {
      return;
    }

    final token = ++_copyFeedbackToken;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || token != _copyFeedbackToken) {
      return;
    }
    setState(() => _copied = false);
  }

  void _handleBubblePointerUp(PointerUpEvent event) {
    if (_suppressActionRowToggle) {
      _suppressActionRowToggle = false;
      return;
    }
    if (event.kind == PointerDeviceKind.mouse) {
      return;
    }
    setState(() => _isActionRowPinned = !_isActionRowPinned);
  }

  void _openImageViewer(Uint8List bytes) {
    final message = widget.message;
    showMessageImageViewer(
      context: context,
      previewBytes: bytes,
      previewMimeType: message.imageMimeType,
      originalImagePath: message.originalImagePath,
      originalMimeType: message.originalImageMimeType,
      suggestedFileName: suggestedMessageImageFileName(
        originalImagePath: message.originalImagePath,
        mimeType: message.originalImageMimeType ?? message.imageMimeType,
      ),
    );
  }

  Uint8List? _imageBytesFor(String? imageBase64) {
    if (imageBase64 == null || imageBase64.isEmpty) {
      _cachedImageBase64 = null;
      _cachedImageBytes = null;
      return null;
    }
    // Reuse the cached result for an unchanged input, including a cached decode
    // failure (null bytes), so malformed base64 is not re-decoded on every
    // rebuild while the message streams.
    if (_cachedImageBase64 == imageBase64) {
      return _cachedImageBytes;
    }

    _cachedImageBase64 = imageBase64;
    try {
      _cachedImageBytes = base64Decode(imageBase64);
    } catch (_) {
      _cachedImageBytes = null;
    }
    return _cachedImageBytes;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final selectedProject = ref.watch(
      codingProjectsNotifierProvider.select((state) => state.selectedProject),
    );
    final tts = ref.read(ttsServiceProvider);
    final projectAccessIssue = !isUser
        ? _extractProjectAccessIssue(message.content)
        : null;
    final hasBodyContent = message.content.isNotEmpty || message.isStreaming;
    final responseMetrics = !isUser && !message.isStreaming
        ? message.responseMetrics
        : null;
    final participantToolNames = !isUser && !message.isStreaming
        ? _visibleParticipantToolNames(message.participantToolNames)
        : const <String>[];
    final handoffTargetLabel = !isUser && !message.isStreaming
        ? _handoffTargetLabel(message)
        : null;
    final imageBytes = _imageBytesFor(message.imageBase64);
    final hasParticipantHeader = !isUser && message.participantId != null;
    final hasAnabasisHeader =
        !isUser && !hasParticipantHeader && message.isAnabasisParent;
    final showActionRow = _isHovering || _isActionRowPinned;
    final viewportWidth = MediaQuery.of(context).size.width;
    final assistantHorizontalMargin = viewportWidth >= 840 ? 56.0 : 20.0;
    final bubble = Container(
      width: isUser ? null : double.infinity,
      constraints: isUser
          ? BoxConstraints(maxWidth: viewportWidth * 0.8)
          : const BoxConstraints(),
      margin: EdgeInsets.symmetric(
        vertical: isUser ? 4 : 12,
        horizontal: isUser ? 8 : assistantHorizontalMargin,
      ),
      padding: EdgeInsets.symmetric(
        vertical: isUser ? 10 : 6,
        horizontal: isUser ? 14 : 0,
      ),
      decoration: isUser
          ? BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(
                16,
              ).copyWith(bottomRight: const Radius.circular(4)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAnabasisHeader)
            Padding(
              padding: EdgeInsets.only(bottom: hasBodyContent ? 8 : 0),
              child: const AnabasisSpeakerHeader(),
            ),
          if (hasParticipantHeader)
            Padding(
              padding: EdgeInsets.only(bottom: hasBodyContent ? 8 : 0),
              child: _ParticipantSpeakerHeader(message: message),
            ),
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
          if (message.imageBase64 != null)
            Padding(
              padding: EdgeInsets.only(bottom: hasBodyContent ? 8 : 0),
              child: imageBytes == null
                  ? _BrokenImagePreview(theme: theme)
                  : _MessageImageThumbnail(
                      bytes: imageBytes,
                      onOpen: () => _openImageViewer(imageBytes),
                      onPointerDown: () => _suppressActionRowToggle = true,
                    ),
            ),
          if (message.hasVideoAttachment)
            Padding(
              padding: EdgeInsets.only(bottom: hasBodyContent ? 8 : 0),
              child: _MessageVideoChip(message: message, isUser: isUser),
            ),
          if (hasBodyContent)
            isUser
                ? _UserMessageContent(
                    content: message.content.isEmpty && message.isStreaming
                        ? '...'
                        : message.content,
                    textColor: theme.colorScheme.onPrimary,
                    attachmentPath: message.attachmentPath,
                  )
                : ParsedContentView(
                    content: message.content.isEmpty && message.isStreaming
                        ? '...'
                        : message.content,
                    textColor: theme.colorScheme.onSurface,
                    isStreaming: message.isStreaming,
                    showMemoryUpdates: settings.showMemoryUpdates,
                    fileReferenceRootPath: selectedProject?.normalizedRootPath,
                    fileReferenceProjectName: selectedProject?.name,
                    onOpenFileWorkspaceViewer: widget.onOpenFileWorkspaceViewer,
                    onReviewMemory: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChatSettingsPage(),
                        ),
                      );
                    },
                  ),
          if (handoffTargetLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ParticipantHandoffCueRow(targetLabel: handoffTargetLabel),
            ),
          if (participantToolNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ParticipantToolSummaryRow(
                toolNames: participantToolNames,
              ),
            ),
          if (responseMetrics != null &&
              _ResponseMetricsRow.hasVisibleMetrics(responseMetrics))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ResponseMetricsRow(metrics: responseMetrics),
            ),
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
          if (!isUser &&
              !message.isStreaming &&
              widget.turnDiff?.hasChanges == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _TurnDiffChip(
                diff: widget.turnDiff!,
                onPressed: widget.onOpenTurnDiff,
              ),
            ),
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
                    onTap: () => _toggleTts(
                      tts: tts,
                      message: message,
                      settings: settings,
                    ),
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
              widget.onReselectProject != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _ProjectAccessErrorCard(
                issue: projectAccessIssue,
                onReselectProject: widget.onReselectProject!,
              ),
            ),
        ],
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerUp: _handleBubblePointerUp,
              child: bubble,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: showActionRow
                  ? Padding(
                      padding: EdgeInsets.only(
                        top: 2,
                        left: isUser ? 0 : 12,
                        right: isUser ? 12 : 0,
                      ),
                      child: _MessageActionRow(
                        timestamp: _formatTimestamp(context),
                        copied: _copied,
                        onCopy: message.content.trim().isEmpty
                            ? null
                            : _copyMessageContent,
                        canRewind: widget.canRewind,
                        onRewindToHere: widget.onRewindToHere,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTts({
    required TtsService tts,
    required Message message,
    required AppSettings settings,
  }) async {
    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }

    final readableText = _extractReadableText(message.content);
    if (readableText.isEmpty) {
      return;
    }
    await tts.setSpeechRate(settings.speechRate);
    await tts.speak(readableText);
  }
}

List<String> _visibleParticipantToolNames(List<String> toolNames) {
  final seen = <String>{};
  final visible = <String>[];
  for (final toolName in toolNames) {
    final normalized = toolName.trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    visible.add(normalized);
  }
  return visible;
}

String? _handoffTargetLabel(Message message) {
  final targetId = message.handoffTargetParticipantId?.trim();
  final targetName = message.handoffTargetDisplayName?.trim();
  final targetRole = message.handoffTargetRoleLabel?.trim();
  if ((targetId == null || targetId.isEmpty) &&
      (targetName == null || targetName.isEmpty) &&
      (targetRole == null || targetRole.isEmpty)) {
    return null;
  }

  final name = targetName == null || targetName.isEmpty
      ? (targetId == null || targetId.isEmpty ? null : targetId)
      : targetName;
  final role = targetRole == null || targetRole.isEmpty ? null : targetRole;
  if (name == null || name.isEmpty) {
    return role;
  }
  if (role == null || role.isEmpty || role == name) {
    return name;
  }
  return '$name · $role';
}

class _ParticipantSpeakerHeader extends StatelessWidget {
  const _ParticipantSpeakerHeader({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _displayName(message);
    final role = _roleLabel(message, name);
    final color = Color(message.participantColorValue ?? 0xFF6750A4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (role != null) ...[
          const SizedBox(width: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              child: Text(
                role,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _displayName(Message message) {
    final value = message.participantDisplayName?.trim();
    return value == null || value.isEmpty ? 'Assistant' : value;
  }

  static String? _roleLabel(Message message, String displayName) {
    final value = message.participantRoleLabel?.trim();
    if (value == null || value.isEmpty || value == displayName) {
      return null;
    }
    return value;
  }
}

class _ParticipantToolSummaryRow extends StatelessWidget {
  const _ParticipantToolSummaryRow({required this.toolNames});

  final List<String> toolNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: 'chat.participant_tools_used'.tr(),
          child: Icon(Icons.manage_search_outlined, size: 14, color: color),
        ),
        Text(
          'chat.participant_tools_used'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        for (final toolName in toolNames)
          _ParticipantToolNameChip(toolName: toolName),
      ],
    );
  }
}

class _ParticipantHandoffCueRow extends StatelessWidget {
  const _ParticipantHandoffCueRow({required this.targetLabel});

  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.record_voice_over_outlined, size: 14, color: color),
        Text(
          'chat.participant_handoff_requested'.tr(
            namedArgs: {'participant': targetLabel},
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ParticipantToolNameChip extends StatelessWidget {
  const _ParticipantToolNameChip({required this.toolName});

  final String toolName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: toolName,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              toolName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseMetricsRow extends StatelessWidget {
  const _ResponseMetricsRow({required this.metrics});

  final MessageResponseMetrics metrics;

  static bool hasVisibleMetrics(MessageResponseMetrics metrics) {
    return metrics.completionTokens > 0 ||
        metrics.elapsedMilliseconds > 0 ||
        (metrics.finishReason?.trim().isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    final elapsedSeconds = metrics.elapsedMilliseconds / 1000.0;
    if (metrics.completionTokens > 0 && metrics.elapsedMilliseconds > 0) {
      chips.add(
        _ResponseMetricChip(
          icon: Icons.speed,
          label:
              '${_formatRate(metrics.completionTokens, elapsedSeconds)} tok/sec',
          tooltip: 'Generated tokens per second',
        ),
      );
    }
    if (metrics.completionTokens > 0) {
      chips.add(
        _ResponseMetricChip(
          icon: Icons.format_list_numbered,
          label:
              '${metrics.completionTokens} '
              '${metrics.completionTokens == 1 ? 'token' : 'tokens'}',
          tooltip: 'Generated completion tokens',
        ),
      );
    }
    if (metrics.elapsedMilliseconds > 0) {
      chips.add(
        _ResponseMetricChip(
          icon: Icons.timer_outlined,
          label: '${elapsedSeconds.toStringAsFixed(2)}s',
          tooltip: 'Response duration',
        ),
      );
    }
    final finishReason = _formatFinishReason(metrics.finishReason);
    if (finishReason != null) {
      chips.add(
        _ResponseMetricChip(
          icon: Icons.stop_circle_outlined,
          label: 'Stop reason: $finishReason',
          tooltip: 'Model finish reason',
        ),
      );
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  static String _formatRate(int tokens, double elapsedSeconds) {
    final rate = tokens / elapsedSeconds;
    return rate >= 100 ? rate.toStringAsFixed(1) : rate.toStringAsFixed(2);
  }

  static String? _formatFinishReason(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .toLowerCase();
    return switch (normalized) {
      'content filter' => 'Content Filter',
      'eos token' || 'eos token found' => 'EOS Token Found',
      'stream end' => 'Stream End',
      'tool calls' => 'Tool Calls',
      _ =>
        normalized
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' '),
    };
  }
}

class _ResponseMetricChip extends StatelessWidget {
  const _ResponseMetricChip({
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnDiffChip extends StatelessWidget {
  const _TurnDiffChip({required this.diff, this.onPressed});

  final TurnDiff diff;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(
        Icons.difference_outlined,
        size: 16,
        color: theme.colorScheme.primary,
      ),
      label: Text(diff.summaryLabel, overflow: TextOverflow.ellipsis),
      tooltip: 'View file changes',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      side: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.30),
      ),
      backgroundColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.28,
      ),
      labelStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MessageActionRow extends StatelessWidget {
  const _MessageActionRow({
    required this.timestamp,
    required this.copied,
    required this.canRewind,
    this.onCopy,
    this.onRewindToHere,
  });

  final String timestamp;
  final bool copied;
  final VoidCallback? onCopy;
  final bool canRewind;
  final VoidCallback? onRewindToHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timestamp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onCopy,
          tooltip: 'content.code_copy'.tr(),
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
          iconSize: 18,
          icon: Icon(
            copied ? Icons.check_rounded : Icons.content_copy_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (canRewind && onRewindToHere != null)
          IconButton(
            onPressed: onRewindToHere,
            tooltip: 'Rewind conversation to here',
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
            iconSize: 18,
            icon: Icon(
              Icons.restore_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _MessageImageThumbnail extends StatelessWidget {
  const _MessageImageThumbnail({
    required this.bytes,
    required this.onOpen,
    required this.onPointerDown,
  });

  final Uint8List bytes;
  final VoidCallback onOpen;
  final VoidCallback onPointerDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'message.view_image'.tr(),
      child: MouseRegion(
        cursor: SystemMouseCursors.zoomIn,
        child: GestureDetector(
          onTap: onOpen,
          child: Listener(
            onPointerDown: (_) => onPointerDown(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    width: _messageImagePreviewWidth,
                    height: _messageImagePreviewHeight,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) {
                      return _BrokenImagePreview(theme: theme);
                    },
                  ),
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x8C000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.zoom_in,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrokenImagePreview extends StatelessWidget {
  const _BrokenImagePreview({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _messageImagePreviewWidth,
      height: _messageImagePreviewHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.colorScheme.errorContainer),
        child: Center(
          child: Icon(
            Icons.broken_image,
            color: theme.colorScheme.onErrorContainer,
          ),
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
                fontFamily: kMonoFontFamily,
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

/// The `[File: name]` header a composer attachment leaves in the transcript.
///
/// Current messages put the person's text first and append the header, and it
/// carries no body — the file's text goes to the model, not into the bubble.
final _trailingFileBlockPattern = RegExp(r'(?:\n\n|^)\[File: (.+?)\]\s*$');

/// The same header, at the front of the message.
///
/// Messages written before the visible/model split inlined the whole file
/// under it; the ones written between that split and the reorder put it there
/// with nothing under it at all. The body is captured separately so the second
/// kind does not read the person's own question as file content — which is
/// what put their message inside the file box.
final _leadingFileBlockPattern = RegExp(r'^\[File: (.+?)\]\n');

/// One attachment header pulled out of a user message.
class _FileBlock {
  const _FileBlock({
    required this.label,
    required this.userText,
    required this.inlinedBody,
  });

  final String label;
  final String userText;

  /// The file's text, for a message old enough to have carried it inline.
  final String inlinedBody;

  static _FileBlock? parse(String content) {
    final trailing = _trailingFileBlockPattern.firstMatch(content);
    if (trailing != null) {
      return _FileBlock(
        label: trailing.group(1)!,
        userText: content.substring(0, trailing.start).trim(),
        inlinedBody: '',
      );
    }
    final leading = _leadingFileBlockPattern.firstMatch(content);
    if (leading == null) return null;
    final rest = content.substring(leading.end);
    // A blank line right after the header means the header stood alone and
    // everything below it is the person's message.
    final blankLine = rest.indexOf('\n\n');
    if (rest.startsWith('\n')) {
      return _FileBlock(
        label: leading.group(1)!,
        userText: rest.trim(),
        inlinedBody: '',
      );
    }
    return _FileBlock(
      label: leading.group(1)!,
      userText: blankLine < 0 ? '' : rest.substring(blankLine).trim(),
      inlinedBody: (blankLine < 0 ? rest : rest.substring(0, blankLine)).trim(),
    );
  }
}

/// Renders user message content, naming any file the message carried.
///
/// The header is a label, not a control: there is nothing behind it to open on
/// a current message, because the attachment's text is sent to the model
/// rather than kept in the transcript. A message from before that split still
/// holds its file inline, so that text is shown in a bounded scroll area
/// instead of being hidden behind a disclosure nobody can see is there.
class _UserMessageContent extends StatelessWidget {
  const _UserMessageContent({
    required this.content,
    required this.textColor,
    this.attachmentPath,
  });

  final String content;
  final Color textColor;

  /// The stored copy of the attachment, when the message kept one.
  final String? attachmentPath;

  Future<void> _openAttachment(BuildContext context) async {
    final path = attachmentPath;
    if (path == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await openAttachmentWithPlatformViewer(path: path);
    if (result == AttachmentOpenResult.opened) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result == AttachmentOpenResult.missing
                ? 'message.attachment_missing'.tr()
                : 'message.attachment_open_failed'.tr(),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final block = _FileBlock.parse(content);
    if (block == null) {
      return SelectableText(content, style: TextStyle(color: textColor));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.userText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              block.userText,
              style: TextStyle(color: textColor),
            ),
          ),
        _AttachmentSummary(
          label: block.label,
          textColor: textColor,
          onOpen: attachmentPath == null
              ? null
              : () => unawaited(_openAttachment(context)),
        ),
        if (block.inlinedBody.isNotEmpty)
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
                  block.inlinedBody,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontFamily: kMonoFontFamily,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One line naming the file a message carried.
///
/// Tappable only when the message kept a copy on disk: the app cannot render
/// the document itself, so opening it means handing the file to the platform
/// viewer, and there is nothing to hand over for a message written before
/// attachments were preserved.
class _AttachmentSummary extends StatelessWidget {
  const _AttachmentSummary({
    required this.label,
    required this.textColor,
    this.onOpen,
  });

  final String label;
  final Color textColor;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.picture_as_pdf_outlined,
            size: 16,
            color: textColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                decoration: onOpen == null ? null : TextDecoration.underline,
                decorationColor: textColor.withValues(alpha: 0.5),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (onOpen == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(message: 'message.attachment_open'.tr(), child: row),
      ),
    );
  }
}

/// Names a video the message carried, without trying to play it.
///
/// A thumbnail would need a decode pass and a player dependency to show one
/// frame of something the person just picked from their own library; the
/// filename and size are what makes the message legible in the transcript.
class _MessageVideoChip extends StatelessWidget {
  const _MessageVideoChip({required this.message, required this.isUser});

  final Message message;
  final bool isUser;

  Future<void> _open(BuildContext context) {
    return showMessageVideoViewer(
      context: context,
      filePath: message.videoPath,
      url: message.videoUrl,
      fileName: _displayName(),
      mimeType: message.effectiveVideoMimeType,
      sizeBytes: message.videoSizeBytes,
    );
  }

  /// Whether a still can be shown: there has to be a local file to read a
  /// frame from, so a video given only as a URL keeps the plain chip.
  bool get _canShowPoster =>
      (message.videoPath?.isNotEmpty ?? false) &&
      File(message.videoPath!).existsSync();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: const ValueKey('message-video-chip'),
      onTap: () => unawaited(_open(context)),
      borderRadius: BorderRadius.circular(_canShowPoster ? 12 : 8),
      child: _canShowPoster
          ? _buildPoster(theme, foreground)
          : _buildChipOnly(theme, foreground),
    );
  }

  /// The still, with the play affordance over it.
  Widget _buildPoster(ThemeData theme, Color foreground) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              MessageVideoPoster(
                key: const ValueKey('message-video-poster'),
                filePath: message.videoPath!,
                width: _messageImagePreviewWidth,
                height: _messageImagePreviewHeight,
                placeholder: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.play_arrow,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _messageImagePreviewWidth,
          child: Text(
            _label(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }

  /// Fallback when there is no frame to read: a URL attachment, or a file the
  /// attachments sweep has since removed.
  Widget _buildChipOnly(ThemeData theme, Color foreground) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            message.videoUrl != null
                ? Icons.play_circle_outline
                : Icons.play_circle_fill,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _label(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  String _label() {
    final name = _displayName();
    final parts = <String>[
      if (name.isNotEmpty) name,
      if ((message.videoSizeBytes ?? 0) > 0)
        formatAttachmentSize(message.videoSizeBytes!),
      if ((message.videoDurationMs ?? 0) > 0)
        formatAttachmentDuration(message.videoDurationMs!),
    ];
    return parts.isEmpty ? 'message.attach_video'.tr() : parts.join(' · ');
  }

  String _displayName() {
    final url = message.videoUrl;
    if (url != null) {
      final parsed = Uri.tryParse(url);
      if (parsed == null) return url;
      return parsed.pathSegments.isEmpty
          ? parsed.host
          : parsed.pathSegments.last;
    }
    final path = message.videoPath;
    if (path == null || path.isEmpty) return '';
    return path.split(Platform.pathSeparator).last;
  }
}

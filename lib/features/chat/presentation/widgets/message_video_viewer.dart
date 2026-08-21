import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/attachment_format.dart';
import '../../../../core/utils/logger.dart';
import 'message_video_io.dart';
import 'message_video_playback.dart';

const Key kMessageVideoViewerKey = Key('message-video-viewer');

Future<void> showMessageVideoViewer({
  required BuildContext context,
  String? filePath,
  String? url,
  required String fileName,
  required String mimeType,
  int? sizeBytes,
  MessageVideoIo io = const MessageVideoIo(),
  VideoControllerFactory controllerFactory = defaultVideoControllerFactory,
  bool Function() supportsPlayback = defaultSupportsVideoPlayback,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'message.close_video_viewer'.tr(),
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => MessageVideoViewer(
      filePath: filePath,
      url: url,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      io: io,
      controllerFactory: controllerFactory,
      supportsPlayback: supportsPlayback,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// Full-screen playback for a video a message carried.
///
/// Opened from the transcript chip rather than played in place: a conversation
/// can hold several videos, and a player per bubble would decode all of them
/// while the reader scrolls past.
class MessageVideoViewer extends StatefulWidget {
  const MessageVideoViewer({
    super.key,
    this.filePath,
    this.url,
    required this.fileName,
    required this.mimeType,
    this.sizeBytes,
    this.io = const MessageVideoIo(),
    this.controllerFactory = defaultVideoControllerFactory,
    this.supportsPlayback = defaultSupportsVideoPlayback,
  }) : assert(
         filePath != null || url != null,
         'A video viewer needs a file or a URL to show',
       );

  final String? filePath;
  final String? url;
  final String fileName;
  final String mimeType;
  final int? sizeBytes;
  final MessageVideoIo io;
  final VideoControllerFactory controllerFactory;
  final bool Function() supportsPlayback;

  @override
  State<MessageVideoViewer> createState() => _MessageVideoViewerState();
}

class _MessageVideoViewerState extends State<MessageVideoViewer> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _busy = false;
  String? _playbackError;

  @override
  void initState() {
    super.initState();
    if (widget.supportsPlayback()) {
      unawaited(_initializePlayer());
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    setState(() => _initializing = true);
    final controller = widget.controllerFactory(
      file: widget.filePath,
      url: widget.url,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlaybackTick);
      setState(() {
        _controller = controller;
        _initializing = false;
      });
      await controller.play();
    } catch (error) {
      appLog('[MessageVideoViewer] Playback failed: $error');
      await controller.dispose();
      if (!mounted) return;
      // Named, not swallowed: an attachment that will not open is a fact the
      // reader needs, and the file is still there to download.
      setState(() {
        _initializing = false;
        _playbackError = 'message.video_playback_failed'.tr();
      });
    }
  }

  void _onPlaybackTick() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _download() async {
    final path = widget.filePath;
    if (_busy || path == null) return;
    setState(() => _busy = true);
    try {
      final outcome = await widget.io.save(
        sourcePath: path,
        fileName: widget.fileName,
        mimeType: widget.mimeType,
        dialogTitle: 'message.download_video'.tr(),
      );
      if (!mounted) return;
      switch (outcome) {
        case MessageVideoSaveOutcome.saved:
          _showSnack('message.video_saved'.tr());
        case MessageVideoSaveOutcome.shared:
        case MessageVideoSaveOutcome.cancelled:
          break;
      }
    } catch (error) {
      appLog('[MessageVideoViewer] Save failed: $error');
      if (mounted) _showSnack('message.video_save_failed'.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: kMessageVideoViewerKey,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(theme),
            Expanded(child: Center(child: _buildStage(theme))),
            if (_controller != null) _buildControls(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final subtitle = (widget.sizeBytes ?? 0) > 0
        ? formatAttachmentSize(widget.sizeBytes!)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('message-video-viewer-close'),
            tooltip: 'message.close_video_viewer'.tr(),
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.filePath != null)
            IconButton(
              key: const ValueKey('message-video-viewer-download'),
              tooltip: 'message.download_video'.tr(),
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: _busy ? null : _download,
            ),
        ],
      ),
    );
  }

  Widget _buildStage(ThemeData theme) {
    final controller = _controller;
    if (controller != null) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: GestureDetector(
          onTap: _togglePlay,
          child: VideoPlayer(controller),
        ),
      );
    }
    if (_initializing) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return _MessageVideoNotice(
      // Two different situations, and the reader can act on the difference:
      // one is worth retrying elsewhere, the other never will be.
      message:
          _playbackError ?? 'message.video_playback_unavailable'.tr(),
      theme: theme,
    );
  }

  Widget _buildControls(ThemeData theme) {
    final controller = _controller!;
    final value = controller.value;
    final duration = value.duration;
    final position = value.position;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('message-video-viewer-play'),
            tooltip: value.isPlaying
                ? 'message.video_pause'.tr()
                : 'message.video_play'.tr(),
            icon: Icon(
              value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: _togglePlay,
          ),
          Expanded(
            child: Slider(
              value: _sliderValue(position, duration),
              onChanged: duration.inMilliseconds <= 0
                  ? null
                  : (fraction) => unawaited(
                      controller.seekTo(
                        Duration(
                          milliseconds:
                              (duration.inMilliseconds * fraction).round(),
                        ),
                      ),
                    ),
            ),
          ),
          Text(
            '${formatPlaybackPosition(position)} / '
            '${formatPlaybackPosition(duration)}',
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  static double _sliderValue(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) return 0;
    final fraction = position.inMilliseconds / duration.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }
}

class _MessageVideoNotice extends StatelessWidget {
  const _MessageVideoNotice({required this.message, required this.theme});

  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_outlined, color: Colors.white70, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

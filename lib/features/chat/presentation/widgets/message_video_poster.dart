import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'message_video_playback.dart';

/// A still from the video, shown in the transcript.
///
/// Built from the player the viewer already uses rather than an extraction
/// package: a controller holds its first decoded frame after `initialize`, so
/// a paused player *is* a poster frame, and the app carries one video
/// dependency instead of two.
///
/// The cost of that choice is that the frame is not cached anywhere. The
/// controller lives only while this widget is mounted, so scrolling a long
/// conversation re-initializes each poster as it comes back into view. That is
/// affordable for the handful of videos a conversation holds, and it is the
/// reason this never plays: a paused controller is one decoded frame, while a
/// playing one is a decode loop per visible bubble.
class MessageVideoPoster extends StatefulWidget {
  const MessageVideoPoster({
    super.key,
    required this.filePath,
    required this.width,
    required this.height,
    required this.placeholder,
    this.controllerFactory = defaultVideoControllerFactory,
    this.supportsPlayback = defaultSupportsVideoPlayback,
  });

  final String filePath;
  final double width;
  final double height;

  /// Shown until a frame is ready, and instead of one where none can be had.
  final Widget placeholder;

  final VideoControllerFactory controllerFactory;
  final bool Function() supportsPlayback;

  /// A second in, not frame zero.
  static const Duration posterFrameAt = Duration(seconds: 1);

  @override
  State<MessageVideoPoster> createState() => _MessageVideoPosterState();
}

class _MessageVideoPosterState extends State<MessageVideoPoster> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.supportsPlayback()) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final controller = widget.controllerFactory(file: widget.filePath);
    try {
      await controller.initialize();
      // A second in, not frame zero: the first frame of a phone recording is
      // often the shutter still settling, so it is black or a blurred sweep.
      final duration = controller.value.duration;
      if (duration > MessageVideoPoster.posterFrameAt) {
        await controller.seekTo(MessageVideoPoster.posterFrameAt);
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      // A poster is decoration. Failing to get one leaves the placeholder,
      // which still names the video and still opens it.
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: controller == null
          ? widget.placeholder
          : FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
    );
  }
}

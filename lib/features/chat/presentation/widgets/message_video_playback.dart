import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Whether this platform can play a video attachment in-app.
///
/// `video_player` ships implementations for Android, iOS and macOS only.
/// Windows and Linux would need a bundled libmpv, which is a large thing to
/// carry for two platforms, so the viewer there offers download instead of
/// pretending at a player that cannot start.
bool defaultSupportsVideoPlayback() {
  if (kIsWeb) return true;
  return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
}

/// Creates the controller the viewer drives.
///
/// Indirected so a widget test can supply a fake: the real one talks to a
/// platform channel that does not exist under `flutter_test`.
typedef VideoControllerFactory =
    VideoPlayerController Function({String? file, String? url});

VideoPlayerController defaultVideoControllerFactory({
  String? file,
  String? url,
}) {
  if (file != null) return VideoPlayerController.file(File(file));
  return VideoPlayerController.networkUrl(Uri.parse(url!));
}

/// `m:ss`, or `h:mm:ss` once it runs past an hour.
String formatPlaybackPosition(Duration position) {
  final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
  final minutes = position.inMinutes.remainder(60);
  if (position.inHours <= 0) {
    return '${position.inMinutes}:$seconds';
  }
  return '${position.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
}

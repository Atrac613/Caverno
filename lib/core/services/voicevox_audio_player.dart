import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';

/// Audio player that queues and plays WAV byte arrays sequentially.
///
/// Used by voice mode to play VOICEVOX-synthesized speech chunks one after
/// another. Supports immediate stop for barge-in interruption.
class VoicevoxAudioPlayer {
  VoicevoxAudioPlayer() {
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _cleanupLastFile();
      _playNext();
    });
    cleanupStaleFiles();
  }

  /// Remove leftover voicevox temp files older than [maxAge].
  static Future<void> cleanupStaleFiles({
    Duration maxAge = const Duration(hours: 1),
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final entries = tempDir.listSync();
      for (final entry in entries) {
        if (entry is File &&
            entry.path.contains('voicevox_') &&
            entry.path.endsWith('.wav')) {
          final stat = entry.statSync();
          if (now.difference(stat.modified) > maxAge) {
            entry.deleteSync();
          }
        }
      }
    } catch (_) {}
  }

  final AudioPlayer _player = AudioPlayer();

  /// Queue of WAV byte arrays waiting to be played.
  final Queue<Uint8List> _queue = Queue<Uint8List>();

  bool _isPlaying = false;
  File? _lastPlayedFile;

  /// Called when the entire queue has been drained and playback finishes.
  void Function()? onQueueComplete;

  /// Whether audio is currently playing or queued.
  bool get isActive => _isPlaying || _queue.isNotEmpty;

  /// Add WAV bytes to the playback queue.
  ///
  /// If nothing is currently playing, playback starts immediately.
  void enqueue(Uint8List wavBytes) {
    if (wavBytes.isEmpty) return;
    _queue.add(wavBytes);
    if (!_isPlaying) {
      _playNext();
    }
  }

  Future<void> stop() async {
    _queue.clear();
    _isPlaying = false;
    await _player.stop();
    _cleanupLastFile();
    appLog('[AudioPlayer] Stopped and queue cleared');
  }

  void _cleanupLastFile() {
    if (_lastPlayedFile != null) {
      try {
        if (_lastPlayedFile!.existsSync()) {
          _lastPlayedFile!.deleteSync();
        }
      } catch (_) {}
      _lastPlayedFile = null;
    }
  }

  /// Play the next item in the queue.
  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      onQueueComplete?.call();
      return;
    }

    _isPlaying = true;
    final wavBytes = _queue.removeFirst();

    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }
      _lastPlayedFile = File('${tempDir.path}/voicevox_${DateTime.now().microsecondsSinceEpoch}.wav');
      await _lastPlayedFile!.writeAsBytes(wavBytes);

      await _player.play(DeviceFileSource(_lastPlayedFile!.path));
      appLog('[AudioPlayer] Playing ${wavBytes.length} bytes via temp file');
    } catch (e) {
      appLog('[AudioPlayer] Playback error: $e');
      _isPlaying = false;
      _cleanupLastFile();
      // Continue with the next item instead of stalling.
      _playNext();
    }
  }

  /// Release resources.
  Future<void> dispose() async {
    _queue.clear();
    _cleanupLastFile();
    await _player.dispose();
  }
}

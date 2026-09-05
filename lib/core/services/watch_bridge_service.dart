import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/watch/domain/watch_command.dart';
import '../../features/watch/domain/watch_snapshot.dart';

/// Transport between the Flutter app and the paired Apple Watch companion.
///
/// Flutter does not run on watchOS, so the watch app is a native SwiftUI target
/// and everything crosses a `WCSession` in the iOS Runner. This interface is
/// what the Dart side sees; [MethodChannelWatchBridgeService] is the real
/// implementation and tests substitute a fake.
abstract interface class WatchBridgeService {
  /// Commands arriving from the watch. Malformed frames are dropped by the
  /// implementation rather than surfaced, so listeners only see valid commands.
  Stream<WatchCommand> get commands;

  /// Whether a watch is paired and its app is installed. Cheap enough to poll
  /// before doing projection work.
  Future<bool> isAvailable();

  /// Push the latest state. Delivered as application context (coalescing, so an
  /// old frame never overwrites a newer one) and, when the watch app is
  /// foreground-reachable, also as an immediate message.
  Future<void> pushSnapshot(WatchSnapshot snapshot);

  /// Push an incremental spoken/streamed chunk during a turn.
  ///
  /// Separate from [pushSnapshot] because snapshots coalesce: the OS is free to
  /// drop an intermediate application context, which is right for state but
  /// wrong for text that is being read aloud sentence by sentence.
  Future<void> pushStreamChunk({
    required String turnId,
    required String text,
    required bool isFinal,
  });

  /// Answer a command the watch is waiting on.
  Future<void> sendCommandResult(WatchCommandResult result);

  void dispose();
}

/// Real bridge, backed by `WatchBridgePlugin` in `ios/Runner/AppDelegate.swift`.
class MethodChannelWatchBridgeService implements WatchBridgeService {
  MethodChannelWatchBridgeService({
    MethodChannel? methodChannel,
    EventChannel? commandChannel,
    bool? isSupportedPlatform,
  }) : _channel = methodChannel ?? const MethodChannel(methodChannelName),
       _commandChannel =
           commandChannel ?? const EventChannel(commandChannelName),
       _isSupportedPlatform =
           isSupportedPlatform ?? (!kIsWeb && Platform.isIOS);

  static const String methodChannelName = 'com.caverno/watch_bridge';
  static const String commandChannelName = 'com.caverno/watch_bridge/commands';

  final MethodChannel _channel;
  final EventChannel _commandChannel;
  final bool _isSupportedPlatform;

  Stream<WatchCommand>? _commands;

  @override
  Stream<WatchCommand> get commands {
    if (!_isSupportedPlatform) return const Stream<WatchCommand>.empty();
    return _commands ??= _commandChannel
        .receiveBroadcastStream()
        .map(_decodeCommand)
        .where((command) => command != null)
        .cast<WatchCommand>()
        .asBroadcastStream();
  }

  WatchCommand? _decodeCommand(Object? event) {
    try {
      final decoded = event is String ? jsonDecode(event) : event;
      if (decoded is! Map) return null;
      return WatchCommand.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!_isSupportedPlatform) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> pushSnapshot(WatchSnapshot snapshot) =>
      _invoke('pushSnapshot', snapshot.encode());

  @override
  Future<void> pushStreamChunk({
    required String turnId,
    required String text,
    required bool isFinal,
  }) => _invoke(
    'pushStreamChunk',
    jsonEncode({'turnId': turnId, 'text': text, 'isFinal': isFinal}),
  );

  @override
  Future<void> sendCommandResult(WatchCommandResult result) =>
      _invoke('sendCommandResult', jsonEncode(result.toJson()));

  Future<void> _invoke(String method, String payload) async {
    if (!_isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>(method, payload);
    } on PlatformException {
      // Best-effort: a watch that is out of range or has the app closed is a
      // normal condition, not an error the chat loop should react to.
    } on MissingPluginException {
      // Runner built without the watch bridge (e.g. an older host binary).
    }
  }

  @override
  void dispose() {}
}

import '../../domain/entities/video_delivery.dart';

/// Remembers how each message's video was delivered, by message id.
///
/// Exists because the two ends of the question sit on opposite sides of a
/// layer: the request layer decides how a video is sent, while the session
/// logger writes the request from above it and cannot see that decision. The
/// ledger is what the logger asks.
///
/// Message ids are unique, so concurrent turns share this without colliding.
class VideoDeliveryLedger {
  /// Enough to cover a tool loop's worth of re-sends without growing forever.
  static const int historyLimit = 16;

  final Map<String, VideoDelivery> _deliveries = <String, VideoDelivery>{};

  void recordAll(Map<String, VideoDelivery> deliveries) {
    if (deliveries.isEmpty) return;
    _deliveries.addAll(deliveries);
    while (_deliveries.length > historyLimit) {
      _deliveries.remove(_deliveries.keys.first);
    }
  }

  /// How the video on [messageId] went out, or null if none did.
  VideoDelivery? operator [](String messageId) => _deliveries[messageId];
}

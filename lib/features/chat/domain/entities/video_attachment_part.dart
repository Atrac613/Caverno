/// Encodes a video attachment as a text part the HTTP layer rewrites.
///
/// `openai_dart` 8.0.0 models content parts as a sealed type with no video
/// variant, so a video cannot be expressed in the typed request at all. The
/// message formatter emits this marker and `VideoContentPartClient` swaps it
/// for `{"type": "video_url", "video_url": {"url": ...}}` once the body is JSON.
///
/// The URL travels inside the marker rather than through an ambient side
/// channel. Streaming request bodies are built lazily, on first listen, by
/// which point the zone that issued the call is gone -- a zone-carried lookup
/// table would resolve to nothing exactly on the streaming path.
class VideoAttachmentPart {
  const VideoAttachmentPart._();

  static const String _open = '[[caverno-video]]';
  static const String _close = '[[/caverno-video]]';

  /// Cheap pre-check so a request with no video skips JSON round-tripping.
  static const String marker = _open;

  /// Stands in for an attachment the request layer could not resolve.
  static const String omittedNotice =
      '[video attachment omitted from this request]';

  static String encode(String url) => '$_open$url$_close';

  /// Reads the URL back out of a text part, or null if it is ordinary text.
  static String? decode(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(_open) || !trimmed.endsWith(_close)) return null;
    final url = trimmed.substring(
      _open.length,
      trimmed.length - _close.length,
    );
    return url.isEmpty ? null : url;
  }
}

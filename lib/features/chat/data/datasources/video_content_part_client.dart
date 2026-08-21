import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/video_attachment_part.dart';

/// Writes `video_url` content parts into outgoing chat requests.
///
/// The typed request cannot express a video (see [VideoAttachmentPart]), so the
/// formatter plants a marker text part and this client rewrites it on the way
/// out, in the OpenAI-compatible shape:
///
/// ```json
/// {"type": "video_url", "video_url": {"url": "..."}}
/// ```
///
/// This wraps rather than extends the other request policies so their tested
/// behavior is untouched, and a body with no marker is forwarded byte for byte
/// rather than re-encoded.
final class VideoContentPartClient extends http.BaseClient {
  VideoContentPartClient({required http.Client delegate}) : _delegate = delegate;

  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request && _isChatCompletion(request)) {
      _injectVideoParts(request);
    }
    return _delegate.send(request);
  }

  static bool _isChatCompletion(http.Request request) {
    final path = request.url.path.replaceFirst(RegExp(r'/+$'), '');
    return request.method == 'POST' && path.endsWith('/chat/completions');
  }

  void _injectVideoParts(http.Request request) {
    if (!request.body.contains(VideoAttachmentPart.marker)) return;

    final decoded = jsonDecode(request.body);
    if (decoded is! Map) return;
    final body = Map<String, dynamic>.from(decoded);
    final messages = body['messages'];
    if (messages is! List) return;

    var rewrote = false;
    for (final message in messages) {
      if (message is! Map) continue;
      final content = message['content'];
      if (content is! List) continue;
      for (var i = 0; i < content.length; i++) {
        final part = content[i];
        if (part is! Map) continue;
        if (part['type'] != 'text') continue;
        final text = part['text'];
        if (text is! String) continue;
        final url = VideoAttachmentPart.decode(text);
        if (url == null) continue;
        content[i] = <String, dynamic>{
          'type': 'video_url',
          'video_url': <String, dynamic>{'url': url},
        };
        rewrote = true;
      }
    }

    if (!rewrote) return;
    request.body = jsonEncode(body);
  }

  @override
  void close() => _delegate.close();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/services/media_host_service.dart';
import '../../domain/entities/message.dart';

/// Decides how a video attachment reaches the model endpoint.
///
/// Preference is a URL served by [MediaHostService]: the endpoint fetches the
/// bytes itself, so the request body stays small and the same file is not
/// re-encoded on every tool-loop iteration. When the endpoint cannot reach this
/// device -- a cloud endpoint, a phone on cellular, a segmented network -- the
/// payload is inlined as a `data:` URI instead, which always works.
///
/// The two modes are not chosen by guessing. The first video on an endpoint
/// goes out as a URL; if nothing ever fetched it, the endpoint is recorded as
/// unreachable and every later video on that endpoint is inlined from the
/// start. A wrong guess costs one request, and it self-corrects.
class VideoAttachmentDelivery {
  VideoAttachmentDelivery({required MediaHostService mediaHost})
    : _mediaHost = mediaHost;

  final MediaHostService _mediaHost;

  /// Endpoint origins observed to never fetch a published URL.
  final Set<String> _inlineOnlyOrigins = <String>{};

  /// Resolves the video to send, keyed by message id.
  ///
  /// Only the person's most recent turn is considered. Older attachments are
  /// left out so a conversation does not re-upload every video it has ever
  /// seen; the formatter marks the omission in their place.
  Future<Map<String, String>> resolve(
    List<Message> messages, {
    required Uri endpoint,
  }) async {
    final target = _targetMessage(messages);
    if (target == null) return const <String, String>{};

    final typedUrl = target.videoUrl;
    if (typedUrl != null && typedUrl.isNotEmpty) {
      // Handed over verbatim: the person addressed the endpoint's network, not
      // ours, and rewriting it would only break cases we cannot see.
      return <String, String>{target.id: typedUrl};
    }

    final path = target.videoPath;
    if (path == null) return const <String, String>{};
    final file = File(path);
    if (!file.existsSync()) return const <String, String>{};

    final url = await _deliver(
      file: file,
      mimeType: target.effectiveVideoMimeType,
      endpoint: endpoint,
    );
    if (url == null) return const <String, String>{};
    return <String, String>{target.id: url};
  }

  Future<String?> _deliver({
    required File file,
    required String mimeType,
    required Uri endpoint,
  }) async {
    final origin = _originKey(endpoint);
    if (!_inlineOnlyOrigins.contains(origin)) {
      try {
        final ticket = await _mediaHost.publish(
          file: file,
          mimeType: mimeType,
          endpoint: endpoint,
        );
        if (ticket != null) {
          _watchForFetch(ticket.token, origin);
          return ticket.url.toString();
        }
      } on Object {
        // Binding can fail on a locked-down network; inlining still works.
      }
      // No reachable address to advertise: skip straight to inlining, and
      // remember it so the next attachment does not pay for the discovery.
      _inlineOnlyOrigins.add(origin);
    }
    return _inlineDataUri(file: file, mimeType: mimeType);
  }

  void _watchForFetch(String token, String origin) {
    Timer(MediaHostService.ttl, () async {
      if (!_mediaHost.wasFetched(token)) {
        _inlineOnlyOrigins.add(origin);
      }
      await _mediaHost.revoke(token);
    });
  }

  static Future<String> _inlineDataUri({
    required File file,
    required String mimeType,
  }) async {
    final bytes = await file.readAsBytes();
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static String _originKey(Uri endpoint) =>
      '${endpoint.scheme}://${endpoint.host}:${endpoint.port}';

  /// The person's most recent turn, skipping prompts Caverno composed itself.
  static Message? _targetMessage(List<Message> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != MessageRole.user || message.isSynthesizedPrompt) {
        continue;
      }
      return message.hasVideoAttachment ? message : null;
    }
    return null;
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

/// What an endpoint says it accepts as input, as far as it will say.
enum EndpointModalitySupport {
  /// The endpoint did not answer the question. Not the same as "no": a proxy
  /// in front of a capable server usually says nothing at all.
  unknown,
  unsupported,
  supported,
}

/// Reads the input modalities an OpenAI-compatible endpoint advertises.
///
/// llama.cpp answers `GET /props` with a `modalities` map. Nothing in the
/// OpenAI specification requires that, so anything else -- a 404, a proxy's own
/// error page, a body that is not JSON -- reports [EndpointModalitySupport.unknown]
/// rather than a denial. Reporting "no" for silence would hide video behind
/// every proxy the person puts in front of their server.
///
/// The model is named in the query because modalities are a property of the
/// loaded weights, not of the server. A llama.cpp router fronting several
/// models answers a bare `/props` about itself -- `"role":"router"`,
/// `"model_path":"none"`, and no modalities at all -- while `?model=<id>`
/// answers about that model. A single-model server ignores the parameter, so
/// asking this way costs nothing and is the only way to get an answer from a
/// router.
class OpenAiModalitiesProbe {
  const OpenAiModalitiesProbe({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  Future<EndpointModalitySupport> videoSupport({
    required String baseUrl,
    required String model,
    required http.Client client,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final uri = propsUriFor(baseUrl, model: model);
    if (uri == null) return EndpointModalitySupport.unknown;
    try {
      final response = await client.get(uri, headers: headers).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return EndpointModalitySupport.unknown;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return EndpointModalitySupport.unknown;
      final modalities = decoded['modalities'];
      if (modalities is! Map) return EndpointModalitySupport.unknown;
      final video = modalities['video'];
      // A server that lists its modalities but omits `video` predates video
      // support, which is a real "no" rather than silence.
      if (video == null) return EndpointModalitySupport.unsupported;
      if (video is! bool) return EndpointModalitySupport.unknown;
      return video
          ? EndpointModalitySupport.supported
          : EndpointModalitySupport.unsupported;
    } on Object {
      return EndpointModalitySupport.unknown;
    }
  }

  /// `http://host:8080/v1` -> `http://host:8080/props?model=<model>`.
  ///
  /// `/props` sits at the server root, not under the OpenAI path prefix, so the
  /// version segment has to come off first.
  static Uri? propsUriFor(String baseUrl, {String model = ''}) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
    final segments = List<String>.from(parsed.pathSegments)
      ..removeWhere((segment) => segment.isEmpty);
    if (segments.isNotEmpty && RegExp(r'^v\d+$').hasMatch(segments.last)) {
      segments.removeLast();
    }
    final trimmedModel = model.trim();
    return parsed.replace(
      pathSegments: <String>[...segments, 'props'],
      queryParameters: trimmedModel.isEmpty
          ? null
          : <String, String>{'model': trimmedModel},
      fragment: null,
    );
  }
}

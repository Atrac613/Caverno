import 'dart:convert';

import 'package:http/http.dart' as http;

/// What an endpoint says it accepts as a request parameter, as far as it will
/// say.
enum EndpointParameterSupport {
  /// The endpoint did not answer the question. Not the same as "no": most
  /// OpenAI-compatible servers never list their parameters at all.
  unknown,
  unsupported,
  supported,
}

/// Reads the request parameters an OpenAI-compatible endpoint advertises on
/// `GET /models`.
///
/// OpenRouter-shaped servers put a `supported_parameters` list on each model
/// entry. Nothing in the OpenAI specification requires it, so a missing list, a
/// non-JSON body or any non-2xx status reports
/// [EndpointParameterSupport.unknown] rather than a denial -- reporting "no"
/// for silence would make every plain llama.cpp server look incapable.
///
/// Worth one GET because the alternative is a generation. Asking a server that
/// silently drops `response_format` to honor a schema costs a full completion
/// that runs to the token cap and answers nothing: measured at 24 s and an
/// empty `finish_reason: length` completion against Qwen3.8-Flash-Next-Q2,
/// whose `/v1/models` had advertised the absence all along.
class OpenAiParameterSupportProbe {
  const OpenAiParameterSupportProbe({
    this.timeout = const Duration(seconds: 5),
  });

  final Duration timeout;

  /// Whether the endpoint advertises `response_format` for [model].
  Future<EndpointParameterSupport> responseFormatSupport({
    required String baseUrl,
    required String model,
    required http.Client client,
    Map<String, String> headers = const <String, String>{},
  }) => parameterSupport(
    baseUrl: baseUrl,
    model: model,
    parameter: 'response_format',
    client: client,
    headers: headers,
  );

  Future<EndpointParameterSupport> parameterSupport({
    required String baseUrl,
    required String model,
    required String parameter,
    required http.Client client,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final uri = modelsUriFor(baseUrl);
    if (uri == null) return EndpointParameterSupport.unknown;
    try {
      final response = await client.get(uri, headers: headers).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return EndpointParameterSupport.unknown;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return EndpointParameterSupport.unknown;
      final data = decoded['data'];
      if (data is! List) return EndpointParameterSupport.unknown;

      final wanted = model.trim().toLowerCase();
      final entries = data.whereType<Map>().toList();
      final exact = entries
          .where((entry) => '${entry['id']}'.trim().toLowerCase() == wanted)
          .toList();
      // The configured model is routinely absent from the listing -- a quant
      // label like `Qwen3.8-Flash-Next-Q2` against a server that lists
      // `qwen3.8-flash-next` -- and the server accepts it anyway. Fall back to
      // the whole listing: a parameter no model on the server supports is a
      // parameter the server does not support.
      final considered = exact.isNotEmpty ? exact : entries;
      if (considered.isEmpty) return EndpointParameterSupport.unknown;

      for (final entry in considered) {
        final parameters = entry['supported_parameters'];
        // One entry without the list makes the whole listing uninformative:
        // silence about a model says nothing about the parameter.
        if (parameters is! List) return EndpointParameterSupport.unknown;
        if (parameters.any((value) => '$value'.trim() == parameter)) {
          return EndpointParameterSupport.supported;
        }
      }
      return EndpointParameterSupport.unsupported;
    } on Object {
      return EndpointParameterSupport.unknown;
    }
  }

  /// `http://host:8000/v1` -> `http://host:8000/v1/models`.
  ///
  /// Unlike llama.cpp's `/props`, this one lives under the OpenAI path prefix,
  /// so the version segment stays.
  static Uri? modelsUriFor(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
    final segments = List<String>.from(parsed.pathSegments)
      ..removeWhere((segment) => segment.isEmpty);
    if (segments.isNotEmpty && segments.last == 'models') segments.removeLast();
    return parsed.replace(
      pathSegments: <String>[...segments, 'models'],
      queryParameters: null,
      fragment: null,
    );
  }
}

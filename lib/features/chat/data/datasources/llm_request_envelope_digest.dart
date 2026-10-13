import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/message.dart';

/// Per-request digests of the parts of a request that make up its cacheable
/// prefix, so a prompt-cache break can be attributed to what changed.
///
/// LL43: two prefix breaks -- the per-minute prompt clock and mid-loop
/// tool-catalog flapping -- were found only by hand-diffing requests. With a
/// digest per part, `tool/triage_session_logs.py` names the part that changed
/// when the provider's cache-read count falls. The model id is logged in the
/// clear beside these and needs no digest.
final class LlmRequestEnvelopeDigest {
  const LlmRequestEnvelopeDigest({
    required this.config,
    required this.systemPrompt,
    required this.tools,
  });

  factory LlmRequestEnvelopeDigest.compute({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    double? temperature,
    int? maxTokens,
    Map<String, dynamic>? toolChoice,
    bool? enableThinking,
    Map<String, dynamic>? chatTemplateKwargs,
  }) {
    final systemPrompt = messages
        .where((message) => message.role == MessageRole.system)
        .map((message) => message.content)
        .join('\u0000');
    return LlmRequestEnvelopeDigest(
      config: _digest(
        _canonicalJson({
          'temperature': temperature,
          'maxTokens': maxTokens,
          'toolChoice': toolChoice,
          'enableThinking': enableThinking,
          'chatTemplateKwargs': chatTemplateKwargs,
        }),
      ),
      systemPrompt: _digest(systemPrompt),
      tools: _digest(_canonicalJson(tools ?? const [])),
    );
  }

  /// Sampling and template controls sent with the request.
  final String config;

  /// Every system-role message, in order.
  final String systemPrompt;

  /// The serialized tool catalog.
  final String tools;

  Map<String, String> toJson() => {
    'config': config,
    'systemPrompt': systemPrompt,
    'tools': tools,
  };

  /// Hex characters kept from each SHA-256; enough to tell neighbouring
  /// requests apart, short enough to keep log lines readable.
  static const digestChars = 16;

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, digestChars);

  /// JSON with map keys sorted at every depth, so equal values digest equally
  /// regardless of insertion order.
  static String _canonicalJson(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? value) => switch (value) {
    Map() => {
      for (final key
          in value.keys.map((key) => key.toString()).toList()..sort())
        key: _sorted(value[key]),
    },
    List() => value.map(_sorted).toList(growable: false),
    _ => value,
  };
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/utils/logger.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/services/qwen38_request_thinking_policy.dart';

/// Adds Qwen3.8 llama.cpp template controls without changing proxy behavior.
final class Qwen38RequestPolicyClient extends http.BaseClient {
  Qwen38RequestPolicyClient({
    required http.Client delegate,
    required Qwen38RequestThinkingPolicy policy,
  }) : _delegate = delegate,
       _policy = policy;

  final http.Client _delegate;
  final Qwen38RequestThinkingPolicy _policy;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request && _isChatCompletion(request)) {
      _applyPolicy(request);
      _logStrictToolRequest(request);
    }
    return _delegate.send(request);
  }

  bool _isChatCompletion(http.Request request) {
    final path = request.url.path.replaceFirst(RegExp(r'/+$'), '');
    return request.method == 'POST' && path.endsWith('/chat/completions');
  }

  void _applyPolicy(http.Request request) {
    final decoded = jsonDecode(request.body);
    if (decoded is! Map) return;
    final body = Map<String, dynamic>.from(decoded);
    final model = body['model'];
    if (model is! String) return;
    final overrides = _policyFor(body).resolve(
      model: model,
      maxTokens: _asInt(body['max_tokens']),
      role: ModelUsageRole.current,
    );
    if (overrides == null) return;
    request.body = jsonEncode(overrides.applyTo(body));
  }

  /// The policy for the effort this request actually carries.
  ///
  /// The configured effort is fixed at construction, but the datasource drops
  /// `reasoning_effort` when retrying after an HTTP 400. Resolving from the
  /// configured value re-sent the rejected effort inside
  /// `chat_template_kwargs`, where qwen3.8-27b-exl3's template raises
  /// `Unexpected reasoning effort high` (it accepts only low, medium and
  /// xhigh), so the retry failed identically and every turn at that effort
  /// died. Following the wire value lets the retry fall back as intended.
  Qwen38RequestThinkingPolicy _policyFor(Map<String, dynamic> body) {
    if (_policy.reasoningEffort == null) return _policy;
    final wireEffort = body['reasoning_effort'];
    return _policy.withReasoningEffort(
      wireEffort is String ? wireEffort : null,
    );
  }

  /// Records the exact post-policy control request immediately before send.
  ///
  /// Only forced control turns are expanded. Ordinary multi-tool turns keep
  /// their compact existing logs, while session JSONL retains their complete
  /// definitions. Messages and headers are deliberately excluded here.
  void _logStrictToolRequest(http.Request request) {
    final decoded = jsonDecode(request.body);
    if (decoded is! Map) return;
    final body = Map<String, dynamic>.from(decoded);
    final toolChoice = body['tool_choice'];
    if (toolChoice is! Map) return;
    final tools = body['tools'];
    if (tools is! List) return;
    final safeTools = tools
        .whereType<Map>()
        .map((tool) {
          final function = tool['function'];
          if (function is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'name': function['name'],
            'parameters': function['parameters'],
          };
        })
        .where((tool) => tool.isNotEmpty)
        .toList(growable: false);
    appLog(
      '[LLM] Strict tool request: ${jsonEncode({'model': body['model'], 'temperature': body['temperature'], 'enable_thinking': body['enable_thinking'], 'chat_template_kwargs': body['chat_template_kwargs'], 'tool_choice': toolChoice, 'tools': safeTools})}',
    );
  }

  static int? _asInt(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    _ => null,
  };

  @override
  void close() => _delegate.close();
}

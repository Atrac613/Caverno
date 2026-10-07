import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/security/llm_endpoint_transport_policy.dart';
import 'chat_datasource_client_factory.dart';

/// What an endpoint said about the reasoning efforts it was sent.
final class ReasoningEffortProbeResult {
  const ReasoningEffortProbeResult._(this.outcome, this.accepted);

  /// At least one candidate was refused with HTTP 400, so the endpoint
  /// validates the field and [accepted] is a real vocabulary.
  const ReasoningEffortProbeResult.validated(List<String> accepted)
    : this._(validatedOutcome, accepted);

  /// Every candidate was answered, which reads the same whether the endpoint
  /// accepts them all or silently ignores the field. Neither can be told apart
  /// by status alone, so nothing is claimed.
  const ReasoningEffortProbeResult.unvalidated()
    : this._(unvalidatedOutcome, null);

  /// A request failed for a reason other than the effort (transport error,
  /// timeout, a baseline that was itself refused, a router mid-switch).
  const ReasoningEffortProbeResult.inconclusive(String reason)
    : this._(reason, null);

  static const validatedOutcome = 'validated';
  static const unvalidatedOutcome = 'unvalidated';

  /// [validatedOutcome], [unvalidatedOutcome], or why the probe gave up.
  final String outcome;

  /// The candidates the endpoint accepted, in probe order. Null unless
  /// [outcome] is [validatedOutcome].
  final List<String>? accepted;

  bool get isConclusive =>
      outcome == validatedOutcome || outcome == unvalidatedOutcome;
}

/// Asks an endpoint which reasoning efforts it accepts, one candidate at a
/// time.
///
/// There is no discovery API for this: OpenAI's `/v1/models` carries no
/// capability fields, and a llama.cpp or TabbyAPI template decides its own
/// vocabulary (qwen3.8-27b-exl3 takes low, medium and xhigh, and raises on
/// `high`). So each candidate is sent the way a chat request would send it --
/// through the same client stack, which moves the effort into
/// `chat_template_kwargs` where the endpoint opts in -- and the HTTP status is
/// the whole verdict. Error text is never parsed.
///
/// A baseline without any effort goes first. If that is refused too, a 400 on
/// a candidate says nothing about the effort (an unsupported `max_tokens`
/// would look identical), so the probe stops rather than guess.
class ReasoningEffortProbe {
  const ReasoningEffortProbe({this.timeout = const Duration(seconds: 60)});

  /// Per request. Generous because a local router may have to load the model
  /// before it can answer the first one.
  final Duration timeout;

  Future<ReasoningEffortProbeResult> run({
    required String baseUrl,
    required String apiKey,
    required String model,
    required bool acceptsChatTemplateKwargs,
    required List<String> candidates,
    required http.Client client,
  }) async {
    final Uri uri;
    try {
      final validated = const LlmEndpointTransportPolicy().validate(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      uri = Uri.parse(
        '${validated.replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
      );
    } on Object catch (error) {
      return ReasoningEffortProbeResult.inconclusive(
        'invalid_endpoint_${error.runtimeType}',
      );
    }

    Future<int?> statusFor(String? effort) async {
      final wrapped =
          ChatDataSourceClientFactory.wrap(_OneTokenClient(client), (
            reasoningEffort: effort,
            enableThinking: null,
            acceptsChatTemplateKwargs: acceptsChatTemplateKwargs,
          ));
      try {
        final response = await wrapped
            .post(
              uri,
              headers: {
                ...ApiConstants.jsonRequestHeaders,
                if (apiKey.trim().isNotEmpty)
                  'Authorization': 'Bearer ${apiKey.trim()}',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'user', 'content': 'ok'},
                ],
                'max_tokens': 1,
                'stream': false,
                'reasoning_effort': ?effort,
              }),
            )
            .timeout(timeout);
        return response.statusCode;
      } on Object {
        return null;
      }
    }

    bool isSuccess(int status) => status >= 200 && status < 300;

    final baseline = await statusFor(null);
    if (baseline == null || !isSuccess(baseline)) {
      return ReasoningEffortProbeResult.inconclusive(
        'baseline_status_${baseline ?? 'error'}',
      );
    }

    final accepted = <String>[];
    var sawRejection = false;
    for (final candidate in candidates) {
      final status = await statusFor(candidate);
      if (status == null) {
        return ReasoningEffortProbeResult.inconclusive('${candidate}_error');
      }
      if (isSuccess(status)) {
        accepted.add(candidate);
      } else if (status == 400) {
        sawRejection = true;
      } else {
        return ReasoningEffortProbeResult.inconclusive(
          '${candidate}_status_$status',
        );
      }
    }
    return sawRejection
        ? ReasoningEffortProbeResult.validated(accepted)
        : const ReasoningEffortProbeResult.unvalidated();
  }
}

/// Pins `max_tokens` to 1 after the request policy has run.
///
/// The Qwen3.8 policy raises the budget to its thinking floor (1536) for
/// medium and above, which would turn every probe into a full reasoning
/// generation. The probe only needs the status, which the template decides
/// before a single token is sampled.
final class _OneTokenClient extends http.BaseClient {
  _OneTokenClient(this._delegate);

  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        request.body = jsonEncode({...decoded, 'max_tokens': 1});
      }
    }
    return _delegate.send(request);
  }
}

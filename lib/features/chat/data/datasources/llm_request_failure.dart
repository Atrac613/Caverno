import 'dart:async';
import 'dart:io';

import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:drift/native.dart' show SqliteException;
import 'package:hive/hive.dart' show HiveError;
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart';

import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../domain/services/conversation_compaction_service.dart';
import 'chat_datasource.dart';
import 'llama_cpp_slot_transport.dart';

/// Stable, provider-neutral reason an LLM turn failed.
enum LlmRequestFailureCode {
  /// Local persistence or file I/O failed; the provider was never at fault.
  localStorage,
  auth,
  permissionDenied,
  notFound,
  rateLimit,
  server,
  timeout,
  transport,
  contextOverflow,

  /// The server could not parse the model's native tool-call output; the
  /// turn can retry with embedded tool-call tags.
  toolFormatRejected,
  invalidRequest,
  invalidResponse,
  unsupportedInput,
  unsupportedLocale,
  providerUnavailable,
  cancelled,
  unknown,
}

/// A failed LLM request, captured from the exception the transport raised.
///
/// LL45: user-facing text and retry policy both derive from [code], so a
/// digit run inside an error payload can no longer pick the classification.
/// Session 7171235a showed a SQLite failure whose message embedded the
/// conversation as "Authentication failed", because the code was read back
/// out of the error text.
final class LlmRequestFailure {
  const LlmRequestFailure({
    required this.code,
    this.statusCode,
    this.retryAfter,
    this.requestId,
    this.endpointUnreachable = false,
  });

  /// Classifies [error] by its type and the structured fields it carries.
  ///
  /// Storage and local I/O failures are recognised first and never reach the
  /// provider classifier. Two provider conditions have no structured signal on
  /// OpenAI-compatible servers -- context overflow and text-only input -- so
  /// they are matched against the provider-supplied message only, never
  /// against a local exception's text.
  factory LlmRequestFailure.from(Object error) {
    if (_isLocalStorage(error)) {
      return const LlmRequestFailure(code: LlmRequestFailureCode.localStorage);
    }
    return switch (error) {
      ApiException() => _fromApi(error),
      SlotChatTransportException(:final statusCode, :final body) =>
        LlmRequestFailure(
          code: _providerMessageCode(body) ?? _codeForStatus(statusCode),
          statusCode: statusCode,
        ),
      AppleFoundationModelsException() => _fromAppleFoundationModels(error),
      StreamException(:final message, :final cause) => LlmRequestFailure(
        code: _providerMessageCode(message) ?? LlmRequestFailureCode.transport,
        endpointUnreachable: cause != null && _isUnreachable(cause),
      ),
      RequestTimeoutException() || TimeoutException() =>
        const LlmRequestFailure(code: LlmRequestFailureCode.timeout),
      _ when _isUnreachable(error) => const LlmRequestFailure(
        code: LlmRequestFailureCode.transport,
        endpointUnreachable: true,
      ),
      ConnectionException() || HttpException() => const LlmRequestFailure(
        code: LlmRequestFailureCode.transport,
      ),
      ParseException() || FormatException() => const LlmRequestFailure(
        code: LlmRequestFailureCode.invalidResponse,
      ),
      AbortedException() || ChatCompletionStreamCancelledException() =>
        const LlmRequestFailure(code: LlmRequestFailureCode.cancelled),
      // An untyped error carries no provider structure. Context overflow is
      // still recognised so the compaction retry keeps its reach; nothing
      // else is inferred from free text.
      _ when _isContextOverflowText(error.toString()) =>
        const LlmRequestFailure(code: LlmRequestFailureCode.contextOverflow),
      _ => const LlmRequestFailure(code: LlmRequestFailureCode.unknown),
    };
  }

  final LlmRequestFailureCode code;

  /// HTTP status the provider answered with, when there was a response.
  final int? statusCode;

  /// Delay the provider asked for before a retry.
  final Duration? retryAfter;

  /// Provider request id, for correlating with server-side logs.
  final String? requestId;

  /// Whether the endpoint could not be reached at all, as opposed to an
  /// ambiguous failure (timeout, a stream cut mid-answer, a 5xx). Endpoint
  /// health demotes an unreachable endpoint immediately.
  final bool endpointUnreachable;

  bool get isContextOverflow => code == LlmRequestFailureCode.contextOverflow;

  bool get isToolFormatRejected =>
      code == LlmRequestFailureCode.toolFormatRejected;

  /// Whether the failure is one an endpoint that cannot handle tool requests
  /// produces: a rejected request, an unparseable response, or a server
  /// error. The tool loop then retries the turn without tools.
  bool get mayRejectToolRequests => switch (code) {
    LlmRequestFailureCode.invalidRequest ||
    LlmRequestFailureCode.invalidResponse ||
    LlmRequestFailureCode.server => true,
    _ => false,
  };

  /// The runtime terminal classification for this failure.
  CavernoRuntimeFailureClassification get runtimeClassification =>
      switch (code) {
        LlmRequestFailureCode.localStorage =>
          const CavernoRuntimeFailureClassification(
            code: 'persistence_failed',
            exitCode: 74,
          ),
        LlmRequestFailureCode.transport ||
        LlmRequestFailureCode.timeout ||
        LlmRequestFailureCode.server =>
          const CavernoRuntimeFailureClassification(
            code: 'service_unavailable',
            exitCode: 69,
          ),
        _ => const CavernoRuntimeFailureClassification(
          code: 'turn_failed',
          exitCode: 2,
        ),
      };

  static LlmRequestFailure _fromApi(ApiException error) {
    final statusCode = error.statusCode;
    final providerCode = error.code;
    final LlmRequestFailureCode code;
    // A 429 is a rate limit whatever its message says, so the retry policy
    // keyed on it cannot be diverted by wording.
    if (statusCode == 429) {
      code = LlmRequestFailureCode.rateLimit;
    } else if (providerCode == 'context_length_exceeded') {
      code = LlmRequestFailureCode.contextOverflow;
    } else if (_providerMessageCode(error.message) case final fromMessage?) {
      code = fromMessage;
    } else if (statusCode == 400 && _isTextOnlyInputText(error.message)) {
      code = LlmRequestFailureCode.unsupportedInput;
    } else {
      code = _codeForStatus(statusCode);
    }
    return LlmRequestFailure(
      code: code,
      statusCode: statusCode,
      retryAfter: code == LlmRequestFailureCode.rateLimit
          ? _serverRequestedDelay(error)
          : null,
      requestId: error.requestId,
    );
  }

  /// The endpoint's own retry hint: the `Retry-After` header when the client
  /// parsed one, and otherwise the figure OpenAI-compatible servers put in the
  /// message body ("Please try again in 3.336s").
  static Duration? _serverRequestedDelay(ApiException error) {
    if (error case RateLimitException(retryAfter: final retryAfter?)) {
      return retryAfter;
    }
    final match = _retryHintPattern.firstMatch(error.message);
    final value = double.tryParse(match?.group(1) ?? '');
    if (match == null || value == null) return null;
    final microseconds = switch (match.group(2)!.toLowerCase()) {
      'ms' => value * Duration.microsecondsPerMillisecond,
      'm' => value * Duration.microsecondsPerMinute,
      _ => value * Duration.microsecondsPerSecond,
    };
    return Duration(microseconds: microseconds.ceil());
  }

  static final RegExp _retryHintPattern = RegExp(
    r'try again in\s+([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m)\b',
    caseSensitive: false,
  );

  /// The native bridge names the `GenerationError` case in a stable code.
  /// Builds that predate those codes send `foundation_models_error` for every
  /// case, so the provider's own text helpers remain the fallback.
  static LlmRequestFailure _fromAppleFoundationModels(
    AppleFoundationModelsException error,
  ) {
    final byCode = switch (error.code) {
      'foundation_models_context_overflow' =>
        LlmRequestFailureCode.contextOverflow,
      'foundation_models_unsupported_locale' =>
        LlmRequestFailureCode.unsupportedLocale,
      'foundation_models_rate_limited' => LlmRequestFailureCode.rateLimit,
      _ => null,
    };
    if (byCode != null) return LlmRequestFailure(code: byCode);
    if (error.isUnsupportedLanguageOrLocale) {
      return const LlmRequestFailure(
        code: LlmRequestFailureCode.unsupportedLocale,
      );
    }
    if (error.isProviderUnavailable) {
      return const LlmRequestFailure(
        code: LlmRequestFailureCode.providerUnavailable,
      );
    }
    final text = [error.message, error.details].whereType<String>().join(' ');
    return LlmRequestFailure(
      code: _isContextOverflowText(text)
          ? LlmRequestFailureCode.contextOverflow
          : LlmRequestFailureCode.unknown,
    );
  }

  static LlmRequestFailureCode _codeForStatus(int statusCode) =>
      switch (statusCode) {
        401 => LlmRequestFailureCode.auth,
        403 => LlmRequestFailureCode.permissionDenied,
        404 => LlmRequestFailureCode.notFound,
        408 => LlmRequestFailureCode.timeout,
        429 => LlmRequestFailureCode.rateLimit,
        >= 500 && < 600 => LlmRequestFailureCode.server,
        >= 400 && < 500 => LlmRequestFailureCode.invalidRequest,
        _ => LlmRequestFailureCode.unknown,
      };

  /// Connectivity failures that mean the endpoint is down or unreachable. A
  /// connection attempt that only timed out stays ambiguous.
  static bool _isUnreachable(Object error) => switch (error) {
    SocketException() || HandshakeException() || http.ClientException() => true,
    ConnectionException(:final cause) => cause is! TimeoutException,
    _ => false,
  };

  static bool _isLocalStorage(Object error) => switch (error) {
    SqliteException() ||
    DriftWrappedException() ||
    HiveError() ||
    FileSystemException() => true,
    _ => false,
  };

  /// The code a provider-supplied message states when no structured field
  /// does. Never applied to a local exception's text.
  static LlmRequestFailureCode? _providerMessageCode(String message) {
    if (_isContextOverflowText(message)) {
      return LlmRequestFailureCode.contextOverflow;
    }
    if (_nativeToolFormatPattern.hasMatch(message)) {
      return LlmRequestFailureCode.toolFormatRejected;
    }
    return null;
  }

  /// llama.cpp's PEG parser rejecting the model's native tool-call output.
  static final RegExp _nativeToolFormatPattern = RegExp(
    r'peg-native|native tool.*format',
    caseSensitive: false,
  );

  static bool _isContextOverflowText(String text) =>
      ConversationCompactionService.isContextLengthError(text);

  static final RegExp _textOnlyInputPattern = RegExp(
    r"only 'text' content type is supported",
    caseSensitive: false,
  );

  static bool _isTextOnlyInputText(String text) =>
      _textOnlyInputPattern.hasMatch(text);
}

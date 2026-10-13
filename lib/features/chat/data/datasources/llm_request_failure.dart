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
        _isContextOverflowText(body)
            ? LlmRequestFailure(
                code: LlmRequestFailureCode.contextOverflow,
                statusCode: statusCode,
              )
            : LlmRequestFailure(
                code: _codeForStatus(statusCode),
                statusCode: statusCode,
              ),
      AppleFoundationModelsException() => _fromAppleFoundationModels(error),
      StreamException(:final message) =>
        _isContextOverflowText(message)
            ? const LlmRequestFailure(
                code: LlmRequestFailureCode.contextOverflow,
              )
            : const LlmRequestFailure(code: LlmRequestFailureCode.transport),
      RequestTimeoutException() || TimeoutException() =>
        const LlmRequestFailure(code: LlmRequestFailureCode.timeout),
      ConnectionException() ||
      SocketException() ||
      HandshakeException() ||
      HttpException() ||
      http.ClientException() => const LlmRequestFailure(
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

  bool get isContextOverflow => code == LlmRequestFailureCode.contextOverflow;

  /// The runtime terminal classification for this failure, or `null` when the
  /// code does not decide one and the caller keeps its own default.
  CavernoRuntimeFailureClassification? get runtimeClassification =>
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
        _ => null,
      };

  static LlmRequestFailure _fromApi(ApiException error) {
    final statusCode = error.statusCode;
    final retryAfter = error is RateLimitException ? error.retryAfter : null;
    final providerCode = error.code;
    final LlmRequestFailureCode code;
    if (providerCode == 'context_length_exceeded' ||
        _isContextOverflowText(error.message)) {
      code = LlmRequestFailureCode.contextOverflow;
    } else if (statusCode == 400 && _isTextOnlyInputText(error.message)) {
      code = LlmRequestFailureCode.unsupportedInput;
    } else {
      code = _codeForStatus(statusCode);
    }
    return LlmRequestFailure(
      code: code,
      statusCode: statusCode,
      retryAfter: retryAfter,
      requestId: error.requestId,
    );
  }

  static LlmRequestFailure _fromAppleFoundationModels(
    AppleFoundationModelsException error,
  ) {
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
    final text = [
      error.code,
      error.message,
      error.details,
    ].whereType<String>().join(' ');
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

  static bool _isLocalStorage(Object error) => switch (error) {
    SqliteException() ||
    DriftWrappedException() ||
    HiveError() ||
    FileSystemException() => true,
    _ => false,
  };

  static bool _isContextOverflowText(String text) =>
      ConversationCompactionService.isContextLengthError(text);

  static final RegExp _textOnlyInputPattern = RegExp(
    r"only 'text' content type is supported",
    caseSensitive: false,
  );

  static bool _isTextOnlyInputText(String text) =>
      _textOnlyInputPattern.hasMatch(text);
}

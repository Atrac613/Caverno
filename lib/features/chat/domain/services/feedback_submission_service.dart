import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/constants/build_info.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../data/datasources/llm_session_log_store.dart';

class FeedbackSubmissionInput {
  const FeedbackSubmissionInput({
    required this.endpointUrl,
    required this.feedbackText,
    required this.sessionLogFile,
    required this.context,
    required this.conversationMessageCount,
  });

  final String endpointUrl;
  final String feedbackText;
  final File sessionLogFile;
  final LlmSessionLogContext context;
  final int conversationMessageCount;
}

class FeedbackSubmissionResult {
  const FeedbackSubmissionResult({
    required this.submissionId,
    required this.objectKey,
    required this.uri,
    required this.payloadBytes,
    required this.submittedBytes,
    required this.sessionLogBytes,
  });

  final String submissionId;
  final String objectKey;
  final Uri uri;
  final int payloadBytes;
  final int submittedBytes;
  final int sessionLogBytes;
}

class FeedbackSubmissionException implements Exception {
  const FeedbackSubmissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FeedbackSubmissionClient {
  Future<FeedbackSubmissionResult> submit(FeedbackSubmissionInput input);
}

class FeedbackSubmissionService implements FeedbackSubmissionClient {
  static const missingSessionLogMessage = 'Session log file does not exist.';

  FeedbackSubmissionService({
    http.Client? client,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? const Uuid().v4;

  final http.Client _client;
  final DateTime Function() _clock;
  final String Function() _idFactory;

  @override
  Future<FeedbackSubmissionResult> submit(FeedbackSubmissionInput input) async {
    final endpoint = _normalizeEndpoint(input.endpointUrl);
    if (!await input.sessionLogFile.exists()) {
      throw const FeedbackSubmissionException(missingSessionLogMessage);
    }

    final now = _clock().toUtc();
    final submissionId = _safeSegment(_idFactory(), fallback: 'feedback');
    final sessionLogContent = await input.sessionLogFile.readAsString();
    final payload = _buildPayload(
      input: input,
      submissionId: submissionId,
      now: now,
      sessionLogContent: sessionLogContent,
    );
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final bodyBytes = gzip.encode(payloadBytes);
    final response = await _client.post(
      endpoint,
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'content-encoding': 'gzip',
        'x-caverno-feedback-schema': 'caverno_feedback_submission',
        'x-caverno-feedback-id': submissionId,
      },
      body: bodyBytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason = response.body.trim();
      throw FeedbackSubmissionException(
        reason.isEmpty
            ? 'Feedback endpoint failed with HTTP ${response.statusCode}.'
            : 'Feedback endpoint failed with HTTP ${response.statusCode}: '
                  '${_truncate(reason, 300)}',
      );
    }
    final responseJson = _tryDecodeResponse(response.body);
    final objectKey =
        _responseString(responseJson, 'objectKey') ??
        _responseString(responseJson, 'key') ??
        submissionId;
    return FeedbackSubmissionResult(
      submissionId: submissionId,
      objectKey: objectKey,
      uri: endpoint,
      payloadBytes: payloadBytes.length,
      submittedBytes: bodyBytes.length,
      sessionLogBytes: utf8.encode(sessionLogContent).length,
    );
  }

  Map<String, dynamic> _buildPayload({
    required FeedbackSubmissionInput input,
    required String submissionId,
    required DateTime now,
    required String sessionLogContent,
  }) {
    final contextJson = input.context.toJson();
    return {
      'schemaName': 'caverno_feedback_submission',
      'schemaVersion': 1,
      'submissionId': submissionId,
      'timestamp': now.toIso8601String(),
      'build': BuildInfo.toJson(),
      'feedback': {'text': input.feedbackText.trim()},
      'context': contextJson,
      'conversation': {
        'workspaceMode':
            contextJson['workspaceMode'] ?? WorkspaceMode.chat.name,
        'conversationId': contextJson['conversationId'],
        'title': contextJson['sessionTitle'],
        'messageCount': input.conversationMessageCount,
      },
      'sessionLog': {
        'path': input.sessionLogFile.path,
        'byteLength': utf8.encode(sessionLogContent).length,
        'lineCount': sessionLogContent.isEmpty
            ? 0
            : sessionLogContent
                  .split('\n')
                  .where((line) => line.isNotEmpty)
                  .length,
        'content': sessionLogContent,
      },
    };
  }

  Uri _normalizeEndpoint(String endpointUrl) {
    final normalized = endpointUrl.trim();
    if (normalized.isEmpty) {
      throw const FeedbackSubmissionException(
        'Feedback endpoint URL is required.',
      );
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw FeedbackSubmissionException(
        'Invalid feedback endpoint URL: $normalized',
      );
    }
    if (uri.scheme == 'https') {
      return uri;
    }
    if (uri.scheme == 'http' && _isLoopbackHost(uri.host)) {
      return uri;
    }
    throw const FeedbackSubmissionException(
      'Feedback endpoint URL must use HTTPS.',
    );
  }

  bool _isLoopbackHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]';
  }

  String _safeSegment(String value, {required String fallback}) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    return normalized.isEmpty ? fallback : normalized;
  }

  Map<String, dynamic>? _tryDecodeResponse(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _responseString(Map<String, dynamic>? response, String key) {
    final value = response?[key];
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}

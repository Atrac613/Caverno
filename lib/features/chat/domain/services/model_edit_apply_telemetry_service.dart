import 'dart:convert';

import '../../../settings/domain/entities/app_settings.dart';
import '../entities/tool_call_info.dart';

enum ModelEditApplyOutcome {
  success,
  editMismatch,
  multipleMatches,
  malformedRequest,
  missingFile,
  otherFailure,
}

class ModelEditApplyObservation {
  const ModelEditApplyObservation({
    required this.outcome,
    required this.path,
    required this.message,
  });

  final ModelEditApplyOutcome outcome;
  final String path;
  final String message;

  bool get isFailure => outcome != ModelEditApplyOutcome.success;
}

class ModelEditApplyTelemetryService {
  ModelEditApplyTelemetryService._();

  static const attemptsKey = 'll15.editFile.attempts';
  static const successesKey = 'll15.editFile.successes';
  static const failuresKey = 'll15.editFile.failures';
  static const editMismatchFailuresKey = 'll15.editFile.failures.editMismatch';
  static const multipleMatchFailuresKey =
      'll15.editFile.failures.multipleMatches';
  static const malformedRequestFailuresKey =
      'll15.editFile.failures.malformedRequest';
  static const missingFileFailuresKey = 'll15.editFile.failures.missingFile';
  static const otherFailuresKey = 'll15.editFile.failures.other';
  static const failureRateKey = 'll15.editFile.failureRate';
  static const lastOutcomeKey = 'll15.editFile.lastOutcome';
  static const lastPathKey = 'll15.editFile.lastPath';
  static const lastObservedAtKey = 'll15.editFile.lastObservedAt';

  static ModelCapabilityProfile? recordToolResult({
    required ModelCapabilityProfile profile,
    required ToolResultInfo toolResult,
    DateTime? observedAt,
  }) {
    final observation = classifyToolResult(toolResult);
    if (observation == null) {
      return null;
    }

    final metadata = Map<String, String>.from(profile.probeMetadata);
    final attempts = _readInt(metadata[attemptsKey]) + 1;
    final successes =
        _readInt(metadata[successesKey]) + (observation.isFailure ? 0 : 1);
    final failures =
        _readInt(metadata[failuresKey]) + (observation.isFailure ? 1 : 0);

    metadata[attemptsKey] = attempts.toString();
    metadata[successesKey] = successes.toString();
    metadata[failuresKey] = failures.toString();
    metadata[failureRateKey] = (failures / attempts).toStringAsFixed(3);
    metadata[lastOutcomeKey] = observation.outcome.name;
    if (observation.path.isNotEmpty) {
      metadata[lastPathKey] = observation.path;
    } else {
      metadata.remove(lastPathKey);
    }
    metadata[lastObservedAtKey] = (observedAt ?? DateTime.now())
        .toUtc()
        .toIso8601String();

    if (observation.isFailure) {
      final key = _failureCounterKey(observation.outcome);
      metadata[key] = (_readInt(metadata[key]) + 1).toString();
    }

    return profile.copyWith(probeMetadata: metadata).normalizedForPersistence();
  }

  static ModelEditApplyObservation? classifyToolResult(
    ToolResultInfo toolResult,
  ) {
    if (toolResult.name.trim() != 'edit_file') {
      return null;
    }

    final pathFromArguments = _pathFromArguments(toolResult.arguments);
    final decoded = _decodeObject(toolResult.result);
    if (decoded != null) {
      final decodedPath = _stringValue(decoded['path']);
      final path = decodedPath.isNotEmpty ? decodedPath : pathFromArguments;
      final error = _stringValue(decoded['error']);
      if (error.isNotEmpty) {
        final code = _stringValue(decoded['code']);
        if (_isExternalDenialOrPermissionFailure('$code $error')) {
          return null;
        }
        return ModelEditApplyObservation(
          outcome: _classifyFailure(error),
          path: path,
          message: error,
        );
      }
      if (decoded.containsKey('replacements')) {
        return ModelEditApplyObservation(
          outcome: ModelEditApplyOutcome.success,
          path: path,
          message: 'edit_file applied successfully',
        );
      }
    }

    final result = toolResult.result.trim();
    if (_isExternalDenialOrPermissionFailure(result)) {
      return null;
    }
    if (result.isEmpty) {
      return ModelEditApplyObservation(
        outcome: ModelEditApplyOutcome.otherFailure,
        path: pathFromArguments,
        message: 'edit_file returned an empty result',
      );
    }
    final normalized = result.toLowerCase();
    if (normalized.contains('error:') ||
        normalized.contains('old_text') ||
        normalized.contains('file does not exist')) {
      return ModelEditApplyObservation(
        outcome: _classifyFailure(result),
        path: pathFromArguments,
        message: result,
      );
    }
    return ModelEditApplyObservation(
      outcome: ModelEditApplyOutcome.success,
      path: pathFromArguments,
      message: result,
    );
  }

  static int attempts(ModelCapabilityProfile? profile) {
    return _readInt(profile?.probeMetadata[attemptsKey]);
  }

  static double? failureRate(ModelCapabilityProfile? profile) {
    final raw = profile?.probeMetadata[failureRateKey];
    if (raw == null) {
      return null;
    }
    return double.tryParse(raw);
  }

  static String? promptFailureRateLine(ModelCapabilityProfile? profile) {
    final observedAttempts = attempts(profile);
    final rate = failureRate(profile);
    if (rate == null || observedAttempts < 2 || rate <= 0) {
      return null;
    }
    final percent = (rate * 100).toStringAsFixed(1);
    return 'Observed edit_file apply failure rate for this model: $percent% over $observedAttempts attempts. Treat exact old_text selection as high priority.';
  }

  static Map<String, dynamic>? _decodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static ModelEditApplyOutcome _classifyFailure(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('old_text was not found')) {
      return ModelEditApplyOutcome.editMismatch;
    }
    if (normalized.contains('matched multiple locations')) {
      return ModelEditApplyOutcome.multipleMatches;
    }
    if (normalized.contains('old_text must not be empty') ||
        normalized.contains('path is required')) {
      return ModelEditApplyOutcome.malformedRequest;
    }
    if (normalized.contains('file does not exist')) {
      return ModelEditApplyOutcome.missingFile;
    }
    return ModelEditApplyOutcome.otherFailure;
  }

  static String _failureCounterKey(ModelEditApplyOutcome outcome) {
    return switch (outcome) {
      ModelEditApplyOutcome.editMismatch => editMismatchFailuresKey,
      ModelEditApplyOutcome.multipleMatches => multipleMatchFailuresKey,
      ModelEditApplyOutcome.malformedRequest => malformedRequestFailuresKey,
      ModelEditApplyOutcome.missingFile => missingFileFailuresKey,
      ModelEditApplyOutcome.otherFailure => otherFailuresKey,
      ModelEditApplyOutcome.success => otherFailuresKey,
    };
  }

  static bool _isExternalDenialOrPermissionFailure(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('user denied') ||
        normalized.contains('auto-review denied') ||
        normalized.contains('approval_denied') ||
        normalized.contains('permission_denied') ||
        normalized.contains('bookmark_restore_failed') ||
        normalized.contains('access denied');
  }

  static String _pathFromArguments(Map<String, dynamic> arguments) {
    return _stringValue(arguments['path']);
  }

  static String _stringValue(Object? value) {
    return value is String ? value.trim() : '';
  }

  static int _readInt(String? value) {
    if (value == null) {
      return 0;
    }
    return int.tryParse(value) ?? 0;
  }
}

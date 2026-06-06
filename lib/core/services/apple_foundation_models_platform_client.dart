import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

class AppleFoundationModelsAvailability {
  const AppleFoundationModelsAvailability({
    required this.isAvailable,
    required this.status,
    this.reason,
  });

  final bool isAvailable;
  final String status;
  final String? reason;

  String get normalizedStatus {
    final value = status.trim();
    return value.isEmpty ? 'unknown' : value;
  }

  String? get normalizedReason {
    final value = reason?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String get logDetails {
    return 'isAvailable=$isAvailable '
        'status=$normalizedStatus '
        'reason=${normalizedReason ?? 'none'}';
  }

  factory AppleFoundationModelsAvailability.fromPlatformValue(Object? value) {
    if (value is Map) {
      final isAvailable = value['isAvailable'];
      final status = value['status'];
      final reason = value['reason'];
      if (isAvailable is bool && status is String) {
        return AppleFoundationModelsAvailability(
          isAvailable: isAvailable,
          status: status,
          reason: reason?.toString(),
        );
      }
    }
    if (value case {'isAvailable': final bool isAvailable}) {
      return AppleFoundationModelsAvailability(
        isAvailable: isAvailable,
        status: isAvailable ? 'available' : 'unavailable',
      );
    }
    return const AppleFoundationModelsAvailability(
      isAvailable: false,
      status: 'unknown',
      reason: 'unexpected_platform_response',
    );
  }
}

abstract class AppleFoundationModelsClient {
  Future<AppleFoundationModelsAvailability> checkAvailability();

  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  });
}

class MethodChannelAppleFoundationModelsClient
    implements AppleFoundationModelsClient {
  MethodChannelAppleFoundationModelsClient({
    MethodChannel channel = const MethodChannel(
      'com.caverno/apple_foundation_models',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get _isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<AppleFoundationModelsAvailability> checkAvailability() async {
    if (!_isSupportedPlatform) {
      const availability = AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: 'apple_platform_required',
      );
      _logAvailability(availability);
      return availability;
    }
    try {
      final value = await _channel.invokeMethod<Object?>('checkAvailability');
      final availability = AppleFoundationModelsAvailability.fromPlatformValue(
        value,
      );
      _logAvailability(availability);
      return availability;
    } on PlatformException catch (error) {
      final availability = AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: error.details?.toString() ?? error.message ?? error.code,
      );
      _logAvailability(availability);
      return availability;
    } on MissingPluginException catch (_) {
      const availability = AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: 'bridge_unavailable',
      );
      _logAvailability(availability);
      return availability;
    }
  }

  void _logAvailability(AppleFoundationModelsAvailability availability) {
    appLog(
      '[AppleFoundationModels] availability '
      'platform=${defaultTargetPlatform.name} '
      'isAvailable=${availability.isAvailable} '
      'status=${availability.status} '
      'reason=${availability.reason ?? 'none'}',
    );
  }

  @override
  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  }) async {
    if (!_isSupportedPlatform) {
      throw UnsupportedError(
        'Apple Foundation Models is available through the iOS and macOS runners.',
      );
    }
    try {
      final arguments = <String, Object?>{
        'instructions': instructions,
        'prompt': prompt,
      };
      if (temperature != null) {
        arguments['temperature'] = temperature;
      }
      if (maxTokens != null) {
        arguments['maxTokens'] = maxTokens;
      }
      final value = await _channel.invokeMethod<Object?>('respond', arguments);
      if (value case {'content': final String content}) {
        return content;
      }
      if (value is String) {
        return value;
      }
      throw const FormatException(
        'Apple Foundation Models returned an unexpected response.',
      );
    } on PlatformException catch (error) {
      final exception = AppleFoundationModelsException.fromPlatformException(
        error,
      );
      appLog(
        '[AppleFoundationModels] respond failed '
        'platform=${defaultTargetPlatform.name} '
        'code=${exception.code ?? 'none'} '
        'unsupportedLanguageOrLocale='
        '${exception.isUnsupportedLanguageOrLocale} '
        'message=${error.message ?? 'none'} '
        'details=${exception.details ?? 'none'}',
      );
      throw exception;
    } on MissingPluginException catch (_) {
      throw const AppleFoundationModelsException(
        'Apple Foundation Models bridge is not registered for this platform.',
        code: 'bridge_unavailable',
      );
    }
  }
}

class AppleFoundationModelsException implements Exception {
  const AppleFoundationModelsException(this.message, {this.code, this.details});

  factory AppleFoundationModelsException.unavailable(
    AppleFoundationModelsAvailability availability,
  ) {
    final status = availability.normalizedStatus;
    final reason = availability.normalizedReason;
    final detailParts = [
      'status=$status',
      if (reason != null) 'reason=$reason',
    ];
    final details = detailParts.join(' ');
    return AppleFoundationModelsException(
      'Apple Foundation Models is unavailable for generation ($details). '
      'Check Apple Intelligence, model readiness, device eligibility, and OS '
      'support, or switch to an OpenAI-compatible provider.',
      code: 'foundation_models_unavailable',
      details: details,
    );
  }

  factory AppleFoundationModelsException.fromPlatformException(
    PlatformException error,
  ) {
    final details = error.details?.toString();
    final baseMessage = error.message ?? error.code;
    return AppleFoundationModelsException(
      details == null || details.isEmpty
          ? baseMessage
          : '$baseMessage: $details',
      code: error.code,
      details: details,
    );
  }

  final String message;
  final String? code;
  final String? details;

  bool get isUnsupportedLanguageOrLocale {
    return isUnsupportedLanguageOrLocaleText(_searchableText);
  }

  bool get isProviderUnavailable {
    return code == 'foundation_models_unavailable' ||
        isProviderUnavailableText(_searchableText);
  }

  String get userFacingMessage {
    if (isUnsupportedLanguageOrLocale) {
      return 'The selected local model rejected this language or locale. Try '
          'an English prompt, reduce system/tool context, or switch to an '
          'OpenAI-compatible provider for this task.';
    }
    if (isProviderUnavailable) {
      return 'Apple Foundation Models is not ready on this device. Check '
          'Apple Intelligence, model readiness, device eligibility, and OS '
          'support, or switch to an OpenAI-compatible provider.';
    }
    return message;
  }

  String get _searchableText {
    return [code, message, details].whereType<String>().join(' ');
  }

  static bool isUnsupportedLanguageOrLocaleText(String value) {
    final haystack = value.toLowerCase();
    return haystack.contains('unsupportedlanguageorlocale') ||
        haystack.contains('unsupported language or locale') ||
        haystack.contains('unsupported language') ||
        haystack.contains('unsupported locale');
  }

  static bool isProviderUnavailableText(String value) {
    final haystack = value.toLowerCase();
    return haystack.contains('foundation_models_unavailable') ||
        haystack.contains('apple foundation models is unavailable') ||
        haystack.contains('apple foundation models is not ready') ||
        haystack.contains('apple_platform_required') ||
        haystack.contains('macos_26_required') ||
        haystack.contains('ios_26_required') ||
        haystack.contains('modelnotready') ||
        haystack.contains('appleintelligencenotenabled') ||
        haystack.contains('devicenoteligible') ||
        haystack.contains('bridge_unavailable');
  }

  @override
  String toString() => message;
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final googleChatDeliveryServiceProvider = Provider<GoogleChatDeliveryService>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleChatDeliveryService(client: client);
});

class GoogleChatDeliveryResult {
  const GoogleChatDeliveryResult({
    required this.isSuccessful,
    required this.message,
    this.deliveredAt,
  });

  final bool isSuccessful;
  final String message;
  final DateTime? deliveredAt;
}

class GoogleChatDeliveryService {
  GoogleChatDeliveryService({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  Future<GoogleChatDeliveryResult> sendMessage({
    required String webhookUrl,
    required String text,
  }) async {
    final normalizedWebhookUrl = webhookUrl.trim();
    final trimmedText = text.trim();

    if (normalizedWebhookUrl.isEmpty) {
      return const GoogleChatDeliveryResult(
        isSuccessful: false,
        message: 'Google Chat webhook URL is empty.',
      );
    }

    if (trimmedText.isEmpty) {
      return const GoogleChatDeliveryResult(
        isSuccessful: false,
        message: 'Google Chat message is empty.',
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse(normalizedWebhookUrl),
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'text': trimmedText}),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return GoogleChatDeliveryResult(
          isSuccessful: false,
          message: 'Google Chat returned HTTP ${response.statusCode}.',
        );
      }

      return GoogleChatDeliveryResult(
        isSuccessful: true,
        message: 'Posted to Google Chat.',
        deliveredAt: DateTime.now(),
      );
    } catch (error) {
      return GoogleChatDeliveryResult(
        isSuccessful: false,
        message: 'Google Chat delivery failed: $error',
      );
    }
  }
}

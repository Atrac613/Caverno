import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/core/services/google_chat_delivery_service.dart';

void main() {
  group('GoogleChatDeliveryService', () {
    test('posts text payload to the webhook', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://chat.googleapis.com/v1/spaces/test',
        );
        expect(request.headers['Content-Type'], contains('application/json'));
        expect(jsonDecode(request.body), {
          'text': 'Routine "Morning summary" completed.',
        });
        return http.Response('{}', 200);
      });

      final service = GoogleChatDeliveryService(client: client);
      final result = await service.sendMessage(
        webhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        text: 'Routine "Morning summary" completed.',
      );

      expect(result.isSuccessful, isTrue);
      expect(result.deliveredAt, isNotNull);
      expect(result.message, 'Posted to Google Chat.');
    });

    test('returns a failed result on non-2xx responses', () async {
      final client = MockClient((request) async {
        return http.Response('forbidden', 403);
      });

      final service = GoogleChatDeliveryService(client: client);
      final result = await service.sendMessage(
        webhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        text: 'Routine failed.',
      );

      expect(result.isSuccessful, isFalse);
      expect(result.deliveredAt, isNull);
      expect(result.message, 'Google Chat returned HTTP 403.');
    });

    test('returns a failed result when the request throws', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });

      final service = GoogleChatDeliveryService(client: client);
      final result = await service.sendMessage(
        webhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        text: 'Routine failed.',
      );

      expect(result.isSuccessful, isFalse);
      expect(result.deliveredAt, isNull);
      expect(result.message, contains('Google Chat delivery failed'));
    });
  });
}

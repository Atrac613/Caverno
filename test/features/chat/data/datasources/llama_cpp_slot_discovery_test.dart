import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_discovery.dart';

void main() {
  group('SlotInventory.fromJson', () {
    test('parses slot ids and processing state (bool and int forms)', () {
      final inventory = SlotInventory.fromJson([
        {'id': 0, 'state': 0},
        {'id': 1, 'state': 1},
        {'id': 2, 'is_processing': true},
      ]);

      expect(inventory.supported, isTrue);
      expect(inventory.slotCount, 3);
      expect(inventory.hasParallelSlots, isTrue);
      expect(inventory.slotIds, [0, 1, 2]);
      expect(inventory.idleSlotIds, [0]);
    });

    test('treats unknown state as available', () {
      final inventory = SlotInventory.fromJson([
        {'id': 0},
      ]);
      expect(inventory.supported, isTrue);
      expect(inventory.idleSlotIds, [0]);
      expect(inventory.hasParallelSlots, isFalse);
    });

    test('is unsupported for a non-list, empty list, or idless entries', () {
      expect(
        SlotInventory.fromJson({'error': 'slots disabled'}).supported,
        isFalse,
      );
      expect(SlotInventory.fromJson(const []).supported, isFalse);
      expect(
        SlotInventory.fromJson([
          {'state': 0},
        ]).supported,
        isFalse,
      );
    });
  });

  group('LlamaCppSlotDiscovery', () {
    test('queries /slots at the native root (strips /v1)', () async {
      late Uri requestedUri;
      final discovery = LlamaCppSlotDiscovery(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'k',
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode([
              {'id': 0, 'state': 0},
              {'id': 1, 'state': 1},
            ]),
            200,
          );
        }),
      );

      final inventory = await discovery.discover();

      expect(requestedUri.toString(), 'http://localhost:1234/slots');
      expect(inventory.supported, isTrue);
      expect(inventory.slotCount, 2);
      expect(inventory.idleSlotIds, [0]);
    });

    test('falls back to unsupported on a 501 (slots disabled)', () async {
      final discovery = LlamaCppSlotDiscovery(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: '',
        client: MockClient((request) async {
          return http.Response('not supported', 501);
        }),
      );

      final inventory = await discovery.discover();
      expect(inventory.supported, isFalse);
      expect(inventory.slotCount, 0);
    });

    test('falls back to unsupported on a network error', () async {
      final discovery = LlamaCppSlotDiscovery(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: '',
        client: MockClient((request) async {
          throw const SocketExceptionLike();
        }),
      );

      final inventory = await discovery.discover();
      expect(inventory.supported, isFalse);
    });
  });
}

/// A throwable that is not a FormatException/TimeoutException, to exercise the
/// generic catch path in [LlamaCppSlotDiscovery.discover].
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}

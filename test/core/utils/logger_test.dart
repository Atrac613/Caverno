import 'dart:convert';

import 'package:caverno/core/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts credentials before debug console output', () {
    const apiKey = 'sk-1234567890abcdefghijklmnop';
    const bearerToken = 'secret-bearer-token-123456';
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    appDebugPrint('Authorization: Bearer $bearerToken; key=$apiKey');

    expect(messages, hasLength(1));
    expect(messages.single, isNot(contains(bearerToken)));
    expect(messages.single, isNot(contains(apiKey)));
    expect(messages.single, contains('Authorization: [redacted]'));
    expect(messages.single, contains('sk-[redacted]'));
  });

  test('redacts credentials in nested and serialized diagnostics', () {
    const sessionId = 'mcp-session-secret-123';
    const nestedToken = 'nested-secret-token';
    const serializedPassword = 'serialized-password';
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    appLogDiagnostic('MCP diagnostic', {
      'mcp-session-id': sessionId,
      'headers': {'authorization': 'Bearer $nestedToken'},
      'payload': jsonEncode({'password': serializedPassword, 'safe': 'kept'}),
    });

    expect(messages, hasLength(1));
    expect(messages.single, isNot(contains(sessionId)));
    expect(messages.single, isNot(contains(nestedToken)));
    expect(messages.single, isNot(contains(serializedPassword)));
    expect(messages.single, contains('[redacted]'));
    expect(messages.single, contains('kept'));
  });

  test('fails closed at the serialized diagnostic depth limit', () {
    const deepSecret = 'deep-serialized-secret';
    Object nested = {'password': deepSecret};
    for (var depth = 0; depth < 10; depth++) {
      nested = jsonEncode({'payload': nested});
    }
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    appLogDiagnostic('Deep diagnostic', nested);

    expect(messages.single, isNot(contains(deepSecret)));
    expect(messages.single, contains('[redacted]'));
  });
}

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
}

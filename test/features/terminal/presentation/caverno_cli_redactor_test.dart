import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/terminal/presentation/caverno_cli_redactor.dart';

void main() {
  test('redacts configured and structured secret values', () {
    final redactor = CavernoCliRedactor(secrets: const ['exact-secret']);
    final safe = redactor.redact(
      'Bearer abc --api-key exact-secret password=hunter2 '
      'http://user:pass@example.test',
    );

    expect(safe, isNot(contains('exact-secret')));
    expect(safe, isNot(contains('hunter2')));
    expect(safe, isNot(contains('user:pass@')));
    expect(safe, contains(CavernoCliRedactor.redacted));
  });

  test('redacts sensitive JSON keys recursively', () {
    final safe = CavernoCliRedactor().redactJson({
      'payload': {
        'apiKey': 'secret',
        'nested': [
          {'authorization': 'Bearer token'},
        ],
      },
    });

    expect(safe.toString(), isNot(contains('secret')));
    expect(safe.toString(), isNot(contains('Bearer token')));
  });
}

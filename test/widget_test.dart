import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Translation files contain matching keys', () {
    final jaFile = File('assets/translations/ja.json');
    final enFile = File('assets/translations/en.json');

    expect(jaFile.existsSync(), isTrue, reason: 'ja.json should exist');
    expect(enFile.existsSync(), isTrue, reason: 'en.json should exist');

    final jaMap = jsonDecode(jaFile.readAsStringSync()) as Map<String, dynamic>;
    final enMap = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;

    // Flatten nested JSON keys for comparison.
    Map<String, dynamic> flatten(Map<String, dynamic> map, [String prefix = '']) {
      final result = <String, dynamic>{};
      for (final entry in map.entries) {
        final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
        if (entry.value is Map<String, dynamic>) {
          result.addAll(flatten(entry.value as Map<String, dynamic>, key));
        } else {
          result[key] = entry.value;
        }
      }
      return result;
    }

    final jaKeys = flatten(jaMap).keys.toSet();
    final enKeys = flatten(enMap).keys.toSet();

    final missingInEn = jaKeys.difference(enKeys);
    final missingInJa = enKeys.difference(jaKeys);

    expect(missingInEn, isEmpty, reason: 'Keys in ja.json but missing in en.json: $missingInEn');
    expect(missingInJa, isEmpty, reason: 'Keys in en.json but missing in ja.json: $missingInJa');
  });
}

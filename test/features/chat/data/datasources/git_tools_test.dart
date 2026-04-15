import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/git_tools.dart';

void main() {
  group('GitTools.normalizeCommand', () {
    test('strips a leading git binary prefix', () {
      expect(GitTools.normalizeCommand('git status --short'), 'status --short');
    });

    test('removes repeated git prefixes and control tokens', () {
      expect(
        GitTools.normalizeCommand(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        'commit -m "Add tokyo_weather_next_week.csv"',
      );
    });
  });

  group('GitTools.isReadOnly', () {
    test('classifies normalized prefixed commands correctly', () {
      expect(GitTools.isReadOnly('git status --short'), isTrue);
      expect(
        GitTools.isReadOnly(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        isFalse,
      );
    });
  });
}

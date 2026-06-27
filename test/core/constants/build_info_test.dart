import 'package:caverno/core/constants/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuildInfo', () {
    // These run without tool/safe-flutter's --dart-define injection, so the
    // compile-time defaults apply. This locks in the "no provenance" contract
    // that lets a log reader detect a binary not built via the standard path.
    test('defaults to unknown commit and not dirty', () {
      expect(BuildInfo.commit, 'unknown');
      expect(BuildInfo.dirty, isFalse);
      expect(BuildInfo.builtAt, 'unknown');
    });

    test('toJson always carries commit and dirty, omits unknown builtAt', () {
      final json = BuildInfo.toJson();
      expect(json['commit'], 'unknown');
      expect(json['dirty'], false);
      expect(json.containsKey('builtAt'), isFalse);
    });
  });
}

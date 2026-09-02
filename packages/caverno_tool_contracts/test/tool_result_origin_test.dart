import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ToolResultOrigin', () {
    test('wire values are the strings the analysis tooling parses', () {
      // tool/analyze_tool_results.py reads these literals. Changing one here
      // without changing it there silently empties a measurement rather than
      // failing it, which is the failure mode this whole contract exists to
      // stop.
      expect(ToolResultOrigin.jsonKey, 'result_origin');
      expect(ToolResultOrigin.harness.wireValue, 'harness');
      expect(ToolResultOrigin.refusal.wireValue, 'refusal');
    });

    test('marker spreads into a payload without disturbing its other keys', () {
      final payload = <String, Object?>{
        'ok': false,
        'code': 'example_blocked',
        ...ToolResultOrigin.refusal.marker,
        'error': 'blocked',
      };

      final decoded =
          jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
      expect(decoded['code'], 'example_blocked');
      expect(decoded['error'], 'blocked');
      expect(decoded[ToolResultOrigin.jsonKey], 'refusal');
    });

    test('an undeclared payload reads as null, not as either origin', () {
      // The point of the contract. Absence has to stay distinguishable from
      // both answers, or the reader is guessing again -- see ToolOutcome,
      // where an absent outcome means "unknown" and never "succeeded".
      expect(ToolResultOrigin.fromPayload(null), isNull);
      expect(ToolResultOrigin.fromPayload(<String, Object?>{}), isNull);
      expect(
        ToolResultOrigin.fromPayload(<String, Object?>{
          'ok': false,
          'code': 'some_code',
        }),
        isNull,
      );
    });

    test('an unrecognised or non-string declaration reads as null', () {
      for (final value in <Object?>['execution', '', 'HARNESS', 7, true]) {
        expect(
          ToolResultOrigin.fromPayload(<String, Object?>{
            ToolResultOrigin.jsonKey: value,
          }),
          isNull,
          reason: 'declared as $value',
        );
      }
    });

    test('round-trips both declared origins', () {
      for (final origin in ToolResultOrigin.values) {
        expect(ToolResultOrigin.fromPayload(origin.marker), origin);
      }
    });
  });
}

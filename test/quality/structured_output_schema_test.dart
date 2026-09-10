import 'package:caverno/features/chat/domain/services/flutter_run_issue_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strict structured output rejects a schema whose `required` omits any key in
/// `properties`, and the rejection is an opaque HTTP 400 at request time: the
/// Issue tab simply stopped analysing runs, with the reason only in the log.
/// These schemas are small and hand-written, so pin the rule where it is cheap.
void main() {
  test('every response-format schema requires all of its properties', () {
    const schemas = <String, Map<String, dynamic>>{
      'caverno_run_issue': FlutterRunIssueRequest.schema,
    };

    for (final entry in schemas.entries) {
      final properties = (entry.value['properties'] as Map).keys.toSet();
      final required = (entry.value['required'] as List).toSet();
      expect(
        required,
        equals(properties),
        reason: '${entry.key} must list every property in required',
      );
    }
  });
}

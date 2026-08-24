import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String workflow;

  setUpAll(() {
    workflow = File('.github/workflows/flutter_ci.yml').readAsStringSync();
  });

  test('pins every external action to an approved commit SHA', () {
    const approvedActions = {
      'actions/checkout': (
        sha: '3d3c42e5aac5ba805825da76410c181273ba90b1',
        version: 'v7.0.1',
      ),
      'actions/setup-java': (
        sha: 'b6effb05e454b25005698d916606bdc6ffcbf961',
        version: 'v5.7.0',
      ),
      'subosito/flutter-action': (
        sha: '1a449444c387b1966244ae4d4f8c696479add0b2',
        version: 'v2.23.0',
      ),
      'actions/upload-artifact': (
        sha: '043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
        version: 'v7.0.1',
      ),
    };
    final usesPattern = RegExp(
      r'^\s*uses:\s*([^/@\s]+/[^@\s]+)@([^\s#]+)\s+#\s+(\S+)\s*$',
      multiLine: true,
    );
    final useMatches = usesPattern.allMatches(workflow).toList();

    expect(useMatches, hasLength(10));
    for (final match in useMatches) {
      final action = match.group(1)!;
      final expected = approvedActions[action];
      expect(expected, isNotNull, reason: 'Unapproved action: $action');
      expect(match.group(2), expected!.sha, reason: action);
      expect(match.group(3), expected.version, reason: action);
      expect(match.group(2), matches(RegExp(r'^[0-9a-f]{40}$')));
    }
  });

  test('contains no mutable action tag or branch references', () {
    final useReferences = RegExp(
      r'^\s*uses:\s*\S+@([^\s#]+)',
      multiLine: true,
    ).allMatches(workflow).map((match) => match.group(1)!);

    expect(useReferences, isNotEmpty);
    for (final reference in useReferences) {
      expect(reference, matches(RegExp(r'^[0-9a-f]{40}$')));
    }
  });
}

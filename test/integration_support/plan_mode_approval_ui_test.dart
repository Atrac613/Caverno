import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_approval_ui.dart';

void main() {
  testWidgets('finds the approve FilledButton from its label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilledButton(
            onPressed: () {},
            child: const Text('Approve and start'),
          ),
        ),
      ),
    );

    final approveAction = findPlanModeApproveButtonForLabel(
      find.text('Approve and start'),
    );

    expect(approveAction, findsOneWidget);
    expect(tester.widget(approveAction), isA<FilledButton>());
  });

  testWidgets('falls back to the approve label when no button wraps it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Approve and start'))),
    );

    final approveAction = findPlanModeApproveButtonForLabel(
      find.text('Approve and start'),
    );

    expect(approveAction, findsOneWidget);
    expect(tester.widget(approveAction), isA<Text>());
  });

  testWidgets('finds the Japanese approval action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilledButton(
            onPressed: () {},
            child: const Text('\u627F\u8A8D\u3057\u3066\u958B\u59CB'),
          ),
        ),
      ),
    );

    final approveAction = findPreferredPlanModeApproveAction();

    expect(approveAction, findsOneWidget);
    expect(tester.widget(approveAction), isA<FilledButton>());
  });
}

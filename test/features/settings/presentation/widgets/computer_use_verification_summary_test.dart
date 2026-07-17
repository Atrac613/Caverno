import 'package:caverno/features/settings/presentation/widgets/computer_use_verification_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the generated time and unknown heading fallbacks', () {
    final generated = ComputerUseVerificationSummaryViewModel.fromVerification({
      'generatedAt': '2026-04-25T12:00:00Z',
    });
    final empty = ComputerUseVerificationSummaryViewModel.fromVerification({
      'generatedAt': '',
    });
    final malformed = ComputerUseVerificationSummaryViewModel.fromVerification({
      'generatedAt': 7,
    });

    expect(generated.heading, 'Last Verify: 2026-04-25T12:00:00Z');
    expect(empty.heading, 'Last Verify: ');
    expect(malformed.heading, 'Last Verify: Unknown');
  });

  test('interpolates any non-null summary before the generated time', () {
    final empty = ComputerUseVerificationSummaryViewModel.fromVerification({
      'summary': '',
      'generatedAt': 'ignored',
    });
    final numeric = ComputerUseVerificationSummaryViewModel.fromVerification({
      'summary': 7,
      'generatedAt': 'ignored',
    });
    final boolean = ComputerUseVerificationSummaryViewModel.fromVerification({
      'summary': false,
      'generatedAt': 'ignored',
    });

    expect(empty.heading, 'Last Verify: ');
    expect(numeric.heading, 'Last Verify: 7');
    expect(boolean.heading, 'Last Verify: false');
  });

  test('filters step maps and preserves labels, statuses, and order', () {
    final viewModel = ComputerUseVerificationSummaryViewModel.fromVerification({
      'steps': [
        null,
        {
          'label': 'Permissions',
          'id': 'ignored',
          'ok': true,
          'status': 'ignored',
        },
        {'id': 7, 'ok': false, 'status': 'Blocked'},
        {'ok': 'true'},
        {'label': '', 'ok': false, 'status': ''},
      ],
    });

    expect(viewModel.showSteps, isTrue);
    expect(_renderedRows(viewModel), [
      'Permissions: Done',
      '7: Blocked',
      'Step: Failed',
      ': ',
    ]);
    expect(viewModel.statusRows.map((row) => row.isPositive), [
      true,
      false,
      false,
      false,
    ]);
  });

  test('distinguishes a missing step list from an empty step section', () {
    final absent = ComputerUseVerificationSummaryViewModel.fromVerification({});
    final malformed = ComputerUseVerificationSummaryViewModel.fromVerification({
      'steps': <String, dynamic>{},
    });
    final empty = ComputerUseVerificationSummaryViewModel.fromVerification({
      'steps': <Object?>[],
    });

    expect(absent.showSteps, isFalse);
    expect(malformed.showSteps, isFalse);
    expect(empty.showSteps, isTrue);
    expect(absent.statusRows, isEmpty);
    expect(malformed.statusRows, isEmpty);
    expect(empty.statusRows, isEmpty);
  });

  test('copies nested steps into an unmodifiable presentation list', () {
    final step = <String, dynamic>{
      'label': 'Capture',
      'ok': false,
      'status': 'Blocked',
    };
    final steps = <Object?>[step];
    final source = <String, dynamic>{'summary': 'Before', 'steps': steps};
    final viewModel = ComputerUseVerificationSummaryViewModel.fromVerification(
      source,
    );

    source['summary'] = 'After';
    step
      ..['label'] = 'Changed'
      ..['ok'] = true
      ..['status'] = 'Done';
    steps
      ..clear()
      ..add({'label': 'New', 'ok': true});

    expect(viewModel.heading, 'Last Verify: Before');
    expect(_renderedRows(viewModel), ['Capture: Blocked']);
    expect(
      () => viewModel.statusRows.add(
        const ComputerUseVerificationStatusRow(
          label: 'Extra',
          isPositive: true,
          statusText: 'Done',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  testWidgets('renders ordered immutable rows with existing Material icons', (
    tester,
  ) async {
    final viewModel = ComputerUseVerificationSummaryViewModel(
      heading: 'Last Verify: complete',
      showSteps: true,
      statusRows: const [
        ComputerUseVerificationStatusRow(
          label: 'Permissions',
          isPositive: true,
          statusText: 'Done',
        ),
        ComputerUseVerificationStatusRow(
          label: 'Capture',
          isPositive: false,
          statusText: 'Blocked',
        ),
      ],
    );

    await _pumpSummary(tester, viewModel);

    expect(find.text('Last Verify: complete'), findsOneWidget);
    expect(find.text('Permissions: Done'), findsOneWidget);
    expect(find.text('Capture: Blocked'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Permissions: Done')).dx,
      lessThan(tester.getTopLeft(find.text('Capture: Blocked')).dx),
    );
  });

  testWidgets('keeps an empty list section distinct from a missing section', (
    tester,
  ) async {
    final summaryFinder = find.byType(ComputerUseVerificationSummary);

    await _pumpSummary(
      tester,
      ComputerUseVerificationSummaryViewModel(
        heading: 'Last Verify: empty',
        showSteps: true,
        statusRows: const [],
      ),
    );
    expect(
      find.descendant(of: summaryFinder, matching: find.byType(Wrap)),
      findsOneWidget,
    );

    await _pumpSummary(
      tester,
      ComputerUseVerificationSummaryViewModel(
        heading: 'Last Verify: absent',
        showSteps: false,
        statusRows: const [],
      ),
    );
    expect(
      find.descendant(of: summaryFinder, matching: find.byType(Wrap)),
      findsNothing,
    );
  });
}

List<String> _renderedRows(ComputerUseVerificationSummaryViewModel viewModel) {
  return viewModel.statusRows
      .map((row) => '${row.label}: ${row.statusText}')
      .toList(growable: false);
}

Future<void> _pumpSummary(
  WidgetTester tester,
  ComputerUseVerificationSummaryViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ComputerUseVerificationSummary(viewModel: viewModel),
      ),
    ),
  );
}

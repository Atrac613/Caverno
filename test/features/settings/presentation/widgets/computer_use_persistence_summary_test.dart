import 'package:caverno/features/settings/presentation/widgets/computer_use_persistence_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds idle and passed rows in the existing order', () {
    final viewModel = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'updatedAt': '2026-04-25T12:00:30Z',
      'activeWork': {'systemAudioRecording': false},
      'onboardingVerification': {'ok': true},
    });

    expect(viewModel.heading, 'Helper status saved: 2026-04-25T12:00:30Z');
    expect(_renderedRows(viewModel), [
      'Saved Work: Idle',
      'Saved Verify: Passed',
    ]);
    expect(viewModel.activeWorkDetail, 'Saved active work: none');
  });

  test('filters active work and preserves map insertion order', () {
    final viewModel = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'updatedAt': 'saved',
      'activeWork': {
        'systemAudioRecording': true,
        7: true,
        'ignoredFalse': false,
        'ignoredString': 'true',
      },
    });

    expect(_renderedRows(viewModel), [
      'Saved Work: Active',
      'Saved Verify: Not saved',
    ]);
    expect(
      viewModel.activeWorkDetail,
      'Saved active work: systemAudioRecording, 7',
    );
  });

  test('distinguishes absent, empty, and failed verification maps', () {
    final absent = ComputerUsePersistenceSummaryViewModel.fromPersistence({});
    final malformed = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'onboardingVerification': <Object?>[],
    });
    final empty = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'onboardingVerification': <String, dynamic>{},
    });
    final failed = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'onboardingVerification': {'ok': false},
    });

    expect(absent.statusRows.last.statusText, 'Not saved');
    expect(malformed.statusRows.last.statusText, 'Not saved');
    expect(empty.statusRows.last.statusText, 'Needs attention');
    expect(failed.statusRows.last.statusText, 'Needs attention');
  });

  test('preserves timestamp fallback and empty-string behavior', () {
    final malformed = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'updatedAt': 7,
      'activeWork': <Object?>[],
    });
    final empty = ComputerUsePersistenceSummaryViewModel.fromPersistence({
      'updatedAt': '',
    });

    expect(malformed.heading, 'Helper status saved: Unknown');
    expect(malformed.statusRows.first.statusText, 'Idle');
    expect(malformed.activeWorkDetail, 'Saved active work: none');
    expect(empty.heading, 'Helper status saved: ');
  });

  test('copies nested values into an unmodifiable presentation list', () {
    final activeWork = <Object, dynamic>{'capture': true};
    final verification = <String, dynamic>{'ok': false};
    final source = <String, dynamic>{
      'updatedAt': 'before',
      'activeWork': activeWork,
      'onboardingVerification': verification,
    };
    final viewModel = ComputerUsePersistenceSummaryViewModel.fromPersistence(
      source,
    );

    source['updatedAt'] = 'after';
    activeWork
      ..clear()
      ..['input'] = true;
    verification['ok'] = true;

    expect(viewModel.heading, 'Helper status saved: before');
    expect(_renderedRows(viewModel), [
      'Saved Work: Active',
      'Saved Verify: Needs attention',
    ]);
    expect(viewModel.activeWorkDetail, 'Saved active work: capture');
    expect(
      () => viewModel.statusRows.add(
        const ComputerUsePersistenceStatusRow(
          label: 'Extra',
          isPositive: true,
          positiveText: 'Ready',
          negativeText: 'Missing',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  testWidgets('renders immutable rows with existing Material icons', (
    tester,
  ) async {
    final viewModel = ComputerUsePersistenceSummaryViewModel(
      heading: 'Helper status saved: now',
      statusRows: const [
        ComputerUsePersistenceStatusRow(
          label: 'Saved Work',
          isPositive: true,
          positiveText: 'Idle',
          negativeText: 'Active',
        ),
        ComputerUsePersistenceStatusRow(
          label: 'Saved Verify',
          isPositive: false,
          positiveText: 'Passed',
          negativeText: 'Needs attention',
        ),
      ],
      activeWorkDetail: 'Saved active work: none',
    );

    await _pumpSummary(tester, viewModel);

    expect(find.text('Helper status saved: now'), findsOneWidget);
    expect(find.text('Saved Work: Idle'), findsOneWidget);
    expect(find.text('Saved Verify: Needs attention'), findsOneWidget);
    expect(find.text('Saved active work: none'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Saved Work: Idle')).dx,
      lessThan(
        tester.getTopLeft(find.text('Saved Verify: Needs attention')).dx,
      ),
    );
  });
}

List<String> _renderedRows(ComputerUsePersistenceSummaryViewModel viewModel) {
  return viewModel.statusRows
      .map((row) => '${row.label}: ${row.statusText}')
      .toList(growable: false);
}

Future<void> _pumpSummary(
  WidgetTester tester,
  ComputerUsePersistenceSummaryViewModel viewModel,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ComputerUsePersistenceSummary(viewModel: viewModel)),
    ),
  );
}

import 'package:caverno/core/theme/app_tokens.dart';
import 'package:caverno/features/settings/presentation/widgets/computer_use_debug_diagnostics_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('view model copies audit entries into immutable snapshots', () {
    final sourceEntry = <String, dynamic>{
      'toolName': 'computer_list_windows',
      'success': true,
    };
    final sourceEntries = <Map<String, dynamic>>[sourceEntry];
    final viewModel = ComputerUseDebugDiagnosticsViewModel(
      isBusy: false,
      auditEntries: sourceEntries,
      lastExportPath: '/tmp/diagnostics.json',
    );

    sourceEntry['toolName'] = 'changed';
    sourceEntries.add(<String, dynamic>{'toolName': 'unexpected'});

    expect(viewModel.auditEntries, hasLength(1));
    expect(viewModel.auditEntries.single['toolName'], 'computer_list_windows');
    expect(viewModel.lastExportPath, '/tmp/diagnostics.json');
    expect(
      () => viewModel.auditEntries.add(<String, dynamic>{}),
      throwsUnsupportedError,
    );
    expect(
      () => viewModel.auditEntries.single['toolName'] = 'unexpected',
      throwsUnsupportedError,
    );
  });

  testWidgets('renders ordered actions, audit snapshot, and export path', (
    tester,
  ) async {
    var smokeRuns = 0;
    var copies = 0;
    var exports = 0;
    await _pumpDiagnostics(
      tester,
      viewModel: ComputerUseDebugDiagnosticsViewModel(
        isBusy: false,
        auditEntries: List<Map<String, dynamic>>.generate(
          6,
          (index) => _auditEntry(index),
        ),
        lastExportPath: '/tmp/computer-use-diagnostics.json',
      ),
      onRunSmokeSequence: () => smokeRuns += 1,
      onCopyDiagnostics: () => copies += 1,
      onExportDiagnostics: () => exports += 1,
    );

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(
      find.text('Copy or export a redacted smoke-test snapshot for debugging.'),
      findsOneWidget,
    );
    expect(find.text('Manual Smoke Boundary'), findsOneWidget);
    expect(find.text('Run Smoke Sequence'), findsOneWidget);
    expect(find.text('Copy Diagnostics'), findsOneWidget);
    expect(find.text('Export Diagnostics'), findsOneWidget);
    expect(find.text('tool_0'), findsNothing);
    expect(find.text('tool_1'), findsOneWidget);
    expect(find.text('tool_5'), findsOneWidget);
    expect(
      find.text('Last export: /tmp/computer-use-diagnostics.json'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('computer-use-run-smoke-sequence')),
    );
    await tester.tap(
      find.byKey(const ValueKey('computer-use-copy-diagnostics')),
    );
    await tester.tap(
      find.byKey(const ValueKey('computer-use-export-diagnostics')),
    );
    await tester.pump();

    expect(smokeRuns, 1);
    expect(copies, 1);
    expect(exports, 1);
  });

  testWidgets('busy snapshot disables every action and hides null export', (
    tester,
  ) async {
    var callCount = 0;
    await _pumpDiagnostics(
      tester,
      viewModel: ComputerUseDebugDiagnosticsViewModel(
        isBusy: true,
        auditEntries: const [],
      ),
      onRunSmokeSequence: () => callCount += 1,
      onCopyDiagnostics: () => callCount += 1,
      onExportDiagnostics: () => callCount += 1,
    );

    for (final key in const [
      'computer-use-run-smoke-sequence',
      'computer-use-copy-diagnostics',
      'computer-use-export-diagnostics',
    ]) {
      final button = tester.widget<FilledButton>(
        find.byKey(ValueKey<String>(key)),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byKey(ValueKey<String>(key)));
    }
    await tester.pump();

    expect(callCount, 0);
    expect(
      find.text('No computer-use audit entries have been recorded yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('Last export:'), findsNothing);
  });

  testWidgets('result card keeps action copy and selectable monospace result', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ComputerUseDebugResultCard(
            lastAction: 'Capture display screenshot',
            lastResult: '{"ok":true}',
          ),
        ),
      ),
    );

    expect(find.text('Last Native Result'), findsOneWidget);
    expect(find.text('Capture display screenshot'), findsOneWidget);
    final result = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, '{"ok":true}'),
    );
    expect(result.style?.fontFamily, kMonoFontFamily);
  });
}

Future<void> _pumpDiagnostics(
  WidgetTester tester, {
  required ComputerUseDebugDiagnosticsViewModel viewModel,
  required VoidCallback onRunSmokeSequence,
  required VoidCallback onCopyDiagnostics,
  required VoidCallback onExportDiagnostics,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 800,
            child: ComputerUseDebugDiagnosticsCard(
              viewModel: viewModel,
              onRunSmokeSequence: onRunSmokeSequence,
              onCopyDiagnostics: onCopyDiagnostics,
              onExportDiagnostics: onExportDiagnostics,
            ),
          ),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _auditEntry(int index) => {
  'timestamp': '2026-07-18T00:00:0${index}Z',
  'toolName': 'tool_$index',
  'approvalResult': 'approved',
  'riskCategory': 'observe',
  'success': true,
  'transport': 'xpc_service',
};

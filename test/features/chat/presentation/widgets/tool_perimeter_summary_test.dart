import 'package:caverno/features/chat/presentation/widgets/tool_perimeter_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('shows the shell-execution perimeter for a local command', (
    tester,
  ) async {
    await _pump(tester, const ToolPerimeterSummary(toolName: 'local_execute_command'));
    expect(find.textContaining('shell execution'), findsOneWidget);
    expect(find.textContaining('mutates host'), findsOneWidget);
  });

  testWidgets('shows the filesystem-write perimeter for write_file', (
    tester,
  ) async {
    await _pump(tester, const ToolPerimeterSummary(toolName: 'write_file'));
    expect(find.textContaining('filesystem write'), findsOneWidget);
  });

  testWidgets('flags untrusted output for a network fetch', (tester) async {
    await _pump(tester, const ToolPerimeterSummary(toolName: 'http_get'));
    expect(find.textContaining('output: untrusted'), findsOneWidget);
  });

  testWidgets('renders read-only inspection without a risk-escalating note', (
    tester,
  ) async {
    await _pump(tester, const ToolPerimeterSummary(toolName: 'read_file'));
    expect(find.textContaining('read-only inspection'), findsOneWidget);
    expect(find.textContaining('mutates host'), findsNothing);
  });
}

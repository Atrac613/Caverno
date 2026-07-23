import 'package:caverno/core/widgets/quit_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the dialog from a live app and exposes the resolved answer.
  Future<ValueNotifier<bool?>> showDialogUnderTest(WidgetTester tester) async {
    final answer = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              answer.value = await QuitConfirmationDialog.show(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('Enter confirms the quit', (tester) async {
    final answer = await showDialogUnderTest(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(answer.value, isTrue);
    expect(find.text('Quit Caverno?'), findsNothing);
  });

  testWidgets('Escape cancels the quit', (tester) async {
    final answer = await showDialogUnderTest(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(answer.value, isFalse);
    expect(find.text('Quit Caverno?'), findsNothing);
  });

  testWidgets('Enter on the tabbed-to Cancel button cancels', (tester) async {
    final answer = await showDialogUnderTest(tester);

    // The destructive action holds initial focus, so one traversal step moves
    // to Cancel and Enter must then activate Cancel rather than the default.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(answer.value, isFalse);
  });

  testWidgets('actions advertise their shortcuts', (tester) async {
    await showDialogUnderTest(tester);

    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('⏎'), findsOneWidget);
  });
}

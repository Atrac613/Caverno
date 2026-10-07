import 'dart:async';

import 'package:caverno/core/widgets/quit_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the dialog from a live app and exposes the resolved answer.
  Future<ValueNotifier<bool?>> showDialogUnderTest(
    WidgetTester tester, {
    Future<void> Function()? onConfirmed,
    void Function(Object error)? onError,
  }) async {
    final answer = ValueNotifier<bool?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              try {
                answer.value = await QuitConfirmationDialog.show(
                  context,
                  onConfirmed: onConfirmed,
                );
              } catch (error) {
                onError?.call(error);
              }
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

  testWidgets('confirming shows progress and holds the dialog open', (
    tester,
  ) async {
    final teardown = Completer<void>();
    final answer = await showDialogUnderTest(
      tester,
      onConfirmed: () => teardown.future,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    // The wait the user reported as a freeze is now on screen, and the dialog
    // has not handed the ordinary UI back while teardown runs.
    expect(find.text('Quitting Caverno…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Quit Caverno?'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(answer.value, isNull);

    teardown.complete();
    await tester.pumpAndSettle();

    expect(answer.value, isTrue);
    expect(find.text('Quitting Caverno…'), findsNothing);
  });

  testWidgets('Escape cannot cancel a teardown already under way', (
    tester,
  ) async {
    final teardown = Completer<void>();
    final answer = await showDialogUnderTest(
      tester,
      onConfirmed: () => teardown.future,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('Quitting Caverno…'), findsOneWidget);
    expect(answer.value, isNull);

    teardown.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a teardown failure surfaces to the caller', (tester) async {
    Object? seen;
    await showDialogUnderTest(
      tester,
      onConfirmed: () async => throw StateError('close failed'),
      onError: (error) => seen = error,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(seen, isA<StateError>());
    expect(find.text('Quitting Caverno…'), findsNothing);
  });
}

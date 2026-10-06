part of 'approval_widgets_tiny_test.dart';

void _runSerialOpenApprovalSheet() {
  testWidgets('renders serial port details and approves', (tester) async {
    bool? result;
    await _pumpHarnessSerialOpenApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Serial Port'), findsOneWidget);
    expect(find.text('/dev/tty.usbserial'), findsOneWidget);
    expect(find.text('115200 baud'), findsOneWidget);

    await tester.tap(find.text('Open').last);
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('deny returns false', (tester) async {
    bool? result = true;
    await _pumpHarnessSerialOpenApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

Future<void> _pumpHarnessSerialOpenApprovalSheet(
  WidgetTester tester, {
  required ValueChanged<bool?> onResult,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(
                    await SerialOpenApprovalSheet.show(
                      context,
                      PendingSerialOpen(
                        owner: ChatTurnOwner(
                          conversationId: 'serial-test',
                          interactionGeneration: 1,
                        ),
                        id: 'serial-open-test',
                        portName: '/dev/tty.usbserial',
                        baudRate: 115200,
                        completer: Completer<bool>(),
                      ),
                    ),
                  );
                },
                child: const Text('Show Sheet'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

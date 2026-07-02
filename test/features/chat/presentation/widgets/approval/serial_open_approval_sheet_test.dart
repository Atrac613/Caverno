import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/serial_open_approval_sheet.dart';

void main() {
  testWidgets('renders serial port details and approves', (tester) async {
    bool? result;
    await _pumpHarness(tester, onResult: (approved) => result = approved);

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
    await _pumpHarness(tester, onResult: (approved) => result = approved);

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

Future<void> _pumpHarness(
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

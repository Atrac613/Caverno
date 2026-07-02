import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/ble_connect_approval_sheet.dart';

void main() {
  testWidgets('renders BLE device details and approves', (tester) async {
    bool? result;
    await _pumpHarness(tester, onResult: (approved) => result = approved);

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('BLE Connection'), findsOneWidget);
    expect(find.text('Motion Sensor'), findsOneWidget);
    expect(find.text('device-123'), findsOneWidget);

    await tester.tap(find.text('Connect'));
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
                    await BleConnectApprovalSheet.show(
                      context,
                      PendingBleConnect(
                        id: 'ble-connect-test',
                        deviceId: 'device-123',
                        deviceName: 'Motion Sensor',
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

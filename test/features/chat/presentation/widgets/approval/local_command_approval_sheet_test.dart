import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/local_command_approval_sheet.dart';

void main() {
  testWidgets('renders local command details and approves', (tester) async {
    LocalCommandApproval? result;
    await _pumpHarness(tester, onResult: (approval) => result = approval);

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Local Command Approval'), findsOneWidget);
    expect(find.text('/repo/caverno'), findsOneWidget);
    expect(find.text('Run verification'), findsOneWidget);
    expect(find.text('rm -rf build'), findsOneWidget);

    await tester.tap(find.text('Approve & Run'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.approved, isTrue);
    expect(result!.shouldRemember, isFalse);
  });

  testWidgets('always deny returns remembered deny approval', (tester) async {
    LocalCommandApproval? result = const LocalCommandApproval(approved: true);
    await _pumpHarness(tester, onResult: (approval) => result = approval);

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Always Deny'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.approved, isFalse);
    expect(result!.rememberedRuleAction, LocalCommandPermissionAction.deny);
    expect(result!.rememberedRuleMatch, LocalCommandPermissionMatch.exact);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ValueChanged<LocalCommandApproval?> onResult,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () async {
                  onResult(
                    await LocalCommandApprovalSheet.show(
                      context,
                      PendingLocalCommand(
                        id: 'local-command-test',
                        command: 'rm -rf build',
                        workingDirectory: '/repo/caverno',
                        reason: 'Run verification',
                        warningTitle: null,
                        warningMessage: null,
                        completer: Completer<LocalCommandApproval>(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

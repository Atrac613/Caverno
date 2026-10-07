part of 'approval_widgets_tiny_test.dart';

void _runGitCommandApprovalSheet() {
  testWidgets('renders git command details and approves', (tester) async {
    bool? result;
    await _pumpHarnessGitCommandApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Git Command Approval'), findsOneWidget);
    expect(find.text('/repo/caverno'), findsOneWidget);
    expect(find.text('Commit staged changes'), findsOneWidget);
    expect(find.text('git commit -m test'), findsOneWidget);

    await tester.tap(find.text('Approve & Run'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('deny returns false', (tester) async {
    bool? result = true;
    await _pumpHarnessGitCommandApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

Future<void> _pumpHarnessGitCommandApprovalSheet(
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
                    await GitCommandApprovalSheet.show(
                      context,
                      PendingGitCommand(
                        owner: ChatTurnOwner(
                          conversationId: 'git-sheet-test',
                          interactionGeneration: 1,
                        ),
                        id: 'git-command-test',
                        command: 'git commit -m test',
                        workingDirectory: '/repo/caverno',
                        reason: 'Commit staged changes',
                        completer: Completer<bool>(),
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

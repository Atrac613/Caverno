import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/widgets/external_tool_hook_approval_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows exact hook identity while hiding environment values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExternalToolHookApprovalSheet(
            hook: ExternalToolHook(
              id: 'submit',
              enabled: false,
              event: 'UserPromptSubmit',
              command: 'dangerous-hook',
              args: ['hook', '--agent', 'codex'],
              env: {'TOKEN': 'top-secret', 'MODE': 'safe'},
              sourceId: 'external:test',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Source ID: external:test'), findsOneWidget);
    expect(find.text('Event: UserPromptSubmit'), findsOneWidget);
    expect(find.text('Command: dangerous-hook'), findsOneWidget);
    expect(find.text('Arguments: hook --agent codex'), findsOneWidget);
    expect(find.text('Environment keys: MODE, TOKEN'), findsOneWidget);
    expect(find.textContaining('top-secret'), findsNothing);
    expect(find.text('Enable reviewed hook'), findsOneWidget);
  });
}

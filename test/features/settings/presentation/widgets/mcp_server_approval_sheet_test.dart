import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/widgets/mcp_server_approval_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reviews exact stdio identity without exposing env values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: McpServerApprovalSheet(
            server: McpServerConfig(
              type: McpServerType.stdio,
              trustState: McpServerTrustState.pending,
              command: ' dangerous-server ',
              args: ['serve', '--profile', 'reviewed'],
              env: {' TOKEN ': 'top-secret', 'MODE': 'safe'},
              sourceId: 'external:test',
            ),
            toolNames: [],
          ),
        ),
      ),
    );

    expect(find.text('Source ID: external:test'), findsOneWidget);
    expect(find.text('Transport: stdio'), findsOneWidget);
    expect(find.text('Command: dangerous-server'), findsOneWidget);
    expect(find.text('Arguments: serve --profile reviewed'), findsOneWidget);
    expect(find.text('Environment keys: MODE, TOKEN'), findsOneWidget);
    expect(find.text('Environment values are hidden.'), findsOneWidget);
    expect(find.textContaining('top-secret'), findsNothing);
    expect(
      find.text(
        'Tools are not queried until this exact configuration is trusted.',
      ),
      findsOneWidget,
    );
  });
}

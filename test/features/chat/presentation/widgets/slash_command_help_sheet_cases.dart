part of 'chat_presentation_widgets_tiny_test.dart';

void _runSlashCommandHelpSheet() {
  testWidgets('renders command usage and descriptions in order', (
    tester,
  ) async {
    const commands = [
      SlashCommandDefinition(
        name: 'help',
        action: SlashCommandAction.help,
        description: 'Show help',
      ),
      SlashCommandDefinition(
        name: 'goal',
        action: SlashCommandAction.goal,
        description: 'Manage a goal',
        argumentHint: '[objective]',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SlashCommandHelpSheet(
            title: 'Slash commands',
            commands: commands,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is SafeArea && widget.child is ListView,
      ),
      findsOneWidget,
    );
    expect(find.text('Slash commands'), findsOneWidget);
    expect(find.text('/help'), findsOneWidget);
    expect(find.text('Show help'), findsOneWidget);
    expect(find.text('/goal [objective]'), findsOneWidget);
    expect(find.text('Manage a goal'), findsOneWidget);
    expect(find.byIcon(Icons.terminal), findsNWidgets(2));
    expect(find.byType(Divider), findsNWidgets(2));

    final titleTop = tester.getTopLeft(find.text('Slash commands')).dy;
    final helpTop = tester.getTopLeft(find.text('/help')).dy;
    final goalTop = tester.getTopLeft(find.text('/goal [objective]')).dy;
    expect(titleTop, lessThan(helpTop));
    expect(helpTop, lessThan(goalTop));
  });
}

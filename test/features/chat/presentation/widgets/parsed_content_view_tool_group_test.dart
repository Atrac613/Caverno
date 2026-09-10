import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/presentation/widgets/parsed_content_view.dart';
import 'package:caverno/features/chat/presentation/widgets/tool_call_group.dart';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

String _call(String name, Map<String, dynamic> arguments) =>
    '<tool_use>${jsonEncode({'name': name, 'arguments': arguments})}</tool_use>\n';

Future<void> _pump(
  WidgetTester tester,
  String content, {
  bool showMemoryUpdates = false,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ParsedContentView(
                  content: content,
                  textColor: Colors.white,
                  isStreaming: false,
                  showMemoryUpdates: showMemoryUpdates,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];

  group('toolCallHeadline', () {
    test('appends the argument that names what the call acted on', () {
      expect(
        toolCallHeadline(
          const ToolCallData(
            name: 'read_file',
            arguments: {'path': 'lib/main.dart'},
          ),
        ),
        'read_file · lib/main.dart',
      );
    });

    test('prefers command over other arguments', () {
      expect(
        toolCallHeadline(
          const ToolCallData(
            name: 'execute_command',
            arguments: {
              'working_directory': '/repo',
              'command': 'flutter analyze',
            },
          ),
        ),
        'execute_command · flutter analyze',
      );
    });

    test('prefers a search pattern over the path it searches', () {
      expect(
        toolCallHeadline(
          const ToolCallData(
            name: 'grep',
            arguments: {'path': 'lib', 'pattern': 'emitRuntimeToolLifecycle'},
          ),
        ),
        'grep · emitRuntimeToolLifecycle',
      );
    });

    test('falls back to the first non-intent string argument', () {
      expect(
        toolCallHeadline(
          const ToolCallData(
            name: 'custom_tool',
            arguments: {'reason': 'because', 'target': 'thing'},
          ),
        ),
        'custom_tool · thing',
      );
    });

    test('drops the suffix when no string argument is available', () {
      expect(
        toolCallHeadline(
          const ToolCallData(name: 'list_jobs', arguments: {'limit': 5}),
        ),
        'list_jobs',
      );
    });

    test('collapses whitespace and truncates a long argument', () {
      final headline = toolCallHeadline(
        ToolCallData(
          name: 'execute_command',
          arguments: {'command': 'echo\n  ${'x' * 100}'},
        ),
      );
      expect(headline.startsWith('execute_command · echo x'), isTrue);
      expect(headline.endsWith('…'), isTrue);
      expect(headline.length, lessThan(90));
    });
  });

  testWidgets('collapses a run of tool calls behind one header', (
    tester,
  ) async {
    await _pump(
      tester,
      _call('read_file', {'path': 'lib/main.dart'}) +
          _call('read_file', {'path': 'lib/app.dart'}) +
          _call('grep', {'pattern': 'TODO'}),
    );

    expect(find.text('3 tool calls'), findsOneWidget);
    expect(find.textContaining('lib/main.dart'), findsNothing);

    await tester.tap(find.text('3 tool calls'));
    await tester.pump();

    expect(find.text('read_file · lib/main.dart'), findsOneWidget);
    expect(find.text('read_file · lib/app.dart'), findsOneWidget);
    expect(find.text('grep · TODO'), findsOneWidget);
  });

  testWidgets('reveals the raw arguments one row at a time', (tester) async {
    await _pump(
      tester,
      _call('read_file', {'path': 'lib/main.dart', 'offset': 10}) +
          _call('grep', {'pattern': 'TODO'}),
    );

    await tester.tap(find.text('2 tool calls'));
    await tester.pump();

    expect(find.textContaining('offset: 10'), findsNothing);

    await tester.tap(find.text('read_file · lib/main.dart'));
    await tester.pump();

    expect(find.textContaining('offset: 10'), findsOneWidget);
  });

  testWidgets('titles a lone call with its own headline', (tester) async {
    await _pump(tester, _call('read_file', {'path': 'lib/main.dart'}));

    expect(find.text('1 tool calls'), findsNothing);
    expect(find.text('read_file · lib/main.dart'), findsOneWidget);

    await tester.tap(find.text('read_file · lib/main.dart'));
    await tester.pump();

    expect(find.textContaining('path: lib/main.dart'), findsOneWidget);
  });

  testWidgets('starts a new group after intervening prose', (tester) async {
    await _pump(
      tester,
      '${_call('read_file', {'path': 'a.dart'})}'
      '${_call('read_file', {'path': 'b.dart'})}'
      'Now let me check the tests.\n'
      '${_call('grep', {'pattern': 'TODO'})}',
    );

    expect(find.text('2 tool calls'), findsOneWidget);
    expect(find.text('grep · TODO'), findsOneWidget);
    expect(find.text('Now let me check the tests.'), findsOneWidget);
  });

  testWidgets('does not let a hidden memory update split a run', (
    tester,
  ) async {
    await _pump(
      tester,
      _call('read_file', {'path': 'a.dart'}) +
          _call('memory_update', {'summary': 'hidden'}) +
          _call('grep', {'pattern': 'TODO'}),
    );

    expect(find.text('2 tool calls'), findsOneWidget);
    expect(find.textContaining('hidden'), findsNothing);
  });

  testWidgets('keeps thinking blocks collapsing correctly beside a group', (
    tester,
  ) async {
    await _pump(
      tester,
      '<think>Private reasoning.</think>\n'
      '${_call('read_file', {'path': 'a.dart'})}'
      '${_call('grep', {'pattern': 'TODO'})}',
    );

    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Private reasoning.'), findsNothing);
    expect(find.text('2 tool calls'), findsOneWidget);

    await tester.tap(find.text('Thinking'));
    await tester.pump();

    expect(find.text('Private reasoning.'), findsOneWidget);
    expect(find.text('2 tool calls'), findsOneWidget);
  });

  testWidgets('counts a call and its result as one operation', (tester) async {
    const result =
        '<tool_result>{"name":"list_directory","summary":"3 item(s)",'
        '"details":["[dir] lib","[file] pubspec.yaml"]}</tool_result>';
    await _pump(tester, _call('list_directory', {'path': '.'}) + result);

    // One call plus its result is one operation, so this is a lone-call group
    // titled with its own headline rather than "Ran 2 tools".
    expect(find.textContaining('tool calls'), findsNothing);
    expect(find.text('list_directory · .'), findsOneWidget);

    await tester.tap(find.text('list_directory · .'));
    await tester.pump();

    expect(find.text('3 item(s)'), findsOneWidget);
    expect(find.text('• [dir] lib'), findsOneWidget);
  });

  testWidgets('marks a failed call and counts it in the header', (
    tester,
  ) async {
    const failure =
        '<tool_result>{"name":"execute_command","status":"error",'
        '"summary":"Failed","details":["error: exit 1"]}</tool_result>';
    await _pump(
      tester,
      '${_call('read_file', {'path': 'a.dart'})}'
      '${_call('execute_command', {'command': 'flutter analyze'})}'
      '$failure',
    );

    expect(find.text('2 tool calls · 1 failed'), findsOneWidget);

    await tester.tap(find.text('2 tool calls · 1 failed'));
    await tester.pump();

    final headline = tester.widget<Text>(
      find.text('execute_command · flutter analyze'),
    );
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(headline.style?.color, theme.colorScheme.error);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });

  testWidgets('shows no check for a call whose outcome never arrived', (
    tester,
  ) async {
    await _pump(tester, _call('read_file', {'path': 'a.dart'}));

    // The native tool loop writes no <tool_result>, so the outcome is unknown.
    // Unknown must not render as success.
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets('remembers what was expanded across a rebuild', (tester) async {
    final bucket = PageStorageBucket();
    Widget host(Key key) => PageStorage(
      bucket: bucket,
      child: EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const _TestTranslationLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: ParsedContentView(
                key: key,
                content:
                    _call('read_file', {'path': 'a.dart'}) +
                    _call('grep', {'pattern': 'TODO'}),
                textColor: Colors.white,
                isStreaming: false,
                contentScopeId: 'message-1',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(const ValueKey('first')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('2 tool calls'));
    await tester.pump();
    expect(find.text('grep · TODO'), findsOneWidget);

    // A new key forces a fresh State, the way the ListView does when the
    // bubble scrolls out of view and back.
    await tester.pumpWidget(host(const ValueKey('second')));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('grep · TODO'), findsOneWidget);
  });

  testWidgets('localizes a tool name that has a display string', (
    tester,
  ) async {
    await _pump(tester, _call('calculator', {'expression': '2 + 2'}));

    expect(find.text('Calculator · 2 + 2'), findsOneWidget);
  });
}

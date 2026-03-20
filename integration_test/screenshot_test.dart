import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

/// No-op notification service that skips permission requests.
class _NoOpNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(String title, String body) async {}
}

/// Takes a screenshot via the integration test binding.
/// Uses convertFlutterSurfaceToImage to capture actual rendered pixels.
Future<void> takeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pumpAndSettle();
  await binding.convertFlutterSurfaceToImage();
  await tester.pump();
  await binding.takeScreenshot(name);
}

/// Builds mock conversations for realistic screenshots.
List<Conversation> _buildMockConversations() {
  final now = DateTime.now();

  return [
    // Main conversation with chat + tool call + thinking
    Conversation(
      id: 'conv-1',
      title: 'Flutter Performance Tips',
      messages: [
        Message(
          id: 'msg-1',
          content: 'My Flutter ListView is laggy. How can I improve performance?',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        Message(
          id: 'msg-2',
          content:
              '<think>The user is asking about Flutter ListView performance issues. '
              'I should cover the key optimization techniques: ListView.builder, '
              'const widgets, image caching, and RepaintBoundary.</think>'
              '\n## ListView Performance Optimization\n\n'
              'Here are several effective approaches:\n\n'
              '### 1. Use `ListView.builder`\n'
              'Instead of a regular `ListView`, use `ListView.builder` to '
              '**only build items visible on screen**.\n\n'
              '```dart\nListView.builder(\n'
              '  itemCount: items.length,\n'
              '  itemBuilder: (context, index) {\n'
              '    return ItemWidget(item: items[index]);\n'
              '  },\n)\n```\n\n'
              '### 2. Use `const` Constructors\n'
              'Add `const` to widgets that don\'t change to prevent unnecessary rebuilds.\n\n'
              '### 3. Optimize Images\n'
              'Use the `cached_network_image` package for caching and resize images to appropriate dimensions.',
          role: MessageRole.assistant,
          timestamp: now.subtract(const Duration(minutes: 4)),
        ),
        Message(
          id: 'msg-3',
          content: 'Is RepaintBoundary also effective?',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(minutes: 3)),
        ),
        Message(
          id: 'msg-4',
          content:
              '<tool_call>{"name":"web_search","arguments":{"query":"Flutter RepaintBoundary performance optimization"}}</tool_call>'
              '\n\nYes, `RepaintBoundary` is very effective!\n\n'
              'Flutter\'s rendering engine repaints the **entire subtree** when changes occur, '
              'but wrapping sections with `RepaintBoundary` limits the repaint scope.\n\n'
              'It\'s especially useful for:\n'
              '- Widgets containing animations\n'
              '- Frequently updating counters or timers\n'
              '- Complex custom paint operations',
          role: MessageRole.assistant,
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
      ],
      createdAt: now.subtract(const Duration(minutes: 5)),
      updatedAt: now.subtract(const Duration(minutes: 2)),
    ),

    // Previous conversations for the drawer
    Conversation(
      id: 'conv-2',
      title: 'Riverpod State Management',
      messages: [
        Message(
          id: 'msg-10',
          content: 'What are the best practices for Riverpod?',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(hours: 3)),
        ),
      ],
      createdAt: now.subtract(const Duration(hours: 3)),
      updatedAt: now.subtract(const Duration(hours: 3)),
    ),
    Conversation(
      id: 'conv-3',
      title: 'REST API Error Handling',
      messages: [
        Message(
          id: 'msg-20',
          content: 'How should I handle errors with Dio?',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(days: 1)),
        ),
      ],
      createdAt: now.subtract(const Duration(days: 1)),
      updatedAt: now.subtract(const Duration(days: 1)),
    ),
    Conversation(
      id: 'conv-4',
      title: 'CI/CD Pipeline Setup',
      messages: [
        Message(
          id: 'msg-30',
          content: 'I want to set up CI/CD for Flutter with GitHub Actions',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(days: 2)),
        ),
      ],
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
    Conversation(
      id: 'conv-5',
      title: 'SQLite Migration Strategy',
      messages: [
        Message(
          id: 'msg-40',
          content: 'How do I manage schema migrations with sqflite?',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(days: 4)),
        ),
      ],
      createdAt: now.subtract(const Duration(days: 4)),
      updatedAt: now.subtract(const Duration(days: 4)),
    ),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Store Screenshots', () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;

    setUp(() async {
      await Hive.initFlutter();
      await EasyLocalization.ensureInitialized();

      // Open fresh boxes for each test
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      conversationBox = await Hive.openBox<String>('test_conv_$timestamp');
      memoryBox = await Hive.openBox<String>('test_mem_$timestamp');
    });

    tearDown(() async {
      await conversationBox.clear();
      await memoryBox.clear();
      await conversationBox.close();
      await memoryBox.close();
    });

    /// Helper to build the app with dark theme and pre-seeded data.
    Future<Widget> buildApp({
      required List<Conversation> conversations,
    }) async {
      // Seed the Hive box
      for (final conv in conversations) {
        await conversationBox.put(conv.id, jsonEncode(conv.toJson()));
      }

      SharedPreferences.setMockInitialValues({
        'baseUrl': 'https://api.example.com/v1',
        'model': 'gpt-4o',
        'apiKey': 'sk-demo',
        'temperature': 0.7,
        'maxTokens': 4096,
        'mcpEnabled': true,
        'mcpUrl': 'http://localhost:8081',
        'ttsEnabled': true,
        'autoReadEnabled': false,
        'speechRate': 1.0,
        'assistantMode': 'general',
      });

      final prefs = await SharedPreferences.getInstance();

      return EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ja')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        child: Builder(
          builder: (context) {
            return ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                conversationBoxProvider.overrideWithValue(conversationBox),
                chatMemoryBoxProvider.overrideWithValue(memoryBox),
                notificationServiceProvider.overrideWithValue(
                  _NoOpNotificationService(),
                ),
              ],
              child: MaterialApp(
                title: 'Caverno',
                debugShowCheckedModeBanner: false,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                darkTheme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness: Brightness.dark,
                  ),
                  useMaterial3: true,
                ),
                themeMode: ThemeMode.dark,
                home: const ChatPage(),
              ),
            );
          },
        ),
      );
    }

    testWidgets('1_chat_conversation', (tester) async {
      final conversations = _buildMockConversations();
      await tester.pumpWidget(await buildApp(conversations: conversations));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await takeScreenshot(binding, tester, '1_chat_conversation');
    });

    testWidgets('2_tool_calling', (tester) async {
      final now = DateTime.now();
      final conversations = [
        Conversation(
          id: 'conv-tool',
          title: 'San Francisco Weather',
          messages: [
            Message(
              id: 't-1',
              content: 'What\'s the weather like in San Francisco this weekend?',
              role: MessageRole.user,
              timestamp: now.subtract(const Duration(minutes: 3)),
            ),
            Message(
              id: 't-2',
              content:
                  '<tool_call>{"name":"web_search","arguments":{"query":"San Francisco weekend weather forecast March 2026"}}</tool_call>'
                  '<tool_call>{"name":"get_current_datetime","arguments":{}}</tool_call>'
                  '\n\n## San Francisco Weekend Forecast\n\n'
                  '**Saturday, Mar 21** — Partly Cloudy\n'
                  '- High: 64°F / Low: 50°F\n'
                  '- Chance of rain: 10%\n\n'
                  '**Sunday, Mar 22** — Mostly Sunny\n'
                  '- High: 66°F / Low: 52°F\n'
                  '- Chance of rain: 5%\n\n'
                  'Great weekend for outdoor activities!',
              role: MessageRole.assistant,
              timestamp: now.subtract(const Duration(minutes: 2)),
            ),
            Message(
              id: 't-3',
              content: 'Best places to visit while I\'m there?',
              role: MessageRole.user,
              timestamp: now.subtract(const Duration(minutes: 1)),
            ),
            Message(
              id: 't-4',
              content:
                  '<tool_call>{"name":"web_search","arguments":{"query":"best places to visit San Francisco 2026 spring"}}</tool_call>'
                  '\n\n## Top Places to Visit\n\n'
                  'Here are some must-see spots:\n\n'
                  '1. **Golden Gate Bridge** — Iconic landmark, best viewed from Battery Spencer\n'
                  '2. **Fisherman\'s Wharf** — Seafood, sea lions, and bay cruises\n'
                  '3. **Golden Gate Park** — 1,000+ acres of gardens and museums\n'
                  '4. **Alcatraz Island** — Book ferry tickets in advance\n\n'
                  '> With 66°F and sunshine on Sunday, it\'s perfect for walking the bridge!',
              role: MessageRole.assistant,
              timestamp: now,
            ),
          ],
          createdAt: now.subtract(const Duration(minutes: 3)),
          updatedAt: now,
        ),
      ];

      await tester.pumpWidget(await buildApp(conversations: conversations));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await takeScreenshot(binding, tester, '2_tool_calling');
    });

    testWidgets('3_thinking_block', (tester) async {
      final now = DateTime.now();
      final conversations = [
        Conversation(
          id: 'conv-think',
          title: 'Quicksort Complexity',
          messages: [
            Message(
              id: 'th-1',
              content: 'Explain quicksort time complexity in simple terms',
              role: MessageRole.user,
              timestamp: now.subtract(const Duration(minutes: 2)),
            ),
            Message(
              id: 'th-2',
              content:
                  '<think>The user wants an intuitive explanation of quicksort complexity. '
                  'I should cover the difference between average and worst case, '
                  'the importance of pivot selection, and derive it from recursion depth '
                  'and partition cost.</think>'
                  '\n## Quicksort Time Complexity\n\n'
                  '### Average Case: O(n log n)\n'
                  'When the pivot splits the array roughly in half:\n'
                  '- Each level compares all elements once → **O(n)**\n'
                  '- Depth of recursion is **log n**\n'
                  '- Total: **n × log n**\n\n'
                  '### Worst Case: O(n²)\n'
                  'When the array is already sorted and you pick the first element as pivot:\n'
                  '- Only removes one element per level → depth **n**\n'
                  '- Total: **n × n = n²**\n\n'
                  '```\n'
                  'Average: [####|####]  → even split → log n levels\n'
                  'Worst:   [#|########] → skewed    → n levels\n'
                  '```\n\n'
                  '> **Fix**: Use randomized pivot selection to avoid worst-case behavior.',
              role: MessageRole.assistant,
              timestamp: now.subtract(const Duration(minutes: 1)),
            ),
          ],
          createdAt: now.subtract(const Duration(minutes: 2)),
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ];

      await tester.pumpWidget(await buildApp(conversations: conversations));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await takeScreenshot(binding, tester, '3_thinking_block');
    });

    testWidgets('4_conversation_drawer', (tester) async {
      final conversations = _buildMockConversations();
      await tester.pumpWidget(await buildApp(conversations: conversations));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Open the drawer
      final scaffoldState = tester.firstState<ScaffoldState>(
        find.byType(Scaffold),
      );
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      await takeScreenshot(binding, tester, '4_conversation_drawer');
    });

    testWidgets('5_settings_page', (tester) async {
      final conversations = _buildMockConversations();
      await tester.pumpWidget(await buildApp(conversations: conversations));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to settings
      final settingsButton = find.byIcon(Icons.settings);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      await takeScreenshot(binding, tester, '5_settings_page');
    });
  });
}

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

/// Builds mock conversations for realistic screenshots (Japanese).
List<Conversation> _buildMockConversationsJa() {
  final now = DateTime.now();

  return [
    // Main conversation with chat + tool call + thinking
    Conversation(
      id: 'conv-1-ja',
      title: 'FlutterパフォーマンスTips',
      messages: [
        Message(
          id: 'msg-1-ja',
          content: 'FlutterのListViewが重いです。パフォーマンスを改善するにはどうすればいいですか？',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        Message(
          id: 'msg-2-ja',
          content:
              '<think>ユーザーはListViewのパフォーマンスについて質問しています。'
              'ListView.builderの使用、constウィジェット、画像キャッシュ、RepaintBoundaryなどの主要なテクニックを説明します。</think>'
              '\n## ListViewのパフォーマンス最適化\n\n'
              '以下の手法が効果的です：\n\n'
              '### 1. `ListView.builder`の使用\n'
              '通常の`ListView`の代わりに`ListView.builder`を使い、'
              '**画面に表示されるアイテムのみをビルド**するようにします。\n\n'
              '```dart\nListView.builder(\n'
              '  itemCount: items.length,\n'
              '  itemBuilder: (context, index) {\n'
              '    return ItemWidget(item: items[index]);\n'
              '  },\n)\n```\n\n'
              '### 2. `const`コンストラクタの活用\n'
              '変化しないウィジェットには`const`を付け、不要な再ビルドを防ぎます。\n\n'
              '### 3. 画像の最適化\n'
              '画像キャッシュを活用し、適切なサイズにリサイズします。',
          role: MessageRole.assistant,
          timestamp: now.subtract(const Duration(minutes: 4)),
        ),
      ],
      createdAt: now.subtract(const Duration(minutes: 5)),
      updatedAt: now.subtract(const Duration(minutes: 4)),
    ),

    // Tool calling example (JA)
    Conversation(
      id: 'conv-tool-ja',
      title: 'サンフランシスコの天気',
      messages: [
        Message(
          id: 't-1-ja',
          content: '今週末のサンフランシスコの天気は？',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(minutes: 3)),
        ),
        Message(
          id: 't-2-ja',
          content:
              '<tool_call>{"name":"web_search","arguments":{"query":"サンフランシスコ 週末 天気"}}</tool_call>\n\n快晴で最高気温は19度になる予報です！',
          role: MessageRole.assistant,
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
      ],
      createdAt: now.subtract(const Duration(minutes: 3)),
      updatedAt: now.subtract(const Duration(minutes: 2)),
    ),

    // Thinking block example (JA)
    Conversation(
      id: 'conv-think-ja',
      title: 'クイックソートの計算量',
      messages: [
        Message(
          id: 'th-1-ja',
          content: 'クイックソートの計算量を分かりやすく教えて',
          role: MessageRole.user,
          timestamp: now.subtract(const Duration(minutes: 2)),
        ),
        Message(
          id: 'th-2-ja',
          content:
              '<think>クイックソートの計算量（平均・最悪ケース）と、ピボット選択の重要性を説明します。'
              '再帰の深さと分割コストの観点から導出します。</think>'
              '\n## クイックソートの計算量\n\n'
              '### 平均ケース: O(n log n)\n'
              '### 最悪ケース: O(n²)\n\n'
              'ピボットをランダムに選ぶことで、最悪ケースを回避できます。',
          role: MessageRole.assistant,
          timestamp: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      createdAt: now.subtract(const Duration(minutes: 2)),
      updatedAt: now.subtract(const Duration(minutes: 1)),
    ),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const loc = (locale: Locale('en'), suffix: '');

  group('App Store Screenshots (${loc.locale.languageCode})', () {
      late Box<String> conversationBox;
      late Box<String> memoryBox;

      setUp(() async {
        await Hive.initFlutter();
        await EasyLocalization.ensureInitialized();

        // Open fresh boxes for each test
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        conversationBox = await Hive.openBox<String>('test_conv_${loc.locale.languageCode}_$timestamp');
        memoryBox = await Hive.openBox<String>('test_mem_${loc.locale.languageCode}_$timestamp');
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
          'language': loc.locale.languageCode,
        });

        final prefs = await SharedPreferences.getInstance();

        return EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('ja')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: loc.locale,
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

      testWidgets('1_chat_conversation${loc.suffix}', (tester) async {
        final conversations = loc.locale.languageCode == 'en'
            ? _buildMockConversations()
            : _buildMockConversationsJa();
        await tester.pumpWidget(await buildApp(conversations: conversations));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await takeScreenshot(binding, tester, '1_chat_conversation${loc.suffix}');
      });

      testWidgets('2_tool_calling${loc.suffix}', (tester) async {
        final now = DateTime.now();
        final conversations = [
          Conversation(
            id: 'conv-tool',
            title: loc.locale.languageCode == 'en' ? 'San Francisco Weather' : 'サンフランシスコの天気',
            messages: [
              Message(
                id: 't-1',
                content: loc.locale.languageCode == 'en'
                    ? 'What\'s the weather like in San Francisco this weekend?'
                    : '今週末のサンフランシスコの天気は？',
                role: MessageRole.user,
                timestamp: now.subtract(const Duration(minutes: 3)),
              ),
              Message(
                id: 't-2',
                content: loc.locale.languageCode == 'en'
                    ? '<tool_call>{"name":"web_search","arguments":{"query":"San Francisco weekend weather"}}</tool_call>\n\nIt will be sunny and 66°F!'
                    : '<tool_call>{"name":"web_search","arguments":{"query":"サンフランシスコ 週末 天気"}}</tool_call>\n\n快晴で最高気温は19度になる予報です！',
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

        await takeScreenshot(binding, tester, '2_tool_calling${loc.suffix}');
      });

      testWidgets('3_thinking_block${loc.suffix}', (tester) async {
        final conversations = loc.locale.languageCode == 'en'
            ? _buildMockConversations()
            : _buildMockConversationsJa();
        await tester.pumpWidget(await buildApp(conversations: conversations));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await takeScreenshot(binding, tester, '3_thinking_block${loc.suffix}');
      });

      testWidgets('4_conversation_drawer${loc.suffix}', (tester) async {
        final conversations = loc.locale.languageCode == 'en'
            ? _buildMockConversations()
            : _buildMockConversationsJa();
        await tester.pumpWidget(await buildApp(conversations: conversations));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Open the drawer
        final scaffoldState = tester.firstState<ScaffoldState>(
          find.byType(Scaffold),
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        await takeScreenshot(binding, tester, '4_conversation_drawer${loc.suffix}');
      });

      testWidgets('5_settings_page${loc.suffix}', (tester) async {
        await tester.pumpWidget(await buildApp(conversations: []));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Navigate to settings (Using find.byTooltip to be more robust)
        final settingsButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.icon is Icon && (widget.icon as Icon).icon == Icons.settings,
        );
        await tester.tap(settingsButton.first);
        await tester.pumpAndSettle();

        await takeScreenshot(binding, tester, '5_settings_page${loc.suffix}');
      });

      testWidgets('6_voice_mode${loc.suffix}', (tester) async {
        await tester.pumpWidget(await buildApp(conversations: []));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Show voice recorder button or mock overlay
        await takeScreenshot(binding, tester, '6_voice_mode${loc.suffix}');
      });

      testWidgets('7_image_attachments${loc.suffix}', (tester) async {
        final now = DateTime.now();
        final conversations = [
          Conversation(
            id: 'conv-img',
            title: loc.locale.languageCode == 'en' ? 'Image Analysis' : '画像解析',
            messages: [
              Message(
                id: 'img-1',
                content: loc.locale.languageCode == 'en' ? 'What\'s in this photo?' : 'この写真には何が写っていますか？',
                role: MessageRole.user,
                timestamp: now.subtract(const Duration(minutes: 1)),
                imageBase64: 'dummy_base64',
                imageMimeType: 'image/png',
              ),
              Message(
                id: 'img-2',
                content: loc.locale.languageCode == 'en'
                    ? 'This is a beautiful landscape of a mountain lake.'
                    : 'これは山の中にある湖の美しい風景写真ですね。',
                role: MessageRole.assistant,
                timestamp: now,
              ),
            ],
            createdAt: now.subtract(const Duration(minutes: 1)),
            updatedAt: now,
          ),
        ];

        await tester.pumpWidget(await buildApp(conversations: conversations));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await takeScreenshot(binding, tester, '7_image_attachments${loc.suffix}');
      });
    });
}

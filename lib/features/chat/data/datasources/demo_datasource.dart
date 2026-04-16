import '../../domain/entities/message.dart';
import 'chat_datasource.dart';
import 'chat_remote_datasource.dart';

/// Simulates LLM responses locally for demo / App Store review purposes.
class DemoDataSource implements ChatDataSource {
  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final userMessage = _lastUserMessage(messages);
    final response = _selectResponse(userMessage);
    yield* _streamText(response);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final userMessage = _lastUserMessage(messages);
    final response = _selectResponse(userMessage);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return ChatCompletionResult(content: response, finishReason: 'stop');
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    yield* _streamText(
      'Here are the results I found. '
      'In demo mode, tool execution is simulated, '
      'but in normal mode the app connects to real MCP tool servers.',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return ChatCompletionResult(
      content:
          'Here are the results. In demo mode, tool results are simulated.',
      finishReason: 'stop',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return ChatCompletionResult(
      content:
          'Here are the results. In demo mode, tool results are simulated.',
      finishReason: 'stop',
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final future = createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: future,
    );
  }

  // ---------------------------------------------------------------------------
  // Response selection
  // ---------------------------------------------------------------------------

  String _lastUserMessage(List<Message> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        return messages[i].content;
      }
    }
    return '';
  }

  String _selectResponse(String userMessage) {
    final lower = userMessage.toLowerCase();

    if (_isJapanese(userMessage)) {
      return _selectJapaneseResponse(lower, userMessage);
    }

    // Greeting
    if (_matchesAny(lower, [
      'hello',
      'hi ',
      'hey',
      'good morning',
      'good afternoon',
      'good evening',
    ])) {
      return '<think>The user is greeting me. I should introduce myself and '
          'explain that I\'m running in demo mode so they understand what to '
          'expect.</think>'
          'Hello! Welcome to **Caverno** \u{1F44B}\n\n'
          'I\'m currently running in **demo mode**, which means my responses '
          'are pre-defined examples — no server connection is needed.\n\n'
          'Here\'s what you can try:\n'
          '- Ask me to write some code\n'
          '- Ask me to explain a concept\n'
          '- Try sending a message in Japanese\n\n'
          'To connect to a real AI model, go to **Settings** and configure '
          'your API endpoint, then disable demo mode.';
    }

    // Code request
    if (_matchesAny(lower, [
      'code',
      'function',
      'program',
      'flutter',
      'dart',
      'widget',
      'implement',
      'write a',
    ])) {
      return '<think>The user is asking about code. Let me show a practical '
          'Flutter example to demonstrate that Caverno renders markdown and '
          'code blocks nicely.</think>'
          'Here\'s a simple Flutter counter widget:\n\n'
          '```dart\n'
          'class CounterWidget extends StatefulWidget {\n'
          '  const CounterWidget({super.key});\n'
          '\n'
          '  @override\n'
          '  State<CounterWidget> createState() => _CounterWidgetState();\n'
          '}\n'
          '\n'
          'class _CounterWidgetState extends State<CounterWidget> {\n'
          '  int _count = 0;\n'
          '\n'
          '  @override\n'
          '  Widget build(BuildContext context) {\n'
          '    return Column(\n'
          '      mainAxisAlignment: MainAxisAlignment.center,\n'
          '      children: [\n'
          '        Text(\'Count: \$_count\', style: Theme.of(context).textTheme.headlineMedium),\n'
          '        const SizedBox(height: 16),\n'
          '        FilledButton(\n'
          '          onPressed: () => setState(() => _count++),\n'
          '          child: const Text(\'Increment\'),\n'
          '        ),\n'
          '      ],\n'
          '    );\n'
          '  }\n'
          '}\n'
          '```\n\n'
          'This demonstrates a `StatefulWidget` with local state management. '
          'In a real conversation, I can help you build more complex features!';
    }

    // Explanation
    if (_matchesAny(lower, [
      'explain',
      'what is',
      'how does',
      'why',
      'tell me about',
      'describe',
    ])) {
      return '<think>The user wants an explanation. I\'ll give a structured '
          'overview to showcase the app\'s markdown rendering.</think>'
          '## How Caverno Works\n\n'
          'Caverno is a chat client that connects to **OpenAI-compatible APIs**. '
          'Here\'s a quick overview:\n\n'
          '1. **Local or Remote LLMs** — Connect to any compatible server '
          '(LM Studio, Ollama, OpenAI, etc.)\n'
          '2. **Tool Calling (MCP)** — The app can call external tools like '
          'web search, calculators, and more via the MCP protocol\n'
          '3. **Session Memory** — Caverno remembers context across conversations, '
          'learning your preferences over time\n'
          '4. **Voice I/O** — Speak to the AI and hear responses with '
          'Whisper STT and VOICEVOX TTS integration\n'
          '5. **Multi-language** — Full support for English and Japanese\n\n'
          'To get started with a real model, open **Settings** and enter your '
          'API endpoint.';
    }

    // Math
    if (_matchesAny(lower, [
      'calculate',
      'math',
      'sum',
      'multiply',
      'divide',
      'plus',
      'minus',
    ])) {
      return '<think>The user is asking about math. I\'ll demonstrate step-by-step '
          'reasoning.</think>'
          'Here\'s an example of step-by-step problem solving:\n\n'
          '**Problem:** What is 23 \u00D7 17?\n\n'
          '**Step 1:** Break it down: 23 \u00D7 17 = 23 \u00D7 (10 + 7)\n\n'
          '**Step 2:** 23 \u00D7 10 = 230\n\n'
          '**Step 3:** 23 \u00D7 7 = 161\n\n'
          '**Step 4:** 230 + 161 = **391**\n\n'
          'In normal mode, with MCP tools enabled, I can use a calculator tool '
          'for complex computations!';
    }

    // Help
    if (_matchesAny(lower, [
      'help',
      'what can you do',
      'features',
      'capability',
    ])) {
      return 'Here\'s what **Caverno** can do:\n\n'
          '| Feature | Description |\n'
          '|---------|-------------|\n'
          '| Chat | Conversation with any OpenAI-compatible LLM |\n'
          '| Code | Syntax-highlighted code blocks with markdown |\n'
          '| Tools | Web search, datetime, memory via MCP protocol |\n'
          '| Voice | Speech-to-text input and text-to-speech output |\n'
          '| Memory | Persistent session context across conversations |\n'
          '| i18n | English and Japanese UI |\n\n'
          'You\'re currently in **demo mode**. To use the full features, '
          'configure your API server in Settings.';
    }

    // Default
    return '<think>I\'ll give a general response that showcases Caverno\'s '
        'formatting capabilities.</think>'
        'Thanks for your message! I\'m running in **demo mode** right now, '
        'so my responses are illustrative examples.\n\n'
        'Here are a few things you can try:\n'
        '- Say **"hello"** for an introduction\n'
        '- Ask me to **write code** to see code block rendering\n'
        '- Ask me to **explain** something for a structured answer\n'
        '- Type in **Japanese** to see multilingual support\n\n'
        'To connect to a real AI model, open **Settings** \u2192 **General** '
        'and configure your API endpoint.';
  }

  String _selectJapaneseResponse(String lower, String original) {
    if (_matchesAny(lower, [
      '\u3053\u3093\u306B\u3061\u306F',
      '\u3084\u3042',
      '\u304A\u306F\u3088\u3046',
      '\u306F\u3058\u3081\u307E\u3057\u3066',
    ])) {
      return '<think>\u30E6\u30FC\u30B6\u30FC\u304C\u65E5\u672C\u8A9E\u3067\u6328\u62F6\u3057\u3066\u3044\u308B\u3002'
          '\u30C7\u30E2\u30E2\u30FC\u30C9\u306E\u8AAC\u660E\u3092\u3057\u3088\u3046\u3002</think>'
          '**Caverno**\u3078\u3088\u3046\u3053\u305D\uFF01\u{1F44B}\n\n'
          '\u73FE\u5728\u300C\u30C7\u30E2\u30E2\u30FC\u30C9\u300D\u3067\u52D5\u4F5C\u3057\u3066\u3044\u307E\u3059\u3002'
          '\u30B5\u30FC\u30D0\u30FC\u63A5\u7D9A\u306A\u3057\u3067\u30A2\u30D7\u30EA\u306E\u6A5F\u80FD\u3092\u4F53\u9A13\u3067\u304D\u307E\u3059\u3002\n\n'
          '\u8A66\u3057\u3066\u307F\u3066\u304F\u3060\u3055\u3044\uFF1A\n'
          '- \u30B3\u30FC\u30C9\u3092\u66F8\u3044\u3066\u3068\u4F9D\u983C\n'
          '- \u4F55\u304B\u306E\u6982\u5FF5\u3092\u8AAC\u660E\u3057\u3066\u3068\u4F9D\u983C\n'
          '- \u82F1\u8A9E\u3067\u30E1\u30C3\u30BB\u30FC\u30B8\u3092\u9001\u4FE1\n\n'
          '\u5B9F\u969B\u306EAI\u30E2\u30C7\u30EB\u306B\u63A5\u7D9A\u3059\u308B\u306B\u306F\u3001'
          '**\u8A2D\u5B9A** > **\u4E00\u822C**\u3067API\u30A8\u30F3\u30C9\u30DD\u30A4\u30F3\u30C8\u3092'
          '\u8A2D\u5B9A\u3057\u3066\u304F\u3060\u3055\u3044\u3002';
    }

    // Default Japanese response
    return '<think>\u65E5\u672C\u8A9E\u306E\u30E1\u30C3\u30BB\u30FC\u30B8\u3092'
        '\u53D7\u3051\u53D6\u3063\u305F\u3002\u30C7\u30E2\u30E2\u30FC\u30C9\u306E'
        '\u6A5F\u80FD\u3092\u7D39\u4ECB\u3057\u3088\u3046\u3002</think>'
        '\u30E1\u30C3\u30BB\u30FC\u30B8\u3042\u308A\u304C\u3068\u3046\u3054\u3056\u3044\u307E\u3059\uFF01'
        '\u73FE\u5728\u300C**\u30C7\u30E2\u30E2\u30FC\u30C9**\u300D\u3067\u5B9F\u884C\u4E2D\u3067\u3059\u3002\n\n'
        'Caverno\u306E\u4E3B\u306A\u6A5F\u80FD\uFF1A\n'
        '- **\u30C1\u30E3\u30C3\u30C8**: OpenAI\u4E92\u63DBLLM\u3068\u4F1A\u8A71\n'
        '- **\u30C4\u30FC\u30EB**: MCP\u30D7\u30ED\u30C8\u30B3\u30EB\u3067Web\u691C\u7D22\u7B49\n'
        '- **\u97F3\u58F0**: \u97F3\u58F0\u5165\u51FA\u529B\u5BFE\u5FDC\n'
        '- **\u8A18\u61B6**: \u30BB\u30C3\u30B7\u30E7\u30F3\u9593\u306E\u30B3\u30F3\u30C6\u30AD\u30B9\u30C8\u4FDD\u6301\n\n'
        '\u5B9F\u969B\u306EAI\u3092\u4F7F\u3046\u306B\u306F\u3001**\u8A2D\u5B9A**\u3067API\u30B5\u30FC\u30D0\u30FC\u3092'
        '\u8A2D\u5B9A\u3057\u3066\u304F\u3060\u3055\u3044\u3002';
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  bool _isJapanese(String text) {
    return RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]').hasMatch(text);
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  Stream<String> _streamText(String text) async* {
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (i > 0) yield ' ';
      yield words[i];
      await Future<void>.delayed(const Duration(milliseconds: 35));
    }
  }
}

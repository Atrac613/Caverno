import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/presentation/providers/live_llm_diagnostic_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test('run persists a model capability profile from the report', () async {
    final initialSettings = AppSettings.defaults().copyWith(
      model: 'diagnostic-model',
      mcpEnabled: false,
      mcpUrl: '',
      mcpUrls: const <String>[],
      mcpServers: const <McpServerConfig>[],
    );
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        chatRemoteDataSourceProvider.overrideWithValue(
          _TextOnlyDiagnosticDataSource(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(liveLlmDiagnosticNotifierProvider.notifier).run();

    final diagnosticState = container.read(liveLlmDiagnosticNotifierProvider);
    expect(diagnosticState.isRunning, isFalse);
    expect(
      diagnosticState.report?.overallStatus,
      LiveLlmDiagnosticStatus.passed,
    );

    final settings = SettingsRepository(prefs).load();
    final profile = settings.effectiveModelCapabilityProfile;
    expect(profile, isNotNull);
    expect(profile!.model, 'diagnostic-model');
    expect(profile.toolCallStyle, ModelToolCallStyle.unknown);
    expect(
      profile.structuredOutputSupport,
      ModelStructuredOutputSupport.jsonObject,
    );
    expect(profile.probeMetadata['probe.instruction_echo.status'], 'passed');
  });
}

class _TextOnlyDiagnosticDataSource implements ChatDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final user = messages.last.content;
    if (user.contains('product_label')) {
      return ChatCompletionResult(
        content: 'ZX-900_\u03b1 2026-06-12',
        finishReason: 'stop',
      );
    }
    if (user.contains('example.test/downloads')) {
      return ChatCompletionResult(
        content:
            'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def',
        finishReason: 'stop',
      );
    }
    if (user.contains('12 GiB')) {
      return ChatCompletionResult(
        content: '12 GiB, \u00a53,980',
        finishReason: 'stop',
      );
    }
    return ChatCompletionResult(
      content:
          '{"probe":"instruction_echo","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
      finishReason: 'stop',
    );
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }
}

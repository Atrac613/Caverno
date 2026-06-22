import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/data/datasources/participant_completion_runner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';

NamedEndpoint _endpoint(String baseUrl) => NamedEndpoint(
  id: NamedEndpoint.buildId(baseUrl),
  baseUrl: baseUrl,
).normalizedForPersistence();

ConversationParticipant _participant({
  required String endpointId,
  String model = 'mesh-model',
}) => ConversationParticipant(
  id: 'participant-1',
  displayName: 'Reviewer',
  roleLabel: 'Reviewer',
  roleSystemPrompt: 'Review the answer.',
  endpointId: endpointId,
  model: model,
);

AppSettings _settings({
  required List<NamedEndpoint> endpoints,
  LlmProvider provider = LlmProvider.openAiCompatible,
}) => AppSettings.defaults().copyWith(
  llmProvider: provider,
  baseUrl: 'http://primary.example/v1',
  apiKey: 'primary-key',
  model: 'primary-model',
  namedEndpoints: endpoints,
);

Message _message(String id) => Message(
  id: id,
  content: 'Hello',
  role: MessageRole.user,
  timestamp: DateTime(2026, 6, 23, 10),
);

void main() {
  test(
    'streams participant turns through the assigned mesh endpoint',
    () async {
      final endpoint = _endpoint('http://mesh.example/v1');
      final health = EndpointHealthTracker(failureThreshold: 1);
      final builtDataSources = <_FakeChatDataSource>[];
      final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
        router: const MeshEndpointRouter(),
        health: health,
        buildEndpointDataSource: (baseUrl, apiKey) {
          final dataSource = _FakeChatDataSource(baseUrl, chunks: ['mesh']);
          builtDataSources.add(dataSource);
          return dataSource;
        },
      );
      final runner = ParticipantCompletionRunner(meshRunner: meshRunner);
      final chunks = <String>[];

      await runner.stream(
        primary: _FakeChatDataSource('primary', chunks: ['primary']),
        settings: _settings(endpoints: [endpoint]),
        request: ParticipantCompletionRequest(
          participant: _participant(endpointId: endpoint.id),
          messages: [_message('m1')],
          model: 'mesh-model',
          temperature: 0.25,
          maxTokens: 123,
        ),
        shouldContinue: () => true,
        onChunk: chunks.add,
      );

      expect(chunks, ['mesh']);
      expect(builtDataSources.single.requests.single.model, 'mesh-model');
      expect(builtDataSources.single.requests.single.temperature, 0.25);
      expect(builtDataSources.single.requests.single.maxTokens, 123);
    },
  );

  test('falls back to the primary model when a mesh stream fails', () async {
    final endpoint = _endpoint('http://mesh.example/v1');
    final health = EndpointHealthTracker(failureThreshold: 1);
    final primary = _FakeChatDataSource('primary', chunks: ['fallback']);
    final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
      router: const MeshEndpointRouter(),
      health: health,
      buildEndpointDataSource: (baseUrl, apiKey) =>
          _FakeChatDataSource(baseUrl, error: StateError('mesh stream failed')),
    );
    final runner = ParticipantCompletionRunner(meshRunner: meshRunner);
    final chunks = <String>[];

    await runner.stream(
      primary: primary,
      settings: _settings(endpoints: [endpoint]),
      request: ParticipantCompletionRequest(
        participant: _participant(endpointId: endpoint.id),
        messages: [_message('m1')],
        model: 'mesh-only-model',
        temperature: 0.25,
        maxTokens: 123,
      ),
      shouldContinue: () => true,
      onChunk: chunks.add,
    );

    expect(chunks, ['fallback']);
    expect(primary.requests.single.model, 'primary-model');
    expect(health.isUnhealthy(endpoint.id), isTrue);
  });

  test('stops forwarding chunks when the caller cancels the turn', () async {
    final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
      router: const MeshEndpointRouter(),
      health: EndpointHealthTracker(),
      buildEndpointDataSource: (baseUrl, apiKey) =>
          _FakeChatDataSource(baseUrl),
    );
    final runner = ParticipantCompletionRunner(meshRunner: meshRunner);
    final chunks = <String>[];
    var checks = 0;

    await runner.stream(
      primary: _FakeChatDataSource('primary', chunks: ['a', 'b']),
      settings: _settings(endpoints: const []),
      request: ParticipantCompletionRequest(
        participant: _participant(endpointId: ''),
        messages: [_message('m1')],
        model: 'primary-model',
        temperature: 0.25,
        maxTokens: 123,
      ),
      shouldContinue: () => checks++ == 0,
      onChunk: chunks.add,
    );

    expect(chunks, ['a']);
  });
}

class _StreamRequest {
  const _StreamRequest({
    required this.messages,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final List<Message> messages;
  final String? model;
  final double? temperature;
  final int? maxTokens;
}

class _FakeChatDataSource extends ChatDataSource {
  _FakeChatDataSource(this.name, {this.chunks = const [], this.error});

  final String name;
  final List<String> chunks;
  final Object? error;
  final List<_StreamRequest> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(
      _StreamRequest(
        messages: messages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    final streamError = error;
    if (streamError != null) {
      return Stream<String>.error(streamError);
    }
    return Stream<String>.fromIterable(chunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
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
}

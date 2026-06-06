import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/apple_foundation_models_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

void main() {
  group('AppleFoundationModelsAvailability', () {
    test('parses available payload without a reason field', () {
      final availability = AppleFoundationModelsAvailability.fromPlatformValue({
        'isAvailable': true,
        'status': 'available',
      });

      expect(availability.isAvailable, isTrue);
      expect(availability.status, 'available');
      expect(availability.reason, isNull);
    });

    test('builds unavailable generation exceptions with preflight details', () {
      final exception = AppleFoundationModelsException.unavailable(
        const AppleFoundationModelsAvailability(
          isAvailable: false,
          status: 'unavailable',
          reason: 'modelNotReady',
        ),
      );

      expect(exception.code, 'foundation_models_unavailable');
      expect(exception.details, contains('modelNotReady'));
      expect(exception.isProviderUnavailable, isTrue);
      expect(
        exception.userFacingMessage,
        contains('Apple Foundation Models is not ready'),
      );
      expect(
        AppleFoundationModelsException.isProviderUnavailableText(
          exception.toString(),
        ),
        isTrue,
      );
    });
  });

  group('MethodChannelAppleFoundationModelsClient', () {
    const channel = MethodChannel('test/apple_foundation_models');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('checks availability through the platform bridge on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return {'isAvailable': true, 'status': 'available'};
          });

      final availability = await MethodChannelAppleFoundationModelsClient(
        channel: channel,
      ).checkAvailability();

      expect(availability.isAvailable, isTrue);
      expect(calls.single.method, 'checkAvailability');
    });

    test(
      'reports unavailable before calling the bridge on other platforms',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        var bridgeWasCalled = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async {
              bridgeWasCalled = true;
              return {'isAvailable': true, 'status': 'available'};
            });

        final availability = await MethodChannelAppleFoundationModelsClient(
          channel: channel,
        ).checkAvailability();

        expect(availability.isAvailable, isFalse);
        expect(availability.reason, 'apple_platform_required');
        expect(bridgeWasCalled, isFalse);
      },
    );

    test('classifies unsupported language generation errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'respond');
            throw PlatformException(
              code: 'foundation_models_error',
              message: 'An unsupported language or locale was used.',
              details:
                  'unsupportedLanguageOrLocale(GenerationError.Context(debugDescription: "Unsupported language."))',
            );
          });

      final response = MethodChannelAppleFoundationModelsClient(
        channel: channel,
      ).respond(instructions: 'Be helpful.', prompt: 'Hello');

      await expectLater(
        response,
        throwsA(
          isA<AppleFoundationModelsException>()
              .having((error) => error.code, 'code', 'foundation_models_error')
              .having(
                (error) => error.isUnsupportedLanguageOrLocale,
                'isUnsupportedLanguageOrLocale',
                isTrue,
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('unsupportedLanguageOrLocale'),
              ),
        ),
      );
    });
  });

  group('AppleFoundationModelsDataSource', () {
    test(
      'sends system messages as instructions and chat history as prompt',
      () async {
        final client = _FakeAppleFoundationModelsClient('final answer');
        final dataSource = AppleFoundationModelsDataSource(client: client);

        final result = await dataSource.createChatCompletion(
          messages: [
            _message(
              role: MessageRole.system,
              content: 'Follow the house style.',
            ),
            _message(role: MessageRole.user, content: 'Hello'),
            _message(role: MessageRole.assistant, content: 'Hi.'),
            _message(role: MessageRole.user, content: 'Summarize the chat.'),
          ],
          temperature: 0.7,
          maxTokens: 128,
        );

        expect(result.content, 'final answer');
        expect(result.finishReason, 'stop');
        expect(client.lastInstructions, 'Follow the house style.');
        expect(client.lastPrompt, contains('Conversation so far:'));
        expect(client.lastPrompt, contains('User: Hello'));
        expect(client.lastPrompt, contains('Assistant: Hi.'));
        expect(
          client.lastPrompt,
          contains('Respond to the latest user message.'),
        );
        expect(client.lastTemperature, 0.7);
        expect(client.lastMaxTokens, 128);
      },
    );

    test(
      'streams text response with textual tool bridge instructions',
      () async {
        final client = _FakeAppleFoundationModelsClient('streamed answer');
        final dataSource = AppleFoundationModelsDataSource(client: client);

        final result = dataSource.streamChatCompletionWithTools(
          messages: [
            _message(role: MessageRole.user, content: 'Search later.'),
          ],
          tools: [
            {
              'type': 'function',
              'function': {
                'name': 'search',
                'description': 'Search the web.',
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'query': {'type': 'string', 'description': 'Search query.'},
                  },
                  'required': ['query'],
                },
              },
            },
          ],
        );

        await expectLater(
          result.stream,
          emitsInOrder(['streamed answer', emitsDone]),
        );
        final completion = await result.completion;

        expect(completion.content, 'streamed answer');
        expect(completion.hasToolCalls, isFalse);
        expect(client.lastPrompt, contains('Caverno tool bridge instructions'));
        expect(
          client.lastPrompt,
          contains('<tool_use>{"name":"tool_name","arguments"'),
        );
        expect(client.lastPrompt, contains('- search: Search the web.'));
        expect(client.lastPrompt, contains('query <string> required'));
      },
    );

    test('fails preflight before sending when the model is unavailable', () {
      final client = _UnavailableAppleFoundationModelsClient(
        const AppleFoundationModelsAvailability(
          isAvailable: false,
          status: 'unavailable',
          reason: 'appleIntelligenceNotEnabled',
        ),
      );
      final dataSource = AppleFoundationModelsDataSource(client: client);

      final response = dataSource.createChatCompletion(
        messages: [_message(role: MessageRole.user, content: 'Hello')],
      );

      expect(
        response,
        throwsA(
          isA<AppleFoundationModelsException>()
              .having(
                (error) => error.code,
                'code',
                'foundation_models_unavailable',
              )
              .having(
                (error) => error.isProviderUnavailable,
                'isProviderUnavailable',
                isTrue,
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('appleIntelligenceNotEnabled'),
              ),
        ),
      );
      expect(client.respondCallCount, 0);
    });

    test('does not retry unsupported language errors by default', () async {
      const exception = AppleFoundationModelsException(
        'An unsupported language or locale was used: unsupportedLanguageOrLocale',
        code: 'foundation_models_error',
      );
      final client = _FailingAppleFoundationModelsClient(exception);
      final dataSource = AppleFoundationModelsDataSource(client: client);

      final response = dataSource.createChatCompletion(
        messages: [_message(role: MessageRole.user, content: 'Hello')],
      );

      await expectLater(
        response,
        throwsA(
          isA<AppleFoundationModelsException>().having(
            (error) => error.isUnsupportedLanguageOrLocale,
            'isUnsupportedLanguageOrLocale',
            isTrue,
          ),
        ),
      );
      expect(client.respondCallCount, 1);
    });

    test(
      'retries unsupported language errors with a safe English prompt',
      () async {
        const exception = AppleFoundationModelsException(
          'An unsupported language or locale was used: unsupportedLanguageOrLocale',
          code: 'foundation_models_error',
        );
        final client = _SequenceAppleFoundationModelsClient([
          exception,
          'safe answer',
        ]);
        final dataSource = AppleFoundationModelsDataSource(
          client: client,
          enableSafePromptRetry: true,
        );

        final result = await dataSource.createChatCompletion(
          messages: [
            _message(role: MessageRole.system, content: 'Use the house style.'),
            _message(role: MessageRole.user, content: 'Old request.'),
            _message(role: MessageRole.assistant, content: 'Old answer.'),
            _message(role: MessageRole.user, content: 'Latest request.'),
          ],
          tools: [
            {
              'type': 'function',
              'function': {'name': 'browser_open', 'parameters': {}},
            },
          ],
          temperature: 0.2,
          maxTokens: 128,
        );

        expect(result.content, 'safe answer');
        expect(client.instructions, hasLength(2));
        expect(client.prompts, hasLength(2));
        expect(client.instructions.last, contains('Use plain English only'));
        expect(client.prompts.last, contains('Latest user request:'));
        expect(client.prompts.last, contains('Latest request.'));
        expect(client.prompts.last, isNot(contains('Old request.')));
        expect(client.prompts.last, isNot(contains('Old answer.')));
        expect(client.prompts.last, isNot(contains('Caverno tool bridge')));
        expect(client.prompts.last, contains('application tools'));
        expect(client.temperatures.last, 0.2);
        expect(client.maxTokenValues.last, 128);
      },
    );

    test('rethrows the original error when the safe retry fails', () async {
      const original = AppleFoundationModelsException(
        'An unsupported language or locale was used: unsupportedLanguageOrLocale',
        code: 'foundation_models_error',
      );
      const retry = AppleFoundationModelsException(
        'The safe retry also failed.',
        code: 'foundation_models_retry_error',
      );
      final client = _SequenceAppleFoundationModelsClient([original, retry]);
      final dataSource = AppleFoundationModelsDataSource(
        client: client,
        enableSafePromptRetry: true,
      );

      final response = dataSource.createChatCompletion(
        messages: [_message(role: MessageRole.user, content: 'Hello')],
      );

      await expectLater(
        response,
        throwsA(
          isA<AppleFoundationModelsException>()
              .having((error) => error.code, 'code', 'foundation_models_error')
              .having((error) => error.message, 'message', original.message),
        ),
      );
      expect(client.respondCallCount, 2);
    });

    test('shares tool stream failures with the completion future', () async {
      const exception = AppleFoundationModelsException(
        'Unsupported language.',
        code: 'foundation_models_error',
      );
      final client = _FailingAppleFoundationModelsClient(exception);
      final dataSource = AppleFoundationModelsDataSource(client: client);

      final result = dataSource.streamChatCompletionWithTools(
        messages: [_message(role: MessageRole.user, content: 'Diagnose it.')],
        tools: [
          {
            'type': 'function',
            'function': {'name': 'diagnose', 'parameters': <String, dynamic>{}},
          },
        ],
      );

      await expectLater(
        result.stream,
        emitsError(
          isA<AppleFoundationModelsException>().having(
            (error) => error.code,
            'code',
            'foundation_models_error',
          ),
        ),
      );
      await expectLater(
        result.completion,
        throwsA(isA<AppleFoundationModelsException>()),
      );
      expect(client.respondCallCount, 1);
    });

    test('completes tool stream and completion from one response', () async {
      final client = _FakeAppleFoundationModelsClient('single response');
      final dataSource = AppleFoundationModelsDataSource(client: client);

      final result = dataSource.streamChatCompletionWithTools(
        messages: [_message(role: MessageRole.user, content: 'Hello')],
        tools: [
          {
            'type': 'function',
            'function': {'name': 'diagnose', 'parameters': <String, dynamic>{}},
          },
        ],
      );

      await expectLater(
        result.stream,
        emitsInOrder(['single response', emitsDone]),
      );
      expect((await result.completion).content, 'single response');
      expect(client.respondCallCount, 1);
    });

    test('adds tool results as follow-up prompt content', () async {
      final client = _FakeAppleFoundationModelsClient(
        'answer from tool result',
      );
      final dataSource = AppleFoundationModelsDataSource(client: client);

      await dataSource.createChatCompletionWithToolResults(
        messages: [_message(role: MessageRole.user, content: 'Read the file.')],
        toolResults: [
          ToolResultInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: {'path': 'README.md'},
            result: 'File contents',
          ),
        ],
        assistantContent: 'I will inspect the file.',
      );

      expect(client.lastPrompt, contains('Previous assistant context:'));
      expect(client.lastPrompt, contains('Tool: read_file'));
      expect(client.lastPrompt, contains('Arguments: {path: README.md}'));
      expect(client.lastPrompt, contains('File contents'));
    });
  });
}

Message _message({required MessageRole role, required String content}) {
  return Message(
    id: '${role.name}-$content',
    role: role,
    content: content,
    timestamp: DateTime(2026),
  );
}

class _FakeAppleFoundationModelsClient implements AppleFoundationModelsClient {
  _FakeAppleFoundationModelsClient(this.response);

  final String response;
  String? lastInstructions;
  String? lastPrompt;
  double? lastTemperature;
  int? lastMaxTokens;
  int respondCallCount = 0;

  @override
  Future<AppleFoundationModelsAvailability> checkAvailability() async {
    return const AppleFoundationModelsAvailability(
      isAvailable: true,
      status: 'available',
    );
  }

  @override
  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  }) async {
    respondCallCount++;
    lastInstructions = instructions;
    lastPrompt = prompt;
    lastTemperature = temperature;
    lastMaxTokens = maxTokens;
    return response;
  }
}

class _FailingAppleFoundationModelsClient
    implements AppleFoundationModelsClient {
  _FailingAppleFoundationModelsClient(this.exception);

  final AppleFoundationModelsException exception;
  int respondCallCount = 0;

  @override
  Future<AppleFoundationModelsAvailability> checkAvailability() async {
    return const AppleFoundationModelsAvailability(
      isAvailable: true,
      status: 'available',
    );
  }

  @override
  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  }) async {
    respondCallCount++;
    throw exception;
  }
}

class _SequenceAppleFoundationModelsClient
    implements AppleFoundationModelsClient {
  _SequenceAppleFoundationModelsClient(this.responses);

  final List<Object> responses;
  final instructions = <String>[];
  final prompts = <String>[];
  final temperatures = <double?>[];
  final maxTokenValues = <int?>[];

  int get respondCallCount => prompts.length;

  @override
  Future<AppleFoundationModelsAvailability> checkAvailability() async {
    return const AppleFoundationModelsAvailability(
      isAvailable: true,
      status: 'available',
    );
  }

  @override
  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  }) async {
    this.instructions.add(instructions);
    prompts.add(prompt);
    temperatures.add(temperature);
    maxTokenValues.add(maxTokens);
    final response = responses[prompts.length - 1];
    if (response is AppleFoundationModelsException) {
      throw response;
    }
    return response as String;
  }
}

class _UnavailableAppleFoundationModelsClient
    implements AppleFoundationModelsClient {
  _UnavailableAppleFoundationModelsClient(this.availability);

  final AppleFoundationModelsAvailability availability;
  int respondCallCount = 0;

  @override
  Future<AppleFoundationModelsAvailability> checkAvailability() async {
    return availability;
  }

  @override
  Future<String> respond({
    required String instructions,
    required String prompt,
    double? temperature,
    int? maxTokens,
  }) async {
    respondCallCount++;
    return 'unexpected response';
  }
}

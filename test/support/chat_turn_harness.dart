import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

/// Shared scripted-model support for tests that drive the real `ChatNotifier`
/// and the real `CavernoExecutionRuntime`.
///
/// This reproduces neither state machine. It scripts what the model returns and
/// records what the loop asked for, which is the pair codex's own turn tests
/// rely on (`tmp/codex/codex-rs/core/tests/common/`). Before this existed the
/// capability was re-implemented per double: 36 classes implement
/// `ChatDataSource` across the suite and 26 declare their own request-capture
/// field.
///
/// Recorded prompts and tool results are test-process data. Do not write them
/// to repository files or session logs.

/// The data-source method a recorded request came from.
///
/// Kept distinct rather than collapsed, because the loop treats streaming and
/// non-streaming tool-result follow-ups differently and a test asserting on the
/// wrong one would pass for the wrong reason.
enum ChatDataSourceCall {
  streamChatCompletion,
  createChatCompletion,
  streamChatCompletionWithTools,
  streamWithToolResult,
  createChatCompletionWithToolResult,
  createChatCompletionWithToolResults,
}

/// One outbound call, captured before its response became observable.
final class RecordedChatRequest {
  RecordedChatRequest({
    required this.call,
    required this.index,
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    List<ToolResultInfo>? toolResults,
    this.assistantContent,
    this.model,
    this.temperature,
    this.maxTokens,
  }) : messages = List<Message>.unmodifiable(messages),
       tools = List<Map<String, dynamic>>.unmodifiable(
         tools ?? const <Map<String, dynamic>>[],
       ),
       toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults ?? const <ToolResultInfo>[],
       );

  final ChatDataSourceCall call;

  /// Position in the ledger, so a failure message can name the call.
  final int index;
  final List<Message> messages;
  final List<Map<String, dynamic>> tools;
  final List<ToolResultInfo> toolResults;
  final String? assistantContent;
  final String? model;
  final double? temperature;
  final int? maxTokens;

  List<String> get toolNames => [
    for (final definition in tools)
      if (definition['function'] case final Map<String, dynamic> function)
        if (function['name'] case final String name) name,
  ];

  @override
  String toString() =>
      '#$index ${call.name}(messages: ${messages.length}, '
      'tools: ${toolNames.length}, toolResults: ${toolResults.length})';
}

/// Append-only record of every outbound call, in the order the loop made them.
///
/// Nothing removes entries. A test that consumed matches would make later
/// assertions depend on earlier ones having run.
final class ChatRequestLedger {
  final List<RecordedChatRequest> _records = <RecordedChatRequest>[];

  List<RecordedChatRequest> get records =>
      List<RecordedChatRequest>.unmodifiable(_records);

  int get length => _records.length;

  List<RecordedChatRequest> callsOf(ChatDataSourceCall call) =>
      List<RecordedChatRequest>.unmodifiable(
        _records.where((record) => record.call == call),
      );

  int countOf(ChatDataSourceCall call) => callsOf(call).length;

  RecordedChatRequest _append(RecordedChatRequest Function(int index) build) {
    final record = build(_records.length);
    _records.add(record);
    return record;
  }

  @override
  String toString() => _records.map((record) => '  $record').join('\n');
}

/// One scripted model response, optionally held until [barrier] completes.
///
/// The barrier is how a test interleaves two turns deterministically: the
/// response exists but does not become observable until the test releases it.
final class ScriptedStep {
  const ScriptedStep(this.response, {this.barrier});

  final ChatCompletionResult response;
  final Future<void> Function()? barrier;

  static List<ScriptedStep> of(Iterable<ChatCompletionResult> responses) => [
    for (final response in responses) ScriptedStep(response),
  ];
}

/// A `ChatRemoteDataSource` that returns a script and records what it was asked.
///
/// Two response sequences are kept apart because the loop's first request and
/// its tool-result follow-ups are different decisions. Running past either
/// sequence yields a terminal `done`, preserving the behaviour of the private
/// doubles this replaces; [ledger] exposes exact counts so a stricter test can
/// assert the script was consumed rather than exhausted.
final class ScriptedChatDataSource extends ChatRemoteDataSource {
  ScriptedChatDataSource({
    List<ChatCompletionResult> initialResponses = const [],
    List<ChatCompletionResult> toolResultResponses = const [],
    List<ScriptedStep>? initialSteps,
    List<ScriptedStep>? toolResultSteps,
    this.beforeInitialResponse,
    this.beforeToolResultResponse,
  }) : _initialSteps = initialSteps ?? ScriptedStep.of(initialResponses),
       _toolResultSteps =
           toolResultSteps ?? ScriptedStep.of(toolResultResponses);

  final List<ScriptedStep> _initialSteps;
  final List<ScriptedStep> _toolResultSteps;

  /// Legacy index hooks, retained so the private doubles could move without
  /// rewriting their scenarios. New tests should prefer [ScriptedStep.barrier].
  final Future<void> Function(int requestIndex)? beforeInitialResponse;
  final Future<void> Function(int requestIndex)? beforeToolResultResponse;

  final ChatRequestLedger ledger = ChatRequestLedger();

  /// Tool-result batches in call order, one entry per follow-up request.
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<String>> toolResultToolNames = [];
  final List<List<Message>> streamedRequestMessages = <List<Message>>[];

  var initialRequests = 0;
  var toolResultRequests = 0;

  /// Ambient compatibility reads stay poisoned: an owner-scoped turn must not
  /// consult shared completion state.
  var finishReasonReads = 0;
  var usageReads = 0;
  TokenUsage _compatibilityUsage = TokenUsage.zero;

  @override
  String? get lastFinishReason {
    finishReasonReads += 1;
    throw StateError('Shared completion finish reason was read.');
  }

  @override
  TokenUsage get lastUsage {
    usageReads += 1;
    throw StateError('Shared completion token usage was read.');
  }

  @override
  set lastUsage(TokenUsage value) {
    _compatibilityUsage = value;
  }

  Iterable<Map<String, dynamic>> get decodedToolResults sync* {
    for (final result in toolResultBatches.expand((batch) => batch)) {
      final decoded = jsonDecode(result.result);
      if (decoded is Map<String, dynamic>) {
        yield decoded;
      }
    }
  }

  /// Running past the script yields a terminal response, which is what the
  /// private doubles this replaces did. [ledger] exposes the counts a stricter
  /// test needs to tell consumption from exhaustion.
  static ScriptedStep get _terminalStep =>
      ScriptedStep(ChatCompletionResult(content: 'done', finishReason: 'stop'));

  ScriptedStep _nextInitialStep() {
    final index = initialRequests;
    initialRequests += 1;
    return index >= _initialSteps.length ? _terminalStep : _initialSteps[index];
  }

  ScriptedStep _nextToolResultStep() {
    final index = toolResultRequests;
    toolResultRequests += 1;
    return index >= _toolResultSteps.length
        ? _terminalStep
        : _toolResultSteps[index];
  }

  ToolResultInfo _toolResult({
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
  }) => ToolResultInfo(
    id: toolCallId,
    name: toolName,
    arguments: jsonDecode(toolArguments) as Map<String, dynamic>,
    result: toolResult,
  );

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamedRequestMessages.add(List<Message>.unmodifiable(messages));
    ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.streamChatCompletion,
        index: index,
        messages: messages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    return StreamedChatCompletion.fromStream(
      Stream<String>.value('done'),
      finishReason: 'stop',
      usage: _compatibilityUsage,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.createChatCompletion,
        index: index,
        messages: messages,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    return ChatCompletionResult(content: 'done', finishReason: 'stop');
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamedRequestMessages.add(List<Message>.unmodifiable(messages));
    ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.streamChatCompletionWithTools,
        index: index,
        messages: messages,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    final requestIndex = initialRequests;
    final step = _nextInitialStep();
    final response = step.response;
    lastUsage = response.usage;
    // The stream and the completion have independent timing; a barrier holds
    // only the completion, so a test can observe the stream first.
    final hook = beforeInitialResponse;
    final barrier = step.barrier;
    Future<ChatCompletionResult> completion() async {
      if (barrier != null) await barrier();
      if (hook != null) await hook(requestIndex);
      return response;
    }

    return StreamWithToolsResult(
      stream: response.finishReason == 'stop'
          ? Stream<String>.value(response.content)
          : const Stream<String>.empty(),
      completion: barrier == null && hook == null
          ? Future<ChatCompletionResult>.value(response)
          : completion(),
    );
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
    final results = [
      _toolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
      ),
    ];
    toolResultBatches.add(results);
    ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.streamWithToolResult,
        index: index,
        messages: messages,
        toolResults: results,
        assistantContent: assistantContent,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    yield 'done';
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
    final results = [
      _toolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        toolArguments: toolArguments,
        toolResult: toolResult,
      ),
    ];
    toolResultBatches.add(results);
    final record = ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.createChatCompletionWithToolResult,
        index: index,
        messages: messages,
        tools: tools,
        toolResults: results,
        assistantContent: assistantContent,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    toolResultToolNames.add(record.toolNames);
    return _completeToolResultStep();
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
    toolResultBatches.add(List<ToolResultInfo>.unmodifiable(toolResults));
    final record = ledger._append(
      (index) => RecordedChatRequest(
        call: ChatDataSourceCall.createChatCompletionWithToolResults,
        index: index,
        messages: messages,
        tools: tools,
        toolResults: toolResults,
        assistantContent: assistantContent,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    toolResultToolNames.add(record.toolNames);
    return _completeToolResultStep();
  }

  Future<ChatCompletionResult> _completeToolResultStep() async {
    final requestIndex = toolResultRequests;
    final step = _nextToolResultStep();
    lastUsage = step.response.usage;
    if (step.barrier != null) await step.barrier!();
    await beforeToolResultResponse?.call(requestIndex);
    return step.response;
  }
}

/// Append-only view of the shared runtime's event stream.
///
/// [waitFor] does not consume: an unmatched event stays available to every
/// later predicate, so two assertions about ordering cannot interfere.
final class RuntimeEventLedger {
  RuntimeEventLedger(Stream<CavernoRuntimeEvent> events) {
    _subscription = events.listen((event) {
      _events.add(event);
      for (final waiter in List<_EventWaiter>.from(_waiters)) {
        if (waiter.matches(event) && !waiter.completer.isCompleted) {
          waiter.completer.complete(event);
          _waiters.remove(waiter);
        }
      }
    });
  }

  final List<CavernoRuntimeEvent> _events = <CavernoRuntimeEvent>[];
  final List<_EventWaiter> _waiters = <_EventWaiter>[];
  late final StreamSubscription<CavernoRuntimeEvent> _subscription;

  List<CavernoRuntimeEvent> get events =>
      List<CavernoRuntimeEvent>.unmodifiable(_events);

  List<String> get types => [for (final event in _events) event.type];

  /// Completes with the first event matching [predicate], including one already
  /// recorded. Reports the ledger on timeout, because a bare timeout in a
  /// concurrency test says nothing about what did happen.
  Future<CavernoRuntimeEvent> waitFor(
    bool Function(CavernoRuntimeEvent event) predicate, {
    Duration timeout = const Duration(seconds: 5),
    String? description,
  }) {
    for (final event in _events) {
      if (predicate(event)) return Future<CavernoRuntimeEvent>.value(event);
    }
    final waiter = _EventWaiter(predicate);
    _waiters.add(waiter);
    return waiter.completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw TimeoutException(
          'No runtime event matched ${description ?? 'the predicate'} within '
          '$timeout. Recorded: ${types.join(', ')}',
        );
      },
    );
  }

  Future<CavernoRuntimeEvent> waitForTerminal({
    String? conversationId,
    Duration timeout = const Duration(seconds: 5),
  }) => waitFor(
    (event) =>
        event is CavernoRuntimeTerminalEvent &&
        (conversationId == null || event.conversationId == conversationId),
    timeout: timeout,
    description: conversationId == null
        ? 'a terminal event'
        : 'a terminal event for $conversationId',
  );

  Future<void> dispose() => _subscription.cancel();
}

final class _EventWaiter {
  _EventWaiter(this.matches);

  final bool Function(CavernoRuntimeEvent event) matches;
  final Completer<CavernoRuntimeEvent> completer =
      Completer<CavernoRuntimeEvent>();
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_issue.dart';
import 'package:caverno/features/chat/domain/entities/flutter_run_session.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_issue_analyser.dart';
import 'package:caverno/features/chat/domain/services/flutter_run_issue_collector.dart';

const _overflow = '''
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 42 pixels on the right.
  Row Row:file:///Users/dev/app/lib/home_page.dart:64:16
════════════════════════════════════════════════════════════════════════════════
''';

const _nullCheck = '''
[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception: Null check operator used on a null value
#0      _HomePageState._load (package:app/home_page.dart:88:24)
''';

void main() {
  List<FlutterRunLogLine> logsOf(String raw) => [
    for (final line in raw.trim().split('\n'))
      FlutterRunLogLine(
        text: line,
        source: FlutterRunLogSource.stdout,
        at: DateTime.utc(2026, 8, 15),
      ),
  ];

  FlutterRunIssueCollector collectorFor(
    _CountingDataSource dataSource, {
    int budget = 20,
  }) {
    return FlutterRunIssueCollector(
      dataSource: () => dataSource,
      model: () => 'log-model',
      analyser: const FlutterRunIssueAnalyser(),
      debounce: Duration.zero,
      analysisBudget: budget,
    );
  }

  test('a repeated failure is one issue and one model call', () async {
    // The point of the whole design: an exception re-thrown every frame must
    // not become a second entry or a second call.
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);

    for (var frame = 0; frame < 60; frame += 1) {
      collector.observe(logsOf(_overflow * (frame + 1)));
    }
    await collector.analyseNow();

    expect(collector.issues, hasLength(1));
    expect(collector.issues.single.occurrences, greaterThan(1));
    expect(dataSource.calls, 1);
    await collector.dispose();
  });

  test('distinct failures each get analysed once', () async {
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);

    collector.observe(logsOf('$_overflow\n$_nullCheck'));
    await collector.analyseNow();
    collector.observe(logsOf('$_overflow\n$_nullCheck'));
    await collector.analyseNow();

    expect(collector.issues, hasLength(2));
    expect(dataSource.calls, 2);
    await collector.dispose();
  });

  test('an issue appears before it is analysed', () async {
    // The block was a real failure the moment it was printed; waiting for a
    // model before showing anything would hide it behind latency.
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);

    collector.observe(logsOf(_overflow));

    expect(collector.issues.single.analysed, isFalse);
    expect(
      collector.issues.single.title,
      'The following assertion was thrown during layout:',
    );
    expect(collector.issues.single.evidence, contains('RenderFlex overflowed'));

    await collector.analyseNow();

    expect(collector.issues.single.analysed, isTrue);
    expect(collector.issues.single.title, 'Row overflows its width');
    await collector.dispose();
  });

  test('the budget stops spending but keeps collecting', () async {
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource, budget: 1);

    collector.observe(logsOf('$_overflow\n$_nullCheck'));
    await collector.analyseNow();

    expect(dataSource.calls, 1);
    expect(collector.budgetExhausted, isTrue);
    expect(collector.issues, hasLength(2));
    expect(
      collector.issues.where((issue) => issue.analysed),
      hasLength(1),
      reason: 'the second issue is kept, just not analysed',
    );

    // The manual resume is the way back.
    await collector.analyseNow();
    expect(dataSource.calls, 2);
    await collector.dispose();
  });

  test('a model failure keeps the issue with its raw evidence', () async {
    final dataSource = _CountingDataSource(throwOnCall: true);
    final collector = collectorFor(dataSource);

    collector.observe(logsOf(_overflow));
    await collector.analyseNow();

    final issue = collector.issues.single;
    expect(issue.analysed, isFalse);
    expect(issue.evidence, contains('RenderFlex overflowed by 42 pixels'));
    await collector.dispose();
  });

  test('a data source without structured output still collects', () async {
    final collector = FlutterRunIssueCollector(
      dataSource: _PlainDataSource.new,
      model: () => 'log-model',
      debounce: Duration.zero,
    );

    collector.observe(logsOf(_overflow));
    await collector.analyseNow();

    expect(collector.issues, hasLength(1));
    expect(collector.issues.single.analysed, isFalse);
    await collector.dispose();
  });

  test('a failed run with nothing recognisable yields a tail issue', () async {
    // Reported from the app: an Xcode build error produced a failed run and an
    // empty issue list, because no pattern matched it.
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);

    collector.observe(logsOf('SomeToolchain::fatal — malformed object file'));
    expect(collector.issues, isEmpty);

    await collector.analyseNow(runFailed: true);

    expect(collector.issues, hasLength(1));
    expect(
      collector.issues.single.kind,
      FlutterRunIssueKind.unclassifiedFailure,
    );
    expect(collector.issues.single.evidence, contains('malformed object file'));
    await collector.dispose();
  });

  test('the model may rule out a tail, and only a tail', () async {
    // The window merely accompanied a bad exit, so "no failure here" is a real
    // answer. A framed failure is one whatever the model says about it.
    final dismissing = _CountingDataSource(isFailure: false);
    final tailCollector = collectorFor(dismissing);
    tailCollector.observe(logsOf('nothing interesting happened'));
    await tailCollector.analyseNow(runFailed: true);

    expect(tailCollector.issues, isEmpty);
    await tailCollector.dispose();

    final framed = collectorFor(_CountingDataSource(isFailure: false));
    framed.observe(logsOf(_overflow));
    await framed.analyseNow(runFailed: true);

    expect(framed.issues, hasLength(1));
    await framed.dispose();
  });

  test('a failed run with a recognised block does not add a tail', () async {
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);

    collector.observe(logsOf(_overflow));
    await collector.analyseNow(runFailed: true);

    expect(collector.issues, hasLength(1));
    expect(
      collector.issues.single.kind,
      FlutterRunIssueKind.frameworkException,
    );
    await collector.dispose();
  });

  test('clear drops the list and the spend', () async {
    final dataSource = _CountingDataSource();
    final collector = collectorFor(dataSource);
    collector.observe(logsOf(_overflow));
    await collector.analyseNow();

    collector.clear();

    expect(collector.issues, isEmpty);
    expect(collector.analysisCount, 0);
    await collector.dispose();
  });
}

class _CountingDataSource extends _PlainDataSource
    implements StructuredOutputChatDataSource {
  _CountingDataSource({this.throwOnCall = false, this.isFailure = true});

  final bool throwOnCall;
  final bool isFailure;
  int calls = 0;

  @override
  Future<ChatCompletionResult> createStructuredChatCompletion({
    required List<Message> messages,
    required StructuredOutputRequest responseFormat,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    calls += 1;
    if (throwOnCall) throw StateError('endpoint unavailable');
    return ChatCompletionResult(
      content:
          '{"title":"Row overflows its width",'
          '"cause":"The Row is wider than its parent allows.",'
          '"severity":"warning","location":"lib/home_page.dart:64",'
          '"isFailure":$isFailure}',
      finishReason: 'stop',
    );
  }
}

class _PlainDataSource implements ChatDataSource {
  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => throw UnimplementedError();

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

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
  }) async => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => throw UnimplementedError();
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/google_chat_delivery_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/providers/routines_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  Future<ProviderContainer> createContainer({
    required List<Routine> initialRoutines,
    RoutineExecutionService? executionService,
    NotificationService? notificationService,
    GoogleChatDeliveryService? googleChatDeliveryService,
    AppSettings? settings,
  }) async {
    SharedPreferences.setMockInitialValues({
      'routines': jsonEncode(
        initialRoutines.map((routine) => routine.toJson()).toList(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();

    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(settings ?? AppSettings.defaults()),
        ),
        if (executionService != null)
          routineExecutionServiceProvider.overrideWithValue(executionService),
        if (notificationService != null)
          notificationServiceProvider.overrideWithValue(notificationService),
        if (googleChatDeliveryService != null)
          googleChatDeliveryServiceProvider.overrideWithValue(
            googleChatDeliveryService,
          ),
      ],
    );
  }

  Routine buildRoutine({
    required String id,
    required String name,
    bool enabled = true,
    bool toolsEnabled = false,
    bool notifyOnCompletion = true,
    RoutineCompletionAction completionAction = RoutineCompletionAction.none,
    RoutineGoogleChatRule googleChatRule = RoutineGoogleChatRule.onFailure,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    List<RoutineRunRecord> runs = const [],
  }) {
    final now = DateTime(2026, 4, 21, 10);
    return Routine(
      id: id,
      name: name,
      prompt: 'Summarize the latest updates.',
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      notifyOnCompletion: notifyOnCompletion,
      toolsEnabled: toolsEnabled,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      intervalValue: 1,
      intervalUnit: RoutineIntervalUnit.hours,
      nextRunAt: nextRunAt,
      lastRunAt: lastRunAt,
      runs: runs,
    );
  }

  group('RoutinesNotifier', () {
    test('duplicateRoutine creates a clean copy without run history', () async {
      final source = buildRoutine(
        id: 'routine-1',
        name: 'Morning summary',
        toolsEnabled: true,
        nextRunAt: DateTime(2026, 4, 21, 11),
        lastRunAt: DateTime(2026, 4, 21, 9),
        runs: [
          RoutineRunRecord(
            id: 'run-1',
            startedAt: DateTime(2026, 4, 21, 9),
            finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
            preview: 'Latest summary ready',
          ),
        ],
      );
      final container = await createContainer(initialRoutines: [source]);
      addTearDown(container.dispose);

      final notifier = container.read(routinesNotifierProvider.notifier);
      final duplicate = await notifier.duplicateRoutine(
        routineId: source.id,
        duplicatedName: 'Copy of Morning summary',
      );

      final state = container.read(routinesNotifierProvider);
      expect(duplicate, isNotNull);
      expect(state.routines, hasLength(2));
      expect(duplicate!.name, 'Copy of Morning summary');
      expect(duplicate.prompt, source.prompt);
      expect(duplicate.toolsEnabled, isTrue);
      expect(duplicate.runs, isEmpty);
      expect(duplicate.lastRunAt, isNull);
      expect(duplicate.nextRunAt, isNotNull);
    });

    test(
      'clearRunHistory removes stored runs and last run timestamp',
      () async {
        final source = buildRoutine(
          id: 'routine-1',
          name: 'Morning summary',
          nextRunAt: DateTime(2026, 4, 21, 11),
          lastRunAt: DateTime(2026, 4, 21, 9),
          runs: [
            RoutineRunRecord(
              id: 'run-1',
              startedAt: DateTime(2026, 4, 21, 9),
              finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
              preview: 'Latest summary ready',
            ),
          ],
        );
        final container = await createContainer(initialRoutines: [source]);
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.clearRunHistory(source.id);

        final cleared = container
            .read(routinesNotifierProvider.notifier)
            .findRoutine(source.id);
        expect(cleared, isNotNull);
        expect(cleared!.runs, isEmpty);
        expect(cleared.lastRunAt, isNull);
        expect(cleared.nextRunAt, source.nextRunAt);
      },
    );

    test(
      'runDueRoutines executes only due routines with the requested trigger',
      () async {
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final futureRoutine = buildRoutine(
          id: 'routine-future',
          name: 'Future routine',
          nextRunAt: DateTime(3026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine, futureRoutine],
          executionService: _FakeRoutineExecutionService(),
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        final executedCount = await notifier.runDueRoutines(
          trigger: RoutineRunTrigger.manual,
        );

        final updatedDue = notifier.findRoutine(dueRoutine.id);
        final untouchedFuture = notifier.findRoutine(futureRoutine.id);

        expect(executedCount, 1);
        expect(updatedDue?.latestRun, isNotNull);
        expect(updatedDue?.latestRun?.trigger, RoutineRunTrigger.manual);
        expect(updatedDue?.latestRun?.preview, 'Executed by fake service');
        expect(untouchedFuture?.runs, isEmpty);
      },
    );

    test(
      'scheduled runs notify when routine notifications are enabled',
      () async {
        final notificationService = _FakeNotificationService();
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine],
          executionService: _FakeRoutineExecutionService(),
          notificationService: notificationService,
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.runDueRoutines();

        expect(notificationService.calls, hasLength(1));
        expect(notificationService.calls.single.routineId, dueRoutine.id);
        expect(notificationService.calls.single.routineName, 'Due routine');
        expect(notificationService.calls.single.isSuccessful, isTrue);
        expect(
          notificationService.calls.single.body,
          'Executed by fake service',
        );
      },
    );

    test(
      'scheduled runs skip notifications when disabled on the routine',
      () async {
        final notificationService = _FakeNotificationService();
        final dueRoutine = buildRoutine(
          id: 'routine-due',
          name: 'Due routine',
          notifyOnCompletion: false,
          nextRunAt: DateTime(2026, 4, 21, 9),
        );
        final container = await createContainer(
          initialRoutines: [dueRoutine],
          executionService: _FakeRoutineExecutionService(),
          notificationService: notificationService,
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        await notifier.runDueRoutines();

        expect(notificationService.calls, isEmpty);
      },
    );

    test(
      'runRoutineNow posts to Google Chat when the rule matches and webhook exists',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService(
          result: GoogleChatDeliveryResult(
            isSuccessful: true,
            message: 'Posted to Google Chat.',
            deliveredAt: DateTime(2026, 4, 21, 10, 0, 3),
          ),
        );
        final routine = buildRoutine(
          id: 'routine-delivery',
          name: 'Delivery routine',
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.always,
          nextRunAt: DateTime(2026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [routine],
          executionService: _FakeRoutineExecutionService(),
          googleChatDeliveryService: deliveryService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );
        addTearDown(container.dispose);

        final notifier = container.read(routinesNotifierProvider.notifier);
        final runRecord = await notifier.runRoutineNow(routine.id);
        final updatedRoutine = notifier.findRoutine(routine.id);

        expect(deliveryService.calls, hasLength(1));
        expect(
          deliveryService.calls.single.webhookUrl,
          'https://chat.googleapis.com/v1/spaces/test',
        );
        expect(
          deliveryService.calls.single.text,
          contains('Routine "Delivery routine" completed.'),
        );
        expect(runRecord?.deliveryStatus, RoutineDeliveryStatus.delivered);
        expect(runRecord?.deliveredAt, DateTime(2026, 4, 21, 10, 0, 3));
        expect(runRecord?.deliveryMessage, 'Posted to Google Chat.');
        expect(
          updatedRoutine?.latestRun?.deliveryStatus,
          RoutineDeliveryStatus.delivered,
        );
      },
    );

    test(
      'runRoutineNow skips Google Chat delivery when the rule does not match',
      () async {
        final deliveryService = _FakeGoogleChatDeliveryService();
        final routine = buildRoutine(
          id: 'routine-skip',
          name: 'Skip routine',
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.onFailure,
          nextRunAt: DateTime(2026, 4, 21, 11),
        );
        final container = await createContainer(
          initialRoutines: [routine],
          executionService: _FakeRoutineExecutionService(),
          googleChatDeliveryService: deliveryService,
          settings: AppSettings.defaults().copyWith(
            googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
          ),
        );
        addTearDown(container.dispose);

        final runRecord = await container
            .read(routinesNotifierProvider.notifier)
            .runRoutineNow(routine.id);

        expect(deliveryService.calls, isEmpty);
        expect(runRecord?.deliveryStatus, RoutineDeliveryStatus.skipped);
        expect(runRecord?.deliveryMessage, contains('only failed runs'));
      },
    );
  });
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

class _FakeRoutineExecutionService extends RoutineExecutionService {
  _FakeRoutineExecutionService()
    : super(
        dataSource: _StubChatDataSource(),
        settings: AppSettings.defaults(),
      );

  @override
  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    return RoutineRunRecord(
      id: 'fake-run-${routine.id}',
      startedAt: DateTime(2026, 4, 21, 10),
      finishedAt: DateTime(2026, 4, 21, 10, 0, 2),
      trigger: trigger,
      preview: 'Executed by fake service',
      output: 'Fake output',
      durationMs: 2000,
    );
  }
}

class _StubChatDataSource implements ChatDataSource {
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
}

class _FakeNotificationService extends NotificationService {
  final List<_RoutineNotificationCall> calls = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> showRoutineCompletionNotification({
    required String routineId,
    required String routineName,
    required bool isSuccessful,
    required String body,
  }) async {
    calls.add(
      _RoutineNotificationCall(
        routineId: routineId,
        routineName: routineName,
        isSuccessful: isSuccessful,
        body: body,
      ),
    );
  }
}

class _FakeGoogleChatDeliveryService extends GoogleChatDeliveryService {
  _FakeGoogleChatDeliveryService({
    this.result = const GoogleChatDeliveryResult(
      isSuccessful: true,
      message: 'Posted to Google Chat.',
    ),
  }) : super();

  final GoogleChatDeliveryResult result;
  final List<_GoogleChatDeliveryCall> calls = [];

  @override
  Future<GoogleChatDeliveryResult> sendMessage({
    required String webhookUrl,
    required String text,
  }) async {
    calls.add(_GoogleChatDeliveryCall(webhookUrl: webhookUrl, text: text));
    return result;
  }
}

class _RoutineNotificationCall {
  const _RoutineNotificationCall({
    required this.routineId,
    required this.routineName,
    required this.isSuccessful,
    required this.body,
  });

  final String routineId;
  final String routineName;
  final bool isSuccessful;
  final String body;
}

class _GoogleChatDeliveryCall {
  const _GoogleChatDeliveryCall({required this.webhookUrl, required this.text});

  final String webhookUrl;
  final String text;
}

import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/create_routine_tool_handler.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );
  final ownerANextGeneration = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 5,
  );
  final poisonedIdentities = [
    _identity(ownerB),
    _identity(ownerANextGeneration),
    _identity(ownerA, toolCallId: 'call-create-routine-concurrent'),
  ];

  group('CreateRoutineToolRequest', () {
    test('recursively freezes arguments and normalizes request fields', () {
      final labels = <Object?>['morning'];
      final flags = <Object?>['safe'];
      final metadata = <String, Object?>{'labels': labels, 'flags': flags};
      final arguments = <String, dynamic>{
        'name': '  Morning Routine  ',
        'prompt': '  Start the day.  ',
        'reason': '  Keep a daily cadence.  ',
        'metadata': metadata,
      };

      final request = CreateRoutineToolRequest(
        owner: ownerA,
        toolCallId: 'call-7',
        toolName: 'create_routine',
        arguments: arguments,
      );

      labels.add('poisoned');
      flags.add('poisoned');
      metadata['labels'] = ['replaced'];
      arguments['name'] = 'Poisoned';

      expect(request.owner, ownerA);
      expect(request.toolCallId, 'call-7');
      expect(request.toolName, 'create_routine');
      expect(request.name, 'Morning Routine');
      expect(request.prompt, 'Start the day.');
      expect(request.reason, 'Keep a daily cadence.');
      expect(
        RoutineCreationApprovalDecision(
          identity: request.identity,
          approved: true,
        ).owner,
        ownerA,
      );
      expect(
        RoutineCreationOwnerState.current(identity: request.identity).owner,
        ownerA,
      );
      expect(request.arguments['metadata'], {
        'labels': ['morning'],
        'flags': ['safe'],
      });
      expect(
        () => (request.arguments['metadata'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['flags'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects ambiguous identity and mutable argument leaves', () {
      for (final toolCallId in [
        '',
        '   ',
        ' call-create-routine',
        'call-create-routine ',
      ]) {
        expect(
          () => _request(ownerA, toolCallId: toolCallId),
          throwsArgumentError,
        );
      }
      for (final toolName in [
        'Create_Routine',
        ' create_routine',
        'create_routine ',
      ]) {
        expect(() => _request(ownerA, toolName: toolName), throwsArgumentError);
      }
      expect(
        () => _request(
          ownerA,
          arguments: _arguments({
            'metadata': <Object?, Object?>{7: 'ambiguous'},
          }),
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          ownerA,
          arguments: _arguments({'metadata': StringBuffer('mutable')}),
        ),
        throwsArgumentError,
      );
      for (final invalid in <Object?>[
        <Object?>{'not-json'},
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => _request(ownerA, arguments: _arguments({'metadata': invalid})),
          throwsArgumentError,
          reason: invalid.toString(),
        );
      }
      for (final token in ['', '   ', ' token', 'token ']) {
        expect(
          () => RoutineStoreCompensationToken(
            identity: _identity(ownerA),
            value: token,
          ),
          throwsArgumentError,
        );
      }
    });

    test('freezes the owner routine snapshot list', () {
      final source = <Routine>[_routine(id: 'one', name: 'One')];
      final snapshot = RoutineStoreSnapshot(
        identity: _identity(ownerA),
        routines: source,
        createdRoutine: source.single,
      );

      source.add(_routine(id: 'two', name: 'Two'));

      expect(snapshot.owner, ownerA);
      expect(snapshot.routines.map((routine) => routine.id), ['one']);
      expect(
        () => snapshot.routines.add(_routine(id: 'late', name: 'Late')),
        throwsUnsupportedError,
      );
    });
  });

  group('CreateRoutineToolHandler validation', () {
    test('preserves missing-field ordering and exact errors', () async {
      final cases = [
        (arguments: <String, dynamic>{}, error: 'name is required'),
        (
          arguments: <String, dynamic>{'name': '   ', 'prompt': 'Run a task'},
          error: 'name is required',
        ),
        (
          arguments: <String, dynamic>{'name': 'Morning'},
          error: 'prompt is required',
        ),
        (
          arguments: <String, dynamic>{'name': 'Morning', 'prompt': '   '},
          error: 'prompt is required',
        ),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(ownerA, arguments: testCase.arguments),
        );

        expect(result.toolName, 'create_routine');
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, testCase.error);
        expect(fixture.events, isEmpty);
      }
    });

    test(
      'materializes name, prompt, and reason before required checks',
      () async {
        final cases = <Map<String, dynamic>>[
          {'name': ' ', 'prompt': 3},
          {'name': ' ', 'prompt': 'Run a task', 'reason': 3},
          {'name': 'Morning', 'prompt': ' ', 'reason': 3},
        ];

        for (final arguments in cases) {
          final fixture = _fixture();
          await expectLater(
            fixture.handler.handle(_request(ownerA, arguments: arguments)),
            throwsA(isA<TypeError>()),
          );
          expect(fixture.events, isEmpty);
        }
      },
    );

    test('preserves invalid-field cast failures before approval', () async {
      final cases = <({String label, Map<String, dynamic> overrides})>[
        (label: 'name', overrides: {'name': 3}),
        (label: 'prompt', overrides: {'prompt': 3}),
        (label: 'reason', overrides: {'reason': 3}),
        (label: 'schedule_mode', overrides: {'schedule_mode': 3}),
        (label: 'interval_value', overrides: {'interval_value': '3'}),
        (label: 'interval_unit', overrides: {'interval_unit': 3}),
        (
          label: 'time_of_day',
          overrides: {
            'time_of_day': <int>[8, 30],
          },
        ),
        (label: 'tools_enabled', overrides: {'tools_enabled': 'true'}),
        (label: 'notify_on_completion', overrides: {'notify_on_completion': 1}),
        (label: 'completion_action', overrides: {'completion_action': 3}),
        (label: 'google_chat_rule', overrides: {'google_chat_rule': 3}),
        (label: 'workspace_directory', overrides: {'workspace_directory': 3}),
        (
          label: 'allow_workspace_writes',
          overrides: {'allow_workspace_writes': 'true'},
        ),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();

        await expectLater(
          fixture.handler.handle(
            _request(ownerA, arguments: _arguments(testCase.overrides)),
          ),
          throwsA(isA<TypeError>()),
          reason: testCase.label,
        );
        expect(fixture.events, isEmpty, reason: testCase.label);
      }
    });
  });

  group('CreateRoutineToolHandler parsing', () {
    test('preserves every schedule mode alias and default', () async {
      final cases =
          <({Object? input, RoutineScheduleMode expected, String summary})>[
            (
              input: null,
              expected: RoutineScheduleMode.interval,
              summary: 'every 1 hour',
            ),
            (
              input: '',
              expected: RoutineScheduleMode.interval,
              summary: 'every 1 hour',
            ),
            (
              input: ' interval ',
              expected: RoutineScheduleMode.interval,
              summary: 'every 1 hour',
            ),
            (
              input: 'unknown',
              expected: RoutineScheduleMode.interval,
              summary: 'every 1 hour',
            ),
            (
              input: 'daily',
              expected: RoutineScheduleMode.dailyTime,
              summary: 'daily at 08:00',
            ),
            (
              input: 'DAILYTIME',
              expected: RoutineScheduleMode.dailyTime,
              summary: 'daily at 08:00',
            ),
            (
              input: ' daily_time ',
              expected: RoutineScheduleMode.dailyTime,
              summary: 'daily at 08:00',
            ),
            (
              input: 'time_of_day',
              expected: RoutineScheduleMode.dailyTime,
              summary: 'daily at 08:00',
            ),
          ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({'schedule_mode': testCase.input}),
          ),
        );

        expect(
          fixture.store.creates.single.request.scheduleMode,
          testCase.expected,
        );
        expect(
          jsonDecode(result.result),
          containsPair('schedule', testCase.summary),
        );
      }
    });

    test('preserves every interval unit alias and default', () async {
      final cases =
          <({Object? input, RoutineIntervalUnit expected, String summary})>[
            (
              input: null,
              expected: RoutineIntervalUnit.hours,
              summary: 'every 1 hour',
            ),
            (
              input: '',
              expected: RoutineIntervalUnit.hours,
              summary: 'every 1 hour',
            ),
            (
              input: 'hour',
              expected: RoutineIntervalUnit.hours,
              summary: 'every 1 hour',
            ),
            (
              input: ' HOURS ',
              expected: RoutineIntervalUnit.hours,
              summary: 'every 1 hour',
            ),
            (
              input: 'unknown',
              expected: RoutineIntervalUnit.hours,
              summary: 'every 1 hour',
            ),
            (
              input: 'minute',
              expected: RoutineIntervalUnit.minutes,
              summary: 'every 1 minute',
            ),
            (
              input: ' MINUTES ',
              expected: RoutineIntervalUnit.minutes,
              summary: 'every 1 minute',
            ),
            (
              input: 'day',
              expected: RoutineIntervalUnit.days,
              summary: 'every 1 day',
            ),
            (
              input: ' DAYS ',
              expected: RoutineIntervalUnit.days,
              summary: 'every 1 day',
            ),
          ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({'interval_unit': testCase.input}),
          ),
        );

        expect(
          fixture.store.creates.single.request.intervalUnit,
          testCase.expected,
        );
        expect(
          jsonDecode(result.result),
          containsPair('schedule', testCase.summary),
        );
      }
    });

    test('normalizes interval boundaries and plural summaries', () async {
      final cases = <({Object? input, int expected, String summary})>[
        (input: null, expected: 1, summary: 'every 1 hour'),
        (input: -4, expected: 1, summary: 'every 1 hour'),
        (input: 0, expected: 1, summary: 'every 1 hour'),
        (input: 1, expected: 1, summary: 'every 1 hour'),
        (input: 2, expected: 2, summary: 'every 2 hours'),
        (input: 2.9, expected: 2, summary: 'every 2 hours'),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({'interval_value': testCase.input}),
          ),
        );

        expect(
          fixture.store.creates.single.request.intervalValue,
          testCase.expected,
        );
        expect(
          jsonDecode(result.result),
          containsPair('schedule', testCase.summary),
        );
      }
    });

    test('parses and clamps every time-of-day boundary form', () async {
      final cases = <({Object? input, int expected, String summary})>[
        (input: null, expected: 480, summary: 'daily at 08:00'),
        (input: '', expected: 480, summary: 'daily at 08:00'),
        (input: 'invalid', expected: 480, summary: 'daily at 08:00'),
        (input: '1:2', expected: 480, summary: 'daily at 08:00'),
        (input: -1, expected: 0, summary: 'daily at 00:00'),
        (input: 7.9, expected: 7, summary: 'daily at 00:07'),
        (input: ' 8:05 ', expected: 485, summary: 'daily at 08:05'),
        (input: '08:05', expected: 485, summary: 'daily at 08:05'),
        (input: '123', expected: 123, summary: 'daily at 02:03'),
        (input: '-1', expected: 0, summary: 'daily at 00:00'),
        (input: 1439, expected: 1439, summary: 'daily at 23:59'),
        (input: 1440, expected: 1439, summary: 'daily at 23:59'),
        (input: '24:00', expected: 1439, summary: 'daily at 23:59'),
        (input: '99:99', expected: 1439, summary: 'daily at 23:59'),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({
              'schedule_mode': 'daily',
              'time_of_day': testCase.input,
            }),
          ),
        );

        expect(
          fixture.store.creates.single.request.timeOfDayMinutes,
          testCase.expected,
        );
        expect(
          jsonDecode(result.result),
          containsPair('schedule', testCase.summary),
        );
      }
    });

    test('preserves every completion action alias and default', () async {
      final cases =
          <
            ({Object? input, RoutineCompletionAction expected, String delivery})
          >[
            (
              input: null,
              expected: RoutineCompletionAction.none,
              delivery: 'Delivery: none',
            ),
            (
              input: '',
              expected: RoutineCompletionAction.none,
              delivery: 'Delivery: none',
            ),
            (
              input: 'none',
              expected: RoutineCompletionAction.none,
              delivery: 'Delivery: none',
            ),
            (
              input: 'unknown',
              expected: RoutineCompletionAction.none,
              delivery: 'Delivery: none',
            ),
            (
              input: 'google_chat',
              expected: RoutineCompletionAction.googleChat,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: ' GOOGLECHAT ',
              expected: RoutineCompletionAction.googleChat,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: 'prompt_google_chat',
              expected: RoutineCompletionAction.promptGoogleChat,
              delivery: 'Delivery: Google Chat (prompt before posting)',
            ),
            (
              input: ' PROMPTGOOGLECHAT ',
              expected: RoutineCompletionAction.promptGoogleChat,
              delivery: 'Delivery: Google Chat (prompt before posting)',
            ),
          ];

      for (final testCase in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({
              'completion_action': testCase.input,
              'notify_on_completion': false,
            }),
          ),
        );

        expect(
          fixture.store.creates.single.request.completionAction,
          testCase.expected,
        );
        expect(
          fixture.approval.requests.single.request.preview,
          contains(testCase.delivery),
        );
        expect(
          jsonDecode(result.result),
          containsPair('completion_action', testCase.expected.name),
        );
      }
    });

    test('preserves every Google Chat rule alias and default', () async {
      final cases =
          <({Object? input, RoutineGoogleChatRule expected, String delivery})>[
            (
              input: null,
              expected: RoutineGoogleChatRule.onFailure,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: '',
              expected: RoutineGoogleChatRule.onFailure,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: 'on_failure',
              expected: RoutineGoogleChatRule.onFailure,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: ' ONFAILURE ',
              expected: RoutineGoogleChatRule.onFailure,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: 'unknown',
              expected: RoutineGoogleChatRule.onFailure,
              delivery: 'Delivery: Google Chat (onFailure)',
            ),
            (
              input: 'on_success',
              expected: RoutineGoogleChatRule.onSuccess,
              delivery: 'Delivery: Google Chat (onSuccess)',
            ),
            (
              input: ' ONSUCCESS ',
              expected: RoutineGoogleChatRule.onSuccess,
              delivery: 'Delivery: Google Chat (onSuccess)',
            ),
            (
              input: 'always',
              expected: RoutineGoogleChatRule.always,
              delivery: 'Delivery: Google Chat (always)',
            ),
          ];

      for (final testCase in cases) {
        final fixture = _fixture();
        await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({
              'completion_action': 'google_chat',
              'google_chat_rule': testCase.input,
              'notify_on_completion': false,
            }),
          ),
        );

        expect(
          fixture.store.creates.single.request.googleChatRule,
          testCase.expected,
        );
        expect(
          fixture.approval.requests.single.request.preview,
          contains(testCase.delivery),
        );
      }
    });
  });

  group('CreateRoutineToolHandler preview and persistence', () {
    test('creates defaults with exact approval, fields, and payload', () async {
      final nextRunAt = DateTime.utc(2026, 7, 3, 9, 30);
      final fixture = _fixture(
        routines: [
          _routine(
            id: 'routine-new',
            name: 'Morning Routine',
            createdAt: DateTime.utc(2026, 7, 2),
            nextRunAt: nextRunAt,
          ),
        ],
      );
      final request = _request(
        ownerA,
        arguments: const {
          'name': '  Morning Routine  ',
          'prompt': '  Start the day.  ',
          'reason': '  Keep a daily cadence.  ',
        },
      );

      final result = await fixture.handler.handle(request);

      expect(
        result.result,
        '{"ok":true,"action":"created","id":"routine-new",'
        '"name":"Morning Routine","schedule":"every 1 hour",'
        '"tools_enabled":false,"notify_on_completion":true,'
        '"completion_action":"none",'
        '"next_run_at":"2026-07-03T09:30:00.000Z"}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      final approval = fixture.approval.requests.single;
      expect(approval.owner, ownerA);
      expect(approval.request.toolRequest, same(request));
      expect(approval.request.operation, 'Create Routine');
      expect(approval.request.path, 'Morning Routine');
      expect(approval.request.reason, 'Keep a daily cadence.');
      expect(
        approval.request.preview,
        'Routine: Morning Routine\n'
        'Schedule: every 1 hour\n'
        'Runs automatically without further confirmation once scheduled.\n'
        'Tools enabled: no\n'
        'Delivery: local notification\n'
        '\n'
        'Prompt:\n'
        'Start the day.',
      );

      final create = fixture.store.creates.single;
      expect(create.owner, ownerA);
      expect(
        (
          name: create.request.name,
          prompt: create.request.prompt,
          intervalValue: create.request.intervalValue,
          intervalUnit: create.request.intervalUnit,
          scheduleMode: create.request.scheduleMode,
          timeOfDayMinutes: create.request.timeOfDayMinutes,
          enabled: create.request.enabled,
          notifyOnCompletion: create.request.notifyOnCompletion,
          toolsEnabled: create.request.toolsEnabled,
          completionAction: create.request.completionAction,
          googleChatRule: create.request.googleChatRule,
          workspaceDirectory: create.request.workspaceDirectory,
          allowWorkspaceWrites: create.request.allowWorkspaceWrites,
        ),
        (
          name: 'Morning Routine',
          prompt: 'Start the day.',
          intervalValue: 1,
          intervalUnit: RoutineIntervalUnit.hours,
          scheduleMode: RoutineScheduleMode.interval,
          timeOfDayMinutes: 480,
          enabled: true,
          notifyOnCompletion: true,
          toolsEnabled: false,
          completionAction: RoutineCompletionAction.none,
          googleChatRule: RoutineGoogleChatRule.onFailure,
          workspaceDirectory: '',
          allowWorkspaceWrites: false,
        ),
      );
      expect(fixture.events, [
        'approval.request:conversation-a:4',
        'approval.expired:conversation-a:4',
        'store.create:conversation-a:4',
        'store.snapshot:conversation-a:4',
        'approval.expired:conversation-a:4',
      ]);
    });

    test(
      'preserves Google Chat, tools, and writable workspace preview',
      () async {
        final fixture = _fixture();

        await fixture.handler.handle(
          _request(
            ownerA,
            arguments: const {
              'name': '  Release Routine  ',
              'prompt': '  Ship the app.  ',
              'interval_value': 2.9,
              'interval_unit': 'days',
              'schedule_mode': 'interval',
              'time_of_day': '09:45',
              'tools_enabled': true,
              'notify_on_completion': true,
              'completion_action': 'google_chat',
              'google_chat_rule': 'on_success',
              'workspace_directory': '  /workspace/app  ',
              'allow_workspace_writes': true,
            },
          ),
        );

        expect(
          fixture.approval.requests.single.request.preview,
          'Routine: Release Routine\n'
          'Schedule: every 2 days\n'
          'Runs automatically without further confirmation once scheduled.\n'
          'Tools enabled: yes\n'
          'Delivery: local notification, Google Chat (onSuccess)\n'
          'Workspace: /workspace/app (writes allowed)\n'
          '\n'
          'Prompt:\n'
          'Ship the app.',
        );
        final create = fixture.store.creates.single.request;
        expect(create.name, 'Release Routine');
        expect(create.prompt, 'Ship the app.');
        expect(create.intervalValue, 2);
        expect(create.intervalUnit, RoutineIntervalUnit.days);
        expect(create.scheduleMode, RoutineScheduleMode.interval);
        expect(create.timeOfDayMinutes, 585);
        expect(create.enabled, isTrue);
        expect(create.notifyOnCompletion, isTrue);
        expect(create.toolsEnabled, isTrue);
        expect(create.completionAction, RoutineCompletionAction.googleChat);
        expect(create.googleChatRule, RoutineGoogleChatRule.onSuccess);
        expect(create.workspaceDirectory, '/workspace/app');
        expect(create.allowWorkspaceWrites, isTrue);
      },
    );

    test('preserves prompt delivery and read-only workspace preview', () async {
      final fixture = _fixture();

      await fixture.handler.handle(
        _request(
          ownerA,
          arguments: const {
            'name': 'Daily Review',
            'prompt': 'Review changes.',
            'schedule_mode': 'daily',
            'time_of_day': '17:05',
            'notify_on_completion': false,
            'completion_action': 'prompt_google_chat',
            'workspace_directory': '  /workspace/review  ',
          },
        ),
      );

      expect(
        fixture.approval.requests.single.request.preview,
        'Routine: Daily Review\n'
        'Schedule: daily at 17:05\n'
        'Runs automatically without further confirmation once scheduled.\n'
        'Tools enabled: no\n'
        'Delivery: Google Chat (prompt before posting)\n'
        'Workspace: /workspace/review (read-only)\n'
        '\n'
        'Prompt:\n'
        'Review changes.',
      );
    });

    test('uses none when every delivery channel is disabled', () async {
      final fixture = _fixture();

      await fixture.handler.handle(
        _request(
          ownerA,
          arguments: _arguments({'notify_on_completion': false}),
        ),
      );

      expect(
        fixture.approval.requests.single.request.preview,
        contains('Delivery: none'),
      );
    });

    test('always requests a fresh approval for repeated requests', () async {
      final fixture = _fixture();

      await fixture.handler.handle(_request(ownerA));
      await fixture.handler.handle(_request(ownerA));

      expect(fixture.approval.requests, hasLength(2));
      expect(fixture.approval.expirationOwners, [
        ownerA,
        ownerA,
        ownerA,
        ownerA,
      ]);
      expect(fixture.store.creates, hasLength(2));
    });

    test(
      'uses the exact receipt routine among concurrent same-name entries',
      () async {
        final newestTime = DateTime.utc(2026, 7, 4);
        final exactCreated = _routine(
          id: 'newest',
          name: '  MORNING ROUTINE  ',
          createdAt: newestTime,
          nextRunAt: DateTime.utc(2026, 7, 5, 8),
        );
        final fixture = _fixture(
          routines: [
            _routine(
              id: 'unrelated-newer',
              name: 'Evening',
              createdAt: DateTime.utc(2026, 7, 10),
            ),
            _routine(
              id: 'older',
              name: 'Morning Routine',
              createdAt: DateTime.utc(2026, 7, 1),
            ),
            exactCreated,
            _routine(
              id: 'same-time-later-in-list',
              name: 'morning routine',
              createdAt: newestTime,
              nextRunAt: DateTime.utc(2026, 7, 6, 8),
            ),
          ],
        );
        fixture.store.createdRoutines[ownerA] = exactCreated;

        final result = await fixture.handler.handle(
          _request(
            ownerA,
            arguments: _arguments({'name': '  Morning Routine  '}),
          ),
        );

        expect(
          result.result,
          '{"ok":true,"action":"created","id":"newest",'
          '"name":"Morning Routine","schedule":"every 1 hour",'
          '"tools_enabled":false,"notify_on_completion":true,'
          '"completion_action":"none",'
          '"next_run_at":"2026-07-05T08:00:00.000Z"}',
        );
      },
    );

    test(
      'uses receipt identity instead of a global same-name search',
      () async {
        final fixture = _fixture(
          routines: [_routine(id: 'other', name: 'Other')],
        );

        final result = await fixture.handler.handle(_request(ownerA));
        final payload = jsonDecode(result.result) as Map<String, dynamic>;

        expect(payload, {
          'ok': true,
          'action': 'created',
          'id': 'other',
          'name': 'Morning Routine',
          'schedule': 'every 1 hour',
          'tools_enabled': false,
          'notify_on_completion': true,
          'completion_action': 'none',
        });
        expect(payload, isNot(contains('next_run_at')));
      },
    );
  });

  group('CreateRoutineToolHandler approval and failures', () {
    test('returns exact denial without persisting', () async {
      final fixture = _fixture();
      fixture.approval.decisions[ownerA] = RoutineCreationApprovalDecision(
        identity: _identity(ownerA),
        approved: false,
      );

      final result = await fixture.handler.handle(_request(ownerA));

      expect(result.toolName, 'create_routine');
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User denied creating the routine');
      expect(fixture.store.creates, isEmpty);
      expect(fixture.events, [
        'approval.request:conversation-a:4',
        'approval.expired:conversation-a:4',
      ]);
    });

    test('returns expiration before applying a denial', () async {
      const expired = McpToolResult(
        toolName: 'create_routine',
        result: '',
        isSuccess: false,
        errorMessage: 'The approval turn expired before execution',
      );
      final fixture = _fixture();
      fixture.approval.decisions[ownerA] = RoutineCreationApprovalDecision(
        identity: _identity(ownerA),
        approved: false,
      );
      fixture.approval.expirations[ownerA] = expired;

      expect(await fixture.handler.handle(_request(ownerA)), same(expired));
      expect(fixture.store.creates, isEmpty);
    });

    test(
      'reports uncertain persistence for create and snapshot errors',
      () async {
        final cases = [
          (
            configure: (_Fixture fixture) {
              fixture.store.createErrors[ownerA] = StateError(
                'routine repository unavailable',
              );
            },
            message:
                'Routine creation may have persisted because the routine store '
                'failed: Bad state: routine repository unavailable. '
                'Inspect scheduled routines before retrying.',
          ),
          (
            configure: (_Fixture fixture) {
              fixture.store.snapshotErrors[ownerA] = const FormatException(
                'invalid routine snapshot',
              );
            },
            message:
                'Routine creation may have persisted because the routine store '
                'failed: FormatException: invalid routine snapshot. '
                'Inspect scheduled routines before retrying.',
          ),
        ];

        for (final testCase in cases) {
          final fixture = _fixture();
          testCase.configure(fixture);

          final result = await fixture.handler.handle(_request(ownerA));

          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.message);
        }
      },
    );

    test('preserves explicit noncommitted store outcomes', () async {
      final cases = [
        (
          result: RoutineStoreWriteResult.rejected(
            identity: _identity(ownerA),
            errorMessage: 'Routine persistence rejected the write.',
          ),
          message: 'Routine persistence rejected the write.',
        ),
        (
          result: RoutineStoreWriteResult.ownerExpired(
            identity: _identity(ownerA),
          ),
          message: 'Routine store rejected an owner that is still current.',
        ),
      ];

      for (final testCase in cases) {
        final fixture = _fixture();
        fixture.store.writeResults[ownerA] = testCase.result;

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, testCase.message);
        expect(fixture.store.compensations, isEmpty);
      }
    });

    test(
      'propagates approval failures before expiration and persistence',
      () async {
        final fixture = _fixture();
        fixture.approval.errors[ownerA] = StateError('approval unavailable');

        await expectLater(
          fixture.handler.handle(_request(ownerA)),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'approval unavailable',
            ),
          ),
        );
        expect(fixture.approval.expirationOwners, isEmpty);
        expect(fixture.store.creates, isEmpty);
      },
    );
  });

  group('CreateRoutineToolHandler owner poison', () {
    test(
      'rejects another owner approval before expiration or writes',
      () async {
        for (final poisonedIdentity in poisonedIdentities) {
          final fixture = _fixture();
          fixture.approval.decisions[ownerA] = RoutineCreationApprovalDecision(
            identity: poisonedIdentity,
            approved: true,
          );

          await expectLater(
            fixture.handler.handle(_request(ownerA)),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Routine creation approval identity mismatch',
              ),
            ),
          );
          expect(fixture.approval.expirationOwners, isEmpty);
          expect(fixture.store.creates, isEmpty);
        }
      },
    );

    test('contains another owner store completion as a failure', () async {
      for (final poisonedIdentity in poisonedIdentities) {
        final fixture = _fixture();
        fixture.store.writeResults[ownerA] = RoutineStoreWriteResult.committed(
          identity: poisonedIdentity,
          compensationToken: RoutineStoreCompensationToken(
            identity: poisonedIdentity,
            value: 'poisoned-write',
          ),
          snapshot: RoutineStoreSnapshot(
            identity: poisonedIdentity,
            routines: const [],
            createdRoutine: _routine(id: 'poisoned', name: 'Morning Routine'),
          ),
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'Routine creation may have persisted because the routine store '
          'returned a completion for another tool call. '
          'Inspect scheduled routines before retrying.',
        );
        expect(fixture.store.snapshotOwners, isEmpty);
      }
    });

    test(
      'rejects a compensation token from a concurrent exact-owner call',
      () async {
        final fixture = _fixture();
        final identity = _identity(ownerA);
        fixture.store.writeResults[ownerA] = RoutineStoreWriteResult.committed(
          identity: identity,
          compensationToken: RoutineStoreCompensationToken(
            identity: _identity(
              ownerA,
              toolCallId: 'call-create-routine-concurrent',
            ),
            value: 'poisoned-token',
          ),
          snapshot: RoutineStoreSnapshot(
            identity: identity,
            routines: const [],
            createdRoutine: _routine(id: 'poisoned', name: 'Morning Routine'),
          ),
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'Routine creation may have persisted because the committed write '
          'lacked an exact compensation token. '
          'Inspect scheduled routines before retrying.',
        );
        expect(fixture.store.compensations, isEmpty);
      },
    );

    test(
      'compensates a committed write that lacks an exact snapshot',
      () async {
        final fixture = _fixture();
        final identity = _identity(ownerA);
        fixture.store.writeResults[ownerA] = RoutineStoreWriteResult.committed(
          identity: identity,
          compensationToken: RoutineStoreCompensationToken(
            identity: identity,
            value: 'write-without-snapshot',
          ),
          snapshot: null,
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'Routine store committed without an exact snapshot.',
        );
        expect(fixture.store.compensations, hasLength(1));
        expect(
          fixture.store.compensations.single.identity.belongsTo(identity),
          isTrue,
        );
      },
    );

    test('contains another owner snapshot as a failure', () async {
      for (final poisonedIdentity in poisonedIdentities) {
        final fixture = _fixture();
        fixture.store.snapshots[ownerA] = RoutineStoreSnapshot(
          identity: poisonedIdentity,
          routines: [_routine(id: 'poisoned', name: 'Morning Routine')],
          createdRoutine: _routine(id: 'poisoned', name: 'Morning Routine'),
        );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(
          result.errorMessage,
          'Failed to create routine: '
          'Bad state: Routine store snapshot identity mismatch.',
        );
        expect(fixture.store.compensations.single.owner, ownerA);
      }
    });

    test(
      'compensates a committed routine when its owner expires in persistence',
      () async {
        const expired = McpToolResult(
          toolName: 'create_routine',
          result: '',
          isSuccess: false,
          errorMessage: 'The routine owner expired during persistence',
        );
        final fixture = _fixture();
        fixture.store.createCallbacks[ownerA] = () {
          fixture.approval.expirations[ownerA] = expired;
        };

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result, same(expired));
        final compensation = fixture.store.compensations.single;
        expect(compensation.owner, ownerA);
        expect(compensation.writeResult.owner, ownerA);
        expect(compensation.writeResult.didCommit, isTrue);
        expect(compensation.writeResult.compensationToken?.value, isNotEmpty);
        expect(fixture.store.snapshotOwners, [ownerA]);
        expect(fixture.events, [
          'approval.request:conversation-a:4',
          'approval.expired:conversation-a:4',
          'store.create:conversation-a:4',
          'store.snapshot:conversation-a:4',
          'approval.expired:conversation-a:4',
          'store.compensate:conversation-a:4',
        ]);
      },
    );

    test(
      'trusts ownerExpired only as an already-compensated no-write outcome',
      () async {
        const expired = McpToolResult(
          toolName: 'create_routine',
          result: '',
          isSuccess: false,
          errorMessage: 'The routine owner expired during persistence',
        );
        final fixture = _fixture();
        fixture.store.writeResults[ownerA] =
            RoutineStoreWriteResult.ownerExpired(identity: _identity(ownerA));
        fixture.store.createCallbacks[ownerA] = () {
          fixture.approval.expirations[ownerA] = expired;
        };

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result, same(expired));
        expect(fixture.store.compensations, isEmpty);
        expect(fixture.store.snapshotOwners, isEmpty);
        expect(result.isSuccess, isFalse);
      },
    );

    test(
      'reports a typed compensation failure instead of stale success',
      () async {
        const expired = McpToolResult(
          toolName: 'create_routine',
          result: '',
          isSuccess: false,
          errorMessage: 'The routine owner expired during persistence',
        );
        final fixture = _fixture();
        fixture.store.createCallbacks[ownerA] = () {
          fixture.approval.expirations[ownerA] = expired;
        };
        fixture.store.compensationResults[ownerA] =
            RoutineStoreCompensationResult(
              identity: _identity(ownerA),
              disposition: RoutineStoreCompensationDisposition.failed,
              errorMessage: 'delete unavailable',
            );

        final result = await fixture.handler.handle(_request(ownerA));

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Routine creation may still be persisted after owner invalidation '
          'because compensation failed: delete unavailable; '
          'inspect scheduled routines before retrying.',
        );
        expect(fixture.store.compensations, hasLength(1));
      },
    );

    test(
      'rejects poisoned post-write validity and compensation outcomes',
      () async {
        for (final poisonedIdentity in poisonedIdentities) {
          final fixture = _fixture();
          fixture.approval.ownerStates[ownerA] = [
            RoutineCreationOwnerState.current(identity: _identity(ownerA)),
            RoutineCreationOwnerState.current(identity: poisonedIdentity),
          ];
          fixture.store.compensationResults[ownerA] =
              RoutineStoreCompensationResult(
                identity: poisonedIdentity,
                disposition: RoutineStoreCompensationDisposition.reverted,
              );

          final result = await fixture.handler.handle(_request(ownerA));

          expect(result.isSuccess, isFalse);
          expect(
            result.errorMessage,
            'Routine creation may still be persisted after owner invalidation '
            'because compensation failed: Bad state: '
            'Routine store compensation identity mismatch; '
            'inspect scheduled routines before retrying.',
          );
          expect(fixture.store.compensations.single.owner, ownerA);
        }
      },
    );

    test(
      'uses only the exact owner approval, expiration, and snapshot',
      () async {
        const ownerBExpired = McpToolResult(
          toolName: 'create_routine',
          result: '',
          isSuccess: false,
          errorMessage: 'Owner B expired',
        );
        final fixture = _fixture();
        fixture.approval.decisions
          ..[ownerA] = RoutineCreationApprovalDecision(
            identity: _identity(ownerA),
            approved: true,
          )
          ..[ownerB] = RoutineCreationApprovalDecision(
            identity: _identity(ownerB),
            approved: false,
          )
          ..[ownerANextGeneration] = RoutineCreationApprovalDecision(
            identity: _identity(ownerANextGeneration),
            approved: false,
          );
        fixture.approval.expirations[ownerB] = ownerBExpired;
        fixture.store.snapshots
          ..[ownerA] = RoutineStoreSnapshot(
            identity: _identity(ownerA),
            routines: const [],
            createdRoutine: _routine(
              id: 'owner-a-routine',
              name: 'Morning Routine',
            ),
          )
          ..[ownerB] = RoutineStoreSnapshot(
            identity: _identity(ownerB),
            routines: [
              _routine(id: 'owner-b-routine', name: 'Morning Routine'),
            ],
            createdRoutine: _routine(
              id: 'owner-b-routine',
              name: 'Morning Routine',
            ),
          )
          ..[ownerANextGeneration] = RoutineStoreSnapshot(
            identity: _identity(ownerANextGeneration),
            routines: [
              _routine(id: 'owner-a-next-routine', name: 'Morning Routine'),
            ],
            createdRoutine: _routine(
              id: 'owner-a-next-routine',
              name: 'Morning Routine',
            ),
          );

        final result = await fixture.handler.handle(_request(ownerA));
        final payload = jsonDecode(result.result) as Map<String, dynamic>;

        expect(result.isSuccess, isTrue);
        expect(payload['id'], 'owner-a-routine');
        expect(fixture.approval.owners.toSet(), {ownerA});
        expect(fixture.store.owners.toSet(), {ownerA});
      },
    );
  });
}

CreateRoutineToolRequest _request(
  ChatTurnOwner owner, {
  String toolCallId = 'call-create-routine',
  String toolName = createRoutineToolName,
  Map<String, dynamic>? arguments,
}) {
  return CreateRoutineToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    arguments: arguments ?? _arguments(),
  );
}

CreateRoutineOperationIdentity _identity(
  ChatTurnOwner owner, {
  String toolCallId = 'call-create-routine',
}) {
  return CreateRoutineOperationIdentity(
    owner: owner,
    toolCallId: toolCallId,
    toolName: createRoutineToolName,
  );
}

Map<String, dynamic> _arguments([Map<String, dynamic> overrides = const {}]) {
  return {'name': 'Morning Routine', 'prompt': 'Start the day.', ...overrides};
}

Routine _routine({
  required String id,
  required String name,
  String prompt = 'Run the task.',
  DateTime? createdAt,
  DateTime? nextRunAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 7, 1);
  return Routine(
    id: id,
    name: name,
    prompt: prompt,
    createdAt: created,
    updatedAt: created,
    nextRunAt: nextRunAt,
  );
}

typedef _Fixture = ({
  CreateRoutineToolHandler handler,
  _StorePort store,
  _ApprovalPort approval,
  List<String> events,
});

_Fixture _fixture({List<Routine> routines = const []}) {
  final events = <String>[];
  final store = _StorePort(events, defaultRoutines: routines);
  final approval = _ApprovalPort(events);
  return (
    handler: CreateRoutineToolHandler(storePort: store, approvalPort: approval),
    store: store,
    approval: approval,
    events: events,
  );
}

typedef _CreateUse = ({ChatTurnOwner owner, RoutineStoreCreateRequest request});
typedef _CompensationUse = ({
  ChatTurnOwner owner,
  CreateRoutineOperationIdentity identity,
  RoutineStoreWriteResult writeResult,
});

final class _StorePort implements RoutineStorePort {
  _StorePort(this.events, {required this.defaultRoutines});

  final List<String> events;
  final List<Routine> defaultRoutines;
  final Map<ChatTurnOwner, RoutineStoreWriteResult> writeResults = {};
  final Map<ChatTurnOwner, RoutineStoreSnapshot> snapshots = {};
  final Map<ChatTurnOwner, Routine> createdRoutines = {};
  final Map<ChatTurnOwner, Object> createErrors = {};
  final Map<ChatTurnOwner, Object> snapshotErrors = {};
  final Map<ChatTurnOwner, Object> compensationErrors = {};
  final Map<ChatTurnOwner, RoutineStoreCompensationResult> compensationResults =
      {};
  final Map<ChatTurnOwner, void Function()> createCallbacks = {};
  final List<_CreateUse> creates = [];
  final List<_CompensationUse> compensations = [];
  final List<ChatTurnOwner> snapshotOwners = [];

  List<ChatTurnOwner> get owners => [
    ...creates.map((create) => create.owner),
    ...compensations.map((compensation) => compensation.owner),
    ...snapshotOwners,
  ];

  @override
  Future<RoutineStoreWriteResult> create(
    CreateRoutineOperationIdentity identity,
    RoutineStoreCreateRequest request,
  ) async {
    final owner = identity.owner;
    events.add(_event('store.create', owner));
    creates.add((owner: owner, request: request));
    final error = createErrors[owner];
    if (error != null) {
      throw error;
    }
    createCallbacks[owner]?.call();
    final configured = writeResults[owner];
    if (configured != null) return configured;
    events.add(_event('store.snapshot', owner));
    snapshotOwners.add(owner);
    final snapshotError = snapshotErrors[owner];
    if (snapshotError != null) {
      throw snapshotError;
    }
    final snapshot =
        snapshots[owner] ??
        RoutineStoreSnapshot(
          identity: identity,
          routines: defaultRoutines,
          createdRoutine:
              createdRoutines[owner] ??
              (defaultRoutines.isEmpty
                  ? _routine(id: 'created-routine', name: request.name)
                  : defaultRoutines.first),
        );
    return RoutineStoreWriteResult.committed(
      identity: identity,
      compensationToken: RoutineStoreCompensationToken(
        identity: identity,
        value: 'routine-write:${owner.interactionGeneration}:${creates.length}',
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<RoutineStoreCompensationResult> compensate(
    CreateRoutineOperationIdentity identity,
    RoutineStoreWriteResult committedWrite,
  ) async {
    final owner = identity.owner;
    events.add(_event('store.compensate', owner));
    compensations.add((
      owner: owner,
      identity: identity,
      writeResult: committedWrite,
    ));
    final error = compensationErrors[owner];
    if (error != null) {
      throw error;
    }
    return compensationResults[owner] ??
        RoutineStoreCompensationResult(
          identity: identity,
          disposition: RoutineStoreCompensationDisposition.reverted,
        );
  }
}

typedef _ApprovalUse = ({
  ChatTurnOwner owner,
  RoutineCreationApprovalRequest request,
});

final class _ApprovalPort implements RoutineCreationApprovalPort {
  _ApprovalPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, RoutineCreationApprovalDecision> decisions = {};
  final Map<ChatTurnOwner, McpToolResult> expirations = {};
  final Map<ChatTurnOwner, List<RoutineCreationOwnerState>> ownerStates = {};
  final Map<ChatTurnOwner, Object> errors = {};
  final List<_ApprovalUse> requests = [];
  final List<ChatTurnOwner> expirationOwners = [];

  List<ChatTurnOwner> get owners => [
    ...requests.map((request) => request.owner),
    ...expirationOwners,
  ];

  @override
  Future<RoutineCreationApprovalDecision> requestApproval(
    CreateRoutineOperationIdentity identity,
    RoutineCreationApprovalRequest request,
  ) async {
    final owner = identity.owner;
    events.add(_event('approval.request', owner));
    requests.add((owner: owner, request: request));
    final error = errors[owner];
    if (error != null) {
      throw error;
    }
    return decisions[owner] ??
        RoutineCreationApprovalDecision(identity: identity, approved: true);
  }

  @override
  RoutineCreationOwnerState ownerState(
    CreateRoutineOperationIdentity identity,
    CreateRoutineToolRequest request,
  ) {
    final owner = identity.owner;
    events.add(_event('approval.expired', owner));
    expirationOwners.add(owner);
    expect(request.owner, owner);
    final queuedStates = ownerStates[owner];
    if (queuedStates != null && queuedStates.isNotEmpty) {
      return queuedStates.removeAt(0);
    }
    final expired = expirations[owner];
    return expired == null
        ? RoutineCreationOwnerState.current(identity: identity)
        : RoutineCreationOwnerState.expired(
            identity: identity,
            result: expired,
          );
  }
}

String _event(String name, ChatTurnOwner owner) {
  return '$name:${owner.conversationId}:${owner.interactionGeneration}';
}

import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/participant_tool_executor.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final ChatTurnOwner _ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final ChatTurnOwner _ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 7,
);
final ChatTurnOwner _ownerANext = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 8,
);

final class _ApprovalPort implements ParticipantToolApprovalPort {
  _ApprovalPort(this.events);

  final List<String> events;
  final List<ParticipantToolApprovalRequest> requests = [];
  ToolApprovalOutcome outcome = const ToolApprovalOutcome.approved(
    gateDecision: ToolApprovalGateDecision.needsManualApproval,
  );
  ParticipantToolScope? responseScope;
  Completer<ParticipantToolApprovalResult>? pending;
  Object? error;

  @override
  Future<ParticipantToolApprovalResult> resolve(
    ParticipantToolApprovalRequest request,
  ) async {
    requests.add(request);
    events.add('approval');
    final portError = error;
    if (portError != null) throw portError;
    final pendingResult = pending;
    if (pendingResult != null) return pendingResult.future;
    return ParticipantToolApprovalResult(
      scope: responseScope ?? request.scope,
      outcome: outcome,
    );
  }
}

final class _ExecutionPort implements ParticipantToolExecutionPort {
  _ExecutionPort(this.events);

  final List<String> events;
  final List<ParticipantToolExecutionRequest> requests = [];
  McpToolResult result = const McpToolResult(
    toolName: 'read_file',
    result: 'file contents',
    isSuccess: true,
  );
  ParticipantToolScope? responseScope;
  Object? error;

  @override
  Future<ParticipantToolExecutionResult> execute(
    ParticipantToolExecutionRequest request,
  ) async {
    requests.add(request);
    events.add('execute');
    final portError = error;
    if (portError != null) throw portError;
    return ParticipantToolExecutionResult(
      scope: responseScope ?? request.scope,
      result: result,
    );
  }
}

final class _ActivityPort implements ParticipantToolActivityPort {
  _ActivityPort(this.events);

  final List<String> events;
  final List<ParticipantToolActivityUpdate> updates = [];
  ParticipantToolScope? startScope;
  ParticipantToolScope? clearScope;
  Object? startError;
  Object? clearError;

  @override
  ParticipantToolScopeAcknowledgement update(
    ParticipantToolActivityUpdate update,
  ) {
    updates.add(update);
    events.add(
      update.activeToolName.isEmpty ? 'activity:clear' : 'activity:start',
    );
    final isClear = update.activeToolName.isEmpty;
    final error = isClear ? clearError : startError;
    if (error != null) throw error;
    return ParticipantToolScopeAcknowledgement(
      scope: isClear ? clearScope ?? update.scope : startScope ?? update.scope,
    );
  }
}

final class _TaintPort implements ParticipantToolTaintPort {
  _TaintPort(this.events);

  final List<String> events;
  final List<ParticipantToolTaintEvent> records = [];
  ParticipantToolScope? responseScope;
  Object? error;

  @override
  ParticipantToolScopeAcknowledgement record(ParticipantToolTaintEvent event) {
    records.add(event);
    events.add('taint');
    final portError = error;
    if (portError != null) throw portError;
    return ParticipantToolScopeAcknowledgement(
      scope: responseScope ?? event.scope,
    );
  }
}

final class _Fixture {
  _Fixture({bool hasExecutionPort = true}) {
    approval = _ApprovalPort(events);
    execution = _ExecutionPort(events);
    activity = _ActivityPort(events);
    taint = _TaintPort(events);
    executor = ParticipantToolExecutor(
      approvalPort: approval,
      executionPort: hasExecutionPort ? execution : null,
      activityPort: activity,
      taintPort: taint,
    );
  }

  final List<String> events = [];
  late final _ApprovalPort approval;
  late final _ExecutionPort execution;
  late final _ActivityPort activity;
  late final _TaintPort taint;
  late final ParticipantToolExecutor executor;
}

ConversationParticipant _participant({
  String id = 'participant-a',
  String displayName = 'Researcher',
  String roleLabel = 'Evidence reviewer',
  ToolApprovalMode approvalMode = ToolApprovalMode.defaultPermissions,
  bool toolsEnabled = true,
}) {
  return ConversationParticipant(
    id: id,
    displayName: displayName,
    roleLabel: roleLabel,
    toolApprovalMode: approvalMode,
    toolsEnabled: toolsEnabled,
  );
}

Map<String, dynamic> _definition(String name) {
  return <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': '$name description',
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'path': <String, dynamic>{'type': 'string'},
        },
      },
    },
  };
}

ParticipantToolSession _session({
  ChatTurnOwner? owner,
  ConversationParticipant? participant,
  bool supportsToolAwareRequests = true,
  List<Map<String, dynamic>>? definitions,
  List<Message>? conversationMessages,
  bool hasUntrustedInfluence = false,
}) {
  return ParticipantToolSession(
    owner: owner ?? _ownerA,
    participant: participant ?? _participant(),
    supportsToolAwareRequests: supportsToolAwareRequests,
    availableDefinitions:
        definitions ??
        <Map<String, dynamic>>[
          _definition('read_file'),
          _definition('web_search'),
        ],
    conversationMessages:
        conversationMessages ??
        <Message>[
          Message(
            id: 'user-1',
            content: 'Inspect the evidence.',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ],
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

ToolCallInfo _call({
  String id = 'call-1',
  String name = 'read_file',
  Map<String, dynamic>? arguments,
}) {
  return ToolCallInfo(
    id: id,
    name: name,
    arguments:
        arguments ??
        <String, dynamic>{
          'path': 'lib/main.dart',
          'reason': 'Inspect the implementation.',
        },
  );
}

McpToolResult _denial(String message) {
  return McpToolResult(
    toolName: 'read_file',
    result: message,
    isSuccess: false,
    errorMessage: message,
  );
}

void main() {
  group('scope and immutable inputs', () {
    test(
      'scope identity includes conversation, generation, and participant',
      () {
        final scope = ParticipantToolScope(
          owner: _ownerA,
          participantId: 'participant-a',
        );
        final equalScope = ParticipantToolScope(
          owner: _ownerA,
          participantId: 'participant-a',
        );

        expect(scope, equalScope);
        expect(scope.hashCode, equalScope.hashCode);
        expect(
          scope.matches(
            ParticipantToolScope(
              owner: _ownerB,
              participantId: 'participant-a',
            ),
          ),
          isFalse,
        );
        expect(
          scope.matches(
            ParticipantToolScope(
              owner: _ownerANext,
              participantId: 'participant-a',
            ),
          ),
          isFalse,
        );
        expect(
          scope.matches(
            ParticipantToolScope(
              owner: _ownerA,
              participantId: 'participant-b',
            ),
          ),
          isFalse,
        );
        expect(scope == Object(), isFalse);
        expect(
          () => ParticipantToolScope(owner: _ownerA, participantId: '  '),
          throwsArgumentError,
        );
      },
    );

    test('session deep-freezes definitions and snapshots messages', () {
      final definitions = <Map<String, dynamic>>[_definition('read_file')];
      final messages = <Message>[
        Message(
          id: 'user-1',
          content: 'Original message',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ];
      final session = _session(
        definitions: definitions,
        conversationMessages: messages,
      );

      (definitions.single['function'] as Map<String, dynamic>)['name'] =
          'write_file';
      messages.clear();

      expect(
        session.availableDefinitions.single['function'],
        containsPair('name', 'read_file'),
      );
      expect(session.conversationMessages, hasLength(1));
      expect(
        () => session.availableDefinitions.add(_definition('web_search')),
        throwsUnsupportedError,
      );
      expect(
        () => (session.availableDefinitions.single['function'] as Map)['name'] =
            'write_file',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (((session.availableDefinitions.single['function']
                        as Map)['parameters']
                    as Map)['properties']
                as Map)['other'] = const {
              'type': 'string',
            },
        throwsUnsupportedError,
      );
    });

    test('execution input deep-freezes JSON maps and lists', () {
      final labels = <Object?>['source'];
      final flags = <Object?>['safe'];
      final metadata = <String, dynamic>{'labels': labels, 'flags': flags};
      final arguments = <String, dynamic>{'metadata': metadata};
      final request = ParticipantToolExecutionRequest(
        scope: _session().scope,
        toolCallId: 'call-immutable',
        toolName: 'read_file',
        arguments: arguments,
      );

      labels.add('poisoned');
      flags.add('poisoned');
      metadata['labels'] = <Object?>['replaced'];
      arguments['metadata'] = <String, dynamic>{};

      expect(request.arguments['metadata'], {
        'labels': ['source'],
        'flags': ['safe'],
      });
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

    test('rejects non-JSON argument values before approval or execution', () {
      final fixture = _Fixture();
      final invalidArguments = <Map<String, dynamic>>[
        {
          'metadata': <Object?, Object?>{7: 'invalid'},
        },
        {
          'metadata': <Object?>{'not-json'},
        },
        {'metadata': Object()},
        {'metadata': double.nan},
        {'metadata': double.infinity},
        {'metadata': double.negativeInfinity},
      ];

      for (final arguments in invalidArguments) {
        expect(
          () =>
              fixture.executor.execute(_session(), _call(arguments: arguments)),
          throwsArgumentError,
          reason: arguments.toString(),
        );
      }
      expect(fixture.approval.requests, isEmpty);
      expect(fixture.execution.requests, isEmpty);
    });
  });

  group('definition filtering', () {
    test('keeps only allowed first definitions in immutable order', () {
      final fixture = _Fixture();
      final definitions = fixture.executor.definitionsFor(
        _session(
          definitions: <Map<String, dynamic>>[
            _definition('read_file'),
            _definition('write_file'),
            <String, dynamic>{'type': 'function'},
            <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{'name': '   '},
            },
            _definition('web_search'),
            _definition('read_file'),
          ],
        ),
      );

      expect(
        definitions
            .map(
              (definition) =>
                  (definition['function'] as Map<String, dynamic>)['name'],
            )
            .toList(),
        <String>['read_file', 'web_search'],
      );
      expect(
        () => definitions.add(_definition('find_files')),
        throwsUnsupportedError,
      );
      expect(
        () => (definitions.first['function'] as Map)['name'] = 'write_file',
        throwsUnsupportedError,
      );
    });

    test('returns no definitions when tools are disabled or unsupported', () {
      final fixture = _Fixture();

      expect(
        fixture.executor.definitionsFor(
          _session(participant: _participant(toolsEnabled: false)),
        ),
        isEmpty,
      );
      expect(
        fixture.executor.definitionsFor(
          _session(supportsToolAwareRequests: false),
        ),
        isEmpty,
      );
      expect(
        _Fixture(hasExecutionPort: false).executor.definitionsFor(_session()),
        isEmpty,
      );
    });
  });

  group('policy and availability', () {
    test('forwards the exact policy denial without touching ports', () async {
      final fixture = _Fixture(hasExecutionPort: false);

      final result = await fixture.executor.execute(
        _session(),
        _call(name: 'write_file'),
      );

      expect(result.toolName, 'write_file');
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Participant tools do not allow write_file.');
      expect(
        result.result,
        '{"error":"Participant tool calls are limited to search, datetime, past conversation search, and read-only inspection tools.","code":"permission_denied","reason":"participant_tools_require_read_only_allowlist","tool":"write_file"}',
      );
      expect(fixture.events, isEmpty);
    });

    test(
      'returns the exact unavailable execution result before approval',
      () async {
        final fixture = _Fixture(hasExecutionPort: false);

        final result = await fixture.executor.execute(_session(), _call());

        expect(result.toolName, 'read_file');
        expect(result.result, '');
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'Participant tool service is unavailable.');
        expect(fixture.events, isEmpty);
      },
    );
  });

  group('typed approval request', () {
    test(
      'preserves exact review keys, manual arguments, and owner facts',
      () async {
        final fixture = _Fixture();
        final rawArguments = <String, dynamic>{
          'path': 'docs/spec.md',
          'reason': '  Verify the requirements.  ',
          'filters': <String, dynamic>{
            'extensions': <String>['md', 'txt'],
          },
        };
        final messages = <Message>[
          Message(
            id: 'user-approval',
            content: 'Review the specification.',
            role: MessageRole.user,
            timestamp: DateTime(2026),
          ),
        ];
        final session = _session(
          participant: _participant(
            displayName: '',
            roleLabel: '',
            approvalMode: ToolApprovalMode.autoReview,
          ),
          conversationMessages: messages,
          hasUntrustedInfluence: true,
        );

        await fixture.executor.execute(
          session,
          _call(
            id: 'approval-call',
            name: 'inspect_file',
            arguments: rawArguments,
          ),
        );
        final request = fixture.approval.requests.single;
        final coordinator = request.coordinatorRequest;

        expect(request.scope, session.scope);
        expect(coordinator.owner, _ownerA);
        expect(coordinator.toolCallId, 'approval-call');
        expect(coordinator.toolName, 'inspect_file');
        expect(coordinator.actionKind, 'participant_read_only_tool');
        expect(coordinator.mode, ToolApprovalMode.autoReview);
        expect(
          coordinator.reviewDomain,
          ToolApprovalAutoReviewDomain.participant,
        );
        expect(coordinator.fullAccessEligible, isTrue);
        expect(coordinator.cacheArguments, isNull);
        expect(coordinator.reason, '  Verify the requirements.  ');
        expect(coordinator.conversationMessages, messages);
        expect(coordinator.conversationMessages, isNot(same(messages)));
        expect(coordinator.hasUntrustedInfluence, isTrue);
        expect(coordinator.arguments.keys.toList(), <String>[
          'participantId',
          'participantName',
          'participantRoleLabel',
          'toolArguments',
        ]);
        expect(coordinator.arguments, {
          'participantId': 'participant-a',
          'participantName': 'Assistant',
          'participantRoleLabel': 'Assistant',
          'toolArguments': rawArguments,
        });
        expect(request.manualArguments, rawArguments);

        (rawArguments['filters'] as Map<String, dynamic>)['extensions'] = [
          'exe',
        ];
        expect(
          (request.manualArguments['filters'] as Map)['extensions'],
          <String>['md', 'txt'],
        );
        expect(
          () => request.manualArguments['path'] = 'changed',
          throwsUnsupportedError,
        );
        expect(
          () =>
              ((coordinator.arguments['toolArguments'] as Map)['filters']
                      as Map)['other'] =
                  true,
          throwsUnsupportedError,
        );
      },
    );

    test('routes every approval mode through the typed request', () async {
      final cases =
          <
            ({
              ToolApprovalMode mode,
              ToolApprovalGateDecision gate,
              bool rememberApproval,
            })
          >[
            (
              mode: ToolApprovalMode.defaultPermissions,
              gate: ToolApprovalGateDecision.needsManualApproval,
              rememberApproval: true,
            ),
            (
              mode: ToolApprovalMode.autoReview,
              gate: ToolApprovalGateDecision.autoReviewAllowed,
              rememberApproval: false,
            ),
            (
              mode: ToolApprovalMode.autoReview,
              gate: ToolApprovalGateDecision.needsManualApproval,
              rememberApproval: false,
            ),
            (
              mode: ToolApprovalMode.fullAccess,
              gate: ToolApprovalGateDecision.fullAccess,
              rememberApproval: false,
            ),
            (
              mode: ToolApprovalMode.defaultPermissions,
              gate: ToolApprovalGateDecision.cachedApproval,
              rememberApproval: false,
            ),
          ];

      for (final testCase in cases) {
        final fixture = _Fixture();
        fixture.approval.outcome = ToolApprovalOutcome.approved(
          gateDecision: testCase.gate,
          rememberApproval: testCase.rememberApproval,
        );

        await fixture.executor.execute(
          _session(participant: _participant(approvalMode: testCase.mode)),
          _call(),
        );

        expect(
          fixture.approval.requests.single.coordinatorRequest.mode,
          testCase.mode,
        );
        expect(fixture.events, <String>[
          'approval',
          'activity:start',
          'execute',
          'taint',
          'activity:clear',
        ]);
      }
    });

    test(
      'forwards auto-review and manual denials without side effects',
      () async {
        final autoReviewDenial = _denial(
          'Auto-review denied: unrelated lookup',
        );
        final manualDenial = ParticipantToolExecutor.manualApprovalDeniedResult(
          'read_file',
        );
        final cachedDenial = _denial('Previously denied.');
        final cases =
            <
              ({
                ToolApprovalMode mode,
                McpToolResult denial,
                ToolApprovalGateDecision? gate,
                bool reusedCachedDenial,
              })
            >[
              (
                mode: ToolApprovalMode.autoReview,
                denial: autoReviewDenial,
                gate: ToolApprovalGateDecision.denied('Denied.'),
                reusedCachedDenial: false,
              ),
              (
                mode: ToolApprovalMode.defaultPermissions,
                denial: manualDenial,
                gate: ToolApprovalGateDecision.needsManualApproval,
                reusedCachedDenial: false,
              ),
              (
                mode: ToolApprovalMode.defaultPermissions,
                denial: cachedDenial,
                gate: null,
                reusedCachedDenial: true,
              ),
            ];

        for (final testCase in cases) {
          final fixture = _Fixture();
          fixture.approval.outcome = ToolApprovalOutcome.denied(
            denialResult: testCase.denial,
            gateDecision: testCase.gate,
            reusedCachedDenial: testCase.reusedCachedDenial,
          );

          final result = await fixture.executor.execute(
            _session(participant: _participant(approvalMode: testCase.mode)),
            _call(),
          );

          expect(result, same(testCase.denial));
          expect(fixture.events, <String>['approval']);
        }
      },
    );

    test('builds the exact manual denial JSON', () {
      final result = ParticipantToolExecutor.manualApprovalDeniedResult(
        'read_file',
      );

      expect(result.toolName, 'read_file');
      expect(
        result.result,
        '{"ok":false,"code":"approval_denied","error":"User denied the participant tool action.","nextAction":"Ask the user for explicit approval before retrying this participant tool."}',
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User denied participant tool action.');
    });

    test('does not start activity when approval throws', () async {
      final fixture = _Fixture();
      fixture.approval.error = StateError('approval unavailable');

      await expectLater(
        fixture.executor.execute(_session(), _call()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'approval unavailable',
          ),
        ),
      );
      expect(fixture.events, <String>['approval']);
    });
  });

  group('execution, activity, and taint', () {
    test(
      'forwards successful and failed results in exact call order',
      () async {
        final results = <McpToolResult>[
          const McpToolResult(
            toolName: 'read_file',
            result: 'contents',
            isSuccess: true,
            isExternalMcpResult: true,
          ),
          const McpToolResult(
            toolName: 'read_file',
            result: '{"error":"not found"}',
            isSuccess: false,
            errorMessage: 'File not found.',
          ),
        ];

        for (final expected in results) {
          final fixture = _Fixture();
          fixture.execution.result = expected;

          final actual = await fixture.executor.execute(_session(), _call());

          expect(actual, same(expected));
          expect(fixture.events, <String>[
            'approval',
            'activity:start',
            'execute',
            'taint',
            'activity:clear',
          ]);
          final executionRequest = fixture.execution.requests.single;
          expect(executionRequest.scope, _session().scope);
          expect(executionRequest.toolCallId, 'call-1');
          expect(executionRequest.toolName, 'read_file');
          expect(executionRequest.arguments, {
            'path': 'lib/main.dart',
            'reason': 'Inspect the implementation.',
          });
          expect(
            () => executionRequest.arguments['path'] = 'changed',
            throwsUnsupportedError,
          );
          expect(fixture.activity.updates.map((item) => item.activeToolName), [
            'read_file',
            '',
          ]);
          expect(fixture.taint.records.single.result, same(expected));
          expect(fixture.taint.records.single.scope, _session().scope);
        }
      },
    );

    test('clears activity and skips taint when execution throws', () async {
      final fixture = _Fixture();
      fixture.execution.error = StateError('transport failed');

      await expectLater(
        fixture.executor.execute(_session(), _call()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'transport failed',
          ),
        ),
      );

      expect(fixture.events, <String>[
        'approval',
        'activity:start',
        'execute',
        'activity:clear',
      ]);
      expect(fixture.taint.records, isEmpty);
    });

    test('clears activity when start or taint fails', () async {
      final startFixture = _Fixture();
      startFixture.activity.startError = StateError('activity unavailable');

      await expectLater(
        startFixture.executor.execute(_session(), _call()),
        throwsStateError,
      );
      expect(startFixture.events, <String>[
        'approval',
        'activity:start',
        'activity:clear',
      ]);
      expect(startFixture.execution.requests, isEmpty);

      final taintFixture = _Fixture();
      taintFixture.taint.error = StateError('taint unavailable');

      await expectLater(
        taintFixture.executor.execute(_session(), _call()),
        throwsStateError,
      );
      expect(taintFixture.events, <String>[
        'approval',
        'activity:start',
        'execute',
        'taint',
        'activity:clear',
      ]);
    });
  });

  group('owner and participant poison', () {
    test(
      'delayed owner A completion stays attached while B is visible',
      () async {
        final fixture = _Fixture();
        final pending = Completer<ParticipantToolApprovalResult>();
        fixture.approval.pending = pending;
        final sessionA = _session(owner: _ownerA);

        final future = fixture.executor.execute(sessionA, _call());
        await Future<void>.delayed(Duration.zero);
        final visibleScope = ParticipantToolScope(
          owner: _ownerB,
          participantId: 'participant-b',
        );
        expect(visibleScope.matches(sessionA.scope), isFalse);

        pending.complete(
          ParticipantToolApprovalResult(
            scope: sessionA.scope,
            outcome: const ToolApprovalOutcome.approved(
              gateDecision: ToolApprovalGateDecision.autoReviewAllowed,
            ),
          ),
        );
        final result = await future;

        expect(result, same(fixture.execution.result));
        expect(fixture.approval.requests.single.scope, sessionA.scope);
        expect(fixture.execution.requests.single.scope, sessionA.scope);
        expect(
          fixture.activity.updates.every(
            (update) => update.scope == sessionA.scope,
          ),
          isTrue,
        );
        expect(fixture.taint.records.single.scope, sessionA.scope);
      },
    );

    test(
      'rejects wrong approval owner or participant before activity',
      () async {
        for (final poison in <ParticipantToolScope>[
          ParticipantToolScope(owner: _ownerB, participantId: 'participant-a'),
          ParticipantToolScope(
            owner: _ownerANext,
            participantId: 'participant-a',
          ),
          ParticipantToolScope(owner: _ownerA, participantId: 'participant-b'),
        ]) {
          final fixture = _Fixture();
          fixture.approval.responseScope = poison;

          await expectLater(
            fixture.executor.execute(_session(), _call()),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Participant tool approval scope mismatch.',
              ),
            ),
          );
          expect(fixture.events, <String>['approval']);
        }
      },
    );

    test(
      'rejects wrong execution scope and still clears owner activity',
      () async {
        final fixture = _Fixture();
        fixture.execution.responseScope = ParticipantToolScope(
          owner: _ownerB,
          participantId: 'participant-a',
        );

        await expectLater(
          fixture.executor.execute(_session(), _call()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Participant tool execution scope mismatch.',
            ),
          ),
        );
        expect(fixture.events, <String>[
          'approval',
          'activity:start',
          'execute',
          'activity:clear',
        ]);
        expect(fixture.taint.records, isEmpty);
      },
    );

    test('rejects wrong activity start and clear acknowledgements', () async {
      final startFixture = _Fixture();
      startFixture.activity.startScope = ParticipantToolScope(
        owner: _ownerA,
        participantId: 'participant-b',
      );

      await expectLater(
        startFixture.executor.execute(_session(), _call()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Participant tool activity start scope mismatch.',
          ),
        ),
      );
      expect(startFixture.events, <String>[
        'approval',
        'activity:start',
        'activity:clear',
      ]);

      final clearFixture = _Fixture();
      clearFixture.activity.clearScope = ParticipantToolScope(
        owner: _ownerANext,
        participantId: 'participant-a',
      );

      await expectLater(
        clearFixture.executor.execute(_session(), _call()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Participant tool activity clear scope mismatch.',
          ),
        ),
      );
      expect(clearFixture.events.last, 'activity:clear');
      expect(clearFixture.taint.records, hasLength(1));
    });

    test(
      'rejects wrong taint scope after result and clears activity',
      () async {
        final fixture = _Fixture();
        fixture.taint.responseScope = ParticipantToolScope(
          owner: _ownerA,
          participantId: 'participant-b',
        );

        await expectLater(
          fixture.executor.execute(_session(), _call()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Participant tool taint scope mismatch.',
            ),
          ),
        );
        expect(fixture.events, <String>[
          'approval',
          'activity:start',
          'execute',
          'taint',
          'activity:clear',
        ]);
      },
    );
  });
}

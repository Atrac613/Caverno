import 'package:caverno/features/chat/data/datasources/run_tests_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/local_command_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/run_tests_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('RunTestsRuntimeIdentity', () {
    test('uses canonical strict JSON and every execution fact', () {
      final first = RunTestsRuntimeIdentity.fromInput(
        _input(
          arguments: {
            'runner': 'dart',
            'metadata': {
              'z': true,
              'a': [1, true],
            },
          },
        ),
      );
      final reordered = RunTestsRuntimeIdentity.fromInput(
        _input(
          arguments: {
            'metadata': {
              'a': [1, true],
              'z': true,
            },
            'runner': 'dart',
          },
        ),
      );

      expect(first, reordered);
      expect(
        first,
        isNot(
          RunTestsRuntimeIdentity.fromInput(
            _input(arguments: const {'runner': 'flutter'}),
          ),
        ),
      );
      expect(
        first,
        isNot(
          RunTestsRuntimeIdentity.fromInput(
            _input(projectRoot: '/workspace/other'),
          ),
        ),
      );
      expect(
        RunTestsRuntimeIdentity.fromInput(
          _input(projectRoot: '/workspace/nested/../project'),
        ).projectRoot,
        '/workspace/project',
      );
    });
  });

  group('RunTestsToolRuntimeAdapter', () {
    test('grants exact project access and runs the scoped command', () async {
      final fixture = _Fixture();

      final result = await fixture.handle(arguments: const {'runner': 'dart'});

      expect(result.isSuccess, isTrue);
      expect(result.toolName, 'run_tests');
      expect(fixture.runtime.accessRequests, hasLength(1));
      expect(fixture.execution.requests.single.command, 'dart test');
      expect(fixture.runtime.ownerAcknowledgements, hasLength(2));
    });

    test('preserves validation ordering without touching runtime', () async {
      final fixture = _Fixture();

      final result = await fixture.handle(projectRoot: null);

      _expectCode(result, 'project_required');
      expect(fixture.runtime.accessRequests, isEmpty);
      expect(fixture.execution.requests, isEmpty);
    });

    test('does not request access after owner retirement', () async {
      final fixture = _Fixture()
        ..runtime.ownerDispositions.add(
          RunTestsRuntimeOwnerDisposition.ownerExpired,
        );

      final result = await fixture.handle();

      _expectCode(result, 'turn_expired');
      expect(fixture.runtime.accessRequests, isEmpty);
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects a poisoned owner acknowledgement before access', () async {
      final fixture = _Fixture()
        ..runtime.ownerIdentityTransform = (identity) =>
            RunTestsRuntimeIdentity(
              owner: _otherOwner,
              toolCallId: identity.toolCallId,
              toolName: identity.toolName,
              projectRoot: identity.projectRoot,
              argumentDigest: identity.argumentDigest,
            );

      final result = await fixture.handle();

      _expectCode(result, 'run_tests_boundary_mismatch');
      expect(fixture.runtime.accessRequests, isEmpty);
      expect(fixture.execution.requests, isEmpty);
    });

    test('maps an unavailable owner state before access', () async {
      final fixture = _Fixture()
        ..runtime.ownerError = StateError('registry unavailable');

      final result = await fixture.handle();

      _expectCode(result, 'run_tests_owner_state_unavailable');
      expect(fixture.runtime.accessRequests, isEmpty);
    });

    test('maps a thrown access boundary to explicit uncertainty', () async {
      final fixture = _Fixture()
        ..runtime.accessError = StateError('bookmark response lost');

      final result = await fixture.handle();

      _expectCode(result, 'run_tests_project_access_effect_uncertain');
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects every poisoned access receipt identity', () async {
      final poisoners =
          <RunTestsRuntimeIdentity Function(RunTestsRuntimeIdentity)>[
            (identity) => RunTestsRuntimeIdentity(
              owner: _otherOwner,
              toolCallId: identity.toolCallId,
              toolName: identity.toolName,
              projectRoot: identity.projectRoot,
              argumentDigest: identity.argumentDigest,
            ),
            (identity) => RunTestsRuntimeIdentity(
              owner: identity.owner,
              toolCallId: 'other-call',
              toolName: identity.toolName,
              projectRoot: identity.projectRoot,
              argumentDigest: identity.argumentDigest,
            ),
            (identity) => RunTestsRuntimeIdentity(
              owner: identity.owner,
              toolCallId: identity.toolCallId,
              toolName: identity.toolName,
              projectRoot: '/workspace/other',
              argumentDigest: identity.argumentDigest,
            ),
            (identity) => RunTestsRuntimeIdentity(
              owner: identity.owner,
              toolCallId: identity.toolCallId,
              toolName: identity.toolName,
              projectRoot: identity.projectRoot,
              argumentDigest: 'other-digest',
            ),
          ];

      for (final poison in poisoners) {
        final fixture = _Fixture()..runtime.accessIdentityTransform = poison;
        final result = await fixture.handle();
        _expectCode(result, 'run_tests_project_access_effect_uncertain');
        expect(fixture.execution.requests, isEmpty);
      }
    });

    test('preserves an exact access denial', () async {
      final denied = const McpToolResult(
        toolName: 'run_tests',
        result: '{"code":"bookmark_restore_failed"}',
        isSuccess: false,
        errorMessage: 'Bookmark restore failed',
      );
      final fixture = _Fixture()
        ..runtime.accessDisposition =
            RunTestsProjectAccessRuntimeDisposition.denied
        ..runtime.failure = denied;

      final result = await fixture.handle();

      expect(result, same(denied));
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects malformed access denials as uncertain', () async {
      final fixture = _Fixture()
        ..runtime.accessDisposition =
            RunTestsProjectAccessRuntimeDisposition.denied
        ..runtime.failure = const McpToolResult(
          toolName: 'other-tool',
          result: 'invalid',
          isSuccess: true,
        );

      final result = await fixture.handle();

      _expectCode(result, 'run_tests_project_access_effect_uncertain');
      expect(fixture.execution.requests, isEmpty);
    });

    test('expires when the owner changes after access', () async {
      final fixture = _Fixture()
        ..runtime.ownerDispositions.addAll([
          RunTestsRuntimeOwnerDisposition.current,
          RunTestsRuntimeOwnerDisposition.ownerExpired,
        ]);

      final result = await fixture.handle();

      _expectCode(result, 'turn_expired');
      expect(fixture.runtime.accessRequests, hasLength(1));
      expect(fixture.execution.requests, isEmpty);
    });

    test('maps explicit uncertain access without command execution', () async {
      final fixture = _Fixture()
        ..runtime.accessDisposition =
            RunTestsProjectAccessRuntimeDisposition.effectUncertain;

      final result = await fixture.handle();

      _expectCode(result, 'run_tests_project_access_effect_uncertain');
      expect(fixture.execution.requests, isEmpty);
    });
  });
}

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 4,
);
final _otherOwner = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 4,
);

RunTestsToolInput _input({
  Map<String, dynamic> arguments = const {'runner': 'dart'},
  String? projectRoot = '/workspace/project',
}) {
  return RunTestsToolInput(
    owner: _owner,
    toolCallId: 'call-run-tests',
    toolName: 'run_tests',
    ownerProjectRoot: projectRoot,
    arguments: arguments,
  );
}

void _expectCode(McpToolResult result, String code) {
  expect(result.isSuccess, isFalse);
  expect(result.result, contains('"code":"$code"'));
}

final class _Fixture {
  final runtime = _RuntimePort();
  final execution = _ExecutionPort();
  final approval = _ApprovalPort();
  final rules = _RuleStore();

  Future<McpToolResult> handle({
    Map<String, dynamic> arguments = const {'runner': 'dart'},
    String? projectRoot = '/workspace/project',
  }) {
    return RunTestsToolRuntimeAdapter(
      runtimePort: runtime,
      executionPort: execution,
      approvalPort: approval,
      permissionRuleStorePort: rules,
      evidencePort: const _EvidencePort(),
    ).handle(_input(arguments: arguments, projectRoot: projectRoot));
  }
}

final class _RuntimePort implements RunTestsRuntimePort {
  final List<RunTestsRuntimeIdentity> ownerAcknowledgements = [];
  final List<RunTestsProjectAccessRuntimeRequest> accessRequests = [];
  final List<RunTestsRuntimeOwnerDisposition> ownerDispositions = [];
  RunTestsRuntimeIdentity Function(RunTestsRuntimeIdentity)?
  ownerIdentityTransform;
  RunTestsRuntimeIdentity Function(RunTestsRuntimeIdentity)?
  accessIdentityTransform;
  RunTestsProjectAccessRuntimeDisposition accessDisposition =
      RunTestsProjectAccessRuntimeDisposition.granted;
  McpToolResult? failure;
  Object? ownerError;
  Object? accessError;

  @override
  RunTestsRuntimeOwnerAcknowledgement acknowledgeOwner(
    RunTestsRuntimeIdentity identity,
  ) {
    ownerAcknowledgements.add(identity);
    final error = ownerError;
    if (error != null) throw error;
    return RunTestsRuntimeOwnerAcknowledgement(
      identity: ownerIdentityTransform?.call(identity) ?? identity,
      disposition: ownerDispositions.isEmpty
          ? RunTestsRuntimeOwnerDisposition.current
          : ownerDispositions.removeAt(0),
    );
  }

  @override
  Future<RunTestsProjectAccessRuntimeAcknowledgement> ensureProjectAccess(
    RunTestsProjectAccessRuntimeRequest request,
  ) async {
    accessRequests.add(request);
    final error = accessError;
    if (error != null) throw error;
    return RunTestsProjectAccessRuntimeAcknowledgement(
      identity:
          accessIdentityTransform?.call(request.identity) ?? request.identity,
      disposition: accessDisposition,
      failure: failure,
    );
  }
}

final class _ExecutionPort implements TestCommandExecutionPort {
  final List<LocalCommandExecutionRequest> requests = [];
  final List<LocalCommandOperationIdentity> settlements = [];

  @override
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  ) async {
    requests.add(request);
    // Mirror the production execution adapter: every completion that carries a
    // launched command's result also carries an identity-bound settlement.
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: const McpToolResult(
        toolName: 'local_execute_command',
        result: 'completed',
        isSuccess: true,
      ),
      effectDisposition: LocalCommandEffectDisposition.settlementRequired,
      effectSettlement: LocalCommandEffectSettlement(
        identity: request.identityFor(owner),
        settle: () {
          settlements.add(request.identityFor(owner));
          return true;
        },
      ),
    );
  }
}

final class _RuleStore implements CommandPermissionRuleStorePort {
  @override
  CommandPermissionRuleDecision evaluate(
    ChatTurnOwner owner,
    CommandPermissionRuleRequest request,
  ) {
    return CommandPermissionRuleDecision.allow;
  }

  @override
  Future<LocalCommandCompletion<Object?>> remember(
    ChatTurnOwner owner,
    String toolCallId,
    RememberedCommandPermissionRule rule,
  ) async {
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: toolCallId,
      value: null,
    );
  }
}

final class _ApprovalPort implements LocalCommandApprovalPort {
  @override
  bool isExpired(ChatTurnOwner owner, String toolCallId) => false;

  @override
  LocalCommandCompletion<McpToolResult>? lookupDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) => null;

  @override
  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: null,
    );
  }

  @override
  LocalCommandCompletion<Object?> rememberResult(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: null,
    );
  }

  @override
  Future<LocalCommandCompletion<LocalCommandManualApproval>>
  requestManualApproval(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    ToolApprovalGateDecision gate,
  ) async {
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: const LocalCommandManualApproval(approved: true),
    );
  }

  @override
  Future<LocalCommandCompletion<ToolApprovalGateDecision>> resolveGate(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) async {
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: ToolApprovalGateDecision.fullAccess,
    );
  }
}

final class _EvidencePort implements RunTestsProjectEvidencePort {
  const _EvidencePort();

  @override
  bool hasFvmMetadata(
    ChatTurnOwner owner, {
    required String packageRoot,
    required String projectRoot,
  }) => false;

  @override
  String? inferPackageRootForTestPath(
    ChatTurnOwner owner, {
    required String projectRoot,
    required String workingDirectory,
    required String testPath,
  }) => null;

  @override
  bool isFlutterPackage(ChatTurnOwner owner, String packageRoot) => false;
}

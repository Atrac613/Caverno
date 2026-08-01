import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/local_command_tool_handler.dart';
import '../../domain/services/run_tests_tool_handler.dart';

/// Exact owner, call, project, and argument identity for one run_tests request.
final class RunTestsRuntimeIdentity {
  factory RunTestsRuntimeIdentity.fromInput(RunTestsToolInput input) {
    final projectRoot = _normalizeRunTestsRuntimeRoot(
      input.ownerProjectRoot ?? '',
    );
    return RunTestsRuntimeIdentity(
      owner: input.owner,
      toolCallId: input.toolCallId,
      toolName: input.toolName,
      projectRoot: projectRoot,
      argumentDigest: localCommandArgumentDigest({
        'project_root': projectRoot,
        'is_remote_interaction': input.isRemoteInteraction,
        'arguments': input.arguments,
      }),
    );
  }

  const RunTestsRuntimeIdentity({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required this.projectRoot,
    required this.argumentDigest,
  });

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String projectRoot;
  final String argumentDigest;

  bool belongsTo(RunTestsRuntimeIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RunTestsRuntimeIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.projectRoot == projectRoot &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode {
    return Object.hash(
      owner,
      toolCallId,
      toolName,
      projectRoot,
      argumentDigest,
    );
  }
}

String _normalizeRunTestsRuntimeRoot(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  try {
    return Uri.file(trimmed).normalizePath().toFilePath();
  } catch (_) {
    return trimmed;
  }
}

enum RunTestsRuntimeOwnerDisposition { current, ownerExpired, effectUncertain }

final class RunTestsRuntimeOwnerAcknowledgement {
  const RunTestsRuntimeOwnerAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final RunTestsRuntimeIdentity identity;
  final RunTestsRuntimeOwnerDisposition disposition;
}

final class RunTestsProjectAccessRuntimeRequest {
  const RunTestsProjectAccessRuntimeRequest({required this.identity});

  final RunTestsRuntimeIdentity identity;
}

enum RunTestsProjectAccessRuntimeDisposition {
  granted,
  denied,
  ownerExpired,
  effectUncertain,
}

final class RunTestsProjectAccessRuntimeAcknowledgement {
  const RunTestsProjectAccessRuntimeAcknowledgement({
    required this.identity,
    required this.disposition,
    this.failure,
  });

  final RunTestsRuntimeIdentity identity;
  final RunTestsProjectAccessRuntimeDisposition disposition;
  final McpToolResult? failure;
}

typedef RunTestsOwnerAcknowledgementCallback =
    RunTestsRuntimeOwnerAcknowledgement Function(
      RunTestsRuntimeIdentity identity,
    );
typedef RunTestsProjectAccessCallback =
    Future<RunTestsProjectAccessRuntimeAcknowledgement> Function(
      RunTestsProjectAccessRuntimeRequest request,
    );

abstract interface class RunTestsRuntimePort {
  RunTestsRuntimeOwnerAcknowledgement acknowledgeOwner(
    RunTestsRuntimeIdentity identity,
  );

  Future<RunTestsProjectAccessRuntimeAcknowledgement> ensureProjectAccess(
    RunTestsProjectAccessRuntimeRequest request,
  );
}

final class CallbackRunTestsRuntimePort implements RunTestsRuntimePort {
  const CallbackRunTestsRuntimePort({
    required RunTestsOwnerAcknowledgementCallback acknowledgeOwner,
    required RunTestsProjectAccessCallback ensureProjectAccess,
  }) : _acknowledgeOwner = acknowledgeOwner,
       _ensureProjectAccess = ensureProjectAccess;

  final RunTestsOwnerAcknowledgementCallback _acknowledgeOwner;
  final RunTestsProjectAccessCallback _ensureProjectAccess;

  @override
  RunTestsRuntimeOwnerAcknowledgement acknowledgeOwner(
    RunTestsRuntimeIdentity identity,
  ) => _acknowledgeOwner(identity);

  @override
  Future<RunTestsProjectAccessRuntimeAcknowledgement> ensureProjectAccess(
    RunTestsProjectAccessRuntimeRequest request,
  ) => _ensureProjectAccess(request);
}

/// Runs the extracted test handler against exact production runtime ports.
final class RunTestsToolRuntimeAdapter {
  const RunTestsToolRuntimeAdapter({
    required RunTestsRuntimePort runtimePort,
    required LocalCommandExecutionPort executionPort,
    required LocalCommandApprovalPort approvalPort,
    required CommandPermissionRuleStorePort permissionRuleStorePort,
    RunTestsProjectEvidencePort evidencePort =
        const DartProjectRunTestsEvidencePort(),
  }) : _runtimePort = runtimePort,
       _executionPort = executionPort,
       _approvalPort = approvalPort,
       _permissionRuleStorePort = permissionRuleStorePort,
       _evidencePort = evidencePort;

  final RunTestsRuntimePort _runtimePort;
  final LocalCommandExecutionPort _executionPort;
  final LocalCommandApprovalPort _approvalPort;
  final CommandPermissionRuleStorePort _permissionRuleStorePort;
  final RunTestsProjectEvidencePort _evidencePort;

  Future<McpToolResult> handle(RunTestsToolInput input) {
    final identity = RunTestsRuntimeIdentity.fromInput(input);
    return RunTestsToolHandler(
      executionPort: _RunTestsCommandExecutionPort(_executionPort),
      approvalPort: _approvalPort,
      permissionRuleStorePort: _permissionRuleStorePort,
      projectAccessPort: _BoundRunTestsProjectAccessPort(
        identity: identity,
        runtimePort: _runtimePort,
      ),
      evidencePort: _evidencePort,
    ).handle(input);
  }
}

final class _RunTestsCommandExecutionPort implements TestCommandExecutionPort {
  const _RunTestsCommandExecutionPort(this._delegate);

  final LocalCommandExecutionPort _delegate;

  @override
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  ) {
    return _delegate.execute(owner, request);
  }
}

final class _BoundRunTestsProjectAccessPort
    implements RunTestsProjectAccessPort {
  const _BoundRunTestsProjectAccessPort({
    required this.identity,
    required RunTestsRuntimePort runtimePort,
  }) : _runtimePort = runtimePort;

  final RunTestsRuntimeIdentity identity;
  final RunTestsRuntimePort _runtimePort;

  @override
  Future<RunTestsProjectAccessCompletion> ensureAccess(
    ChatTurnOwner owner, {
    required String toolCallId,
    required String toolName,
    required String projectRoot,
  }) async {
    if (owner != identity.owner ||
        toolCallId != identity.toolCallId ||
        toolName != identity.toolName ||
        projectRoot.trim() != identity.projectRoot) {
      return _denied(
        code: 'run_tests_boundary_mismatch',
        message: 'The run_tests project-access identity did not match.',
      );
    }

    final before = _ownerAcknowledgement();
    if (before == null) {
      return _denied(
        code: 'run_tests_owner_state_unavailable',
        message:
            'The run_tests owner state could not be verified before project '
            'access.',
      );
    }
    if (!before.identity.belongsTo(identity)) {
      return _denied(
        code: 'run_tests_boundary_mismatch',
        message: 'The run_tests owner acknowledgement did not match.',
      );
    }
    if (before.disposition == RunTestsRuntimeOwnerDisposition.ownerExpired) {
      return _expired();
    }
    if (before.disposition != RunTestsRuntimeOwnerDisposition.current) {
      return _uncertain(
        'The run_tests owner state was ambiguous before project access.',
      );
    }

    final RunTestsProjectAccessRuntimeAcknowledgement acknowledgement;
    try {
      acknowledgement = await _runtimePort.ensureProjectAccess(
        RunTestsProjectAccessRuntimeRequest(identity: identity),
      );
    } catch (error) {
      return _uncertain(
        'Project access may have changed before run_tests failed: $error',
      );
    }
    if (!acknowledgement.identity.belongsTo(identity)) {
      return _uncertain(
        'The run_tests project-access receipt belonged to another request.',
      );
    }

    switch (acknowledgement.disposition) {
      case RunTestsProjectAccessRuntimeDisposition.granted:
        final after = _ownerAcknowledgement();
        if (after == null ||
            !after.identity.belongsTo(identity) ||
            after.disposition != RunTestsRuntimeOwnerDisposition.current) {
          return _expired();
        }
        if (acknowledgement.failure != null) {
          return _uncertain(
            'Project access returned both success and failure evidence.',
          );
        }
        return RunTestsProjectAccessCompletion.granted(
          owner: identity.owner,
          toolCallId: identity.toolCallId,
          toolName: identity.toolName,
        );
      case RunTestsProjectAccessRuntimeDisposition.denied:
        final failure = acknowledgement.failure;
        if (failure == null ||
            failure.toolName != identity.toolName ||
            failure.isSuccess) {
          return _uncertain(
            'Project access returned an invalid denial receipt.',
          );
        }
        return RunTestsProjectAccessCompletion.denied(
          owner: identity.owner,
          toolCallId: identity.toolCallId,
          toolName: identity.toolName,
          failure: failure,
        );
      case RunTestsProjectAccessRuntimeDisposition.ownerExpired:
        return _expired();
      case RunTestsProjectAccessRuntimeDisposition.effectUncertain:
        return _uncertain(
          'Project access may have changed without an authoritative receipt.',
        );
    }
  }

  RunTestsRuntimeOwnerAcknowledgement? _ownerAcknowledgement() {
    try {
      return _runtimePort.acknowledgeOwner(identity);
    } catch (_) {
      return null;
    }
  }

  RunTestsProjectAccessCompletion _expired() {
    return RunTestsProjectAccessCompletion.ownerExpired(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
    );
  }

  RunTestsProjectAccessCompletion _uncertain(String message) {
    return _denied(
      code: 'run_tests_project_access_effect_uncertain',
      message: message,
    );
  }

  RunTestsProjectAccessCompletion _denied({
    required String code,
    required String message,
  }) {
    return RunTestsProjectAccessCompletion.denied(
      owner: identity.owner,
      toolCallId: identity.toolCallId,
      toolName: identity.toolName,
      failure: McpToolResult(
        toolName: identity.toolName,
        result: jsonEncode({
          'ok': false,
          'code': code,
          'error': message,
          if (code.endsWith('effect_uncertain'))
            'required_action':
                'Re-select the project if needed and inspect read-only state '
                'before retrying tests.',
        }),
        isSuccess: false,
        errorMessage: message,
      ),
    );
  }
}

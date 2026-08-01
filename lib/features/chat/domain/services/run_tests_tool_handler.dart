// ChatNotifier decomposition collaborator: run-tests-tool-handler

import 'dart:convert';

import '../../data/datasources/filesystem_tools.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'dart_project_tooling.dart';
import 'local_command_tool_handler.dart';
import 'tool_call_execution_policy.dart';

/// Immutable run_tests call and exact-owner project facts.
final class RunTestsToolInput {
  RunTestsToolInput({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String? ownerProjectRoot,
    required Map<String, dynamic> arguments,
    this.isRemoteInteraction = false,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requiredValue(toolName, 'toolName'),
       ownerProjectRoot = _normalizedOptional(ownerProjectRoot),
       arguments = freezeLocalCommandArguments(arguments);

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String? ownerProjectRoot;
  final Map<String, dynamic> arguments;
  final bool isRemoteInteraction;
}

/// Test-command process boundary with the WS6-5 execution contract.
abstract interface class TestCommandExecutionPort
    implements LocalCommandExecutionPort {}

enum RunTestsProjectAccessDisposition { granted, denied, ownerExpired }

/// Exact-owner completion from the security-scoped project access boundary.
final class RunTestsProjectAccessCompletion {
  const RunTestsProjectAccessCompletion.granted({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) : disposition = RunTestsProjectAccessDisposition.granted,
       failure = null;

  const RunTestsProjectAccessCompletion.denied({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
    required this.failure,
  }) : disposition = RunTestsProjectAccessDisposition.denied,
       assert(failure != null);

  const RunTestsProjectAccessCompletion.ownerExpired({
    required this.owner,
    required this.toolCallId,
    required this.toolName,
  }) : disposition = RunTestsProjectAccessDisposition.ownerExpired,
       failure = null;

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final RunTestsProjectAccessDisposition disposition;
  final McpToolResult? failure;
}

/// Restores project access without consulting the currently visible project.
abstract interface class RunTestsProjectAccessPort {
  Future<RunTestsProjectAccessCompletion> ensureAccess(
    ChatTurnOwner owner, {
    required String toolCallId,
    required String toolName,
    required String projectRoot,
  });
}

/// Owner-aware filesystem evidence used for runner and package inference.
abstract interface class RunTestsProjectEvidencePort {
  String? inferPackageRootForTestPath(
    ChatTurnOwner owner, {
    required String projectRoot,
    required String workingDirectory,
    required String testPath,
  });

  bool isFlutterPackage(ChatTurnOwner owner, String packageRoot);

  bool hasFvmMetadata(
    ChatTurnOwner owner, {
    required String packageRoot,
    required String projectRoot,
  });
}

/// Production filesystem evidence adapter with no ambient owner lookup.
final class DartProjectRunTestsEvidencePort
    implements RunTestsProjectEvidencePort {
  const DartProjectRunTestsEvidencePort();

  @override
  String? inferPackageRootForTestPath(
    ChatTurnOwner owner, {
    required String projectRoot,
    required String workingDirectory,
    required String testPath,
  }) {
    return DartProjectTooling.inferPackageRootForTestPath(
      projectRoot: projectRoot,
      workingDirectory: workingDirectory,
      testPath: testPath,
    );
  }

  @override
  bool isFlutterPackage(ChatTurnOwner owner, String packageRoot) {
    return DartProjectTooling.isFlutterPackage(packageRoot);
  }

  @override
  bool hasFvmMetadata(
    ChatTurnOwner owner, {
    required String packageRoot,
    required String projectRoot,
  }) {
    return DartProjectTooling.hasFvmMetadata(
      packageRoot: packageRoot,
      projectRoot: projectRoot,
    );
  }
}

/// Builds and executes a scoped test command without notifier state.
final class RunTestsToolHandler {
  RunTestsToolHandler({
    required TestCommandExecutionPort executionPort,
    required LocalCommandApprovalPort approvalPort,
    required CommandPermissionRuleStorePort permissionRuleStorePort,
    required RunTestsProjectAccessPort projectAccessPort,
    RunTestsProjectEvidencePort evidencePort =
        const DartProjectRunTestsEvidencePort(),
  }) : _projectAccessPort = projectAccessPort,
       _evidencePort = evidencePort,
       _localCommandHandler = LocalCommandToolHandler(
         executionPort: executionPort,
         approvalPort: approvalPort,
         permissionRuleStorePort: permissionRuleStorePort,
       );

  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _canonicalToolName = 'run_tests';
  static const _expiredMessage =
      'The run_tests turn expired before project access completed';

  final RunTestsProjectAccessPort _projectAccessPort;
  final RunTestsProjectEvidencePort _evidencePort;
  final LocalCommandToolHandler _localCommandHandler;

  Future<McpToolResult> handle(RunTestsToolInput input) async {
    if (input.toolName != _canonicalToolName) {
      return _error(
        input.toolName,
        code: 'unsupported_tool',
        message: 'RunTestsToolHandler only accepts run_tests',
      );
    }
    final projectRoot = _normalizeAbsolutePath(
      input.ownerProjectRoot?.trim() ?? '',
    );
    if (projectRoot.isEmpty) {
      return _error(
        input.toolName,
        code: 'project_required',
        message: 'run_tests requires a selected coding project',
      );
    }

    final explicitWorkingDirectory =
        (input.arguments['working_directory'] as String?)?.trim() ?? '';
    final explicitCwd = (input.arguments['cwd'] as String?)?.trim() ?? '';
    final rawWorkingDirectory = explicitWorkingDirectory.isNotEmpty
        ? explicitWorkingDirectory
        : explicitCwd;
    final hasExplicitWorkingDirectory = rawWorkingDirectory.isNotEmpty;
    var workingDirectory = _normalizeAbsolutePath(
      FilesystemTools.resolvePath(
            rawWorkingDirectory,
            defaultRoot: projectRoot,
          ) ??
          projectRoot,
    );
    if (workingDirectory.isEmpty ||
        !DartProjectPath.isInsideRoot(workingDirectory, projectRoot)) {
      return _error(
        input.toolName,
        code: 'working_directory_outside_project',
        message:
            'working_directory must resolve inside the selected coding project',
      );
    }

    final access = await _projectAccessPort.ensureAccess(
      input.owner,
      toolCallId: input.toolCallId,
      toolName: input.toolName,
      projectRoot: projectRoot,
    );
    _validateProjectAccessCompletion(input, access);
    switch (access.disposition) {
      case RunTestsProjectAccessDisposition.ownerExpired:
        return _error(
          input.toolName,
          code: 'turn_expired',
          message: _expiredMessage,
        );
      case RunTestsProjectAccessDisposition.denied:
        return access.failure!;
      case RunTestsProjectAccessDisposition.granted:
        break;
    }

    final rawTestPath = _executionPolicy.runTestsPathArgument(input.arguments);
    if (!hasExplicitWorkingDirectory && rawTestPath != null) {
      final inferredWorkingDirectory = _evidencePort
          .inferPackageRootForTestPath(
            input.owner,
            projectRoot: projectRoot,
            workingDirectory: workingDirectory,
            testPath: rawTestPath,
          );
      if (inferredWorkingDirectory != null &&
          DartProjectPath.isInsideRoot(inferredWorkingDirectory, projectRoot)) {
        workingDirectory = _normalizeAbsolutePath(inferredWorkingDirectory);
      }
    }

    String? commandTestPath;
    if (rawTestPath != null) {
      final normalizedRawTestPath = _normalizePathForWorkingDirectory(
        rawTestPath,
        projectRoot: projectRoot,
        workingDirectory: workingDirectory,
      );
      final resolvedTestPath = _normalizeAbsolutePath(
        FilesystemTools.resolvePath(
              normalizedRawTestPath,
              defaultRoot: workingDirectory,
            ) ??
            '',
      );
      if (resolvedTestPath.isEmpty ||
          !DartProjectPath.isInsideRoot(resolvedTestPath, projectRoot)) {
        return _error(
          input.toolName,
          code: 'test_path_outside_project',
          message: 'test_path must resolve inside the selected coding project',
        );
      }
      if (DartProjectPath.isInsideRoot(resolvedTestPath, workingDirectory)) {
        final relative = DartProjectPath.relativePath(
          resolvedTestPath,
          workingDirectory,
        );
        commandTestPath = relative.isEmpty ? '.' : relative;
      } else {
        commandTestPath = resolvedTestPath;
      }
    }

    final runner = _normalizeRunner(input.arguments['runner']);
    if (runner == null) {
      return _error(
        input.toolName,
        code: 'unsupported_runner',
        message: 'runner must be one of auto, flutter, or dart',
      );
    }

    final command = _buildCommand(
      owner: input.owner,
      runner: runner,
      projectRoot: projectRoot,
      workingDirectory: workingDirectory,
      testPath: commandTestPath,
    );
    final reason = input.arguments['reason']?.toString().trim();
    final localArguments = <String, dynamic>{
      'command': command,
      'working_directory': workingDirectory,
      'reason': reason == null || reason.isEmpty
          ? 'Run scoped test validation'
          : reason,
      'test_path': ?rawTestPath,
      if (runner != 'auto') 'runner': runner,
    };
    final result = await _localCommandHandler.handle(
      LocalCommandToolRequest(
        owner: input.owner,
        toolCallId: input.toolCallId,
        toolName: 'local_execute_command',
        allowedWorkingDirectoryRoot: projectRoot,
        defaultWorkingDirectory: workingDirectory,
        arguments: localArguments,
        isRemoteInteraction: input.isRemoteInteraction,
      ),
    );
    return result.copyWith(toolName: input.toolName);
  }

  void _validateProjectAccessCompletion(
    RunTestsToolInput input,
    RunTestsProjectAccessCompletion completion,
  ) {
    if (completion.owner != input.owner) {
      throw StateError('Run tests project access owner mismatch.');
    }
    if (completion.toolCallId != input.toolCallId) {
      throw StateError('Run tests project access tool call mismatch.');
    }
    if (completion.toolName != input.toolName) {
      throw StateError('Run tests project access tool name mismatch.');
    }
    final failure = completion.failure;
    if (completion.disposition == RunTestsProjectAccessDisposition.denied) {
      if (failure == null || failure.toolName != input.toolName) {
        throw StateError('Run tests project access failure mismatch.');
      }
    } else if (failure != null) {
      throw StateError(
        'Run tests project access returned an unexpected failure.',
      );
    }
  }

  McpToolResult _error(
    String toolName, {
    required String code,
    required String message,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({'code': code, 'error': message}),
      isSuccess: false,
      errorMessage: message,
    );
  }

  String? _normalizeRunner(Object? rawRunner) {
    final runner = rawRunner?.toString().trim().toLowerCase();
    if (runner == null || runner.isEmpty || runner == 'auto') {
      return 'auto';
    }
    if (runner == 'flutter' || runner == 'dart') {
      return runner;
    }
    return null;
  }

  String _buildCommand({
    required ChatTurnOwner owner,
    required String runner,
    required String projectRoot,
    required String workingDirectory,
    String? testPath,
  }) {
    final effectiveRunner = runner == 'auto'
        ? _inferRunner(
            owner: owner,
            projectRoot: projectRoot,
            workingDirectory: workingDirectory,
          )
        : runner;
    final hasFvmMetadata = _evidencePort.hasFvmMetadata(
      owner,
      packageRoot: workingDirectory,
      projectRoot: projectRoot,
    );
    final executable = switch (effectiveRunner) {
      'dart' => hasFvmMetadata ? 'fvm dart' : 'dart',
      _ => hasFvmMetadata ? 'fvm flutter' : 'flutter',
    };
    final parts = <String>[executable, 'test'];
    if (testPath != null && testPath.trim().isNotEmpty) {
      parts.add(_shellQuoteArgument(testPath.trim()));
    }
    return parts.join(' ');
  }

  String _inferRunner({
    required ChatTurnOwner owner,
    required String projectRoot,
    required String workingDirectory,
  }) {
    return _evidencePort.isFlutterPackage(owner, workingDirectory) ||
            _evidencePort.isFlutterPackage(owner, projectRoot)
        ? 'flutter'
        : 'dart';
  }

  String _normalizePathForWorkingDirectory(
    String rawTestPath, {
    required String projectRoot,
    required String workingDirectory,
  }) {
    final trimmed = rawTestPath.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      return trimmed;
    }

    final workingDirectoryFromProject = DartProjectPath.relativePath(
      workingDirectory,
      projectRoot,
    ).replaceAll('\\', '/');
    if (workingDirectoryFromProject.isEmpty ||
        workingDirectoryFromProject == '.') {
      return trimmed;
    }

    final normalizedTestPath = trimmed.replaceAll('\\', '/');
    if (normalizedTestPath == workingDirectoryFromProject) {
      return '.';
    }
    final workingDirectoryPrefix = '$workingDirectoryFromProject/';
    if (normalizedTestPath.startsWith(workingDirectoryPrefix)) {
      final stripped = normalizedTestPath.substring(
        workingDirectoryPrefix.length,
      );
      return stripped.isEmpty ? '.' : stripped;
    }
    return trimmed;
  }

  String _shellQuoteArgument(String value) {
    if (value.isEmpty) return "''";
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _normalizeAbsolutePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '';
    try {
      return Uri.file(trimmed).normalizePath().toFilePath();
    } catch (_) {
      return trimmed;
    }
  }
}

String? _normalizedOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}

import '../../../../core/services/ssh_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';

/// Exposes SSH tools and executes only post-approval service operations.
final class BuiltInSshToolHandler {
  BuiltInSshToolHandler({SshService? sshService}) : _sshService = sshService;

  static const List<String> toolNames = <String>[
    'ssh_connect',
    'ssh_execute_command',
    'ssh_disconnect',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final SshService? _sshService;

  bool get isAvailable => _sshService != null;

  List<Map<String, dynamic>> get definitions => <Map<String, dynamic>>[
    _sshConnectTool,
    _sshExecuteCommandTool,
    _sshDisconnectTool,
  ];

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown SSH tool');
    }

    switch (name) {
      case 'ssh_connect':
        return _failure(
          name,
          'ssh_connect must be handled by ChatNotifier (internal error)',
        );

      case 'ssh_execute_command':
        return _executeCommand(name, arguments);

      case 'ssh_disconnect':
        return _disconnect(name);
    }

    throw StateError('Unreachable SSH tool: $name');
  }

  Future<McpToolResult> _executeCommand(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final ssh = _sshService;
    if (ssh == null) {
      return _failure(name, 'SSH service is unavailable');
    }
    if (!ssh.isConnected) {
      return _failure(name, 'No active SSH session — call ssh_connect first');
    }
    try {
      final command = (arguments['command'] as String?)?.trim() ?? '';
      if (command.isEmpty) {
        return _failure(name, 'command is required');
      }
      final result = await ssh.execute(command);
      appLog('[McpToolService] SSH command executed successfully');
      return _success(name, result.formatted());
    } catch (error) {
      appLog('[McpToolService] SSH execution error: $error');
      return _failure(name, error.toString());
    }
  }

  Future<McpToolResult> _disconnect(String name) async {
    final ssh = _sshService;
    if (ssh == null) {
      return _success(name, 'No active SSH session');
    }
    final wasConnected = ssh.isConnected;
    try {
      await ssh.disconnect();
      return _success(
        name,
        wasConnected ? 'Disconnected' : 'No active SSH session',
      );
    } catch (error) {
      appLog('[McpToolService] SSH disconnect error: $error');
      return _failure(name, error.toString());
    }
  }

  static McpToolResult _success(String toolName, String result) {
    return McpToolResultNormalizer.success(toolName: toolName, result: result);
  }

  static McpToolResult _failure(String toolName, String errorMessage) {
    return McpToolResultNormalizer.failure(
      toolName: toolName,
      errorMessage: errorMessage,
    );
  }

  static Map<String, dynamic> get _sshConnectTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_connect',
      'description':
          "Open an interactive SSH session to a remote host. The user will "
          "see a dialog to confirm or edit the connection details and enter "
          "the password (pre-filled if previously saved for this host). "
          "Keeps the session alive for subsequent ssh_execute_command calls "
          "until ssh_disconnect is called. Use this when the user asks to "
          "connect to a server via SSH.",
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                "Hostname or IP of the SSH server, e.g. '192.168.1.10' or "
                "'example.com'.",
          },
          'port': {
            'type': 'integer',
            'description': 'SSH port. Defaults to 22 when omitted.',
          },
          'username': {
            'type': 'string',
            'description':
                'SSH username. Optional — if omitted, the confirmation '
                'dialog will ask the user to enter it.',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _sshExecuteCommandTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_execute_command',
      'description':
          "Execute a shell command on the currently active SSH session. "
          "Requires ssh_connect to have succeeded first. Each command is "
          "shown to the user in a confirmation dialog and must be approved "
          "before it runs. Returns stdout, stderr, and the exit code.",
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Exact shell command to run on the remote server.',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason shown to the user in the '
                'confirmation dialog.',
          },
        },
        'required': ['command'],
      },
    },
  };

  static Map<String, dynamic> get _sshDisconnectTool => {
    'type': 'function',
    'function': {
      'name': 'ssh_disconnect',
      'description':
          'Close the currently active SSH session. Safe to call even if '
          'nothing is connected.',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  };
}

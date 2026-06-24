part of 'chat_notifier.dart';

extension ChatNotifierToolHandlerRegistry on ChatNotifier {
  ChatToolHandlerRegistry _buildToolHandlerRegistry({
    int? interactionGeneration,
  }) {
    return ChatToolHandlerRegistry.fromModules([
      _ProjectScopedToolHandlerModule(this),
      _LocalFileToolHandlerModule(this),
      _PythonToolHandlerModule(this),
      _SshToolHandlerModule(this),
      _GitToolHandlerModule(this),
      _DeviceToolHandlerModule(this),
      _SkillToolHandlerModule(this),
      _RoutineToolHandlerModule(this),
      _ConversationToolHandlerModule(
        this,
        interactionGeneration: interactionGeneration,
      ),
    ]);
  }
}

final class _ProjectScopedToolHandlerModule implements ChatToolHandlerModule {
  const _ProjectScopedToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {
      for (final toolName in const [
        'list_directory',
        'read_file',
        'inspect_file',
        'find_files',
        'search_files',
        'process_status',
        'process_tail',
        'process_wait',
      ])
        toolName: _notifier._handleProjectScopedTool,
      'lsp_go_to_definition': _notifier._handleLspGoToDefinition,
    };
  }
}

final class _LocalFileToolHandlerModule implements ChatToolHandlerModule {
  const _LocalFileToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {
      'write_file': _notifier._handleWriteFile,
      'edit_file': _notifier._handleEditFile,
      'rollback_last_file_change': _notifier._handleRollbackLastFileChange,
      'local_execute_command': _notifier._handleLocalExecuteCommand,
      'process_start': _notifier._handleProcessStart,
      'process_cancel': _notifier._handleProcessCancel,
      'run_tests': _notifier._handleRunTests,
    };
  }
}

final class _PythonToolHandlerModule implements ChatToolHandlerModule {
  const _PythonToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {'run_python_script': _notifier._handlePythonScript};
  }
}

final class _SshToolHandlerModule implements ChatToolHandlerModule {
  const _SshToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {
      'ssh_connect': _notifier._handleSshConnect,
      'ssh_execute_command': _notifier._handleSshExecuteCommand,
    };
  }
}

final class _GitToolHandlerModule implements ChatToolHandlerModule {
  const _GitToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {'git_execute_command': _notifier._handleGitExecuteCommand};
  }
}

final class _DeviceToolHandlerModule implements ChatToolHandlerModule {
  const _DeviceToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {
      'ble_connect': _notifier._handleBleConnect,
      'serial_open': _notifier._handleSerialOpen,
    };
  }
}

final class _SkillToolHandlerModule implements ChatToolHandlerModule {
  const _SkillToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {'save_skill': _notifier._handleSaveSkill};
  }
}

final class _RoutineToolHandlerModule implements ChatToolHandlerModule {
  const _RoutineToolHandlerModule(this._notifier);

  final ChatNotifier _notifier;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {'create_routine': _notifier._handleCreateRoutine};
  }
}

final class _ConversationToolHandlerModule implements ChatToolHandlerModule {
  const _ConversationToolHandlerModule(
    this._notifier, {
    required this.interactionGeneration,
  });

  final ChatNotifier _notifier;
  final int? interactionGeneration;

  @override
  Map<String, ChatToolHandler> get handlers {
    return {
      'ask_user_question': (toolCall) => _notifier._handleAskUserQuestion(
        toolCall,
        interactionGeneration: interactionGeneration,
      ),
      'spawn_subagent': (toolCall) => _notifier._handleSpawnSubagent(
        toolCall,
        interactionGeneration: interactionGeneration,
      ),
      'get_subagent_result': _notifier._handleGetSubagentResult,
    };
  }
}

part of 'chat_notifier.dart';

extension ChatNotifierToolHandlerRegistry on ChatNotifier {
  ChatToolHandlerRegistry _buildToolHandlerRegistry({
    int? interactionGeneration,
  }) {
    return ChatToolHandlerRegistry({
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
        toolName: _handleProjectScopedTool,
      'write_file': _handleWriteFile,
      'edit_file': _handleEditFile,
      'rollback_last_file_change': _handleRollbackLastFileChange,
      'local_execute_command': _handleLocalExecuteCommand,
      'process_start': _handleProcessStart,
      'process_cancel': _handleProcessCancel,
      'run_python_script': _handlePythonScript,
      'run_tests': _handleRunTests,
      'ssh_connect': _handleSshConnect,
      'ssh_execute_command': _handleSshExecuteCommand,
      'git_execute_command': _handleGitExecuteCommand,
      'ble_connect': _handleBleConnect,
      'serial_open': _handleSerialOpen,
      'ask_user_question': (toolCall) => _handleAskUserQuestion(
        toolCall,
        interactionGeneration: interactionGeneration,
      ),
      'spawn_subagent': (toolCall) => _handleSpawnSubagent(
        toolCall,
        interactionGeneration: interactionGeneration,
      ),
      'get_subagent_result': _handleGetSubagentResult,
    });
  }
}

// Same-library extension on [ChatNotifier]; `ref`/`state` are reached through
// the part-of bridge. Riverpod marks them `@protected`/`@visibleForTesting`,
// which are not aware of extensions even in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// In-chat scheduled-routine authoring (ROUTINE1).
///
/// `create_routine` lets the agent schedule a recurring routine from the
/// conversation through the same path as the routine editor UI
/// ([RoutinesNotifier.createRoutine]). A routine is an autonomous, recurring,
/// unattended run, so the write is always gated by an explicit, non-cacheable
/// approval whose preview surfaces the schedule, enabled tools/workspace
/// writes, and any external delivery (Google Chat). It never consults or
/// populates [ToolApprovalCache], so a routine is never scheduled silently.
extension ChatNotifierRoutineHandlers on ChatNotifier {
  Future<McpToolResult> _handleCreateRoutine(ToolCallInfo toolCall) async {
    final arguments = toolCall.arguments;
    final name = (arguments['name'] as String?)?.trim() ?? '';
    final prompt = (arguments['prompt'] as String?)?.trim() ?? '';
    final reason = (arguments['reason'] as String?)?.trim();

    if (name.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'name is required',
      );
    }
    if (prompt.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'prompt is required',
      );
    }

    final scheduleMode = _parseRoutineScheduleMode(arguments['schedule_mode']);
    final intervalValue = RoutineScheduleService.normalizeIntervalValue(
      (arguments['interval_value'] as num?)?.toInt() ?? 1,
    );
    final intervalUnit = _parseRoutineIntervalUnit(arguments['interval_unit']);
    final timeOfDayMinutes = RoutineScheduleService.normalizeTimeOfDayMinutes(
      _parseRoutineTimeOfDayMinutes(arguments['time_of_day']),
    );
    final toolsEnabled = (arguments['tools_enabled'] as bool?) ?? false;
    final notifyOnCompletion =
        (arguments['notify_on_completion'] as bool?) ?? true;
    final completionAction = _parseRoutineCompletionAction(
      arguments['completion_action'],
    );
    final googleChatRule = _parseRoutineGoogleChatRule(
      arguments['google_chat_rule'],
    );
    final workspaceDirectory =
        (arguments['workspace_directory'] as String?)?.trim() ?? '';
    final allowWorkspaceWrites =
        (arguments['allow_workspace_writes'] as bool?) ?? false;

    final scheduleSummary = _routineScheduleSummary(
      scheduleMode: scheduleMode,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      timeOfDayMinutes: timeOfDayMinutes,
    );

    final preview = _buildRoutinePreview(
      name: name,
      prompt: prompt,
      scheduleSummary: scheduleSummary,
      toolsEnabled: toolsEnabled,
      notifyOnCompletion: notifyOnCompletion,
      completionAction: completionAction,
      googleChatRule: googleChatRule,
      workspaceDirectory: workspaceDirectory,
      allowWorkspaceWrites: allowWorkspaceWrites,
    );

    // ROUTINE1: scheduling an autonomous recurring agent is non-cacheable. Go
    // straight to a manual approval that previews the schedule, tools, and
    // delivery; never auto-review and never remember the decision.
    final approved = await requestFileOperation(
      operation: 'Create Routine',
      path: name,
      preview: preview,
      reason: reason,
    );
    if (!approved) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'User denied creating the routine',
      );
    }

    try {
      final notifier = ref.read(routinesNotifierProvider.notifier);
      await notifier.createRoutine(
        name: name,
        prompt: prompt,
        intervalValue: intervalValue,
        intervalUnit: intervalUnit,
        scheduleMode: scheduleMode,
        timeOfDayMinutes: timeOfDayMinutes,
        enabled: true,
        notifyOnCompletion: notifyOnCompletion,
        toolsEnabled: toolsEnabled,
        completionAction: completionAction,
        googleChatRule: googleChatRule,
        workspaceDirectory: workspaceDirectory,
        allowWorkspaceWrites: allowWorkspaceWrites,
      );

      final created = _findNewestRoutineNamed(name);
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': true,
          'action': 'created',
          if (created != null) 'id': created.id,
          'name': name,
          'schedule': scheduleSummary,
          'tools_enabled': toolsEnabled,
          'notify_on_completion': notifyOnCompletion,
          'completion_action': completionAction.name,
          if (created?.nextRunAt != null)
            'next_run_at': created!.nextRunAt!.toIso8601String(),
        }),
        isSuccess: true,
      );
    } catch (error) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Failed to create routine: $error',
      );
    }
  }

  Routine? _findNewestRoutineNamed(String name) {
    final normalized = name.trim().toLowerCase();
    Routine? newest;
    for (final routine in ref.read(routinesNotifierProvider).routines) {
      if (routine.trimmedName.toLowerCase() != normalized) {
        continue;
      }
      if (newest == null || routine.createdAt.isAfter(newest.createdAt)) {
        newest = routine;
      }
    }
    return newest;
  }

  String _routineScheduleSummary({
    required RoutineScheduleMode scheduleMode,
    required int intervalValue,
    required RoutineIntervalUnit intervalUnit,
    required int timeOfDayMinutes,
  }) {
    if (scheduleMode == RoutineScheduleMode.dailyTime) {
      return 'daily at '
          '${RoutineScheduleService.formatTimeOfDayMinutes(timeOfDayMinutes)}';
    }
    final unit = intervalUnit.name;
    final singular = unit.substring(0, unit.length - 1);
    return 'every $intervalValue ${intervalValue == 1 ? singular : unit}';
  }

  String _buildRoutinePreview({
    required String name,
    required String prompt,
    required String scheduleSummary,
    required bool toolsEnabled,
    required bool notifyOnCompletion,
    required RoutineCompletionAction completionAction,
    required RoutineGoogleChatRule googleChatRule,
    required String workspaceDirectory,
    required bool allowWorkspaceWrites,
  }) {
    final delivery = <String>[
      if (notifyOnCompletion) 'local notification',
      if (completionAction == RoutineCompletionAction.googleChat)
        'Google Chat (${googleChatRule.name})'
      else if (completionAction == RoutineCompletionAction.promptGoogleChat)
        'Google Chat (prompt before posting)',
    ];
    final lines = <String>[
      'Routine: $name',
      'Schedule: $scheduleSummary',
      'Runs automatically without further confirmation once scheduled.',
      'Tools enabled: ${toolsEnabled ? 'yes' : 'no'}',
      'Delivery: ${delivery.isEmpty ? 'none' : delivery.join(', ')}',
      if (workspaceDirectory.isNotEmpty)
        'Workspace: $workspaceDirectory'
            '${allowWorkspaceWrites ? ' (writes allowed)' : ' (read-only)'}',
      '',
      'Prompt:',
      prompt,
    ];
    return lines.join('\n');
  }

  RoutineScheduleMode _parseRoutineScheduleMode(Object? value) {
    final normalized = (value as String?)?.trim().toLowerCase() ?? '';
    if (normalized == 'daily' ||
        normalized == 'dailytime' ||
        normalized == 'daily_time' ||
        normalized == 'time_of_day') {
      return RoutineScheduleMode.dailyTime;
    }
    return RoutineScheduleMode.interval;
  }

  RoutineIntervalUnit _parseRoutineIntervalUnit(Object? value) {
    switch ((value as String?)?.trim().toLowerCase()) {
      case 'minute':
      case 'minutes':
        return RoutineIntervalUnit.minutes;
      case 'day':
      case 'days':
        return RoutineIntervalUnit.days;
      case 'hour':
      case 'hours':
      default:
        return RoutineIntervalUnit.hours;
    }
  }

  RoutineCompletionAction _parseRoutineCompletionAction(Object? value) {
    switch ((value as String?)?.trim().toLowerCase()) {
      case 'google_chat':
      case 'googlechat':
        return RoutineCompletionAction.googleChat;
      case 'prompt_google_chat':
      case 'promptgooglechat':
        return RoutineCompletionAction.promptGoogleChat;
      case 'none':
      default:
        return RoutineCompletionAction.none;
    }
  }

  RoutineGoogleChatRule _parseRoutineGoogleChatRule(Object? value) {
    switch ((value as String?)?.trim().toLowerCase()) {
      case 'on_success':
      case 'onsuccess':
        return RoutineGoogleChatRule.onSuccess;
      case 'always':
        return RoutineGoogleChatRule.always;
      case 'on_failure':
      case 'onfailure':
      default:
        return RoutineGoogleChatRule.onFailure;
    }
  }

  int _parseRoutineTimeOfDayMinutes(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    final text = (value as String?)?.trim() ?? '';
    if (text.isEmpty) {
      return 480;
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      return hours * 60 + minutes;
    }
    final asInt = int.tryParse(text);
    return asInt ?? 480;
  }
}

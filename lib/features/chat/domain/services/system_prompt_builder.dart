import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../entities/conversation_goal.dart';
import '../entities/conversation_plan_artifact.dart';
import '../entities/conversation_workflow.dart';

class SystemPromptBuilder {
  SystemPromptBuilder._();

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String build({
    required DateTime now,
    required AssistantMode assistantMode,
    String languageCode = 'en',
    List<String> toolNames = const [],
    String? sessionMemoryContext,
    String? projectName,
    String? projectRootPath,
    ConversationGoal? goal,
    ConversationWorkflowStage workflowStage = ConversationWorkflowStage.idle,
    ConversationWorkflowSpec? workflowSpec,
    ConversationPlanArtifact? planArtifact,
    bool isVoiceMode = false,
  }) {
    final uniqueToolNames = toolNames.toSet().toList()..sort();
    final hasTools = uniqueToolNames.isNotEmpty;
    final hasSearchTool = uniqueToolNames.any(
      (name) => name == 'searxng_web_search' || name == 'web_search',
    );
    final hasToolSearch = uniqueToolNames.contains('tool_search');
    final hasWebReader = uniqueToolNames.contains('web_url_read');
    final hasDatetimeTool = uniqueToolNames.contains('get_current_datetime');
    final hasProjectReadTools =
        uniqueToolNames.contains('list_directory') ||
        uniqueToolNames.contains('read_file') ||
        uniqueToolNames.contains('find_files') ||
        uniqueToolNames.contains('search_files');
    final hasProjectWriteTools =
        uniqueToolNames.contains('write_file') ||
        uniqueToolNames.contains('edit_file');
    final hasRollbackTool = uniqueToolNames.contains(
      'rollback_last_file_change',
    );
    final hasLocalShellTool = uniqueToolNames.contains('local_execute_command');
    final hasOsSystemInfoTool = uniqueToolNames.contains('os_get_system_info');
    final hasOsLogTool = uniqueToolNames.contains('os_log_read');
    final hasGitTool = uniqueToolNames.contains('git_execute_command');
    final hasComputerUseTools = uniqueToolNames.any(
      (name) => name.startsWith('computer_'),
    );

    final date = _formatDate(now);
    final time = _formatTime(now);
    final weekday = _weekdays[now.weekday - 1];
    final timeZoneName = now.timeZoneName.isEmpty ? 'Local' : now.timeZoneName;
    final utcOffset = _formatUtcOffset(now.timeZoneOffset);

    final buffer = StringBuffer()
      ..writeln(
        'Current local date and time (source of truth): '
        '$date ($weekday) $time $timeZoneName (UTC$utcOffset).',
      )
      ..writeln(
        'Resolve relative date/time references (today, yesterday, tomorrow, '
        'this week, recently, now, latest, current) against this source of truth.',
      );

    // In voice mode, dates should be spoken naturally; skip YYYY-MM-DD instruction.
    if (!isVoiceMode) {
      buffer.writeln(
        'When responding to time-relative questions, include exact dates '
        '(YYYY-MM-DD) to avoid ambiguity.',
      );
    }

    buffer
      ..writeln(SystemPromptConstants.coreAssistantPrompt)
      ..writeln(SystemPromptConstants.priorityInstruction)
      ..writeln(SystemPromptConstants.judgmentInstruction)
      ..writeln(SystemPromptConstants.communicationInstruction)
      ..writeln(SystemPromptConstants.oversightInstruction)
      ..writeln(SystemPromptConstants.languageInstruction(languageCode));

    // In voice mode, follow-up questions are handled by the voice mode instruction.
    if (!isVoiceMode) {
      buffer.writeln(SystemPromptConstants.optionalFollowUpQuestionInstruction);
    }

    if (assistantMode == AssistantMode.general) {
      buffer.writeln(SystemPromptConstants.generalModeInstruction);
    } else {
      buffer.writeln(SystemPromptConstants.codingModeInstruction);
      if (assistantMode == AssistantMode.plan) {
        buffer.writeln(SystemPromptConstants.planModeInstruction);
      }
      final normalizedWorkflowSpec =
          workflowSpec ?? const ConversationWorkflowSpec();
      final activeGoal = goal?.isActive ?? false ? goal : null;
      final normalizedProjectName = projectName?.trim();
      final normalizedProjectRootPath = projectRootPath?.trim();
      if ((normalizedProjectName?.isNotEmpty ?? false) ||
          (normalizedProjectRootPath?.isNotEmpty ?? false)) {
        buffer.writeln(
          SystemPromptConstants.codingProjectContextInstruction(
            projectName: normalizedProjectName,
            projectRootPath: normalizedProjectRootPath,
          ),
        );
      }
      if (activeGoal != null) {
        buffer.writeln('Active coding goal for this thread:');
        buffer.writeln(activeGoal.normalizedObjective!);
        if (!activeGoal.budgetExceeded) {
          buffer.writeln(
            'Keep this goal in force across turns. Continue moving it forward '
            'until it is complete, genuinely blocked, disabled, or the user '
            'changes direction.',
          );
          buffer.writeln(
            'When the goal is complete, state the concrete completion evidence. '
            'When blocked, state the blocking condition and what is needed next.',
          );
        }
        final remainingTokens = activeGoal.remainingTokenBudget;
        if (remainingTokens != null) {
          buffer.writeln(
            'Goal token budget remaining: $remainingTokens approximate tokens.',
          );
        }
        final remainingTurns = activeGoal.remainingTurnBudget;
        if (remainingTurns != null) {
          buffer.writeln('Goal turn budget remaining: $remainingTurns turns.');
        }
        if (activeGoal.budgetExceeded) {
          buffer.writeln(
            'The goal budget is exhausted. Do not continue autonomous work '
            'without explicit user direction.',
          );
        }
      }
      if (hasProjectReadTools) {
        buffer.writeln(
          'For codebase exploration, prefer list_directory, find_files, '
          'search_files, and read_file before using local shell commands.',
        );
      }
      if (hasProjectWriteTools) {
        buffer.writeln(
          'For file changes, prefer edit_file for targeted replacements and '
          'write_file only when creating or fully rewriting files.',
        );
      }
      if (hasRollbackTool) {
        buffer.writeln(
          'If a recent file mutation needs to be undone, use '
          'rollback_last_file_change instead of manually reconstructing the '
          'previous file contents.',
        );
      }
      if (hasLocalShellTool) {
        buffer.writeln(
          'Use local_execute_command mainly for running tests, analyzers, '
          'formatters, or other toolchain commands that are awkward to '
          'express with the file tools.',
        );
      }
      if (hasOsSystemInfoTool) {
        buffer.writeln(
          'Use os_get_system_info when the current machine operating system '
          'or version matters.',
        );
      }
      if (hasOsLogTool) {
        buffer.writeln(
          'For local machine diagnostics, prefer os_log_read when you need '
          'recent WiFi, network, or authentication logs from the current '
          'computer.',
        );
      }
      if (hasOsSystemInfoTool && hasOsLogTool) {
        buffer.writeln(
          'Before interpreting local OS logs, call os_get_system_info first '
          'if the current OS or version is unclear.',
        );
      }
      if (hasGitTool) {
        buffer.writeln(
          'Use git_execute_command for repository inspection and git write '
          'operations instead of generic shell commands when possible.',
        );
      }
      if (hasProjectReadTools || hasLocalShellTool || hasGitTool) {
        buffer.writeln(
          'If a tool result contains permission_denied or '
          'bookmark_restore_failed, do not repeat the same tool call with the '
          'same arguments. Explain the access issue and ask the user to '
          're-select the project folder or grant access.',
        );
      }
      if (workflowStage != ConversationWorkflowStage.idle ||
          normalizedWorkflowSpec.hasContent) {
        final planningPlanMarkdown = planArtifact?.planningMarkdown;
        final executionPlanMarkdown = planArtifact?.executionMarkdown;
        final preferredPlanMarkdown = assistantMode == AssistantMode.plan
            ? planningPlanMarkdown
            : executionPlanMarkdown;
        if (preferredPlanMarkdown != null) {
          buffer.writeln(
            assistantMode == AssistantMode.plan
                ? 'Current plan document draft for this coding thread (source of truth while planning):'
                : 'Approved plan document for this coding thread (source of truth while implementing):',
          );
          buffer.writeln(_clipPlanDocumentForPrompt(preferredPlanMarkdown));
          if (assistantMode != AssistantMode.plan &&
              (planArtifact?.hasPendingEdits ?? false)) {
            buffer.writeln(
              'A newer draft plan document exists, but the last approved document remains the source of truth until the draft is approved.',
            );
          }
          buffer.writeln(
            'Treat the structured workflow data below as a supporting execution projection, not as a separate source of truth.',
          );
        }
        buffer.writeln(
          'Current workflow stage for this coding thread: '
          '${_formatWorkflowStage(workflowStage)}.',
        );
        buffer.writeln(
          'Use the saved workflow context below to stay aligned with the '
          'current implementation effort.',
        );
        if (normalizedWorkflowSpec.goal.trim().isNotEmpty) {
          buffer.writeln('Goal: ${normalizedWorkflowSpec.goal.trim()}');
        }
        if (normalizedWorkflowSpec.constraints.isNotEmpty) {
          buffer.writeln(
            'Constraints: ${_joinWorkflowItems(normalizedWorkflowSpec.constraints)}',
          );
        }
        if (normalizedWorkflowSpec.acceptanceCriteria.isNotEmpty) {
          buffer.writeln(
            'Acceptance criteria: ${_joinWorkflowItems(normalizedWorkflowSpec.acceptanceCriteria)}',
          );
        }
        if (normalizedWorkflowSpec.openQuestions.isNotEmpty) {
          buffer.writeln(
            'Open questions: ${_joinWorkflowItems(normalizedWorkflowSpec.openQuestions)}',
          );
        }
        if (normalizedWorkflowSpec.tasks.isNotEmpty) {
          buffer.writeln('Saved tasks:');
          for (
            var index = 0;
            index < normalizedWorkflowSpec.tasks.length;
            index++
          ) {
            final task = normalizedWorkflowSpec.tasks[index];
            final taskParts = <String>[
              '${index + 1}. [${_formatWorkflowTaskStatus(task.status)}] ${task.title.trim()}',
            ];
            final targetFiles = task.targetFiles
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .join(', ');
            if (targetFiles.isNotEmpty) {
              taskParts.add('files: $targetFiles');
            }
            final validationCommand = task.validationCommand.trim();
            if (validationCommand.isNotEmpty) {
              taskParts.add('validate: $validationCommand');
            }
            final notes = task.notes.trim();
            if (notes.isNotEmpty) {
              taskParts.add('notes: $notes');
            }
            buffer.writeln(taskParts.join(' | '));
          }
          buffer.writeln(
            'Prefer moving the highest-priority unfinished saved task forward unless the user redirects you.',
          );
          buffer.writeln(
            'When a saved task is complete, continue to the next pending saved task automatically instead of asking for confirmation between tasks.',
          );
          buffer.writeln(
            'When writing CLI validation scripts, assert success versus non-zero failure semantics unless the saved task explicitly requires a platform-specific exit code.',
          );
          buffer.writeln(
            'Pause only when you are blocked, the requirements changed, or completing the next task would require changing the approved workflow.',
          );
          buffer.writeln(
            'If normal file or command approvals are shown by the app, treat those approvals as sufficient and do not ask for duplicate permission in natural language.',
          );
        }
        buffer.writeln(
          'If the latest user request changes this workflow, explain the '
          'mismatch and propose the updated plan before making broad changes.',
        );
      }
      if ((workflowStage == ConversationWorkflowStage.idle &&
              !normalizedWorkflowSpec.hasContent) &&
          (planArtifact?.displayMarkdown(
                isPlanning: assistantMode == AssistantMode.plan,
              ) !=
              null)) {
        final preferredPlanMarkdown = planArtifact!.displayMarkdown(
          isPlanning: assistantMode == AssistantMode.plan,
        )!;
        buffer.writeln(
          assistantMode == AssistantMode.plan
              ? 'Current plan document draft for this coding thread (source of truth while planning):'
              : 'Approved plan document for this coding thread (source of truth while implementing):',
        );
        buffer.writeln(_clipPlanDocumentForPrompt(preferredPlanMarkdown));
      }
    }

    if (isVoiceMode) {
      buffer.writeln(SystemPromptConstants.voiceModeInstruction);
      if (hasTools) {
        buffer.writeln(SystemPromptConstants.voiceModeToolInstruction);
      }
    }

    final hasMemorySearch = uniqueToolNames.contains(
      'search_past_conversations',
    );
    final hasRecallMemory = uniqueToolNames.contains('recall_memory');

    if (hasTools) {
      buffer.writeln(
        'Use available tools when they materially improve accuracy, '
        'grounding, or recency.',
      );
      buffer.writeln(SystemPromptConstants.toolInterpretationInstruction);
      buffer.writeln('Available tools: ${uniqueToolNames.join(', ')}.');
      if (hasToolSearch) {
        buffer.writeln(
          'If the task needs a tool or capability that is not listed in '
          'Available tools, call tool_search with a concise capability query '
          'before claiming that you will use the missing tool. After '
          'tool_search returns a match, call the discovered tool in the next '
          'tool-call turn.',
        );
      }
      if (hasDatetimeTool) {
        buffer.writeln(
          'When the user asks about dates/times such as today, this week, '
          'recent, current, latest, or now, call get_current_datetime before '
          'answering.',
        );
      }
      if (hasMemorySearch || hasRecallMemory) {
        buffer.writeln(
          'When the user asks about something they previously mentioned, '
          'discussed, bought, decided, or any past event from their '
          'conversations, use search_past_conversations to find the relevant '
          'information before answering from memory alone. '
          'Use recall_memory for quick lookups of known facts and preferences.',
        );
      }
      if (hasComputerUseTools) {
        final spaceSwitchAction =
            uniqueToolNames.contains('computer_switch_space')
            ? 'approved computer_switch_space'
            : 'an approved Control-Left/Right key press';
        buffer.writeln(
          'For macOS computer-use tasks, start with computer_vision_observe. '
          'Use target=window with a known window_id, target=front_window for '
          'the first visible non-Caverno window, or target=display for the '
          'full display. Use display_id from computer_list_displays when '
          'the target is on a non-main display.',
        );
        buffer.writeln(
          'For macOS Spaces, use computer_list_windows or '
          'computer_vision_observe with space_scope=all_spaces when the '
          'target may be on another desktop. Treat windows marked outside '
          'the active Space as read-only candidates until the window is '
          'focused or the Space is switched with $spaceSwitchAction, then '
          'observe again.',
        );
        buffer.writeln(
          'After every click, drag, scroll, text input, key press, or system '
          'audio recording state change, observe again with '
          'computer_vision_observe before deciding the next desktop action.',
        );
        buffer.writeln(
          'Use raw computer_list_displays, computer_list_windows, '
          'computer_screenshot, and computer_screenshot_window only for '
          'focused follow-up checks when computer_vision_observe is too broad.',
        );
        buffer.writeln(
          'Use computer_accessibility_snapshot when labels, roles, frames, '
          'enabled state, or focused state would reduce coordinate ambiguity. '
          'Treat its element IDs as valid only for the current snapshot.',
        );
        buffer.writeln(
          'When computer_vision_observe returns elementGrounding candidates, '
          'use the matching candidate elementId as element_id and repeat it '
          'in target.elementId before asking for an approved desktop action. '
          'Also include target appName, windowTitle, role, label, action, and '
          'risk when those values are available.',
        );
        buffer.writeln(
          'Use screenshot pixel coordinates from the latest observation. '
          'Include window_id for window screenshots, source_width, '
          'source_height, coordinate_space, and vision_observation_id when '
          'calling coordinate-based computer tools.',
        );
        buffer.writeln(
          'Read the actionProposalPolicy returned by computer_vision_observe '
          'before proposing a desktop action. Include target metadata for '
          'approved desktop actions when the policy requires target approval.',
        );
        buffer.writeln(
          'Treat productionActionPolicy as the required production gate: every '
          'desktop action needs fresh observation, an approval packet, '
          'action-time confirmation, emergency stop availability, execution '
          'result intake, and post-action review.',
        );
        buffer.writeln(
          'For computer_type_text, include the exact text to type and do not '
          'ask the user to approve a vague or summarized text action.',
        );
        buffer.writeln(
          'For controls that post, send, submit, or publish, set '
          'target.risk=public_action and wait for separate '
          'public action approval before clicking or pressing the key.',
        );
        buffer.writeln(
          'For secure fields, credential prompts, payment flows, or destructive '
          'controls, set target.risk to secure_field, credential, payment, or '
          'destructive and do not ask Caverno to execute the action; ask the '
          'user to handle it manually or choose a safer target.',
        );
        buffer.writeln(
          'When a desktop action returns an attached post-action observation, '
          'inspect that observation before proposing any further desktop '
          'action. Treat one observe-action-observe cycle as the smallest safe '
          'unit of work.',
        );
        buffer.writeln(
          'If a computer-use result reports accessibility_denied, '
          'screen_capture_unavailable, or screenshot_failed, follow the '
          'returned nextAction. Use computer_open_system_settings only when '
          'the user wants the relevant macOS settings pane opened.',
        );
        buffer.writeln(
          'If the target is ambiguous, hidden, or could trigger credential, '
          'payment, destructive, or external-send behavior, pause and ask the '
          'user instead of guessing.',
        );
        buffer.writeln(
          'The app will show approval dialogs for desktop control actions; '
          'treat those approvals as sufficient and do not ask for duplicate '
          'permission in natural language.',
        );
      }
    }

    if (hasSearchTool || hasWebReader) {
      buffer.writeln(
        'When current or external information matters, use the web '
        'tools before answering from memory.',
      );
      if (hasSearchTool) {
        final searchToolNames = uniqueToolNames
            .where(
              (name) => name == 'searxng_web_search' || name == 'web_search',
            )
            .join(', ');
        buffer.writeln('Use $searchToolNames for web search.');
      }
      if (hasWebReader) {
        buffer.writeln(
          'Use web_url_read to inspect page contents when snippets are '
          'insufficient.',
        );
      }
      buffer.writeln(
        'Do not claim that you cannot access real-time information '
        'when these tools are available.',
      );
      // In voice mode, the voiceModeInstruction already covers citation style
      // ("say the site name only"). Skip the URL-based citation instruction.
      if (!isVoiceMode) {
        buffer.writeln(SystemPromptConstants.webCitationInstruction);
      }
    }

    final memoryContext = sessionMemoryContext?.trim();
    if (memoryContext != null && memoryContext.isNotEmpty) {
      buffer.writeln(
        'Use the following context from past conversations to maintain '
        'continuity when helpful.',
      );
      buffer.writeln(memoryContext);
      buffer.writeln(
        'Treat low-confidence memories as hypotheses and verify against the '
        'current user message.',
      );
      buffer.writeln(
        'If memory conflicts with the current request, prioritize the current '
        'request.',
      );
    }

    return buffer.toString().trimRight();
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  static String _formatWorkflowStage(ConversationWorkflowStage value) {
    return switch (value) {
      ConversationWorkflowStage.idle => 'idle',
      ConversationWorkflowStage.clarify => 'clarify',
      ConversationWorkflowStage.plan => 'plan',
      ConversationWorkflowStage.tasks => 'tasks',
      ConversationWorkflowStage.implement => 'implement',
      ConversationWorkflowStage.review => 'review',
    };
  }

  static String _formatWorkflowTaskStatus(
    ConversationWorkflowTaskStatus value,
  ) {
    return switch (value) {
      ConversationWorkflowTaskStatus.pending => 'pending',
      ConversationWorkflowTaskStatus.inProgress => 'in_progress',
      ConversationWorkflowTaskStatus.completed => 'completed',
      ConversationWorkflowTaskStatus.blocked => 'blocked',
    };
  }

  static String _joinWorkflowItems(List<String> items) {
    return items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join(' | ');
  }

  static String _clipPlanDocumentForPrompt(String markdown) {
    final normalized = markdown.replaceAll(RegExp(r'\s+\n'), '\n').trim();
    if (normalized.length <= 2200) {
      return normalized;
    }
    return '${normalized.substring(0, 2200)}...';
  }
}

import '../../../../core/constants/system_prompt_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../entities/conversation_goal.dart';
import '../entities/conversation_plan_artifact.dart';
import '../entities/conversation_workflow.dart';
import 'weak_model_edit_harness_service.dart';

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
    String? repoMapContext,
    ConversationGoal? goal,
    ConversationWorkflowStage workflowStage = ConversationWorkflowStage.idle,
    ConversationWorkflowSpec? workflowSpec,
    ConversationPlanArtifact? planArtifact,
    bool isVoiceMode = false,
    String? agentsMarkdown,
    String? skillsContext,
    bool hasPythonInputAttachment = false,
    ModelCapabilityProfile? modelCapabilityProfile,
    ModelHarnessConfig? modelHarnessConfig,
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
        uniqueToolNames.contains('inspect_file') ||
        uniqueToolNames.contains('find_files') ||
        uniqueToolNames.contains('search_files');
    final hasDependencyGroundingTool = uniqueToolNames.contains(
      'resolve_installed_dependency',
    );
    final hasProjectWriteTools =
        uniqueToolNames.contains('write_file') ||
        uniqueToolNames.contains('edit_file');
    final hasRollbackTool = uniqueToolNames.contains(
      'rollback_last_file_change',
    );
    final hasLocalShellTool = uniqueToolNames.contains('local_execute_command');
    final hasRunTestsTool = uniqueToolNames.contains('run_tests');
    final hasRunPythonScriptTool = uniqueToolNames.contains(
      'run_python_script',
    );
    final hasBackgroundProcessTools = uniqueToolNames.any(
      (name) =>
          name == 'process_start' ||
          name == 'process_status' ||
          name == 'process_tail' ||
          name == 'process_wait' ||
          name == 'process_cancel' ||
          name == 'process_list',
    );
    final hasSubagentTools = uniqueToolNames.contains('spawn_subagent');
    final hasOsSystemInfoTool = uniqueToolNames.contains('os_get_system_info');
    final hasOsLogTool = uniqueToolNames.contains('os_log_read');
    final hasGitTool = uniqueToolNames.contains('git_execute_command');
    final hasLoadSkillTool = uniqueToolNames.contains('load_skill');
    final hasComputerUseTools = uniqueToolNames.any(
      (name) => name.startsWith('computer_'),
    );
    final hasBrowserTools = uniqueToolNames.any(
      (name) => name.startsWith('browser_'),
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
      ..writeln(SystemPromptConstants.knowledgeCutoffHumilityInstruction)
      ..writeln(SystemPromptConstants.coreAssistantPrompt)
      ..writeln(SystemPromptConstants.priorityInstruction)
      ..writeln(SystemPromptConstants.judgmentInstruction)
      ..writeln(SystemPromptConstants.communicationInstruction)
      ..writeln(SystemPromptConstants.noSystemPromptReferenceInstruction)
      ..writeln(SystemPromptConstants.oversightInstruction)
      ..writeln(SystemPromptConstants.languageInstruction(languageCode));

    final modelCapabilityGuidance = _modelCapabilityGuidance(
      modelCapabilityProfile,
    );
    if (modelCapabilityGuidance.isNotEmpty) {
      buffer.writeln(modelCapabilityGuidance);
    }

    final modelHarnessGuidance = _modelHarnessGuidance(modelHarnessConfig);
    if (modelHarnessGuidance.isNotEmpty) {
      buffer.writeln(modelHarnessGuidance);
    }

    // In voice mode, follow-up questions are handled by the voice mode
    // instruction, and the voice mode instruction already bans all formatting,
    // so the formatting-minimization guidance is redundant there.
    if (!isVoiceMode) {
      buffer.writeln(SystemPromptConstants.formattingMinimizationInstruction);
      buffer.writeln(SystemPromptConstants.optionalFollowUpQuestionInstruction);
      buffer.writeln(SystemPromptConstants.exactPreservationInstruction);
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
      final normalizedRepoMapContext = repoMapContext?.trim();
      if (normalizedRepoMapContext != null &&
          normalizedRepoMapContext.isNotEmpty) {
        buffer.writeln(
          'Repository map for the active project. Treat this as bounded, '
          'read-only orientation and verify current file contents with tools '
          'before editing.',
        );
        buffer.writeln('<repo_map>');
        buffer.writeln(normalizedRepoMapContext);
        buffer.writeln('</repo_map>');
      }
      final normalizedAgentsMarkdown = agentsMarkdown?.trim();
      if (normalizedAgentsMarkdown != null &&
          normalizedAgentsMarkdown.isNotEmpty) {
        buffer.writeln(
          'The following AGENTS.md from the project root contains '
          'project-specific guidance the user maintains for coding agents. '
          'Treat it as authoritative for this project unless it conflicts '
          'with the user\'s current request or the safety and oversight '
          'rules above.',
        );
        buffer.writeln('<agents_md>');
        buffer.writeln(normalizedAgentsMarkdown);
        buffer.writeln('</agents_md>');
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
        buffer.writeln(
          'For very large files (logs, JSONL/CSV exports, multi-MB text), do '
          'not read the whole file. First call inspect_file to get size, total '
          'lines, and head/tail; then use search_files to locate relevant '
          'lines and read_file with offset and limit to read only the ranges '
          'you need. If a message contains an "Attached file:" path, treat it '
          'as a large on-disk file and explore it with these tools.',
        );
        buffer.writeln(
          'When analyzing Caverno LLM session logs, treat each JSONL line as '
          'a caverno_llm_session_log_entry object and inspect response.content, '
          'response.finishReason, response.toolCalls, and response.usage '
          'directly instead of assuming an OpenAI choices[] wrapper. Start '
          'with compact per-line metadata before deeper content reads.',
        );
      }
      if (hasDependencyGroundingTool) {
        buffer.writeln(
          'When a coding task depends on a third-party API, package symbol, '
          'import, or version-specific behavior, call '
          'resolve_installed_dependency before guessing. Treat its offline '
          'lockfile-matched source and docs as authoritative for installed '
          'dependency APIs.',
        );
      }
      if (hasProjectWriteTools) {
        buffer.writeln(
          'For file changes, prefer edit_file for targeted replacements and '
          'write_file only when creating or fully rewriting files.',
        );
        buffer.writeln(
          'Do not claim that local files were created, edited, moved, saved, '
          'or deleted unless an application-executed tool result confirms '
          'the successful operation.',
        );
        final weakModelEditHarnessGuidance =
            WeakModelEditHarnessService.buildPromptContext(
              profile: modelCapabilityProfile,
              toolNames: uniqueToolNames,
              assistantMode: assistantMode,
            );
        if (weakModelEditHarnessGuidance.isNotEmpty) {
          buffer.writeln(weakModelEditHarnessGuidance);
        }
      }
      if (hasRollbackTool) {
        buffer.writeln(
          'If a recent file mutation needs to be undone, use '
          'rollback_last_file_change instead of manually reconstructing the '
          'previous file contents.',
        );
      }
      if (hasRunTestsTool) {
        buffer.writeln(
          'Use run_tests only for scoped Dart or Flutter validation tests with '
          'a specific test file or directory. It builds a project-scoped '
          'command and uses the local command approval flow.',
        );
      }
      if (hasLocalShellTool) {
        buffer.writeln(
          'Use local_execute_command mainly for analyzers, '
          'formatters, or other toolchain commands that are awkward to '
          'express with the file tools. Use it for tests only when run_tests '
          'is unavailable or unsuitable.',
        );
        buffer.writeln(
          'For file discovery and reading, prefer list_directory, find_files, '
          'search_files, and read_file. If local_execute_command is necessary, '
          'prefer absolute paths or working_directory over shell-only features '
          'such as pipes, redirection, environment variables, or command '
          'substitution.',
        );
        if (hasProjectWriteTools) {
          buffer.writeln(
            'If the user asks to delete a local project file and no dedicated '
            'file-delete tool is available, use local_execute_command with an '
            'exact non-interactive deletion command in the project workspace.',
          );
        }
      }
      if (hasBackgroundProcessTools) {
        if (hasRunTestsTool) {
          buffer.writeln(
            'For full project test suites such as flutter test, '
            'fvm flutter test, dart test, or fvm dart test with no specific '
            'test path, use local_execute_command with background=true or '
            'process_start instead of run_tests.',
          );
        }
        buffer.writeln(
          'Use local_execute_command with background=true, or use process_start '
          'for builds, releases, migrations, uploads, long tests, or commands '
          'expected to run longer than roughly one minute.',
        );
        buffer.writeln(
          'After starting a background process, use process_list(refresh: true, '
          'include_finished: false) to find and refresh running jobs started '
          'with process_start or background local_execute_command, then use '
          'process_status, process_tail, or process_wait to monitor until '
          'the command exits successfully.',
        );
        buffer.writeln(
          'For long-running background work, do not merely wait silently. '
          'Periodically inspect status plus stdout/stderr tails, report concise '
          'progress with the latest observed phase, elapsed time, and any '
          'important warnings or errors, then continue monitoring until a '
          'terminal status is observed.',
        );
        buffer.writeln(
          'Do not claim task completion from prose or tool argument success '
          'until the relevant background job has exited with exit_code 0.',
        );
      }
      if (hasSubagentTools) {
        buffer.writeln(
          'When using spawn_subagent with background=true, do not claim the '
          'task is complete until get_subagent_result reports status=completed for that '
          'task_id, and include the summary when it does.',
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
        buffer.writeln(
          'Each git_execute_command call must contain exactly one git '
          'subcommand without shell operators such as &&, ;, |, or '
          'redirection. Split staging, committing, and other git steps into '
          'separate tool calls.',
        );
        buffer.writeln(
          'Do not claim that git state changed unless a successful '
          'application-executed git_execute_command result confirms it.',
        );
        buffer.writeln(
          'Before creating a git tag, inspect existing tags with '
          'git_execute_command (for example, "tag --list" or '
          '"for-each-ref refs/tags --format=%(refname:short)") and choose a '
          'new tag name that matches the repository\'s existing tag format.',
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

    final normalizedSkillsContext = skillsContext?.trim();
    if (normalizedSkillsContext != null &&
        normalizedSkillsContext.isNotEmpty &&
        hasLoadSkillTool) {
      buffer.writeln(normalizedSkillsContext);
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
        buffer.writeln(SystemPromptConstants.toolSearchProactiveInstruction);
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
      if (hasLoadSkillTool) {
        buffer.writeln(
          'When a listed user skill is relevant, call load_skill before '
          'using it so you can follow the full saved instructions.',
        );
      }
      if (hasRunPythonScriptTool) {
        buffer.writeln(
          'Use run_python_script to compute answers you cannot derive '
          'directly: parsing or analyzing files, inspecting attached media '
          '(e.g. image metadata/EXIF), data processing, or math. Write a '
          'complete Python 3 script that prints its findings and/or calls '
          'caverno.set_output(value). Only the Python standard library is '
          'guaranteed; piexif is bundled for image EXIF.',
        );
        if (hasPythonInputAttachment) {
          buffer.writeln(
            'The user\'s latest message includes an attached file, staged on '
            'disk and available to run_python_script via caverno.inputs[0] '
            '(.path, .read_bytes(), .read_text()). Reach the attachment '
            'through caverno.inputs instead of asking for or guessing a path.',
          );
          buffer.writeln(
            'For image metadata, prefer `path = caverno.inputs[0].path` and '
            '`piexif.load(path)`. When naming EXIF tags, use '
            '`piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries '
            'are maps.',
          );
        }
      }
      if (hasBrowserTools) {
        buffer.writeln(
          'When the user asks you to click, open, navigate, type, search, '
          'submit, or otherwise act in the built-in browser, call the '
          'relevant browser tool. Do not claim the browser action is complete '
          'from prose, inferred URLs, or memory; report completion only from '
          'a successful browser tool result.',
        );
        buffer.writeln(
          'For built-in browser tasks, call browser_snapshot before using '
          'browser_fill, browser_click, or browser_submit unless the current '
          'message context already includes a fresh browser_snapshot result '
          'with refs. Use only refs from the latest browser_snapshot result; '
          'do not guess refs from labels, summaries, or prior turns.',
        );
        buffer.writeln(
          'For form submission after filling an input, prefer browser_submit '
          'with a selector or the filled field ref instead of guessing a submit '
          'button ref. If browser_fill, browser_click, or browser_submit reports '
          'element_not_found, stale target, or no matching element, call '
          'browser_snapshot once to refresh refs before retrying.',
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
      buffer.writeln(
        'Treat [Recent Session Summaries] and [Retrieved Memories] as '
        'historical context, not verified evidence about the current '
        'workspace, filesystem, runtime, network, external dependencies, or '
        'root cause. Use this context to choose what to verify next; do not '
        'present prior assistant conclusions from it as confirmed unless the '
        'current user message or current application-executed tool results '
        'support them.',
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

  static String _modelCapabilityGuidance(ModelCapabilityProfile? profile) {
    if (profile == null) {
      return '';
    }
    final lines = <String>[];
    switch (profile.toolCallStyle) {
      case ModelToolCallStyle.embeddedToolTags:
        lines.add(
          'MODEL CAPABILITY PROFILE: This model is more reliable with Caverno textual tool-call tags than native OpenAI tool calls. When a tool is required, emit exactly one complete <tool_call>{"name":"tool_name","arguments":{...}}</tool_call> block and no surrounding prose.',
        );
      case ModelToolCallStyle.none:
        lines.add(
          'MODEL CAPABILITY PROFILE: This model has not demonstrated reliable tool calling. Do not emit tool-call-shaped text unless the user request truly requires a tool and the available tool contract is clear.',
        );
      case ModelToolCallStyle.nativeToolCalls:
        lines.add(
          'MODEL CAPABILITY PROFILE: This model has demonstrated reliable native tool calls. Prefer native tool calls over textual tool-call tags.',
        );
      case ModelToolCallStyle.unknown:
        break;
    }
    switch (profile.structuredOutputSupport) {
      case ModelStructuredOutputSupport.none:
        lines.add(
          'MODEL CAPABILITY PROFILE: This model has weak structured-output adherence. Keep JSON and code blocks minimal, syntactically complete, and verify required keys before answering.',
        );
      case ModelStructuredOutputSupport.jsonObject:
      case ModelStructuredOutputSupport.jsonSchema:
        lines.add(
          'MODEL CAPABILITY PROFILE: This model has demonstrated structured-output adherence. Use compact, valid JSON when a machine-readable response is requested.',
        );
      case ModelStructuredOutputSupport.unknown:
        break;
    }
    switch (profile.editFormatPreference) {
      case ModelEditFormatPreference.wholeFile:
        lines.add(
          'MODEL CAPABILITY PROFILE: Prefer whole-file edits when editing is required.',
        );
      case ModelEditFormatPreference.searchReplace:
        lines.add(
          'MODEL CAPABILITY PROFILE: Prefer small search-and-replace edit blocks with exact surrounding context.',
        );
      case ModelEditFormatPreference.unifiedDiff:
        lines.add(
          'MODEL CAPABILITY PROFILE: Prefer unified diffs for file edits when the tool accepts them.',
        );
      case ModelEditFormatPreference.unknown:
        break;
    }
    if (profile.usableContextTokens > 0) {
      lines.add(
        'MODEL CAPABILITY PROFILE: Keep prompt construction within approximately ${profile.usableContextTokens} usable context tokens for this model.',
      );
    }
    if (lines.isEmpty) {
      return '';
    }
    return lines.join('\n');
  }

  /// LL23: renders the prompt-level surfaces of the per-model harness config.
  ///
  /// Only the instruction surfaces and the exploration-to-edit nudge are
  /// rendered here; runtime control policy (tool-loop cap, recovery middleware)
  /// is applied by the tool loop, not the prompt. Empty surfaces fall back to
  /// the built-in guidance, so a config with no overrides emits nothing.
  static String _modelHarnessGuidance(ModelHarnessConfig? config) {
    if (config == null) {
      return '';
    }
    final lines = <String>[];
    void addSurface(String label, String value) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        lines.add('MODEL HARNESS GUIDANCE ($label): $normalized');
      }
    }

    addSurface('bootstrap', config.bootstrapInstruction);
    addSurface('execution', config.executionInstruction);
    addSurface('verification', config.verificationInstruction);
    addSurface('failure recovery', config.failureRecoveryInstruction);
    if (config.explorationToEditNudgeEnabled) {
      lines.add(
        'MODEL HARNESS GUIDANCE (exploration): Once you understand the task, '
        'transition from exploration to implementation and make the change '
        'instead of continuing to read or search.',
      );
    }
    if (config.recoveryMiddlewareEnabled) {
      lines.add(
        'MODEL HARNESS GUIDANCE (recovery): When a tool call fails, do not '
        'blindly retry the same call. Diagnose the error, re-read the relevant '
        'file or state, recreate any missing required artifacts, then proceed.',
      );
    }
    if (lines.isEmpty) {
      return '';
    }
    return lines.join('\n');
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

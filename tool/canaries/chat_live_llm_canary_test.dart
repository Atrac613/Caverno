import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/apple_foundation_models_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _basicMarker = 'CHAT_BASIC_LIVE_OK';
const _embeddedMarker = 'EMBEDDED_TOOL_LIVE_OK';
const _inlineRecoveryMarker = 'INLINE_TOOL_RECOVERY_LIVE_OK';
const _inlineRecoveryTrigger = 'INLINE_TOOL_RECOVERY_CANARY_TRIGGER';
const _toolResultIgnoredMarker = 'ASSISTANT_TOOL_RESULT_IGNORED_LIVE_OK';
const _toolResultIgnoredTrigger =
    'ASSISTANT_TOOL_RESULT_IGNORED_CANARY_TRIGGER';
const _toolSearchArtifactMarker = 'TOOL_SEARCH_ARTIFACT_LIVE_OK';
const _exactToolResultValue =
    'https://example.test/downloads/build_2026-06-10.tar.zst?sha=abc123_def | '
    'ZX-900_α | 2026-06-12 | ¥3,980 | 12 GiB';
const _skillFollowUpMarker = 'SKILL_FOLLOWUP_LIVE_OK';
const _skillFollowUpContinuation = 'では実際に確認を進めます';
const _foundationEnglishMatrixMarker = 'FOUNDATION_LANGUAGE_EN_OK';
const _foundationJapaneseMatrixMarker = 'FOUNDATION_LANGUAGE_JA_OK';

void main() {
  final liveEnabled = Platform.environment['CAVERNO_CHAT_LIVE_CANARY'] == '1';
  final foundationModelsRun =
      liveEnabled && _isAppleFoundationModelsEnvironment();
  final foundationLanguageMatrixRun =
      foundationModelsRun &&
      Platform.environment['CAVERNO_FOUNDATION_MODELS_LANGUAGE_MATRIX'] == '1';

  test(
    'live LLM produces a plain chat response without tools',
    () async {
      final env = _ChatLiveEnv.fromEnvironment();
      final container = _buildChatContainer(
        env,
        mcpEnabled: false,
        toolService: _NoToolsMcpToolService(),
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Reply with exactly $_basicMarker and no extra text.',
        );
        await _waitForChatIdle(container);

        final content = _lastAssistantContent(container);
        expect(
          content.toUpperCase(),
          contains(_basicMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  if (foundationModelsRun) {
    test(
      'Foundation Models surfaces locale rejection without crashing',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final container = _buildChatContainer(
          env,
          mcpEnabled: false,
          toolService: _NoToolsMcpToolService(),
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Reply in the ja-JP locale with one short sentence.',
          );
          await _waitForChatSettled(container);

          final state = container.read(chatNotifierProvider);
          final assistantContent = _lastAssistantContent(container).trim();
          final error = state.error ?? '';
          if (error.isNotEmpty) {
            expect(
              error.toLowerCase(),
              anyOf(
                contains('language or locale'),
                contains('unsupported language'),
              ),
              reason: _chatDiagnostic(container),
            );
          } else {
            expect(
              assistantContent,
              isNotEmpty,
              reason: _chatDiagnostic(container),
            );
          }
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  if (foundationLanguageMatrixRun) {
    test(
      'Foundation Models language matrix accepts English baseline',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final container = _buildChatContainer(
          env,
          mcpEnabled: false,
          toolService: _NoToolsMcpToolService(),
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Reply with exactly $_foundationEnglishMatrixMarker and no extra text.',
          );
          await _waitForChatIdle(container);

          final content = _lastAssistantContent(container);
          expect(
            content.toUpperCase(),
            contains(_foundationEnglishMatrixMarker),
            reason: _chatDiagnostic(container),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'Foundation Models language matrix classifies Japanese prompt behavior',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final container = _buildChatContainer(
          env,
          mcpEnabled: false,
          toolService: _NoToolsMcpToolService(),
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            '\u6b21\u306e\u6587\u5b57\u5217\u3060\u3051\u3092\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044: $_foundationJapaneseMatrixMarker',
          );
          await _waitForChatSettled(container);

          final state = container.read(chatNotifierProvider);
          final assistantContent = _lastAssistantContent(container).trim();
          final error = state.error ?? '';
          if (error.isNotEmpty) {
            expect(
              error.toLowerCase(),
              anyOf(
                contains('language or locale'),
                contains('unsupported language'),
              ),
              reason: _chatDiagnostic(container),
            );
          } else {
            expect(
              assistantContent.toUpperCase(),
              contains(_foundationJapaneseMatrixMarker),
              reason: _chatDiagnostic(container),
            );
          }
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  if (!foundationModelsRun) {
    test(
      'live LLM memory extraction returns parseable bounded memory',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final dataSource = env.createDataSource();
        final now = DateTime(2026, 5, 22, 10, 0);
        final messages = [
          Message(
            id: 'memory_canary_user',
            role: MessageRole.user,
            timestamp: now,
            content:
                'My standing preference is concise English summaries. '
                'I bought a model canary notebook for 1200 yen on 2026-05-22.',
          ),
          Message(
            id: 'memory_canary_assistant',
            role: MessageRole.assistant,
            timestamp: now,
            content: 'Understood.',
          ),
        ];
        final extractionInput = MemoryExtractionDraftService.buildInput(
          messages,
          UserMemoryProfile.empty(),
        );

        final result = await dataSource.createChatCompletion(
          messages: [
            Message(
              id: 'memory_canary_system',
              role: MessageRole.system,
              timestamp: now,
              content: MemoryExtractionDraftService.systemPrompt,
            ),
            Message(
              id: 'memory_canary_request',
              role: MessageRole.user,
              timestamp: now,
              content: extractionInput,
            ),
          ],
          model: env.model,
          temperature: 0.1,
          maxTokens: env.maxTokens > 1200 ? 1200 : env.maxTokens,
        );
        final draft = MemoryExtractionDraftService.parseDraft(result.content);
        expect(
          draft,
          isNotNull,
          reason: 'rawMemoryExtraction=${result.content}',
        );

        final parsed = draft!;
        final combined = [
          parsed.summary,
          ...parsed.persona,
          ...parsed.preferences,
          ...parsed.doNot,
          ...parsed.entries.map((entry) => entry.text),
        ].join('\n').toLowerCase();
        expect(combined, contains('concise'));
        expect(combined, contains('1200'));
        expect(parsed.summary.length, lessThanOrEqualTo(160));
        expect(parsed.entries.length, lessThanOrEqualTo(8));
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  test(
    'live LLM embedded tool call executes once and exposes the result',
    () async {
      final env = _ChatLiveEnv.fromEnvironment();
      final toolService = _EchoMarkerToolService();
      final container = _buildChatContainer(
        env,
        mcpEnabled: false,
        toolService: toolService,
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Return exactly one content-embedded tool call and no markdown. '
          'Use this exact tool call: '
          '<tool_call>{"name":"echo_marker","arguments":{"marker":"$_embeddedMarker"}}</tool_call>. '
          'After the tool result is available, answer with $_embeddedMarker.',
        );
        await _waitForChatIdle(container);

        expect(toolService.executedToolNames, [
          _EchoMarkerToolService.toolName,
        ], reason: _chatDiagnostic(container));
        expect(
          _chatTranscript(container),
          contains(_embeddedMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  if (!foundationModelsRun) {
    test(
      'live LLM preserves exact raw tool result values',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final toolService = _ExactPreservationToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Return exactly one content-embedded tool call and no markdown. '
            'Use this exact tool call: '
            '<tool_call>{"name":"exact_preservation_payload","arguments":{}}</tool_call>. '
            'After the tool result is available, return only the raw_value '
            'from Raw result. Do not add quotes, punctuation, explanation, '
            'markdown, or any other characters.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
            diagnostic: () =>
                _exactPreservationDiagnostic(container, toolService),
          );

          expect(
            toolService.executedToolNames,
            [_ExactPreservationToolService.toolName],
            reason: _exactPreservationDiagnostic(container, toolService),
          );
          expect(
            _lastAssistantContent(container).trim(),
            _exactToolResultValue,
            reason: _exactPreservationDiagnostic(container, toolService),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'live LLM continues after recovered incomplete content tool call',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final prelude = _ScriptedIncompleteToolPrelude(
          trigger: _inlineRecoveryTrigger,
          toolName: _InlineRecoveryToolService.toolName,
          marker: _inlineRecoveryMarker,
        );
        final dataSource = _ChatLiveDataSource(
          env.createDataSource(),
          scriptedIncompleteToolPrelude: prelude,
        );
        final toolService = _InlineRecoveryToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
          chatDataSource: dataSource,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Run $_inlineRecoveryTrigger. '
            'After the recovered tool result is available, answer with exactly '
            '$_inlineRecoveryMarker and no extra text.',
          );
          await _waitForChatIdle(container);

          expect(
            prelude.used,
            isTrue,
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            toolService.executedToolNames,
            [_InlineRecoveryToolService.toolName],
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            toolService.executedArguments.single['marker'],
            _inlineRecoveryMarker,
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            _lastAssistantContent(container).toUpperCase(),
            contains(_inlineRecoveryMarker),
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );

          final liveContinuationRequest = dataSource.streamRequests.lastOrNull;
          expect(
            liveContinuationRequest,
            isNotNull,
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          final assistantHistory = liveContinuationRequest!
              .where((message) => message.role == MessageRole.assistant)
              .map((message) => message.content)
              .join('\n');
          expect(
            assistantHistory,
            isNot(contains('<tool_use>')),
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            assistantHistory,
            isNot(contains('<tool_result>')),
            reason: _inlineRecoveryDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'live LLM continues after ignored assistant-authored tool result',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final prelude = _ScriptedAssistantToolResultPrelude(
          trigger: _toolResultIgnoredTrigger,
          toolName: _ToolResultIgnoredToolService.toolName,
          marker: _toolResultIgnoredMarker,
        );
        final dataSource = _ChatLiveDataSource(
          env.createDataSource(),
          scriptedAssistantToolResultPrelude: prelude,
        );
        final toolService = _ToolResultIgnoredToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
          chatDataSource: dataSource,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Run $_toolResultIgnoredTrigger. '
            'This is a no-tool recovery canary. If the application reports that '
            'an assistant-authored tool_result was ignored, do not call tools. '
            'Answer with exactly $_toolResultIgnoredMarker and no extra text.',
          );
          await _waitForChatIdle(
            container,
            diagnostic: () => _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );

          expect(
            prelude.used,
            isTrue,
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            toolService.executedToolNames,
            isEmpty,
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            _lastAssistantContent(container).toUpperCase(),
            contains(_toolResultIgnoredMarker),
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            _chatTranscript(container),
            isNot(contains('<tool_result>')),
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );

          final liveContinuationRequest = dataSource.streamRequests.lastOrNull;
          expect(
            liveContinuationRequest,
            isNotNull,
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
          expect(
            liveContinuationRequest!.last.content,
            contains('[Assistant-authored tool_result ignored]'),
            reason: _toolResultIgnoredDiagnostic(
              container,
              toolService,
              prelude,
              dataSource,
            ),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'live LLM trims load_skill follow-up inspection text',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final toolService = _SkillFollowUpToolService();
        final dataSource = _ChatLiveDataSource(env.createDataSource());
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
          chatDataSource: dataSource,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Use the Release Check skill to verify release readiness. '
            'Call load_skill first with id "release-check". '
            'After the skill is loaded, follow its instructions exactly.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
            diagnostic: () =>
                _skillFollowUpDiagnostic(container, toolService, dataSource),
          );

          ChatCompletionResult? toolResultResponse;
          for (final response in dataSource.toolResultResponses) {
            final toolNames =
                response.toolCalls
                    ?.map((toolCall) => toolCall.name)
                    .toList(growable: false) ??
                const <String>[];
            if (toolNames.contains(
              _SkillFollowUpToolService.listDirectoryToolName,
            )) {
              toolResultResponse = response;
              break;
            }
          }
          expect(
            toolResultResponse,
            isNotNull,
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
          final followUpToolNames =
              toolResultResponse!.toolCalls
                  ?.map((toolCall) => toolCall.name)
                  .toList(growable: false) ??
              const <String>[];
          expect(
            followUpToolNames,
            contains(_SkillFollowUpToolService.listDirectoryToolName),
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
          expect(
            toolResultResponse.content,
            contains(_skillFollowUpContinuation),
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
          expect(
            toolService.executedToolNames,
            containsAll([
              _SkillFollowUpToolService.loadSkillToolName,
              _SkillFollowUpToolService.listDirectoryToolName,
            ]),
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
          expect(
            _lastAssistantContent(container).toUpperCase(),
            contains(_skillFollowUpMarker),
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
          expect(
            _lastAssistantContent(container),
            isNot(contains(_skillFollowUpContinuation)),
            reason: _skillFollowUpDiagnostic(
              container,
              toolService,
              dataSource,
            ),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'live LLM discovers a deferred tool and reads its persisted artifact',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final artifactRoot = Directory.systemTemp.createTempSync(
          'caverno_tool_search_artifact_live_',
        );
        final artifactStore = ToolResultArtifactStore(
          baseDirectory: artifactRoot,
        );
        final toolService = _ToolSearchArtifactToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
          artifactStore: artifactStore,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Find the hidden canary marker from the deep archive capability. '
            'The needed archive capability is not in your current tool list, so first call tool_search with query "deep archive canary lookup". '
            'Then call the matching archive tool. '
            'If that tool result says the full output was saved and gives a file_path plus a line number, call read_file with that file_path, offset, and limit. '
            'Answer with only the marker value, with no markdown or explanation.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
            diagnostic: () => _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );

          final artifactDirectory = Directory(
            '${artifactRoot.path}/tool-results',
          );
          final persistedFiles = artifactDirectory.existsSync()
              ? artifactDirectory
                    .listSync(recursive: true)
                    .whereType<File>()
                    .toList(growable: false)
              : const <File>[];
          final readFilePath = toolService.readFileArguments
              .map((arguments) => arguments['path']?.toString() ?? '')
              .where((path) => path.isNotEmpty)
              .lastOrNull;

          expect(
            toolService.executedToolNames,
            contains(ToolDefinitionSearchService.toolName),
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
          expect(
            toolService.executedToolNames,
            contains(_ToolSearchArtifactToolService.archiveToolName),
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
          expect(
            toolService.executedToolNames,
            contains(_ToolSearchArtifactToolService.readFileToolName),
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
          expect(
            persistedFiles,
            isNotEmpty,
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
          expect(
            readFilePath,
            startsWith(artifactRoot.path),
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
          expect(
            _lastAssistantContent(container).toUpperCase(),
            contains(_toolSearchArtifactMarker),
            reason: _toolSearchArtifactDiagnostic(
              container,
              toolService,
              artifactRoot,
            ),
          );
        } finally {
          container.dispose();
          if (artifactRoot.existsSync()) {
            artifactRoot.deleteSync(recursive: true);
          }
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'live LLM delegates a sub-task via spawn_subagent',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final toolService = _SubagentCanaryToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Use the spawn_subagent tool to delegate a sub-task that computes '
            '6 times 7 and returns only the number. After the subagent result '
            'is available, answer with only that number and no other text.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
          );

          expect(
            _lastAssistantContent(container),
            contains('42'),
            reason: _chatDiagnostic(container),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'live LLM subagent uses a tool and reports its result',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final toolService = _SubagentToolUserCanaryToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Use the spawn_subagent tool to delegate this sub-task: the subagent '
            'must call get_current_datetime and report the current year. Then '
            'answer with only the year.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
          );

          expect(
            toolService.executedToolNames,
            contains('get_current_datetime'),
            reason: _chatDiagnostic(container),
          );
          expect(
            _lastAssistantContent(container),
            isNotEmpty,
            reason: _chatDiagnostic(container),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'live LLM recovers a background subagent result',
      () async {
        final env = _ChatLiveEnv.fromEnvironment();
        final toolService = _SubagentToolUserCanaryToolService();
        final container = _buildChatContainer(
          env,
          mcpEnabled: true,
          toolService: toolService,
        );

        try {
          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Use spawn_subagent with the background argument set to true to '
            'compute 8 times 9 and return only the number. Tell me the task_id '
            'immediately.',
          );
          await _waitForChatIdle(
            container,
            timeout: const Duration(minutes: 5),
          );

          // Wait for the fire-and-forget background run to settle.
          final deadline = DateTime.now().add(const Duration(minutes: 4));
          while (DateTime.now().isBefore(deadline)) {
            final tasks = container.read(subagentTaskNotifierProvider);
            if (tasks.isNotEmpty && tasks.first.isTerminal) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }

          final tasks = container.read(subagentTaskNotifierProvider);
          expect(tasks, isNotEmpty, reason: _chatDiagnostic(container));
          expect(
            tasks.first.status,
            SubagentTaskStatus.completed,
            reason: _chatDiagnostic(container),
          );
          expect(
            tasks.first.resultSummary,
            contains('72'),
            reason: _chatDiagnostic(container),
          );
        } finally {
          container.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
}

ProviderContainer _buildChatContainer(
  _ChatLiveEnv env, {
  required bool mcpEnabled,
  required McpToolService toolService,
  ChatDataSource? chatDataSource,
  ToolResultArtifactStore? artifactStore,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(env: env, mcpEnabled: mcpEnabled),
      ),
      conversationsNotifierProvider.overrideWith(
        _LiveConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _LiveCodingProjectsNotifier.new,
      ),
      skillsNotifierProvider.overrideWith(_LiveSkillsNotifier.new),
      chatRemoteDataSourceProvider.overrideWithValue(
        chatDataSource ?? _ChatLiveDataSource(env.createDataSource()),
      ),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      if (artifactStore != null)
        toolResultArtifactStoreProvider.overrideWithValue(artifactStore),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 4),
  Duration settledWithoutAssistantTimeout = const Duration(seconds: 10),
  String Function()? diagnostic,
}) async {
  final deadline = DateTime.now().add(timeout);
  DateTime? idleWithoutAssistantSince;
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final hasFinishedAssistant = state.messages.any(
      (message) =>
          message.role == MessageRole.assistant && !message.isStreaming,
    );
    if (!state.isLoading && hasFinishedAssistant) {
      return;
    }
    if (!state.isLoading && !hasFinishedAssistant) {
      idleWithoutAssistantSince ??= DateTime.now();
      if (DateTime.now().difference(idleWithoutAssistantSince) >=
          settledWithoutAssistantTimeout) {
        throw TimeoutException(
          'Chat live canary settled without an assistant response.\n'
          '${diagnostic?.call() ?? _chatDiagnostic(container)}',
        );
      }
    } else {
      idleWithoutAssistantSince = null;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for chat live canary completion.\n'
    '${diagnostic?.call() ?? _chatDiagnostic(container)}',
  );
}

Future<void> _waitForChatSettled(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final hasFinishedAssistant = state.messages.any(
      (message) =>
          message.role == MessageRole.assistant && !message.isStreaming,
    );
    if (!state.isLoading && (hasFinishedAssistant || state.error != null)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for chat live canary settlement.\n'
    '${_chatDiagnostic(container)}',
  );
}

String _lastAssistantContent(ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  for (final message in messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message.content;
    }
  }
  return '';
}

String _chatTranscript(ProviderContainer container) {
  return container
      .read(chatNotifierProvider)
      .messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
}

String _chatDiagnostic(ProviderContainer container) {
  final state = container.read(chatNotifierProvider);
  return [
    'isLoading=${state.isLoading}',
    'error=${state.error}',
    'messages=${state.messages.length}',
    _chatTranscript(container),
  ].join('\n');
}

String _toolSearchArtifactDiagnostic(
  ProviderContainer container,
  _ToolSearchArtifactToolService toolService,
  Directory artifactRoot,
) {
  final artifactDirectory = Directory('${artifactRoot.path}/tool-results');
  final artifactPaths = artifactDirectory.existsSync()
      ? artifactDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .join(', ')
      : '(missing)';
  return [
    _chatDiagnostic(container),
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    'artifactRoot=${artifactRoot.path}',
    'artifactPaths=$artifactPaths',
  ].join('\n');
}

String _exactPreservationDiagnostic(
  ProviderContainer container,
  _ExactPreservationToolService toolService,
) {
  return [
    _chatDiagnostic(container),
    'expected=$_exactToolResultValue',
    'actual=${_lastAssistantContent(container)}',
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
  ].join('\n');
}

String _inlineRecoveryDiagnostic(
  ProviderContainer container,
  _InlineRecoveryToolService toolService,
  _ScriptedIncompleteToolPrelude prelude,
  _ChatLiveDataSource dataSource,
) {
  return [
    _chatDiagnostic(container),
    'preludeUsed=${prelude.used}',
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    ..._chatLiveDataSourceDiagnosticLines(dataSource),
  ].join('\n');
}

String _toolResultIgnoredDiagnostic(
  ProviderContainer container,
  _ToolResultIgnoredToolService toolService,
  _ScriptedAssistantToolResultPrelude prelude,
  _ChatLiveDataSource dataSource,
) {
  return [
    _chatDiagnostic(container),
    'preludeUsed=${prelude.used}',
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    ..._chatLiveDataSourceDiagnosticLines(dataSource),
  ].join('\n');
}

String _skillFollowUpDiagnostic(
  ProviderContainer container,
  _SkillFollowUpToolService toolService,
  _ChatLiveDataSource dataSource,
) {
  return [
    _chatDiagnostic(container),
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    ..._chatLiveDataSourceDiagnosticLines(dataSource),
  ].join('\n');
}

List<String> _chatLiveDataSourceDiagnosticLines(
  _ChatLiveDataSource dataSource,
) {
  return [
    'streamRequests=${dataSource.streamRequests.length}',
    'streamWithToolsRequests=${dataSource.streamWithToolsRequests.length}',
    'toolResultBatches=${dataSource.toolResultBatches.length}',
    'toolResultResponses=${dataSource.toolResultResponses.map((response) => {
      'finishReason': response.finishReason,
      'content': _diagnosticPreview(response.content),
      'toolCalls': response.toolCalls?.map((toolCall) => {'name': toolCall.name, 'arguments': toolCall.arguments}).toList(growable: false),
    }).map(jsonEncode).join(' | ')}',
  ];
}

String _diagnosticPreview(String value, [int maxLength = 1200]) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}

class _ChatLiveEnv {
  const _ChatLiveEnv({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
  });

  final LlmProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;

  static _ChatLiveEnv fromEnvironment() {
    final provider = _llmProviderFromEnvironment();
    final isAppleFoundationModels =
        provider == LlmProvider.appleFoundationModels;
    return _ChatLiveEnv(
      provider: provider,
      baseUrl: isAppleFoundationModels
          ? 'apple-foundation-models://local'
          : _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: isAppleFoundationModels
          ? ''
          : _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: isAppleFoundationModels
          ? AppSettings.appleFoundationModelsModelId
          : _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CHAT_LIVE_CANARY_MAX_TOKENS'] ?? '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CHAT_LIVE_CANARY_TEMPERATURE'] ?? '',
          ) ??
          0.1,
    );
  }

  ChatDataSource createDataSource() {
    return switch (provider) {
      LlmProvider.appleFoundationModels => AppleFoundationModelsDataSource(),
      LlmProvider.openAiCompatible => ChatRemoteDataSource(
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
    };
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for chat live LLM validation.');
  }
  return value;
}

LlmProvider _llmProviderFromEnvironment() {
  final value = Platform.environment['CAVERNO_LLM_PROVIDER']?.trim();
  return switch (value) {
    null ||
    '' ||
    'openAiCompatible' ||
    'openai' ||
    'openai_compatible' => LlmProvider.openAiCompatible,
    'appleFoundationModels' ||
    'apple_foundation_models' ||
    'foundation_models' => LlmProvider.appleFoundationModels,
    _ => throw StateError(
      'Unsupported CAVERNO_LLM_PROVIDER "$value" for chat live LLM validation.',
    ),
  };
}

bool _isAppleFoundationModelsEnvironment() {
  final value = Platform.environment['CAVERNO_LLM_PROVIDER']?.trim();
  return value == 'appleFoundationModels' ||
      value == 'apple_foundation_models' ||
      value == 'foundation_models';
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier({required this.env, required this.mcpEnabled});

  final _ChatLiveEnv env;
  final bool mcpEnabled;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      llmProvider: env.provider,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: mcpEnabled,
      demoMode: false,
    );
  }
}

class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    return null;
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {}
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _LiveSkillsNotifier extends SkillsNotifier {
  @override
  SkillsState build() {
    final now = DateTime(2026, 5, 29, 21, 0);
    return SkillsState(
      skills: [
        Skill(
          id: 'release-check',
          name: 'Release Check',
          description: 'Use for release readiness checks',
          whenToUse: 'When the user asks to verify release readiness',
          content: _SkillFollowUpToolService.skillContent,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _ChatLiveDataSource implements ChatDataSource {
  _ChatLiveDataSource(
    this.delegate, {
    this.scriptedIncompleteToolPrelude,
    this.scriptedAssistantToolResultPrelude,
  });

  final ChatDataSource delegate;
  final _ScriptedIncompleteToolPrelude? scriptedIncompleteToolPrelude;
  final _ScriptedAssistantToolResultPrelude? scriptedAssistantToolResultPrelude;
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> streamWithToolsRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<ChatCompletionResult> toolResultResponses = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final firstContent = messages.isEmpty ? '' : messages.first.content;
    if (firstContent.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      return Future.value(
        ChatCompletionResult(
          content: jsonEncode(<String, dynamic>{
            'summary': '',
            'open_loops': const <String>[],
            'profile': <String, dynamic>{
              'persona': const <String>[],
              'preferences': const <String>[],
              'do_not': const <String>[],
            },
            'memories': const <Map<String, dynamic>>[],
          }),
          finishReason: 'stop',
        ),
      );
    }
    return delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamWithToolsRequests.add(List<Message>.unmodifiable(messages));
    final prelude = scriptedIncompleteToolPrelude;
    if (prelude != null && prelude.shouldHandle(messages)) {
      return prelude.buildResult();
    }
    final toolResultPrelude = scriptedAssistantToolResultPrelude;
    if (toolResultPrelude != null && toolResultPrelude.shouldHandle(messages)) {
      return toolResultPrelude.buildResult();
    }
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    toolResultBatches.add(List<ToolResultInfo>.unmodifiable(toolResults));
    final result = await delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    toolResultResponses.add(result);
    return result;
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.streamWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _ScriptedIncompleteToolPrelude {
  _ScriptedIncompleteToolPrelude({
    required this.trigger,
    required this.toolName,
    required this.marker,
  });

  final String trigger;
  final String toolName;
  final String marker;
  bool used = false;

  bool shouldHandle(List<Message> messages) {
    if (used) {
      return false;
    }
    return messages.any(
      (message) =>
          message.role == MessageRole.user && message.content.contains(trigger),
    );
  }

  StreamWithToolsResult buildResult() {
    used = true;
    final content =
        'Starting inline recovery canary.\n'
        '<tool_use>{"name":"$toolName","arguments":{"marker":"$marker"}}';
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable([
        'Starting inline recovery canary.\n',
        '<tool_use>{"name":"$toolName","arguments":{"marker":"$marker"}}',
      ]),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: content, finishReason: 'stop'),
      ),
    );
  }
}

class _ScriptedAssistantToolResultPrelude {
  _ScriptedAssistantToolResultPrelude({
    required this.trigger,
    required this.toolName,
    required this.marker,
  });

  final String trigger;
  final String toolName;
  final String marker;
  bool used = false;

  bool shouldHandle(List<Message> messages) {
    if (used) {
      return false;
    }
    return messages.any(
      (message) =>
          message.role == MessageRole.user && message.content.contains(trigger),
    );
  }

  StreamWithToolsResult buildResult() {
    used = true;
    final payload = jsonEncode({
      'name': toolName,
      'summary': 'Completed',
      'details': ['marker: $marker'],
    });
    final content = '<tool_result>$payload</tool_result>';
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable([content]),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: content, finishReason: 'stop'),
      ),
    );
  }
}

class _NoToolsMcpToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Tool is not available'}),
      isSuccess: false,
      errorMessage: 'Tool is not available',
    );
  }
}

class _ToolResultIgnoredToolService extends McpToolService {
  static const toolName = 'assistant_tool_result_marker';

  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description':
              'A canary tool that must not be executed from assistant-authored tool_result content.',
          'parameters': {
            'type': 'object',
            'properties': {
              'marker': {'type': 'string'},
            },
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'This canary tool should not execute'}),
      isSuccess: false,
      errorMessage: 'This canary tool should not execute',
    );
  }
}

class _InlineRecoveryToolService extends McpToolService {
  static const toolName = 'inline_recovery_marker';

  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description':
              'Return a marker after the harness recovers an incomplete inline tool call.',
          'parameters': {
            'type': 'object',
            'properties': {
              'marker': {'type': 'string'},
            },
            'required': ['marker'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));
    if (name != toolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool',
      );
    }
    final marker = arguments['marker']?.toString() ?? '';
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'marker': marker,
        'instruction': 'Answer with exactly $marker and no extra text.',
      }),
      isSuccess: marker == _inlineRecoveryMarker,
      errorMessage: marker == _inlineRecoveryMarker
          ? null
          : 'Unexpected marker',
    );
  }
}

class _ExactPreservationToolService extends McpToolService {
  static const toolName = 'exact_preservation_payload';

  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description':
              'Return a raw exact-preservation payload for live LLM validation.',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));
    if (name != toolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool',
      );
    }
    return McpToolResult(
      toolName: name,
      result:
          'Raw result:\n'
          '${jsonEncode({'raw_value': _exactToolResultValue, 'instruction': 'Return raw_value exactly with no extra characters.'})}',
      isSuccess: true,
    );
  }
}

class _SkillFollowUpToolService extends McpToolService {
  static const loadSkillToolName = 'load_skill';
  static const listDirectoryToolName = 'list_directory';
  static const gitToolName = 'git_execute_command';

  static const skillContent =
      'Live canary skill instructions. After this skill is loaded, your next '
      'assistant response must include $_skillFollowUpMarker, list exactly two '
      'release verification steps in Japanese, and then end the visible text '
      'with the exact sentence "$_skillFollowUpContinuation。". In that same '
      'assistant response, call list_directory with {"path":"."}. Do not ask a follow-up '
      'question and do not add extra prose after the exact Japanese sentence.';

  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': loadSkillToolName,
          'description':
              'Load the full markdown instructions for a saved user skill.',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string'},
              'name': {'type': 'string'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': listDirectoryToolName,
          'description':
              'List files in a directory for release readiness inspection.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': gitToolName,
          'description': 'Run a git command for release readiness inspection.',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {'type': 'string'},
            },
            'required': ['command'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));

    if (name == loadSkillToolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'description': 'Use for release readiness checks',
          'whenToUse': 'When the user asks to verify release readiness',
          'content': skillContent,
        }),
        isSuccess: true,
      );
    }

    if (name == listDirectoryToolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'path': '.',
          'entries': ['pubspec.yaml', 'lib', 'test'],
        }),
        isSuccess: true,
      );
    }

    if (name == gitToolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({
          'command': arguments['command']?.toString() ?? '',
          'exit_code': 0,
          'stdout': 'On branch main\nnothing to commit, working tree clean',
        }),
        isSuccess: true,
      );
    }

    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Unsupported tool: $name'}),
      isSuccess: false,
      errorMessage: 'Unsupported tool: $name',
    );
  }
}

class _EchoMarkerToolService extends McpToolService {
  static const toolName = 'echo_marker';

  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description': 'Echo a canary marker for embedded tool validation.',
          'parameters': {
            'type': 'object',
            'properties': {
              'marker': {'type': 'string'},
            },
            'required': ['marker'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name != toolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool',
      );
    }
    final marker = arguments['marker']?.toString() ?? '';
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'marker': marker, 'ok': marker == _embeddedMarker}),
      isSuccess: marker == _embeddedMarker,
      errorMessage: marker == _embeddedMarker ? null : 'Unexpected marker',
    );
  }
}

/// Exposes only the subagent delegation tool so the canary can verify a model
/// invokes spawn_subagent. Execution is intercepted inside ChatNotifier, so
/// [executeTool] is never reached for spawn_subagent — it only needs to publish
/// the definition.
class _SubagentCanaryToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'spawn_subagent',
          'description':
              'Delegate a focused sub-task to a child agent that runs its own '
              'tool loop and returns a concise summary.',
          'parameters': {
            'type': 'object',
            'properties': {
              'description': {'type': 'string'},
              'prompt': {'type': 'string'},
              'background': {'type': 'boolean'},
            },
            'required': ['description', 'prompt'],
          },
        },
      },
    ];
  }
}

/// Exposes the delegation tools plus a project-free child tool
/// (get_current_datetime), so the canary can verify a subagent that actually
/// uses a tool, and background result recovery.
class _SubagentToolUserCanaryToolService extends McpToolService {
  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    Map<String, dynamic> fn(
      String name,
      String description,
      Map<String, dynamic> properties,
      List<String> required,
    ) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
        },
      },
    };

    return [
      fn(
        'spawn_subagent',
        'Delegate a sub-task to a child agent that runs its '
            'own tool loop and returns a summary.',
        {
          'description': {'type': 'string'},
          'prompt': {'type': 'string'},
          'background': {'type': 'boolean'},
        },
        ['description', 'prompt'],
      ),
      fn(
        'get_subagent_result',
        'Fetch the status/result of a background '
            'subagent.',
        {
          'task_id': {'type': 'string'},
        },
        ['task_id'],
      ),
      fn(
        'get_current_datetime',
        'Return the current date and time.',
        const <String, dynamic>{},
        const <String>[],
      ),
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name == 'get_current_datetime') {
      final now = DateTime.now();
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'iso': now.toIso8601String(), 'year': now.year}),
        isSuccess: true,
      );
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'unsupported'}),
      isSuccess: false,
      errorMessage: 'unsupported tool $name',
    );
  }
}

class _ToolSearchArtifactToolService extends McpToolService {
  static const archiveToolName = 'inspect_deep_archive_canary';
  static const readFileToolName = 'read_file';
  static const _markerLineNumber = 700;

  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];
  final List<Map<String, dynamic>> readFileArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return ToolDefinitionSearchService.appendSearchToolIfUseful([
      _readFileToolDefinition,
      for (var index = 0; index < 30; index += 1) _fillerToolDefinition(index),
      _archiveToolDefinition,
    ]);
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));

    if (name == ToolDefinitionSearchService.toolName) {
      final result = ToolDefinitionSearchService.searchToolDefinitions(
        definitions: getOpenAiToolDefinitions(),
        query: (arguments['query'] as String?) ?? '',
        maxResults:
            ((arguments['max_results'] as num?)?.toInt() ??
                    ToolDefinitionSearchService.defaultMaxResults)
                .clamp(1, ToolDefinitionSearchService.maxResultsLimit)
                .toInt(),
      );
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == archiveToolName) {
      return McpToolResult(
        toolName: name,
        result: _buildArchiveContent(),
        isSuccess: true,
      );
    }

    if (name == readFileToolName) {
      readFileArguments.add(Map<String, dynamic>.from(arguments));
      return _readPersistedArtifact(arguments);
    }

    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Unsupported tool: $name'}),
      isSuccess: false,
      errorMessage: 'Unsupported tool: $name',
    );
  }

  McpToolResult _readPersistedArtifact(Map<String, dynamic> arguments) {
    final path = (arguments['path'] as String?)?.trim();
    if (path == null || path.isEmpty) {
      return McpToolResult(
        toolName: readFileToolName,
        result: jsonEncode({
          'error': 'path_required',
          'instruction':
              'Call read_file again with the persisted file_path from the previous tool result.',
        }),
        isSuccess: false,
        errorMessage: 'path_required',
      );
    }

    final offset =
        _intArg(arguments, 'offset') ??
        _intArg(arguments, 'start_line') ??
        _intArg(arguments, 'line');
    final limit =
        _intArg(arguments, 'limit') ?? _intArg(arguments, 'line_count');
    if (offset == null) {
      return McpToolResult(
        toolName: readFileToolName,
        result: jsonEncode({
          'path': path,
          'error': 'offset_required',
          'instruction':
              'Call read_file again with offset $_markerLineNumber and limit 1.',
        }),
        isSuccess: false,
        errorMessage: 'offset_required',
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      return McpToolResult(
        toolName: readFileToolName,
        result: jsonEncode({'path': path, 'error': 'file_not_found'}),
        isSuccess: false,
        errorMessage: 'file_not_found',
      );
    }

    final lines = const LineSplitter().convert(file.readAsStringSync());
    final start = (offset - 1).clamp(0, lines.length);
    final end = (start + (limit ?? 1)).clamp(start, lines.length);
    return McpToolResult(
      toolName: readFileToolName,
      result: jsonEncode({
        'path': path,
        'offset': offset,
        'limit': limit ?? 1,
        'content': lines.sublist(start, end).join('\n'),
      }),
      isSuccess: true,
    );
  }

  static int? _intArg(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    return switch (value) {
      final int parsed => parsed,
      final num parsed => parsed.toInt(),
      final String raw => int.tryParse(raw.trim()),
      _ => null,
    };
  }

  static String _buildArchiveContent() {
    final lines = <String>[
      'Archive index: the marker is intentionally omitted from the preview.',
      'To answer, read this persisted artifact file at line $_markerLineNumber.',
      'Call read_file with the exact file_path from the persisted output payload, offset $_markerLineNumber, and limit 1.',
    ];
    for (var lineNumber = 4; lineNumber <= 1100; lineNumber += 1) {
      if (lineNumber == _markerLineNumber) {
        lines.add('CANARY_MARKER: $_toolSearchArtifactMarker');
      } else {
        lines.add(
          'archive filler line $lineNumber: this padding keeps the marker outside the persisted preview window.',
        );
      }
    }
    return lines.join('\n');
  }

  static Map<String, dynamic> get _readFileToolDefinition => const {
    'type': 'function',
    'function': {
      'name': readFileToolName,
      'description':
          'Read a line range from a persisted UTF-8 artifact file. Use offset and limit when another tool result provides a line number.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'offset': {'type': 'integer'},
          'limit': {'type': 'integer'},
        },
        'required': ['path'],
      },
    },
  };

  static Map<String, dynamic> get _archiveToolDefinition => const {
    'type': 'function',
    'function': {
      'name': archiveToolName,
      'description':
          'Deep archive canary lookup. Use this for hidden canary marker discovery after searching the tool catalog.',
      'parameters': {
        'type': 'object',
        'properties': {
          'request': {'type': 'string'},
        },
      },
    },
  };

  static Map<String, dynamic> _fillerToolDefinition(int index) {
    return {
      'type': 'function',
      'function': {
        'name': 'remote_catalog_filler_$index',
        'description':
            'Irrelevant remote catalog filler tool $index for dynamic search coverage.',
        'parameters': const {'type': 'object'},
      },
    };
  }
}

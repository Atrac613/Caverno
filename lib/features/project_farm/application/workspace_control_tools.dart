import 'dart:convert';

import '../../../core/types/workspace_mode.dart';
import '../../chat/data/datasources/built_in_tool_extension.dart';
import '../../chat/domain/entities/coding_project.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../domain/entities/roadmap_snapshot.dart';

/// Read-only control-plane tools over coding projects and their threads (FARM2).
///
/// See `docs/project_farm_roadmap.md`. Every answer comes from state Caverno
/// already holds: no model call, no file read, no change. A caller in a coding
/// thread sees only its own project; a chat thread sees every project; a call
/// with no identifiable thread is refused rather than guessed.
final class WorkspaceControlTools implements BuiltInToolExtension {
  WorkspaceControlTools({
    required this.projects,
    required this.conversations,
    required this.snapshotFor,
    required this.isBusy,
    required this.needsApproval,
    required this.callerConversationId,
  });

  static const listProjects = 'list_coding_projects';
  static const listThreads = 'list_coding_threads';
  static const projectState = 'get_project_state';
  static const readThread = 'read_coding_thread';

  static const Set<String> names = {
    listProjects,
    listThreads,
    projectState,
    readThread,
  };

  static const int _maxThreads = 50;
  static const int _maxMessages = 30;
  static const int _messageChars = 1500;
  static const int _transcriptChars = 12000;

  final List<CodingProject> Function() projects;
  final List<Conversation> Function() conversations;
  final RoadmapSnapshot? Function(String projectId) snapshotFor;
  final bool Function(String conversationId) isBusy;
  final bool Function(String conversationId) needsApproval;

  /// The thread whose turn is calling, from the `TurnThread` zone in
  /// production.
  final String? Function() callerConversationId;

  @override
  Set<String> get toolNames => names;

  @override
  List<Map<String, dynamic>> get definitions => [
    _function(
      listProjects,
      'List the coding projects in Caverno with each one\'s thread counts and '
      'the next task its roadmap names. Read-only.',
      const {},
    ),
    _function(
      listThreads,
      'List the coding threads of one project with their run state '
      '(running, needs_approval, idle) and goal. Read-only.',
      {
        'project_id': {
          'type': 'string',
          'description': 'Project id from list_coding_projects.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum threads, newest first (default 20, max 50).',
        },
      },
      required: const ['project_id'],
    ),
    _function(
      projectState,
      'Get one project\'s cached roadmap state: the next task, items in '
      'progress and blocked, each with its source line. Read-only; it does not '
      're-read the roadmap.',
      {
        'project_id': {
          'type': 'string',
          'description': 'Project id from list_coding_projects.',
        },
      },
      required: const ['project_id'],
    ),
    _function(
      readThread,
      'Read the latest messages of one coding thread (user and assistant '
      'text, reasoning removed, each message clipped). Read-only.',
      {
        'thread_id': {
          'type': 'string',
          'description': 'Thread id from list_coding_threads.',
        },
        'last_n': {
          'type': 'integer',
          'description': 'How many recent messages (default 10, max 30).',
        },
      },
      required: const ['thread_id'],
    ),
  ];

  @override
  Future<McpToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final scope = _callerScope();
    if (scope == null) {
      return _error(
        name,
        'This tool is only available inside a chat or coding thread.',
      );
    }
    return switch (name) {
      listProjects => _ok(name, {
        'projects': [
          for (final project in _visibleProjects(scope)) _projectJson(project),
        ],
      }),
      listThreads => _listThreads(name, scope, arguments),
      projectState => _projectState(name, scope, arguments),
      readThread => _readThread(name, scope, arguments),
      _ => _error(name, 'Unknown workspace tool.'),
    };
  }

  /// null: no caller. '': a chat thread (every project). Otherwise the one
  /// project a coding thread may see.
  String? _callerScope() {
    final callerId = callerConversationId();
    if (callerId == null) return null;
    final caller = conversations()
        .where((conversation) => conversation.id == callerId)
        .firstOrNull;
    if (caller == null) return null;
    if (caller.workspaceMode == WorkspaceMode.coding) {
      return caller.normalizedProjectId;
    }
    return '';
  }

  Iterable<CodingProject> _visibleProjects(String scope) =>
      projects().where((project) => scope.isEmpty || project.id == scope);

  CodingProject? _project(String scope, Object? id) {
    final wanted = id is String ? id.trim() : '';
    return _visibleProjects(
      scope,
    ).where((project) => project.id == wanted).firstOrNull;
  }

  List<Conversation> _threadsOf(String projectId) =>
      conversations()
          .where(
            (conversation) =>
                conversation.workspaceMode == WorkspaceMode.coding &&
                conversation.normalizedProjectId == projectId,
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  String _runState(String conversationId) => needsApproval(conversationId)
      ? 'needs_approval'
      : isBusy(conversationId)
      ? 'running'
      : 'idle';

  Map<String, dynamic> _projectJson(CodingProject project) {
    final threads = _threadsOf(project.id);
    final snapshot = snapshotFor(project.id);
    return {
      'id': project.id,
      'name': project.name,
      'root': project.rootPath,
      'threads': threads.length,
      'running': threads.where((t) => _runState(t.id) == 'running').length,
      'needs_approval': threads
          .where((t) => _runState(t.id) == 'needs_approval')
          .length,
      'next_task': snapshot?.recommended == null
          ? null
          : {
              'id': snapshot!.recommended!.id,
              'title': snapshot.recommended!.title,
              'verified': snapshot.status == RoadmapSnapshotStatus.verified,
            },
    };
  }

  McpToolResult _listThreads(
    String name,
    String scope,
    Map<String, dynamic> arguments,
  ) {
    final project = _project(scope, arguments['project_id']);
    if (project == null) return _error(name, _projectNotFound);
    final limit = _int(arguments['limit'], 20).clamp(1, _maxThreads);
    return _ok(name, {
      'project_id': project.id,
      'threads': [
        for (final thread in _threadsOf(project.id).take(limit))
          {
            'id': thread.id,
            'title': thread.title,
            'updated_at': thread.updatedAt.toIso8601String(),
            'state': _runState(thread.id),
            'worktree': thread.usesWorktree,
            'goal': thread.goal == null
                ? null
                : {
                    'status': thread.goal!.status.name,
                    'objective': _firstLine(thread.goal!.objective),
                  },
          },
      ],
    });
  }

  McpToolResult _projectState(
    String name,
    String scope,
    Map<String, dynamic> arguments,
  ) {
    final project = _project(scope, arguments['project_id']);
    if (project == null) return _error(name, _projectNotFound);
    final snapshot = snapshotFor(project.id);
    if (snapshot == null) {
      return _ok(name, {
        'project_id': project.id,
        'roadmap': null,
        'note':
            'No roadmap state is cached yet. The user can open the project '
            'dashboard to read the roadmap.',
      });
    }
    Map<String, dynamic> item(RoadmapItemSnapshot item) => {
      'id': item.id,
      'title': item.title,
      'quote': item.quote,
      'source': item.line == null
          ? snapshot.roadmapPath
          : '${snapshot.roadmapPath}:${item.line}',
      'verified': item.verified,
    };
    return _ok(name, {
      'project_id': project.id,
      'roadmap': {
        'path': snapshot.roadmapPath,
        'status': snapshot.status.name,
        'extracted_at': snapshot.extractedAt.toIso8601String(),
        'next_task': snapshot.recommended == null
            ? null
            : item(snapshot.recommended!),
        'in_progress': [for (final i in snapshot.current) item(i)],
        'blocked': [for (final i in snapshot.blocked) item(i)],
      },
    });
  }

  McpToolResult _readThread(
    String name,
    String scope,
    Map<String, dynamic> arguments,
  ) {
    final wanted = arguments['thread_id'] is String
        ? (arguments['thread_id'] as String).trim()
        : '';
    final thread = conversations()
        .where(
          (conversation) =>
              conversation.id == wanted &&
              conversation.workspaceMode == WorkspaceMode.coding &&
              (scope.isEmpty || conversation.normalizedProjectId == scope),
        )
        .firstOrNull;
    if (thread == null) {
      return _error(name, 'No visible coding thread has that id.');
    }
    final lastN = _int(arguments['last_n'], 10).clamp(1, _maxMessages);
    final visible = thread.messages
        .where(
          (message) =>
              message.role != MessageRole.system &&
              !message.isSynthesizedPrompt &&
              !message.isStreaming,
        )
        .toList();
    final recent = visible.skip(
      visible.length > lastN ? visible.length - lastN : 0,
    );
    final messages = <Map<String, dynamic>>[];
    var budget = _transcriptChars;
    for (final message in recent.toList().reversed) {
      final text = _clip(_withoutReasoning(message.content), _messageChars);
      if (text.isEmpty) continue;
      if (text.length > budget) break;
      budget -= text.length;
      messages.insert(0, {
        'role': message.role.name,
        'at': message.timestamp.toIso8601String(),
        'text': text,
      });
    }
    return _ok(name, {
      'thread_id': thread.id,
      'title': thread.title,
      'project_id': thread.normalizedProjectId,
      'state': _runState(thread.id),
      'messages': messages,
      'omitted_earlier': visible.length - messages.length,
    });
  }

  static const _projectNotFound =
      'No visible project has that id. Call list_coding_projects first.';

  static Map<String, dynamic> _function(
    String name,
    String description,
    Map<String, dynamic> properties, {
    List<String> required = const [],
  }) => {
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

  static McpToolResult _ok(String name, Map<String, dynamic> payload) =>
      McpToolResult(
        toolName: name,
        result: jsonEncode(payload),
        isSuccess: true,
      );

  static McpToolResult _error(String name, String message) => McpToolResult(
    toolName: name,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );

  static int _int(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static String _firstLine(String text) => text.trim().split('\n').first;

  static String _withoutReasoning(String text) =>
      text.replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)'), '').trim();

  static String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}

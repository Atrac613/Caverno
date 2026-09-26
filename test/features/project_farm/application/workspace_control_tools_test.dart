import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/project_farm/application/workspace_control_tools.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 9, 26);

CodingProject _project(String id) => CodingProject(
  id: id,
  name: id,
  rootPath: '/work/$id',
  createdAt: _t,
  updatedAt: _t,
);

Message _message(
  MessageRole role,
  String content, {
  bool synthesized = false,
}) => Message(
  id: '$role-$content',
  content: content,
  role: role,
  timestamp: _t,
  isSynthesizedPrompt: synthesized,
);

Conversation _thread(
  String id, {
  WorkspaceMode mode = WorkspaceMode.coding,
  String projectId = '',
  List<Message> messages = const [],
}) => Conversation(
  id: id,
  title: 'Thread $id',
  messages: messages,
  createdAt: _t,
  updatedAt: _t,
  workspaceMode: mode,
  projectId: projectId,
);

void main() {
  late String? caller;
  late List<Conversation> conversations;

  WorkspaceControlTools tools({RoadmapSnapshot? snapshot}) =>
      WorkspaceControlTools(
        projects: () => [_project('alpha'), _project('beta')],
        conversations: () => conversations,
        snapshotFor: (id) => id == 'alpha' ? snapshot : null,
        isBusy: (id) => id == 'a1',
        needsApproval: (id) => id == 'a2',
        callerConversationId: () => caller,
      );

  Future<Map<String, dynamic>> call(
    WorkspaceControlTools subject,
    String name, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final result = await subject.execute(name, arguments);
    expect(result.isSuccess, isTrue, reason: result.errorMessage);
    return jsonDecode(result.result) as Map<String, dynamic>;
  }

  setUp(() {
    conversations = [
      _thread('chat', mode: WorkspaceMode.chat),
      _thread(
        'a1',
        projectId: 'alpha',
        messages: [
          _message(MessageRole.user, 'Fix the parser'),
          _message(MessageRole.user, 'tool envelope', synthesized: true),
          _message(
            MessageRole.assistant,
            '<think>private reasoning</think>Done: parser fixed.',
          ),
        ],
      ),
      _thread('a2', projectId: 'alpha'),
      _thread('b1', projectId: 'beta'),
    ];
    caller = 'chat';
  });

  test('a chat thread sees every project with its thread states', () async {
    final payload = await call(tools(), WorkspaceControlTools.listProjects);
    final projects = (payload['projects'] as List).cast<Map>();

    expect(projects.map((p) => p['id']), ['alpha', 'beta']);
    expect(projects.first['threads'], 2);
    expect(projects.first['running'], 1);
    expect(projects.first['needs_approval'], 1);
  });

  test('a coding thread sees only its own project', () async {
    caller = 'b1';
    final subject = tools();

    final payload = await call(subject, WorkspaceControlTools.listProjects);
    expect((payload['projects'] as List).map((p) => p['id']), ['beta']);

    final foreign = await subject.execute(WorkspaceControlTools.readThread, {
      'thread_id': 'a1',
    });
    expect(foreign.isSuccess, isFalse);
  });

  test('a call with no identifiable thread is refused', () async {
    caller = null;
    final result = await tools().execute(
      WorkspaceControlTools.listProjects,
      const {},
    );
    expect(result.isSuccess, isFalse);
  });

  test('lists threads with run state', () async {
    final payload = await call(tools(), WorkspaceControlTools.listThreads, {
      'project_id': 'alpha',
    });
    final states = {
      for (final thread in (payload['threads'] as List).cast<Map>())
        thread['id']: thread['state'],
    };
    expect(states, {'a1': 'running', 'a2': 'needs_approval'});
  });

  test('reads a thread without reasoning or harness-composed turns', () async {
    final payload = await call(tools(), WorkspaceControlTools.readThread, {
      'thread_id': 'a1',
    });
    final texts = (payload['messages'] as List)
        .cast<Map>()
        .map((m) => m['text'])
        .toList();

    expect(texts, ['Fix the parser', 'Done: parser fixed.']);
  });

  test('reports cached roadmap state with its citation', () async {
    final snapshot = RoadmapSnapshot(
      projectId: 'alpha',
      roadmapPath: 'docs/roadmap.md',
      contentSha256: 'sha',
      extractorVersion: 1,
      model: 'm',
      extractedAt: _t,
      status: RoadmapSnapshotStatus.verified,
      recommended: const RoadmapItemSnapshot(
        id: 'RC1',
        title: 'Evidence',
        quote: 'next slice: RC1',
        line: 97,
      ),
    );
    final subject = tools(snapshot: snapshot);

    final state = await call(subject, WorkspaceControlTools.projectState, {
      'project_id': 'alpha',
    });
    final next = (state['roadmap'] as Map)['next_task'] as Map;
    expect(next['source'], 'docs/roadmap.md:97');

    final empty = await call(subject, WorkspaceControlTools.projectState, {
      'project_id': 'beta',
    });
    expect(empty['roadmap'], isNull);
  });

  group('start_project_task', () {
    final verified = RoadmapSnapshot(
      projectId: 'alpha',
      roadmapPath: 'docs/roadmap.md',
      contentSha256: 'sha',
      extractorVersion: 1,
      model: 'm',
      extractedAt: _t,
      status: RoadmapSnapshotStatus.verified,
      recommended: const RoadmapItemSnapshot(
        id: 'RC1',
        title: 'Evidence',
        quote: 'next slice: RC1',
        line: 97,
      ),
      current: const [
        RoadmapItemSnapshot(id: 'F5', title: 'Split', quote: 'F5', line: 3),
        RoadmapItemSnapshot(
          id: 'SEC1',
          title: 'Perimeter',
          quote: 'SEC1',
          verified: false,
        ),
      ],
    );
    late List<String> started;
    late bool approve;

    WorkspaceControlTools starter({RoadmapSnapshot? snapshot}) =>
        WorkspaceControlTools(
          projects: () => [_project('alpha')],
          conversations: () => conversations,
          snapshotFor: (_) => snapshot ?? verified,
          isBusy: (_) => false,
          needsApproval: (_) => false,
          callerConversationId: () => caller,
          startTask:
              ({required project, required item, required roadmapPath}) async {
                if (!approve) return null;
                started.add('${project.id}:${item.id}:$roadmapPath');
                return 'new-thread';
              },
        );

    setUp(() {
      started = [];
      approve = true;
    });

    test('is offered only when a starter is wired', () {
      expect(tools().toolNames, isNot(contains('start_project_task')));
      expect(starter().toolNames, contains('start_project_task'));
    });

    test('starts the verified next task from a chat thread', () async {
      final payload = await call(
        starter(),
        WorkspaceControlTools.startProjectTask,
        {'project_id': 'alpha'},
      );
      expect(payload['thread_id'], 'new-thread');
      expect(started, ['alpha:RC1:docs/roadmap.md']);
    });

    test('starts a verified in-progress item by id', () async {
      await call(starter(), WorkspaceControlTools.startProjectTask, {
        'project_id': 'alpha',
        'task_id': 'F5',
      });
      expect(started, ['alpha:F5:docs/roadmap.md']);
    });

    test('refuses unverified or unknown items and coding callers', () async {
      final subject = starter();
      for (final taskId in ['SEC1', 'MADE-UP']) {
        final result = await subject.execute(
          WorkspaceControlTools.startProjectTask,
          {'project_id': 'alpha', 'task_id': taskId},
        );
        expect(result.isSuccess, isFalse, reason: taskId);
      }
      final unverified =
          await starter(
            snapshot: verified.copyWith(
              status: RoadmapSnapshotStatus.unverified,
            ),
          ).execute(WorkspaceControlTools.startProjectTask, {
            'project_id': 'alpha',
          });
      expect(unverified.isSuccess, isFalse);

      caller = 'a1';
      final fromCoding = await subject.execute(
        WorkspaceControlTools.startProjectTask,
        {'project_id': 'alpha'},
      );
      expect(fromCoding.isSuccess, isFalse);
      expect(started, isEmpty);
    });

    test('reports a declined approval without starting', () async {
      approve = false;
      final result = await starter().execute(
        WorkspaceControlTools.startProjectTask,
        {'project_id': 'alpha'},
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('declined'));
    });
  });

  test('McpToolService offers and dispatches the extension', () async {
    final extension = tools();
    final service = McpToolService(builtInExtensions: [extension]);
    final names = service
        .getOpenAiToolDefinitions()
        .map((tool) => (tool['function'] as Map)['name'])
        .toSet();
    expect(names, containsAll(extension.toolNames));
    expect(names, isNot(contains('start_project_task')));

    final result = await service.executeTool(
      name: WorkspaceControlTools.listProjects,
      arguments: const {},
    );
    expect(result.isSuccess, isTrue);
  });
}

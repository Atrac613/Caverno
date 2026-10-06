import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/project_farm/application/project_proposal_service.dart';
import 'package:caverno/features/project_farm/application/roadmap_snapshot_service.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/farm_run_record.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// FARM3 live probe: extract a real roadmap, then propose from it.
///
/// Passing means the proposal is grounded (it names a verified candidate or
/// nothing) and carries a label. Which task and which label are recorded for a
/// person to judge, not scored.
///
/// ```bash
/// CAVERNO_FARM3_LIVE_CANARY=1 \
/// CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
/// tool/with_live_llm_loopback.sh -- \
///   fvm flutter test tool/canaries/farm3_proposal_live_canary_test.dart
/// ```
void main() {
  // No TestWidgetsFlutterBinding: it replaces HttpClient with a mock that
  // answers every request with HTTP 400.
  final enabled = Platform.environment['CAVERNO_FARM3_LIVE_CANARY'] == '1';
  final baseUrl = (Platform.environment['CAVERNO_LLM_BASE_URL'] ?? '')
      .replaceAll(RegExp(r'/+$'), '');
  final model = Platform.environment['CAVERNO_LLM_MODEL'] ?? 'qwen3.8-27b-exl3';

  const fixtures = {
    'caverno (FARM0 selected)':
        'tool/fixtures/farm0_next_task/roadmap_2026-09-26_farm0_selected.md',
    'pantry tracker':
        'tool/fixtures/farm0_next_task/synthetic_readme_checklist.md',
    'household ledger':
        'tool/fixtures/farm0_next_task/synthetic_japanese_prose.md',
  };

  for (final entry in fixtures.entries) {
    test(
      'proposes a grounded next step: ${entry.key}',
      () async {
        final repository = _MemoryRepository();
        RoadmapCompletionPort complete() => _httpCompletion(baseUrl, model);
        final snapshot = await RoadmapSnapshotService(
          repository: repository,
          ensureAccess: (_) async => true,
          readFile: (_) async => File(entry.value).readAsStringSync(),
          extractor: () => RoadmapNextTaskExtractor(complete: complete()),
          model: () => model,
        ).refresh(projectId: 'p', projectRoot: '/repo');
        final t = DateTime.now();
        final proposal =
            await ProjectProposalService(
              repository: repository,
              complete: complete,
              model: () => model,
            ).refresh(
              project: CodingProject(
                id: 'p',
                name: entry.key,
                rootPath: '/repo',
                createdAt: t,
                updatedAt: t,
              ),
              snapshot: snapshot,
              threads: const [],
            );
        stdout.writeln(
          '[farm3-probe] ${entry.key}: next=${snapshot?.recommended?.id} '
          'status=${snapshot?.status.name} error=${snapshot?.error} '
          'proposal=${proposal?.taskId} label=${proposal?.automatability} '
          'reason="${proposal?.automatabilityReason}" '
          'rationale="${proposal?.rationale}" error=${proposal?.error}',
        );
        expect(proposal, isNotNull);
        expect(proposal!.error, isNull);
        final ids = proposalCandidates(snapshot).map((c) => c.id);
        expect(
          proposal.taskId.isEmpty || ids.contains(proposal.taskId),
          isTrue,
        );
      },
      skip: enabled ? false : 'Set CAVERNO_FARM3_LIVE_CANARY=1',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

RoadmapCompletionPort _httpCompletion(String baseUrl, String model) =>
    ({
      required system,
      required user,
      required schemaName,
      required schema,
      required maxTokens,
    }) async {
      final client = HttpClient();
      try {
        final payload = utf8.encode(
          jsonEncode({
            'model': model,
            'temperature': 0,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
            'response_format': {
              'type': 'json_schema',
              'json_schema': {
                'name': schemaName,
                'strict': true,
                'schema': schema,
              },
            },
          }),
        );
        final request = await client.postUrl(
          Uri.parse('$baseUrl/chat/completions'),
        );
        request.headers.contentType = ContentType.json;
        request.contentLength = payload.length;
        request.add(payload);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        final choice =
            ((jsonDecode(body) as Map)['choices'] as List).first
                as Map<String, dynamic>;
        return RoadmapCompletion(
          content: (choice['message'] as Map)['content'] as String? ?? '',
          finishReason: choice['finish_reason'] as String?,
        );
      } finally {
        client.close(force: true);
      }
    };

final class _MemoryRepository implements RoadmapSnapshotRepositoryApi {
  final _paths = <String, String>{};
  final _snapshots = <String, RoadmapSnapshot>{};
  final _proposals = <String, ProjectProposal>{};

  @override
  String? roadmapPathFor(String projectId) => _paths[projectId];

  @override
  Future<void> saveRoadmapPath(String projectId, String? roadmapPath) async {
    if (roadmapPath == null) {
      _paths.remove(projectId);
    } else {
      _paths[projectId] = roadmapPath;
    }
  }

  @override
  RoadmapSnapshot? snapshotFor(String projectId) => _snapshots[projectId];

  @override
  Future<void> saveSnapshot(RoadmapSnapshot snapshot) async =>
      _snapshots[snapshot.projectId] = snapshot;

  @override
  ProjectProposal? proposalFor(String projectId) => _proposals[projectId];

  @override
  Future<void> saveProposal(ProjectProposal proposal) async =>
      _proposals[proposal.projectId] = proposal;

  @override
  ProjectFarmPolicy? policyFor(String projectId) => null;

  @override
  Future<void> savePolicy(ProjectFarmPolicy policy) async {}

  @override
  String? pinnedTaskFor(String projectId) => null;

  @override
  Future<void> savePinnedTask(String projectId, String? taskId) async {}

  @override
  List<FarmRunRecord> farmRuns() => const [];

  @override
  Future<void> appendFarmRun(FarmRunRecord record) async {}
}

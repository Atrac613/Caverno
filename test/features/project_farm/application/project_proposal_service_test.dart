import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/project_farm/application/project_proposal_service.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/domain/next_step_proposal_contract.dart';
import 'package:caverno/features/project_farm/domain/roadmap_next_task_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t = DateTime.utc(2026, 9, 26);
final _project = CodingProject(
  id: 'p1',
  name: 'caverno',
  rootPath: '/work',
  createdAt: _t,
  updatedAt: _t,
);
final _snapshot = RoadmapSnapshot(
  projectId: 'p1',
  roadmapPath: 'docs/roadmap.md',
  contentSha256: 'sha',
  extractorVersion: 1,
  model: 'm',
  extractedAt: _t,
  status: RoadmapSnapshotStatus.verified,
  recommended: const RoadmapItemSnapshot(
    id: 'RC1',
    title: 'Evidence',
    quote: 'next: RC1',
    line: 1,
  ),
  current: const [
    RoadmapItemSnapshot(id: 'F5', title: 'Split', quote: 'F5', line: 2),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('verifyNextStepProposal', () {
    final candidates = proposalCandidates(_snapshot);

    test('accepts a listed task', () {
      final verified = verifyNextStepProposal({
        'task_id': 'F5',
        'rationale': 'r',
        'automatability': 'unattended',
        'automatability_reason': 'x',
      }, candidates);
      expect(verified?.taskId, 'F5');
      expect(verified?.automatability, ProposalAutomatability.unattended);
    });

    test('accepts proposing nothing', () {
      final verified = verifyNextStepProposal({
        'task_id': '',
        'rationale': 'all busy',
        'automatability': 'needs_human',
        'automatability_reason': 'x',
      }, candidates);
      expect(verified?.taskId, isEmpty);
    });

    test('rejects an invented task or label', () {
      expect(
        verifyNextStepProposal({
          'task_id': 'MADE-UP',
          'rationale': 'r',
          'automatability': 'unattended',
          'automatability_reason': 'x',
        }, candidates),
        isNull,
      );
      expect(
        verifyNextStepProposal({
          'task_id': 'RC1',
          'rationale': 'r',
          'automatability': 'maybe',
          'automatability_reason': 'x',
        }, candidates),
        isNull,
      );
    });
  });

  test('candidates exclude unverified items and failed snapshots', () {
    final unverifiedNext = _snapshot.copyWith(
      recommended: const RoadmapItemSnapshot(
        id: 'X',
        title: 't',
        quote: 'q',
        verified: false,
      ),
    );
    expect(proposalCandidates(unverifiedNext).map((c) => c.id), ['F5']);
    expect(
      proposalCandidates(
        _snapshot.copyWith(status: RoadmapSnapshotStatus.failed),
      ),
      isEmpty,
    );
  });

  group('ProjectProposalService', () {
    late List<ModelUsageRole> roles;
    late String answer;
    late ProjectProposalService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      roles = [];
      answer = jsonEncode({
        'task_id': 'RC1',
        'rationale': 'The roadmap selects it.',
        'automatability': 'needs_human',
        'automatability_reason': 'Needs signed devices.',
      });
      service = ProjectProposalService(
        repository: RoadmapSnapshotRepository(
          await SharedPreferences.getInstance(),
        ),
        complete: () =>
            ({
              required system,
              required user,
              required schemaName,
              required schema,
              required maxTokens,
            }) async {
              roles.add(ModelUsageRole.current);
              return RoadmapCompletion(content: answer);
            },
        model: () => 'm',
        now: () => _t,
      );
    });

    const idle = [ProposalThread(title: 'a', state: 'idle')];

    test(
      'stores a verified proposal and reuses it until input changes',
      () async {
        final first = await service.refresh(
          project: _project,
          snapshot: _snapshot,
          threads: idle,
        );
        expect(first!.taskId, 'RC1');
        expect(first.automatability, 'needsHuman');
        expect(roles, [ModelUsageRole.projectState]);

        await service.refresh(
          project: _project,
          snapshot: _snapshot,
          threads: idle,
        );
        expect(roles, hasLength(1));

        await service.refresh(
          project: _project,
          snapshot: _snapshot,
          threads: const [ProposalThread(title: 'a', state: 'running')],
        );
        expect(roles, hasLength(2));
        expect(service.cachedProposal('p1')?.taskId, 'RC1');
      },
    );

    test('records an ungrounded answer as an error', () async {
      answer = jsonEncode({
        'task_id': 'MADE-UP',
        'rationale': 'r',
        'automatability': 'unattended',
        'automatability_reason': 'x',
      });
      final proposal = await service.refresh(
        project: _project,
        snapshot: _snapshot,
        threads: idle,
      );
      expect(proposal!.error, isNotNull);
      expect(proposal.taskId, isEmpty);
    });

    test('skips the model when there is nothing to choose from', () async {
      final proposal = await service.refresh(
        project: _project,
        snapshot: null,
        threads: idle,
      );
      expect(proposal, isNull);
      expect(roles, isEmpty);
    });
  });
}

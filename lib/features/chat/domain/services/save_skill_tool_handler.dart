// ChatNotifier decomposition collaborator: save-skill-tool-handler

import 'dart:convert';

import '../../data/datasources/filesystem_diff_builder.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/skill.dart';
import 'save_skill_tool_contract.dart';
import 'skill_markdown_parser.dart';
import 'skill_similarity_service.dart';

export 'save_skill_tool_contract.dart';

/// Parses, checks, approves, and persists one exact skill-save invocation.
final class SaveSkillToolHandler {
  const SaveSkillToolHandler({
    required SkillStorePort storePort,
    required SkillSaveApprovalPort approvalPort,
  }) : _storePort = storePort,
       _approvalPort = approvalPort;

  static const String _expiredMessage =
      'The approval turn expired before execution';
  static const String _effectUncertainMessage =
      'The skill may have been saved after its owner expired; inspect the '
      'skill catalog before retrying';

  final SkillStorePort _storePort;
  final SkillSaveApprovalPort _approvalPort;

  Future<McpToolResult> handle(SaveSkillToolRequest request) async {
    final identity = request.identity;
    final name = request.name;
    final description = request.description;
    final whenToUse = request.whenToUse;
    final body = request.body;
    if (name.isEmpty) {
      return _failure(request.toolName, 'name is required');
    }
    if (body.isEmpty) {
      return _failure(request.toolName, 'content (the skill body) is required');
    }

    final markdown = SkillMarkdownParser.composeMarkdown(
      name: name,
      description: description,
      whenToUse: whenToUse,
      body: body,
    );
    final snapshot = _storePort.snapshot(identity);
    _requireIdentity(snapshot.identity, identity, 'Skill store snapshot');
    final existing = _findSkillByName(snapshot.skills, name);
    if (existing == null && !request.allowDuplicate) {
      final similar = SkillSimilarityService.findSimilar(
        name: name,
        description: description,
        whenToUse: whenToUse,
        existing: snapshot.skills,
      );
      if (similar.isNotEmpty) {
        return _similarSkillResult(request.toolName, similar);
      }
    }

    final preview = existing == null
        ? markdown
        : FilesystemDiffBuilder.buildUnifiedDiff(
            path: 'skill: $name',
            oldContent: SkillMarkdownParser.toMarkdown(existing),
            newContent: markdown,
          );
    final decision = await _approvalPort.requestApproval(
      SkillSaveApprovalRequest(
        toolRequest: request,
        operation: existing == null ? 'Save Skill' : 'Update Skill',
        path: name,
        preview: preview,
        reason: request.reason,
        existingSkill: existing,
      ),
    );
    _requireIdentity(decision.identity, identity, 'Skill save approval');
    final ownerAcknowledgement = _approvalPort.acknowledgeOwner(identity);
    _requireIdentity(
      ownerAcknowledgement.identity,
      identity,
      'Skill save owner acknowledgement',
    );
    if (ownerAcknowledgement.disposition !=
        SkillSaveAcknowledgementDisposition.acknowledged) {
      return _ownerExpired(request.toolName);
    }
    if (!decision.approved) {
      return _failure(request.toolName, 'User denied saving the skill');
    }

    try {
      final stored = await _storePort.upsertMarkdown(
        identity,
        SkillStoreWriteRequest(existingId: existing?.id, markdown: markdown),
      );
      if (stored.identity != identity) {
        return _effectUncertain(request.toolName);
      }
      if (stored.disposition == SkillStoreWriteDisposition.effectUncertain) {
        return _effectUncertain(request.toolName);
      }
      if (stored.disposition == SkillStoreWriteDisposition.rejected) {
        return _failure(request.toolName, stored.errorMessage!);
      }
      if (stored.disposition == SkillStoreWriteDisposition.ownerExpired) {
        return switch (stored.expiredWriteDisposition!) {
          SkillStoreExpiredWriteDisposition.notCommitted ||
          SkillStoreExpiredWriteDisposition.compensated => _ownerExpired(
            request.toolName,
          ),
          SkillStoreExpiredWriteDisposition.retained ||
          SkillStoreExpiredWriteDisposition.uncertain => _effectUncertain(
            request.toolName,
          ),
        };
      }

      final acknowledgement = await _storePort.recordSuccessfulSave(identity);
      if (acknowledgement.identity != identity) {
        return _effectUncertain(request.toolName);
      }
      switch (acknowledgement.disposition) {
        case SkillSaveAcknowledgementDisposition.acknowledged:
          break;
        case SkillSaveAcknowledgementDisposition.ownerExpired:
          return _ownerExpired(request.toolName);
        case SkillSaveAcknowledgementDisposition.effectUncertain:
          return _effectUncertain(request.toolName);
      }
      final saved = stored.skill!;
      return McpToolResult(
        toolName: request.toolName,
        result: jsonEncode({
          'ok': true,
          'action': existing == null ? 'created' : 'updated',
          'id': saved.id,
          'name': saved.normalizedName,
          'enabled': saved.enabled,
        }),
        isSuccess: true,
      );
    } catch (_) {
      return _effectUncertain(request.toolName);
    }
  }

  Skill? _findSkillByName(List<Skill> skills, String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final skill in skills) {
      if (skill.normalizedName.toLowerCase() == normalized) return skill;
    }
    return null;
  }

  McpToolResult _similarSkillResult(
    String toolName,
    List<SkillSimilarityMatch> matches,
  ) {
    return McpToolResult(
      toolName: toolName,
      isSuccess: true,
      result: jsonEncode({
        'saved': false,
        'action': 'similar_skill_found',
        'matches': [
          for (final match in matches)
            {
              'id': match.skill.id,
              'name': match.skill.normalizedName,
              'score': double.parse(match.score.toStringAsFixed(2)),
              if (match.skill.normalizedDescription.isNotEmpty)
                'description': match.skill.normalizedDescription,
            },
        ],
        'message':
            'A similar skill already exists. To improve it, call save_skill '
            'again using that skill\'s exact name (this updates it in place '
            'with a diff for approval). To create a separate skill anyway, '
            'call save_skill again with allow_duplicate set to true.',
      }),
    );
  }

  void _requireIdentity(
    SaveSkillOperationIdentity actual,
    SaveSkillOperationIdentity expected,
    String source,
  ) {
    if (actual != expected) {
      throw StateError('$source identity mismatch.');
    }
  }

  McpToolResult _ownerExpired(String toolName) {
    return _failure(toolName, _expiredMessage);
  }

  McpToolResult _effectUncertain(String toolName) {
    return _failure(toolName, _effectUncertainMessage);
  }

  McpToolResult _failure(String toolName, String message) {
    return McpToolResult(
      toolName: toolName,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }
}

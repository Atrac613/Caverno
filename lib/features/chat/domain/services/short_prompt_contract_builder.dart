import '../entities/conversation_workflow.dart';
import 'conversation_plan_hash.dart';

class SpecificationContractInput {
  const SpecificationContractInput({required this.path, required this.content});

  final String path;
  final String content;
}

class ShortPromptContractBuilder {
  const ShortPromptContractBuilder();

  ConversationWorkflowSpec? build({
    required String userMessageId,
    required String userRequest,
    SpecificationContractInput? specification,
  }) {
    final request = userRequest.trim();
    final messageId = userMessageId.trim();
    if (request.isEmpty || messageId.isEmpty) return null;
    final sourceHash = computeConversationPlanHash(request);
    final sourceId = 'user-message:$messageId';
    final specificationContent = specification?.content.trim() ?? '';
    final specificationPath = specification?.path.trim() ?? '';
    final specificationHash = specificationContent.isEmpty
        ? ''
        : computeConversationPlanHash(specificationContent);
    final specificationSourceId = specificationHash.isEmpty
        ? ''
        : 'specification:$specificationHash';
    final extracted = specificationContent.isEmpty
        ? const _SpecificationContractItems()
        : _extractSpecificationItems(specificationContent);
    final taskId = 'request-$sourceHash';
    return ConversationWorkflowSpec(
      goal: request,
      constraints: extracted.constraints,
      acceptanceCriteria: extracted.acceptanceCriteria,
      tasks: [
        ConversationWorkflowTask(
          id: taskId,
          title: 'Fulfill the sourced user request',
        ),
      ],
      sources: [
        ConversationContractSourceReference(
          id: sourceId,
          kind: ConversationContractSourceKind.userMessage,
          locator: messageId,
          contentHash: sourceHash,
        ),
        if (specificationSourceId.isNotEmpty)
          ConversationContractSourceReference(
            id: specificationSourceId,
            kind: ConversationContractSourceKind.specificationFile,
            locator: specificationPath,
            contentHash: specificationHash,
          ),
      ],
      provenance: [
        ConversationContractItemProvenance(
          itemId: 'goal',
          kind: ConversationContractItemKind.goal,
          sourceIds: [sourceId],
        ),
        ConversationContractItemProvenance(
          itemId: 'task:$taskId',
          kind: ConversationContractItemKind.task,
          sourceIds: [sourceId],
        ),
        for (var index = 0; index < extracted.constraints.length; index++)
          ConversationContractItemProvenance(
            itemId: 'constraint:$index',
            kind: ConversationContractItemKind.constraint,
            sourceIds: [specificationSourceId],
          ),
        for (
          var index = 0;
          index < extracted.acceptanceCriteria.length;
          index++
        )
          ConversationContractItemProvenance(
            itemId: 'acceptance:$index',
            kind: ConversationContractItemKind.acceptanceCriterion,
            sourceIds: [specificationSourceId],
          ),
      ],
    );
  }

  _SpecificationContractItems _extractSpecificationItems(String markdown) {
    final sections = <_SpecificationSectionKind, List<String>>{};
    _SpecificationSectionKind? section;
    String listLabel = '';
    for (final rawLine in markdown.split('\n')) {
      final line = rawLine.trim();
      final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (heading != null) {
        section = _classifySpecificationHeading(heading.group(1)!);
        listLabel = '';
        continue;
      }
      if (section == null) continue;
      if (line.endsWith(':') && !line.startsWith(RegExp(r'[-*]'))) {
        listLabel = line.substring(0, line.length - 1).trim();
        continue;
      }
      final bullet = RegExp(r'^[-*]\s+(?:\[[ xX]\]\s*)?(.+)$').firstMatch(line);
      if (bullet != null) {
        final value = bullet.group(1)!.trim();
        sections
            .putIfAbsent(section, () => <String>[])
            .add(listLabel.isEmpty ? value : '$listLabel: $value');
        continue;
      }
      final items = sections[section];
      if (rawLine.startsWith(RegExp(r'\s')) &&
          line.isNotEmpty &&
          items != null &&
          items.isNotEmpty) {
        items[items.length - 1] = '${items.last} $line';
      }
    }
    return _SpecificationContractItems(
      constraints: List<String>.unmodifiable(
        sections[_SpecificationSectionKind.constraint] ?? const [],
      ),
      acceptanceCriteria: List<String>.unmodifiable(
        sections[_SpecificationSectionKind.acceptanceCriterion] ?? const [],
      ),
    );
  }

  _SpecificationSectionKind? _classifySpecificationHeading(String heading) {
    final normalized = heading.trim().toLowerCase().replaceAll(
      RegExp('[:\uFF1A]+\$'),
      '',
    );
    const acceptanceHeadings = <String>{
      'acceptance criteria',
      'acceptance tests',
      'definition of done',
      'done criteria',
      'completion criteria',
      '\u53d7\u3051\u5165\u308c\u57fa\u6e96',
      '\u53d7\u5165\u57fa\u6e96',
      '\u5b8c\u4e86\u6761\u4ef6',
      '\u5408\u683c\u57fa\u6e96',
      '\u691c\u53ce\u6761\u4ef6',
    };
    if (acceptanceHeadings.contains(normalized)) {
      return _SpecificationSectionKind.acceptanceCriterion;
    }
    const constraintHeadings = <String>{
      'scope',
      'constraint',
      'constraints',
      'requirements',
      'functional requirements',
      'non-functional requirements',
      '\u30b9\u30b3\u30fc\u30d7',
      '\u7bc4\u56f2',
      '\u5236\u7d04',
      '\u8981\u4ef6',
      '\u6a5f\u80fd\u8981\u4ef6',
      '\u975e\u6a5f\u80fd\u8981\u4ef6',
    };
    if (constraintHeadings.contains(normalized)) {
      return _SpecificationSectionKind.constraint;
    }
    return null;
  }
}

enum _SpecificationSectionKind { constraint, acceptanceCriterion }

class _SpecificationContractItems {
  const _SpecificationContractItems({
    this.constraints = const <String>[],
    this.acceptanceCriteria = const <String>[],
  });

  final List<String> constraints;
  final List<String> acceptanceCriteria;
}

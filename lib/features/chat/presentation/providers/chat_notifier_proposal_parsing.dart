// Same-library extension on [ChatNotifier]: proposal parsing text and JSON
// helpers delegate to a domain service while preserving private call sites.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element

part of 'chat_notifier.dart';

extension ChatNotifierProposalParsing on ChatNotifier {
  ProposalJsonExtractor get _proposalJsonExtractor => ProposalJsonExtractor(
    onJsonRepair: _recordPlanningJsonRepairRuntimeFeedback,
  );

  Map<String, dynamic>? _extractJsonMap(String rawContent) {
    return _proposalJsonExtractor.extractJsonMap(rawContent);
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    return ProposalParsingTextUtils.tryDecodeMap(value);
  }

  Map<String, dynamic>? _tryRepairAndDecodeMap(String value) {
    return ProposalParsingTextUtils.tryRepairAndDecodeMap(value);
  }

  String? _repairJsonCandidate(String value) {
    return ProposalParsingTextUtils.repairJsonCandidate(value);
  }

  String? _extractLooseJsonScalar(
    String rawContent, {
    required List<String> keys,
  }) {
    return ProposalParsingTextUtils.extractLooseJsonScalar(
      rawContent,
      keys: keys,
    );
  }

  List<String> _extractLooseJsonStringList(
    String rawContent, {
    required List<String> keys,
  }) {
    return ProposalParsingTextUtils.extractLooseJsonStringList(
      rawContent,
      keys: keys,
    );
  }

  Map<String, List<String>> _collectProposalSections(String rawContent) {
    return ProposalParsingTextUtils.collectProposalSections(rawContent);
  }

  (String, String)? _matchWorkflowSectionLine(String line) {
    return ProposalParsingTextUtils.matchWorkflowSectionLine(line);
  }

  ConversationWorkflowStage? _inferWorkflowStageFromSectionKeys(
    Map<String, List<String>> sections,
  ) {
    return ProposalParsingTextUtils.inferWorkflowStageFromSectionKeys(sections);
  }

  ConversationWorkflowStage _inferWorkflowStageFromLooseProposalContent(
    String rawContent,
  ) {
    return ProposalParsingTextUtils.inferWorkflowStageFromLooseProposalContent(
      rawContent,
    );
  }

  String _normalizeProposalContent(String rawContent) {
    return ProposalParsingTextUtils.normalizeProposalContent(rawContent);
  }

  String _extractProposalReasoningContent(String rawContent) {
    return ProposalParsingTextUtils.extractProposalReasoningContent(rawContent);
  }

  String _extractStructuredWorkflowProposalReasoning(String rawContent) {
    return ProposalParsingTextUtils.extractStructuredWorkflowProposalReasoning(
      rawContent,
    );
  }

  String _extractStructuredTaskProposalReasoning(String rawContent) {
    return ProposalParsingTextUtils.extractStructuredTaskProposalReasoning(
      rawContent,
    );
  }

  String _sanitizeReasoningProposalValue(
    String value, {
    bool preferSingleSentence = false,
  }) {
    return ProposalParsingTextUtils.sanitizeReasoningProposalValue(
      value,
      preferSingleSentence: preferSingleSentence,
    );
  }

  bool _looksLikeStructuredReasoningListItem(String line) {
    return ProposalParsingTextUtils.looksLikeStructuredReasoningListItem(line);
  }

  bool _isWorkflowListSection(String section) {
    return ProposalParsingTextUtils.isWorkflowListSection(section);
  }

  String _workflowSectionDisplayLabel(String section) {
    return ProposalParsingTextUtils.workflowSectionDisplayLabel(section);
  }

  String _taskFieldDisplayLabel(String field) {
    return ProposalParsingTextUtils.taskFieldDisplayLabel(field);
  }

  String _asCleanString(Object? value) {
    return ProposalParsingTextUtils.asCleanString(value);
  }

  List<String> _asStringList(Object? value) {
    return ProposalParsingTextUtils.asStringList(value);
  }

  bool _isCompletionTruncated(String finishReason) {
    return ProposalParsingTextUtils.isCompletionTruncated(finishReason);
  }

  String _stripMarkdownListMarker(String value) {
    return ProposalParsingTextUtils.stripMarkdownListMarker(value);
  }

  String _appendTextValue(String current, String next) {
    return ProposalParsingTextUtils.appendTextValue(current, next);
  }

  String _proposalPreview(String rawContent) {
    return ProposalParsingTextUtils.proposalPreview(rawContent);
  }

  String _extractPlainTextForProposal(String content) {
    return ProposalParsingTextUtils.extractPlainTextForProposal(content);
  }

  String _extractInlineTaskPlanCandidate(String rawContent) {
    return ProposalParsingTextUtils.extractInlineTaskPlanCandidate(rawContent);
  }

  String _sanitizeInlineReasoningTaskTitle(String rawValue) {
    return ProposalParsingTextUtils.sanitizeInlineReasoningTaskTitle(rawValue);
  }

  String? _matchTaskTitleLine(String line, {String? currentField}) {
    return ProposalParsingTextUtils.matchTaskTitleLine(
      line,
      currentField: currentField,
    );
  }

  (String, String)? _matchTaskFieldLine(String line) {
    return ProposalParsingTextUtils.matchTaskFieldLine(line);
  }
}

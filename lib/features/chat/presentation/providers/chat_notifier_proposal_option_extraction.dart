// Same-library extension on [ChatNotifier]: planning decision option helpers
// delegate to a domain service while preserving private call sites.
// ignore_for_file: unused_element

part of 'chat_notifier.dart';

extension ChatNotifierProposalOptionExtraction on ChatNotifier {
  WorkflowProposalDraft _removeAnsweredOpenQuestions(
    WorkflowProposalDraft proposal,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  ) {
    return PlanningDecisionPromotion.removeAnsweredOpenQuestions(
      proposal,
      decisionAnswers,
    );
  }

  List<WorkflowPlanningDecision> _promoteChoiceLikeOpenQuestions(
    List<String> openQuestions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    return PlanningDecisionPromotion.promoteChoiceLikeOpenQuestions(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  List<WorkflowPlanningDecision> _promoteOpenQuestionsToPlanningPrompts(
    List<String> openQuestions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    return PlanningDecisionPromotion.promoteOpenQuestionsToPlanningPrompts(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  WorkflowPlanningDecision? _buildOrderedChoiceDecisionFromOpenQuestion(
    String question,
  ) {
    return PlanningDecisionPromotion.buildOrderedChoiceDecisionFromOpenQuestion(
      question,
    );
  }

  WorkflowPlanningDecision? _buildAlternativeChoiceDecisionFromOpenQuestion(
    String question,
  ) {
    return PlanningDecisionPromotion.buildAlternativeChoiceDecisionFromOpenQuestion(
      question,
    );
  }

  WorkflowPlanningDecision? _buildYesNoDecisionFromOpenQuestion(
    String question,
  ) {
    return PlanningDecisionPromotion.buildYesNoDecisionFromOpenQuestion(
      question,
    );
  }

  List<String> _extractEnglishOrderedOptions(String question) {
    return PlanningDecisionPromotion.extractEnglishOrderedOptions(question);
  }

  List<String> _extractJapaneseOrderedOptions(String question) {
    return PlanningDecisionPromotion.extractJapaneseOrderedOptions(question);
  }

  List<String> _extractEnglishAlternativeOptions(String question) {
    return PlanningDecisionPromotion.extractEnglishAlternativeOptions(question);
  }

  List<String> _extractJapaneseAlternativeOptions(String question) {
    return PlanningDecisionPromotion.extractJapaneseAlternativeOptions(
      question,
    );
  }

  List<String> _splitEnglishChoiceList(String value) {
    return PlanningDecisionPromotion.splitEnglishChoiceList(value);
  }

  List<String> _splitJapaneseChoiceList(String value) {
    return PlanningDecisionPromotion.splitJapaneseChoiceList(value);
  }

  String _stripEnglishChoicePrefix(String value) {
    return PlanningDecisionPromotion.stripEnglishChoicePrefix(value);
  }

  String _stripJapaneseChoicePrefix(String value) {
    return PlanningDecisionPromotion.stripJapaneseChoicePrefix(value);
  }

  String _stripChoiceSuffix(String value) {
    return PlanningDecisionPromotion.stripChoiceSuffix(value);
  }

  String _cleanDecisionOptionLabel(String value) {
    return PlanningDecisionPromotion.cleanDecisionOptionLabel(value);
  }

  String _decisionOptionId(String label) {
    return PlanningDecisionPromotion.decisionOptionId(label);
  }

  bool _looksLikeYesNoOpenQuestion(String question) {
    return PlanningDecisionPromotion.looksLikeYesNoOpenQuestion(question);
  }

  bool _containsJapaneseText(String value) {
    return PlanningDecisionPromotion.containsJapaneseText(value);
  }

  String _normalizeWorkflowDecisionText(String value) {
    return PlanningDecisionPromotion.normalizeWorkflowDecisionText(value);
  }

  void _mergeWorkflowDecisionAnswers(
    List<WorkflowPlanningDecisionAnswer> current,
    List<WorkflowPlanningDecisionAnswer> updates,
  ) {
    PlanningDecisionPromotion.mergeWorkflowDecisionAnswers(current, updates);
  }

  List<WorkflowPlanningDecision> _filterUnansweredWorkflowDecisions(
    List<WorkflowPlanningDecision> decisions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    return PlanningDecisionPromotion.filterUnansweredWorkflowDecisions(
      decisions,
      decisionAnswers: decisionAnswers,
    );
  }
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/production_release_approval_policy.dart';

/// The release gate must reach the same verdict whatever language the user
/// speaks. These assertions run against the *verdict*, never against an
/// individual predicate, so a later vocabulary edit cannot reintroduce a false
/// approval without failing here.
///
/// Every string below was produced by running the retired wording predicates:
/// the denials marked `wasApproved` were read as approvals, and the approvals
/// marked `wasRefused` were refused.
void main() {
  const policy = ProductionReleaseApprovalPolicy();
  const token = 'rel-0123456789abcdef';

  ChatTurnOwner owner() => ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('release approval is language-independent', () {
    // Denials. Four of these were read as approvals by the wording
    // predicates; none may approve now.
    const denials = <String, String>{
      'english negation (was approved)': "I'd rather you didn't ship it",
      'english never (was approved)': 'never release this',
      'portuguese (was approved)': 'nao execute o release',
      'german (was approved)': 'Nein, kein Release',
      'english hold': 'Hold off on the release for now',
      'spanish': 'No ejecutar el release',
      'french': 'Non, ne fais pas le release',
      'chinese': 'bu yao fabu',
      'japanese': 'release wa shinaide kudasai',
    };

    for (final entry in denials.entries) {
      test('a denial never approves: ${entry.key}', () {
        final cache = AskUserQuestionTurnCache();
        // The user typed a denial as free text rather than selecting the
        // token-bearing option.
        cache.store(
          owner: owner(),
          question: 'Approve the production release?',
          optionLabels: ['Approve $token', 'Cancel'],
          result: McpToolResult(
            toolName: 'ask_user_question',
            result: jsonEncode({
              'status': 'answered',
              'question': 'Approve the production release?',
              'other': entry.value,
              'answer': entry.value,
            }),
            isSuccess: true,
          ),
        );

        expect(
          policy
              .evidenceFor(
                owner: owner(),
                capturedProof: null,
                questionResults: cache,
                approvalToken: token,
              )
              .approved,
          isFalse,
          reason: entry.value,
        );
      });
    }

    // Approvals. Two of these were refused by the wording predicates; all
    // must approve now, because the verdict reads the token rather than the
    // words around it.
    const approvals = <String, String>{
      'german (was refused)': 'Ja, bitte veroeffentlichen',
      'chinese (was refused)': 'Shi de, qing fabu',
      'spanish': 'Si, procede con el release',
      'japanese': 'honban ni release shimasu',
      'french': 'Oui, publiez la version',
      'english': 'Approve the production release',
    };

    for (final entry in approvals.entries) {
      test('selecting the token option approves: ${entry.key}', () {
        final label = '${entry.value} $token';
        final cache = AskUserQuestionTurnCache();
        cache.store(
          owner: owner(),
          question: 'Approve the production release?',
          optionLabels: [label, 'Cancel'],
          result: McpToolResult(
            toolName: 'ask_user_question',
            result: jsonEncode({
              'status': 'answered',
              'question': 'Approve the production release?',
              'selected': [
                {'label': label},
              ],
              'answer': label,
            }),
            isSuccess: true,
          ),
        );

        expect(
          policy
              .evidenceFor(
                owner: owner(),
                capturedProof: null,
                questionResults: cache,
                approvalToken: token,
              )
              .approved,
          isTrue,
          reason: label,
        );
      });
    }
  });

  group('token identity cannot be gamed', () {
    McpToolResult answered(String selectedLabel) => McpToolResult(
      toolName: 'ask_user_question',
      result: jsonEncode({
        'status': 'answered',
        'question': 'Approve the production release?',
        'selected': [
          {'label': selectedLabel},
        ],
        'answer': selectedLabel,
      }),
      isSuccess: true,
    );

    test('a token on every option approves nothing', () {
      // The model can see the token in the blocked-release result, so it can
      // attach it to the declining option too. Selecting "cancel" would then
      // report a selection carrying the token.
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: owner(),
        question: 'Approve the production release?',
        optionLabels: ['Approve $token', 'Cancel $token'],
        result: answered('Cancel $token'),
      );

      expect(
        policy
            .evidenceFor(
              owner: owner(),
              capturedProof: null,
              questionResults: cache,
              approvalToken: token,
            )
            .approved,
        isFalse,
        reason: 'an ambiguous token identifies no option',
      );
    });

    test('a stale token from another release does not approve', () {
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: owner(),
        question: 'Approve the production release?',
        optionLabels: ['Approve rel-ffffffffffffffff', 'Cancel'],
        result: answered('Approve rel-ffffffffffffffff'),
      );

      expect(
        policy
            .evidenceFor(
              owner: owner(),
              capturedProof: null,
              questionResults: cache,
              approvalToken: token,
            )
            .approved,
        isFalse,
      );
    });

    test('an unanswered or cancelled question does not approve', () {
      for (final status in ['cancelled', 'policy_resolved', 'pending']) {
        final cache = AskUserQuestionTurnCache();
        cache.store(
          owner: owner(),
          question: 'Approve the production release?',
          optionLabels: ['Approve $token', 'Cancel'],
          result: McpToolResult(
            toolName: 'ask_user_question',
            result: jsonEncode({
              'status': status,
              'selected': [
                {'label': 'Approve $token'},
              ],
            }),
            isSuccess: true,
          ),
        );

        expect(
          policy
              .evidenceFor(
                owner: owner(),
                capturedProof: null,
                questionResults: cache,
                approvalToken: token,
              )
              .approved,
          isFalse,
          reason: status,
        );
      }
    });

    test('free text containing the token does not approve', () {
      // Typing the token is not selecting the option that carries it.
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: owner(),
        question: 'Approve the production release?',
        optionLabels: ['Approve $token', 'Cancel'],
        result: McpToolResult(
          toolName: 'ask_user_question',
          result: jsonEncode({
            'status': 'answered',
            'other': 'go ahead $token',
            'answer': 'go ahead $token',
          }),
          isSuccess: true,
        ),
      );

      expect(
        policy
            .evidenceFor(
              owner: owner(),
              capturedProof: null,
              questionResults: cache,
              approvalToken: token,
            )
            .approved,
        isFalse,
      );
    });

    test('an empty token approves nothing', () {
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: owner(),
        question: 'Approve the production release?',
        optionLabels: const ['Approve', 'Cancel'],
        result: answered('Approve'),
      );

      expect(
        policy
            .evidenceFor(
              owner: owner(),
              capturedProof: null,
              questionResults: cache,
              approvalToken: '',
            )
            .approved,
        isFalse,
      );
    });
  });
}

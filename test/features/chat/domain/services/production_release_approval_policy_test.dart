import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/production_release_approval_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = ProductionReleaseApprovalPolicy();

  group('capture-time proof', () {
    test('captures direct release approval for the exact owner', () {
      final owner = _owner();

      final proof = policy.captureProof(
        owner: owner,
        submittedUserContent: '  Run the production release now. ',
        precedingOwnerMessage: null,
      );

      expect(proof.owner, owner);
      expect(proof.explicitApproval, isTrue);
      expect(proof.affirmativePromptReply, isFalse);
      expect(proof.approved, isTrue);
    });

    test(
      'captures an affirmative reply only to the preceding assistant prompt',
      () {
        final approved = policy.captureProof(
          owner: _owner(),
          submittedUserContent: 'Yes, proceed.',
          precedingOwnerMessage: const ProductionReleasePrecedingMessage(
            isAssistant: true,
            content: 'Do you approve the production release command?',
          ),
        );
        final wrongRole = policy.captureProof(
          owner: _owner(),
          submittedUserContent: 'Yes, proceed.',
          precedingOwnerMessage: const ProductionReleasePrecedingMessage(
            isAssistant: false,
            content: 'Do you approve the production release command?',
          ),
        );
        final wrongPrompt = policy.captureProof(
          owner: _owner(),
          submittedUserContent: 'Yes, proceed.',
          precedingOwnerMessage: const ProductionReleasePrecedingMessage(
            isAssistant: true,
            content: 'Do you approve this unrelated command?',
          ),
        );

        expect(approved.explicitApproval, isFalse);
        expect(approved.affirmativePromptReply, isTrue);
        expect(wrongRole.approved, isFalse);
        expect(wrongPrompt.approved, isFalse);
      },
    );

    test('does not treat a negative prompt reply as approval', () {
      final proof = policy.captureProof(
        owner: _owner(),
        submittedUserContent: 'No, do not run it.',
        precedingOwnerMessage: const ProductionReleasePrecedingMessage(
          isAssistant: true,
          content: 'May I execute the production release?',
        ),
      );

      expect(proof.approved, isFalse);
    });
  });

  group('owner-scoped approval evidence', () {
    test(
      'accepts direct proof only from the exact conversation generation',
      () {
        final owner = _owner();
        final cache = AskUserQuestionTurnCache();
        final matching = policy.captureProof(
          owner: owner,
          submittedUserContent: 'Release now.',
          precedingOwnerMessage: null,
        );
        final otherConversation = policy.captureProof(
          owner: _owner(conversationId: 'conversation-b'),
          submittedUserContent: 'Release now.',
          precedingOwnerMessage: null,
        );
        final otherGeneration = policy.captureProof(
          owner: _owner(generation: 8),
          submittedUserContent: 'Release now.',
          precedingOwnerMessage: null,
        );

        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: matching,
                questionResults: cache,
              )
              .directlyApproved,
          isTrue,
        );
        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: otherConversation,
                questionResults: cache,
              )
              .approved,
          isFalse,
        );
        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: otherGeneration,
                questionResults: cache,
              )
              .approved,
          isFalse,
        );
        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: null,
                questionResults: cache,
              )
              .approved,
          isFalse,
        );
      },
    );

    test('accepts question approval only from the exact owner', () {
      final cache = AskUserQuestionTurnCache();
      final owner = _owner();
      _storeQuestionResult(
        cache,
        _owner(conversationId: 'conversation-b'),
        _answeredResult(answer: 'Release now.'),
      );
      _storeQuestionResult(
        cache,
        _owner(generation: 8),
        _answeredResult(answer: 'Release now.'),
      );

      expect(
        policy
            .evidenceFor(
              owner: owner,
              capturedProof: null,
              questionResults: cache,
            )
            .approved,
        isFalse,
      );

      _storeQuestionResult(
        cache,
        owner,
        _answeredResult(answer: 'Release now.'),
      );
      final evidence = policy.evidenceFor(
        owner: owner,
        capturedProof: null,
        questionResults: cache,
      );

      expect(evidence.owner, owner);
      expect(evidence.directlyApproved, isFalse);
      expect(evidence.questionApproved, isTrue);
      expect(evidence.approved, isTrue);
    });

    test(
      'accepts reused answered results but rejects saved-task policy results',
      () {
        final owner = _owner();
        final reusedCache = AskUserQuestionTurnCache();
        _storeQuestionResult(
          reusedCache,
          owner,
          _questionResult(
            jsonEncode({
              'status': 'answered',
              'question': 'Approve the production release?',
              'answer': 'Yes',
              'reused': true,
            }),
          ),
        );
        final savedTaskCache = AskUserQuestionTurnCache();
        _storeQuestionResult(
          savedTaskCache,
          owner,
          _questionResult(
            jsonEncode({
              'status': 'policy_resolved',
              'question': 'Approve the production release?',
              'answer': 'Release now.',
              'saved_task_id': 'task-1',
            }),
          ),
        );

        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: null,
                questionResults: reusedCache,
              )
              .questionApproved,
          isTrue,
        );
        expect(
          policy
              .evidenceFor(
                owner: owner,
                capturedProof: null,
                questionResults: savedTaskCache,
              )
              .questionApproved,
          isFalse,
        );
        expect(
          policy
              .evaluate(
                owner: owner,
                toolCall: _tool(
                  'local_execute_command',
                  './release_ios_macos.sh',
                ),
                capturedProof: null,
                questionResults: reusedCache,
              )
              .guardResult,
          isNull,
        );
        expect(
          policy
              .evaluate(
                owner: owner,
                toolCall: _tool(
                  'local_execute_command',
                  './release_ios_macos.sh',
                ),
                capturedProof: null,
                questionResults: savedTaskCache,
              )
              .guardResult,
          isNotNull,
        );
      },
    );

    test('returns immutable evidence snapshots of the owner cache', () {
      final owner = _owner();
      final cache = AskUserQuestionTurnCache();
      final beforeApproval = policy.evidenceFor(
        owner: owner,
        capturedProof: null,
        questionResults: cache,
      );

      _storeQuestionResult(
        cache,
        owner,
        _answeredResult(answer: 'Release now.'),
      );
      final afterApproval = policy.evidenceFor(
        owner: owner,
        capturedProof: null,
        questionResults: cache,
      );
      cache.clear();

      expect(beforeApproval.approved, isFalse);
      expect(afterApproval.approved, isTrue);
      expect(afterApproval.owner, same(owner));
      expect(afterApproval.questionApproved, isTrue);
    });
  });

  group('release command recognition', () {
    test('recognizes every supported release script and command tool', () {
      final cases = [
        _tool('local_execute_command', './tool/release_ios_macos.sh'),
        _tool('local_execute_command', '/tmp/BUILD_MACOS_SPARKLE_RELEASE.SH'),
        _tool(
          'process_start',
          'env MODE=prod ./publish_macos_sparkle_release.sh',
        ),
      ];

      for (final toolCall in cases) {
        expect(
          policy.isProductionReleaseCommandToolCall(toolCall),
          isTrue,
          reason: toolCall.arguments['command'] as String,
        );
      }
    });

    test(
      'rejects unrelated tools, missing commands, and read-only inspection',
      () {
        final cases = [
          ToolCallInfo(
            id: 'tool',
            name: 'git_execute_command',
            arguments: {'command': './release_ios_macos.sh'},
          ),
          ToolCallInfo(
            id: 'tool',
            name: 'local_execute_command',
            arguments: const {},
          ),
          _tool('local_execute_command', '   '),
          _tool('local_execute_command', 'cat ./release_ios_macos.sh'),
          _tool('process_start', 'echo hello'),
        ];

        for (final toolCall in cases) {
          expect(policy.isProductionReleaseCommandToolCall(toolCall), isFalse);
        }
        expect(policy.looksLikeProductionReleaseCommand(''), isFalse);
        expect(
          policy.looksLikeProductionReleaseCommand('--verbose echo hello'),
          isFalse,
        );
      },
    );

    test('rejects every dry-run or help switch regardless of position', () {
      for (final switchValue in ['--dry-run', '-n', '--help', '-h']) {
        for (final command in [
          './release_ios_macos.sh $switchValue',
          '$switchValue ./release_ios_macos.sh',
          './release_ios_macos.sh ${switchValue.toUpperCase()}',
        ]) {
          expect(
            policy.looksLikeProductionReleaseCommand(command),
            isFalse,
            reason: command,
          );
        }
      }
    });

    test('parses quoted paths and ignores unrelated flags', () {
      expect(
        policy.looksLikeProductionReleaseCommand(
          'env --verbose "./tools/release_ios_macos.sh"',
        ),
        isTrue,
      );
    });

    test('preserves tool classification precedence before script matching', () {
      final readOnlyLocal = _tool(
        'local_execute_command',
        'cat ./release_ios_macos.sh',
      );
      final processStartWithSameCommand = _tool(
        'process_start',
        'cat ./release_ios_macos.sh',
      );
      final shellControlledRelease = _tool(
        'local_execute_command',
        './release_ios_macos.sh && echo complete',
      );

      expect(policy.isProductionReleaseCommandToolCall(readOnlyLocal), isFalse);
      expect(
        policy.isProductionReleaseCommandToolCall(processStartWithSameCommand),
        isTrue,
      );
      expect(
        policy.isProductionReleaseCommandToolCall(shellControlledRelease),
        isTrue,
      );
    });
  });

  group('guard decision', () {
    test('returns no guard for a non-release or approved release', () {
      final owner = _owner();
      final emptyCache = AskUserQuestionTurnCache();
      final nonRelease = policy.evaluate(
        owner: owner,
        toolCall: _tool('local_execute_command', 'dart analyze'),
        capturedProof: null,
        questionResults: emptyCache,
      );
      final approved = policy.evaluate(
        owner: owner,
        toolCall: _tool('local_execute_command', './release_ios_macos.sh'),
        capturedProof: policy.captureProof(
          owner: owner,
          submittedUserContent: 'Ship the release.',
          precedingOwnerMessage: null,
        ),
        questionResults: emptyCache,
      );

      expect(nonRelease.guardResult, isNull);
      expect(nonRelease.evidence.approved, isFalse);
      expect(approved.guardResult, isNull);
      expect(approved.evidence.approved, isTrue);
    });

    test('returns the exact blocked payload and clips assistant intent', () {
      final owner = _owner();
      final longIntent = '${'Inspect   the output. ' * 20}\nThen release.';

      final decision = policy.evaluate(
        owner: owner,
        toolCall: _tool(
          'process_start',
          ' ./release_ios_macos.sh ',
          toolNameOverride: ' process_start ',
        ),
        capturedProof: null,
        questionResults: AskUserQuestionTurnCache(),
        currentAssistantContent: longIntent,
      );
      final result = decision.guardResult!;
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      final expectedPayload = {
        'ok': false,
        'code': 'production_release_explicit_approval_required',
        'error':
            'A production release command was blocked because the latest user '
            'message or ask_user_question answer did not explicitly approve '
            'production release execution.',
        'command': './release_ios_macos.sh',
        'assistant_intent':
            '${longIntent.replaceAll(RegExp(r'\s+'), ' ').trim().substring(0, 240)}...',
        'required_action':
            'Ask the user to explicitly approve the production release command '
            'after any dry run, then retry only after that user approval.',
      };

      expect(result.toolName, ' process_start ');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.result, jsonEncode(expectedPayload));
      expect(payload, expectedPayload);
    });

    test(
      'omits blank assistant intent and preserves a short normalized value',
      () {
        final evidence = ProductionReleaseApprovalEvidence(
          owner: _owner(),
          directlyApproved: false,
          questionApproved: false,
        );
        final withoutIntent = policy.buildGuardResult(
          _tool('local_execute_command', './release_ios_macos.sh'),
          owner: _owner(),
          currentAssistantContent: ' \n ',
          approvalEvidence: evidence,
        )!;
        final withIntent = policy.buildGuardResult(
          _tool('local_execute_command', './release_ios_macos.sh'),
          owner: _owner(),
          currentAssistantContent: '  Prepare   release. ',
          approvalEvidence: evidence,
        )!;

        expect(
          jsonDecode(withoutIntent.result),
          isNot(contains('assistant_intent')),
        );
        expect(
          (jsonDecode(withIntent.result) as Map)['assistant_intent'],
          'Prepare release.',
        );
      },
    );

    test('does not accept approval evidence owned by another turn', () {
      for (final evidenceOwner in [
        _owner(conversationId: 'conversation-b'),
        _owner(generation: 8),
      ]) {
        final result = policy.buildGuardResult(
          _tool('local_execute_command', './release_ios_macos.sh'),
          owner: _owner(),
          currentAssistantContent: null,
          approvalEvidence: ProductionReleaseApprovalEvidence(
            owner: evidenceOwner,
            directlyApproved: true,
            questionApproved: true,
          ),
        );

        expect(result, isNotNull, reason: evidenceOwner.toString());
      }
    });
  });

  group('ask-user-question approval decoding', () {
    test('rejects failed, malformed, non-object, and non-answered results', () {
      final cases = [
        McpToolResult(
          toolName: 'ask_user_question',
          result: jsonEncode({'status': 'answered', 'answer': 'Release now.'}),
          isSuccess: false,
        ),
        _questionResult('{broken'),
        _questionResult('[]'),
        _questionResult(jsonEncode({'status': 'cancelled'})),
        _questionResult(jsonEncode({'status': 'answered'})),
      ];

      for (final result in cases) {
        expect(policy.answerApproves(result), isFalse);
      }
    });

    test('accepts explicit approval from every answer evidence field', () {
      final payloads = [
        {'status': 'answered', 'answer': 'Run the production release.'},
        {'status': 'answered', 'other': 'Publish the release now.'},
        {
          'status': 'answered',
          'selected': [
            {'label': 'Ship the release'},
          ],
        },
        {
          'status': 'answered',
          'selected': [
            {'description': 'Execute the production upload'},
          ],
        },
        {
          'status': 'answered',
          'selected': [
            {'preview': 'Run the Sparkle release'},
          ],
        },
        {
          'status': 'answered',
          'selected': ['Release now'],
        },
      ];

      for (final payload in payloads) {
        expect(
          policy.answerApproves(_questionResult(jsonEncode(payload))),
          isTrue,
          reason: payload.toString(),
        );
      }
    });

    test(
      'accepts an affirmative answer only to an explicit release question',
      () {
        expect(
          policy.answerApproves(
            _answeredResult(
              question: 'Approve the production release?',
              answer: 'Yes',
            ),
          ),
          isTrue,
        );
        expect(
          policy.answerApproves(
            _answeredResult(question: 'Choose a target.', answer: 'Yes'),
          ),
          isFalse,
        );
        expect(
          policy.answerApproves(
            _answeredResult(
              question: 'Approve the production release?',
              answer: 'No, stop.',
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group('approval language predicates', () {
    test('recognizes direct forms, release mentions, and required actions', () {
      expect(
        policy.looksLikeExplicitProductionReleaseApproval('Release later'),
        isTrue,
      );
      expect(
        policy.looksLikeExplicitProductionReleaseApproval('Ship this build'),
        isTrue,
      );
      expect(
        policy.looksLikeExplicitProductionReleaseApproval(
          'Release is mentioned without another action verb.',
        ),
        isTrue,
      );
      for (final value in [
        'Run the Sparkle build.',
        'Execute the App Store Connect upload.',
        'Start the production publish.',
        'Go ahead with the S3 upload.',
      ]) {
        expect(
          policy.looksLikeExplicitProductionReleaseApproval(value),
          isTrue,
          reason: value,
        );
      }
      expect(
        policy.looksLikeExplicitProductionReleaseApproval(
          'The Sparkle notes are ready.',
        ),
        isFalse,
      );
      expect(policy.mentionsProductionRelease('ordinary command'), isFalse);
    });

    test('recognizes valid prompts and rejects incomplete prompt language', () {
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt(
          'Do you approve the production release command?',
        ),
        isTrue,
      );
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt(
          'The release is prepared.',
        ),
        isFalse,
      );
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt(
          'Do you approve this command?',
        ),
        isFalse,
      );
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt('May I publish?'),
        isFalse,
      );
    });

    test(
      'recognizes affirmative forms while preserving negative precedence',
      () {
        for (final value in [
          'Approved',
          'Yes',
          'Go ahead',
          'Proceed',
          'Execute',
          'Ship',
        ]) {
          expect(
            policy.looksLikeAffirmativeReleaseApprovalAnswer(value),
            isTrue,
            reason: value,
          );
        }
        for (final value in [
          'Do not release',
          "Don't run it",
          'Cancel',
          'Reject',
          'Not now',
        ]) {
          expect(
            policy.looksLikeAffirmativeReleaseApprovalAnswer(value),
            isFalse,
            reason: value,
          );
        }
        expect(
          policy.looksLikeAffirmativeReleaseApprovalAnswer('Maybe later'),
          isFalse,
        );
      },
    );

    test('recognizes code-unit based localized approval forms', () {
      final release = String.fromCharCodes([0x30ea, 0x30ea, 0x30fc, 0x30b9]);
      final execute = String.fromCharCodes([0x5b9f, 0x884c]);
      final affirmative = String.fromCharCodes([0x306f, 0x3044]);
      final fullWidthQuestion = String.fromCharCode(0xff1f);

      expect(policy.mentionsProductionRelease(release), isTrue);
      expect(
        policy.looksLikeExplicitProductionReleaseApproval('$release$execute'),
        isTrue,
      );
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt(
          '$release$execute$fullWidthQuestion',
        ),
        isTrue,
      );
      expect(
        policy.looksLikeProductionReleaseApprovalPrompt('$release$execute'),
        isTrue,
      );
      expect(
        policy.looksLikeAffirmativeReleaseApprovalAnswer(affirmative),
        isTrue,
      );
    });
  });
}

ChatTurnOwner _owner({
  String conversationId = 'conversation-a',
  int generation = 7,
}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ToolCallInfo _tool(String name, String command, {String? toolNameOverride}) {
  return ToolCallInfo(
    id: 'tool-call',
    name: toolNameOverride ?? name,
    arguments: {'command': command},
  );
}

McpToolResult _questionResult(String result) {
  return McpToolResult(
    toolName: 'ask_user_question',
    result: result,
    isSuccess: true,
  );
}

McpToolResult _answeredResult({
  String question = 'Approve the production release?',
  required String answer,
}) {
  return _questionResult(
    jsonEncode({
      'status': 'answered',
      'question': question,
      'answer': answer,
      'selected': const [],
    }),
  );
}

void _storeQuestionResult(
  AskUserQuestionTurnCache cache,
  ChatTurnOwner owner,
  McpToolResult result,
) {
  cache.store(
    owner: owner,
    question: 'Approve the production release?',
    optionLabels: const ['Approve', 'Cancel'],
    result: result,
  );
}

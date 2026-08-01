import 'dart:collection';

import 'package:caverno/core/services/browser_tool_policy.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/browser_session_ownership_coordinator.dart';
import 'package:caverno/features/chat/domain/services/browser_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );
  final ownerANext = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 5,
  );

  group('BrowserToolRequest', () {
    test('recursively freezes nested browser arguments', () {
      final values = <Object?>['initial'];
      final nested = <String, Object?>{
        'owner': 'owner-a',
        'values': values,
        'flags': <Object?>['safe'],
      };
      final arguments = <String, dynamic>{
        'selector': '#query',
        'reason': 'Use the search field.',
        'nested': nested,
      };

      final request = BrowserToolRequest(
        operation: _operation(ownerA, 'browser_fill'),
        arguments: arguments,
      );
      values.add('poisoned');
      (nested['flags'] as List<Object?>).add('poisoned');
      nested['values'] = ['replaced'];
      nested['owner'] = 'visible';
      arguments['selector'] = '#poisoned';

      expect(request.operation.owner, ownerA);
      expect(request.toolName, 'browser_fill');
      expect(request.reason, 'Use the search field.');
      expect(request.arguments['selector'], '#query');
      expect(request.arguments['nested'], {
        'owner': 'owner-a',
        'values': ['initial'],
        'flags': ['safe'],
      });
      expect(
        () => (request.arguments['nested'] as Map)['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['nested'] as Map)['values'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((request.arguments['nested'] as Map)['flags'] as List).add('late'),
        throwsUnsupportedError,
      );
    });

    test('rejects aliased mutable browser values and map keys', () {
      expect(
        () => BrowserToolRequest(
          operation: _operation(ownerA, 'browser_fill'),
          arguments: {'mutable': _MutableValue()},
        ),
        throwsArgumentError,
      );
      expect(
        () => BrowserToolRequest(
          operation: _operation(ownerA, 'browser_fill'),
          arguments: {
            'mutableKey': {_MutableValue(): true},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => BrowserToolRequest(
          operation: _operation(ownerA, 'browser_fill'),
          arguments: {
            'notJson': <Object?>{'value'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => BrowserToolRequest(
          operation: _operation(ownerA, 'browser_fill'),
          arguments: {'notFinite': double.infinity},
        ),
        throwsArgumentError,
      );
    });
  });

  group('BrowserToolHandler action classification', () {
    test('executes every observation action without approval', () async {
      const safeTools = [
        'browser_open',
        'browser_snapshot',
        'browser_get_content',
        'browser_screenshot',
        'browser_wait',
        'browser_navigate_history',
        'browser_close',
      ];

      for (final toolName in safeTools) {
        final fixture = _fixture();
        final expected = _toolResult(toolName, result: '{"ok":true}');
        fixture.execution.results[ownerA] = BrowserExecutionResult(
          operation: _operation(ownerA, toolName),
          result: expected,
        );

        final result = await fixture.handler.handle(
          _request(
            ownerA,
            toolName,
            arguments: {
              'nested': {
                'values': [toolName],
              },
            },
          ),
        );

        expect(result, same(expected), reason: toolName);
        expect(fixture.execution.calls.single.operation.owner, ownerA);
        expect(fixture.execution.calls.single.request.toolName, toolName);
        expect(fixture.execution.calls.single.request.arguments, {
          'nested': {
            'values': [toolName],
          },
        });
        expect(fixture.approval.gateCalls, isEmpty);
        expect(fixture.observation.pageOwners, isEmpty);
        expect(fixture.events, ['execution:$toolName:conversation-a:4']);
      }
    });

    test('routes every sensitive action through the approval gate', () async {
      const sensitiveTools = [
        'browser_fill',
        'browser_click',
        'browser_submit',
        'browser_eval',
        'browser_save_data',
      ];

      for (final toolName in sensitiveTools) {
        final fixture = _fixture();
        fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, toolName),
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        );

        final result = await fixture.handler.handle(_request(ownerA, toolName));

        expect(result.isSuccess, isTrue, reason: toolName);
        expect(
          fixture.approval.gateCalls.single.request.policy.toolName,
          toolName,
        );
        expect(
          fixture.approval.gateCalls.single.request.policy.risk,
          BrowserToolRisk.sensitive,
        );
        expect(fixture.approval.manualCalls, isEmpty);
        expect(fixture.execution.calls.single.request.toolName, toolName);
        expect(fixture.events, [
          'approval.current:conversation-a:4',
          'observation.page:conversation-a:4',
          'approval.gate:$toolName:conversation-a:4',
          'approval.expired:$toolName:conversation-a:4',
          'approval.current:conversation-a:4',
          'execution:$toolName:conversation-a:4',
        ]);
      }
    });

    test('the explicit bypass forwards a sensitive action directly', () async {
      final fixture = _fixture();

      await fixture.handler.handleWithoutApproval(
        _request(ownerA, 'browser_click', arguments: const {'ref': 7}),
      );

      expect(fixture.approval.gateCalls, isEmpty);
      expect(fixture.observation.pageOwners, isEmpty);
      expect(fixture.execution.calls.single.request.arguments, {'ref': 7});
    });

    test(
      'blocks a peer while another browser session lease is active',
      () async {
        final fixture = _fixture();
        final externalOperation = _operation(ownerA, 'browser_open');
        final externalLease = fixture.session
            .acquire(externalOperation, fixture.session.captureSessionEpoch())
            .lease!;

        final result = await fixture.handler.handle(
          _request(ownerB, 'browser_open'),
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Another browser operation is still active.',
        );
        expect(fixture.execution.calls, isEmpty);
        final retired = fixture.session.clearOwner(ownerA);
        expect(retired.invalidatedLease, same(externalLease));
        expect(fixture.session.settleInvalidatedLease(externalLease), isTrue);
      },
    );

    test(
      'contains a safe transport completion after owner retirement',
      () async {
        final fixture = _fixture();
        fixture.execution.beforeReturn = (_) {
          fixture.session.clearOwner(ownerA);
        };

        final result = await fixture.handler.handle(
          _request(ownerA, 'browser_open'),
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'The browser operation expired before completion.',
        );
        expect(fixture.session.captureSessionEpoch().epoch, 0);
        final receipt = fixture.session.pendingEffectRecovery;
        expect(receipt, isNotNull);
        expect(
          await fixture.handler.handle(_request(ownerB, 'browser_open')),
          isA<McpToolResult>().having(
            (value) => value.isSuccess,
            'isSuccess',
            isFalse,
          ),
        );
        expect(fixture.session.clearEffectRecovery(receipt!), isTrue);
        expect(
          await fixture.handler.handle(_request(ownerB, 'browser_open')),
          isA<McpToolResult>().having(
            (value) => value.isSuccess,
            'isSuccess',
            isTrue,
          ),
        );
      },
    );

    test(
      'a direct gate bypass does not read auto-review page metadata',
      () async {
        final fixture = _fixture();
        fixture.approval.materializeReviewArguments = false;
        fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_click'),
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        );

        await fixture.handler.handle(_request(ownerA, 'browser_click'));

        expect(fixture.observation.pageOwners, isEmpty);
        expect(fixture.events, [
          'approval.gate:browser_click:conversation-a:4',
          'approval.expired:browser_click:conversation-a:4',
          'approval.current:conversation-a:4',
          'execution:browser_click:conversation-a:4',
        ]);
      },
    );

    test('rejects lazy review materialization after lease release', () async {
      final fixture = _fixture();
      fixture.approval.materializeReviewArguments = false;

      final result = await fixture.handler.handle(
        _request(ownerA, 'browser_click'),
      );
      final retainedGate = fixture.approval.gateCalls.single.request;

      expect(result.isSuccess, isTrue);
      expect(
        () => retainedGate.reviewArguments,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser operation is no longer current.',
          ),
        ),
      );
      expect(fixture.observation.pageOwners, isEmpty);
    });
  });

  group('BrowserToolHandler review and presentation helpers', () {
    test('sanitizes review arguments and freezes nested values', () {
      final fixture = _fixture();
      final request = _request(
        ownerA,
        'browser_fill',
        arguments: {
          'selector': '#password',
          'value': 'top-secret',
          'script': 'steal()',
          'data': '{"secret":true}',
          'reason': 'Sign in.',
          'nested': {
            'values': ['kept'],
          },
        },
      );

      final review = fixture.handler.reviewArguments(
        request,
        'https://user:password@example.com/account?token=secret',
      );

      expect(review, {
        'selector': '#password',
        'reason': 'Sign in.',
        'nested': {
          'values': ['kept'],
        },
        'pageHost': 'example.com',
      });
      expect(review, isNot(contains('value')));
      expect(review, isNot(contains('script')));
      expect(review, isNot(contains('data')));
      expect(() => review['late'] = true, throwsUnsupportedError);
      expect(
        () => ((review['nested'] as Map)['values'] as List).add('late'),
        throwsUnsupportedError,
      );
    });

    test('preserves an argument pageHost when no observed host exists', () {
      final fixture = _fixture();
      final request = _request(
        ownerA,
        'browser_click',
        arguments: const {'pageHost': 'provided.example'},
      );

      expect(fixture.handler.reviewArguments(request, 'not a host'), {
        'pageHost': 'provided.example',
      });
      expect(
        fixture.handler.reviewArguments(
          request,
          'https://observed.example/path',
        ),
        {'pageHost': 'observed.example'},
      );
    });

    test('preserves every exact browser action description', () {
      final fixture = _fixture();
      final cases = [
        (
          request: _request(
            ownerA,
            'browser_fill',
            arguments: const {'ref': 7, 'value': 'hello'},
          ),
          description: 'Fill element #7 with hello',
        ),
        (
          request: _request(
            ownerA,
            'browser_fill',
            arguments: const {'selector': '  #query  ', 'value': ''},
          ),
          description: 'Fill selector "#query" with (empty)',
        ),
        (
          request: _request(ownerA, 'browser_click'),
          description: 'Click the target element',
        ),
        (
          request: _request(
            ownerA,
            'browser_submit',
            arguments: const {'selector': '#login'},
          ),
          description: 'Submit the form containing #login',
        ),
        (
          request: _request(ownerA, 'browser_submit'),
          description: 'Submit the current form',
        ),
        (
          request: _request(
            ownerA,
            'browser_eval',
            arguments: const {'script': 'abc'},
          ),
          description: 'Run JavaScript in the page (3 chars)',
        ),
        (
          request: _request(
            ownerA,
            'browser_save_data',
            arguments: const {'filename': 'report.json'},
          ),
          description: 'Save data to report.json',
        ),
        (
          request: _request(ownerA, 'browser_save_data'),
          description: 'Save data to a file',
        ),
        (
          request: _request(ownerA, 'browser_unknown'),
          description: 'browser_unknown',
        ),
      ];

      for (final testCase in cases) {
        expect(
          fixture.handler.describeAction(testCase.request),
          testCase.description,
        );
      }
    });

    test('preserves safe, secret, and truncated value previews', () {
      final fixture = _fixture();
      final safe = 'v' * 81;
      final secret = 's' * 40;

      expect(
        fixture.handler.sensitiveValuePreview(_request(ownerA, 'browser_fill')),
        '(empty)',
      );
      expect(
        fixture.handler.sensitiveValuePreview(
          _request(
            ownerA,
            'browser_fill',
            arguments: {'selector': '#query', 'value': safe},
          ),
        ),
        '${'v' * 80}…',
      );
      for (final marker in ['pass', 'pwd', 'secret', 'otp', 'token']) {
        expect(
          fixture.handler.sensitiveValuePreview(
            _request(
              ownerA,
              'browser_fill',
              arguments: {'selector': '#${marker}Field', 'value': secret},
            ),
          ),
          '${'•' * 32} (40 chars, hidden)',
          reason: marker,
        );
      }
      expect(
        fixture.handler.sensitiveValuePreview(
          _request(ownerA, 'browser_eval', arguments: {'script': 'x' * 401}),
        ),
        '${'x' * 400}…',
      );
      expect(
        fixture.handler.sensitiveValuePreview(
          _request(ownerA, 'browser_click'),
        ),
        isNull,
      );
    });

    test('preserves exact target summaries', () {
      final fixture = _fixture();

      expect(
        fixture.handler.actionTargetSummary(
          _request(ownerA, 'browser_fill', arguments: const {'ref': 'node-2'}),
        ),
        'Review the target element #node-2 before approving.',
      );
      expect(
        fixture.handler.actionTargetSummary(
          _request(
            ownerA,
            'browser_click',
            arguments: const {'selector': '#next'},
          ),
        ),
        'Review the target selector "#next" before approving.',
      );
      expect(
        fixture.handler.actionTargetSummary(
          _request(ownerA, 'browser_save_data'),
        ),
        'A file will be written to your device.',
      );
      expect(
        fixture.handler.actionTargetSummary(_request(ownerA, 'browser_eval')),
        'Arbitrary JavaScript will run in the current page.',
      );
      expect(
        fixture.handler.actionTargetSummary(_request(ownerA, 'browser_submit')),
        isNull,
      );
    });
  });

  group('BrowserToolHandler action details', () {
    test('builds exact fill, click, submit, and eval details', () async {
      final fixture = _fixture();
      fixture.observation.pages[ownerA] = BrowserPageObservation(
        operation: _operation(ownerA, 'browser_fill'),
        currentUrl: 'https://user:secret@example.com/form?token=hidden',
      );
      final cases = [
        (
          request: _request(
            ownerA,
            'browser_fill',
            arguments: const {
              'ref': 7,
              'selector': '#email',
              'reason': '  Enter the email.  ',
            },
          ),
          details: const [
            'Tool: browser_fill',
            'Target ref: 7',
            'Selector: #email',
            'Model reason: Enter the email.',
            'Page: example.com',
          ],
        ),
        (
          request: _request(
            ownerA,
            'browser_click',
            arguments: const {'selector': '#next'},
          ),
          details: const [
            'Tool: browser_click',
            'Selector: #next',
            'Page: example.com',
          ],
        ),
        (
          request: _request(
            ownerA,
            'browser_submit',
            arguments: const {'selector': '#login'},
          ),
          details: const [
            'Tool: browser_submit',
            'Form selector: #login',
            'Page: example.com',
          ],
        ),
        (
          request: _request(
            ownerA,
            'browser_eval',
            arguments: const {'script': 'abc'},
          ),
          details: const [
            'Tool: browser_eval',
            'Script length: 3 characters',
            'Page: example.com',
          ],
        ),
      ];

      for (final testCase in cases) {
        fixture.observation.pages[ownerA] = BrowserPageObservation(
          operation: testCase.request.operation,
          currentUrl: 'https://user:secret@example.com/form?token=hidden',
        );
        final details = await fixture.handler.actionDetails(testCase.request);
        expect(details, testCase.details);
        expect(() => details.add('late'), throwsUnsupportedError);
      }
    });

    test('builds exact changed save-target details and defaults', () async {
      final fixture = _fixture();
      fixture.observation.targets[ownerA] = BrowserSaveTargetObservation(
        operation: _operation(ownerA, 'browser_save_data'),
        destinationLabel: 'Caverno application storage',
        destinationChanged: true,
        requestedDestination: 'downloads',
        requestedFilename: '../report',
        filename: 'report.json',
        directoryPath: '/app/browser',
        path: '/app/browser/report.json',
      );

      final details = await fixture.handler.actionDetails(
        _request(
          ownerA,
          'browser_save_data',
          arguments: const {
            'data': 'abcdef',
            'destination': 'downloads',
            'reason': 'Save the report.',
          },
        ),
      );

      expect(
        fixture.observation.targetCalls.single.request.filename,
        'browser_data',
      );
      expect(fixture.observation.targetCalls.single.request.format, 'json');
      expect(
        fixture.observation.targetCalls.single.request.destination,
        'downloads',
      );
      expect(details, [
        'Tool: browser_save_data',
        'Destination: Caverno application storage',
        'Requested destination: downloads',
        'Requested file: ../report',
        'Final file: report.json',
        'Save location: /app/browser',
        'Full path: /app/browser/report.json',
        'Size: 6 characters',
        'Model reason: Save the report.',
        'Page: example.com',
      ]);
    });
  });

  group('BrowserToolHandler approval routes', () {
    test('forwards exact gate facts and manual presentation', () async {
      final fixture = _fixture();
      fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_fill'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      final request = _request(
        ownerA,
        'browser_fill',
        arguments: const {
          'selector': '#password',
          'value': 'hunter2',
          'reason': 'Sign in.',
        },
      );

      await fixture.handler.handle(request);

      final gate = fixture.approval.gateCalls.single.request;
      expect(gate.toolRequest, same(request));
      expect(gate.reviewArguments, {
        'selector': '#password',
        'reason': 'Sign in.',
        'pageHost': 'example.com',
      });
      expect(gate.sensitiveValuePreview, '••••••• (7 chars, hidden)');
      expect(gate.reason, 'Sign in.');
      expect(gate.policy.title, 'Fill a form field');
      expect(gate.policy.riskLabel, 'Sensitive browser action');
      expect(gate.policy.approveLabel, 'Approve');
      expect(
        gate.policy.warningMessage,
        'The agent wants to type into a form field in the built-in browser.',
      );

      final manual = fixture.approval.manualCalls.single.request;
      expect(manual.toolRequest, same(request));
      expect(
        manual.summary,
        'Fill selector "#password" with ••••••• (7 chars, hidden)',
      );
      expect(manual.details, [
        'Tool: browser_fill',
        'Selector: #password',
        'Model reason: Sign in.',
        'Page: example.com',
      ]);
      expect(
        manual.targetSummary,
        'Review the target selector "#password" before approving.',
      );
      expect(manual.sensitiveValuePreview, '••••••• (7 chars, hidden)');
      expect(manual.reason, 'Sign in.');
      expect(() => manual.details.add('late'), throwsUnsupportedError);
    });

    test(
      'maps auto-review denial to the exact result after expiry check',
      () async {
        final fixture = _fixture();
        fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_click'),
          decision: ToolApprovalGateDecision.denied('Untrusted page content.'),
        );

        final result = await fixture.handler.handle(
          _request(ownerA, 'browser_click'),
        );

        expect(
          result.result,
          '{"ok":false,"code":"auto_review_denied",'
          '"error":"Auto-review denied this browser action. '
          'Untrusted page content.","nextAction":"Ask the user for explicit '
          'approval before retrying this browser action."}',
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Auto-review denied: Untrusted page content.',
        );
        expect(fixture.approval.manualCalls, isEmpty);
        expect(fixture.execution.calls, isEmpty);
        expect(fixture.events, [
          'approval.current:conversation-a:4',
          'observation.page:conversation-a:4',
          'approval.gate:browser_click:conversation-a:4',
          'approval.expired:browser_click:conversation-a:4',
          'approval.current:conversation-a:4',
        ]);
      },
    );

    test('returns gate expiry before mapping an auto-review denial', () async {
      const expired = McpToolResult(
        toolName: 'browser_click',
        result: '',
        isSuccess: false,
        errorMessage: 'The approval turn expired before execution',
      );
      final fixture = _fixture();
      fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_click'),
        decision: ToolApprovalGateDecision.denied('Denied.'),
      );
      fixture.approval.expirations[ownerA] = Queue.of([expired]);

      expect(
        await fixture.handler.handle(_request(ownerA, 'browser_click')),
        same(expired),
      );
      expect(fixture.execution.calls, isEmpty);
    });

    test('rejects an expiry result for another browser tool', () async {
      const poisoned = McpToolResult(
        toolName: 'browser_fill',
        result: '',
        isSuccess: false,
        errorMessage: 'Poisoned expiry',
      );
      final fixture = _fixture();
      fixture.approval.expirations[ownerA] = Queue.of([poisoned]);

      await expectLater(
        fixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser expiry tool name mismatch.',
          ),
        ),
      );
      expect(fixture.execution.calls, isEmpty);
    });

    test('preserves manual allow and deny sequencing and payloads', () async {
      final allowedFixture = _fixture();
      allowedFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_submit'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );

      final allowed = await allowedFixture.handler.handle(
        _request(ownerA, 'browser_submit'),
      );

      expect(allowed.isSuccess, isTrue);
      expect(allowedFixture.events, [
        'approval.current:conversation-a:4',
        'observation.page:conversation-a:4',
        'approval.gate:browser_submit:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
        'approval.current:conversation-a:4',
        'observation.page:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
        'approval.manual:browser_submit:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
        'execution:browser_submit:conversation-a:4',
      ]);

      final deniedFixture = _fixture();
      deniedFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_submit'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      deniedFixture.approval.manualResults[ownerA] =
          BrowserManualApprovalResult(
            operation: _operation(ownerA, 'browser_submit'),
            approved: false,
          );

      final denied = await deniedFixture.handler.handle(
        _request(ownerA, 'browser_submit'),
      );

      expect(
        denied.result,
        '{"ok":false,"code":"approval_denied",'
        '"error":"User denied the browser action.","nextAction":"Ask the user '
        'for explicit approval before retrying this browser action."}',
      );
      expect(denied.isSuccess, isFalse);
      expect(denied.errorMessage, 'User denied browser action.');
      expect(deniedFixture.execution.calls, isEmpty);
      expect(deniedFixture.events, [
        'approval.current:conversation-a:4',
        'observation.page:conversation-a:4',
        'approval.gate:browser_submit:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
        'approval.current:conversation-a:4',
        'observation.page:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
        'approval.manual:browser_submit:conversation-a:4',
        'approval.expired:browser_submit:conversation-a:4',
        'approval.current:conversation-a:4',
      ]);
    });

    test('contains a stale manual denial without an expiry result', () async {
      final fixture = _fixture();
      fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_submit'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      fixture.approval.manualResults[ownerA] = BrowserManualApprovalResult(
        operation: _operation(ownerA, 'browser_submit'),
        approved: false,
      );
      fixture.approval.currentResults[ownerA] = Queue.of([
        true,
        true,
        true,
        true,
        false,
      ]);
      fixture.approval.expirations[ownerA] = Queue.of([null, null, null]);

      final result = await fixture.handler.handle(
        _request(ownerA, 'browser_submit'),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'The browser operation expired before completion.',
      );
      expect(fixture.execution.calls, isEmpty);
      expect(fixture.approval.expiredOwners, [ownerA, ownerA, ownerA]);
    });

    test('contains a stale manual approval without executing', () async {
      final fixture = _fixture();
      fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_submit'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      fixture.approval.currentResults[ownerA] = Queue.of([
        true,
        true,
        true,
        true,
        false,
      ]);
      fixture.approval.expirations[ownerA] = Queue.of([null, null, null]);

      final result = await fixture.handler.handle(
        _request(ownerA, 'browser_submit'),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'The browser operation expired before completion.',
      );
      expect(fixture.execution.calls, isEmpty);
    });
  });

  group('BrowserToolHandler result and failure forwarding', () {
    test(
      'forwards returned execution failures without rewriting them',
      () async {
        final fixture = _fixture();
        final failure = _toolResult(
          'browser_open',
          result: '{"ok":false,"code":"browser_unavailable"}',
          isSuccess: false,
          errorMessage: 'Browser tools are unavailable',
        );
        fixture.execution.results[ownerA] = BrowserExecutionResult(
          operation: _operation(ownerA, 'browser_open'),
          result: failure,
        );

        final result = await fixture.handler.handle(
          _request(ownerA, 'browser_open'),
        );

        expect(result, same(failure));
      },
    );

    test('forwards transport and observation failures', () async {
      final transportFixture = _fixture();
      final transportError = StateError('browser transport unavailable');
      transportFixture.execution.errors[ownerA] = transportError;
      await expectLater(
        transportFixture.handler.handle(_request(ownerA, 'browser_open')),
        throwsA(same(transportError)),
      );

      final pageFixture = _fixture();
      final pageError = StateError('page metadata unavailable');
      pageFixture.observation.pageErrors[ownerA] = pageError;
      await expectLater(
        pageFixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(same(pageError)),
      );
      expect(pageFixture.approval.gateCalls, isEmpty);

      final saveFixture = _fixture();
      saveFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_save_data'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      final saveError = StateError('save target unavailable');
      saveFixture.observation.targetErrors[ownerA] = saveError;
      await expectLater(
        saveFixture.handler.handle(_request(ownerA, 'browser_save_data')),
        throwsA(same(saveError)),
      );
      expect(saveFixture.approval.manualCalls, isEmpty);
      expect(saveFixture.execution.calls, isEmpty);
    });

    test(
      'stops save presentation when retirement follows target lookup',
      () async {
        final fixture = _fixture();
        fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_save_data'),
          decision: ToolApprovalGateDecision.needsManualApproval,
        );
        fixture.observation.beforeTargetReturn = (_) {
          fixture.session.clearOwner(ownerA);
        };

        await expectLater(
          fixture.handler.handle(_request(ownerA, 'browser_save_data')),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Browser operation is no longer current.',
            ),
          ),
        );
        expect(fixture.approval.manualCalls, isEmpty);
        expect(fixture.execution.calls, isEmpty);
      },
    );

    test('forwards approval gate and manual approval failures', () async {
      final gateFixture = _fixture();
      final gateError = StateError('approval gate unavailable');
      gateFixture.approval.gateErrors[ownerA] = gateError;
      await expectLater(
        gateFixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(same(gateError)),
      );
      expect(gateFixture.approval.expiredOwners, isEmpty);
      expect(gateFixture.execution.calls, isEmpty);

      final manualFixture = _fixture();
      manualFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_click'),
        decision: ToolApprovalGateDecision.needsManualApproval,
      );
      final manualError = StateError('manual approval unavailable');
      manualFixture.approval.manualErrors[ownerA] = manualError;
      await expectLater(
        manualFixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(same(manualError)),
      );
      expect(manualFixture.execution.calls, isEmpty);
    });
  });

  group('BrowserToolHandler owner poison', () {
    test('rejects same-owner observations from another tool call', () async {
      final fixture = _fixture();
      fixture.observation.pages[ownerA] = BrowserPageObservation(
        operation: _operation(
          ownerA,
          'browser_click',
          toolCallId: 'poisoned-call',
        ),
        currentUrl: 'https://poisoned.example',
      );

      await expectLater(
        fixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser page observation operation mismatch.',
          ),
        ),
      );
      expect(fixture.approval.gateCalls, isEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('rejects same-owner approval from another tool', () async {
      final fixture = _fixture();
      fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
        operation: _operation(ownerA, 'browser_fill'),
        decision: ToolApprovalGateDecision.autoReviewAllowed,
      );

      await expectLater(
        fixture.handler.handle(_request(ownerA, 'browser_click')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser approval gate operation mismatch.',
          ),
        ),
      );
      expect(fixture.approval.expiredOwners, isEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('rejects same-owner transport from another tool call', () async {
      fixtureFor(String toolCallId) {
        final fixture = _fixture();
        fixture.execution.results[ownerA] = BrowserExecutionResult(
          operation: _operation(ownerA, 'browser_open', toolCallId: toolCallId),
          result: _toolResult('browser_open', result: 'poisoned'),
        );
        return fixture;
      }

      final fixture = fixtureFor('poisoned-call');
      await expectLater(
        fixture.handler.handle(_request(ownerA, 'browser_open')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser execution operation mismatch.',
          ),
        ),
      );
    });

    test(
      'rejects page metadata from another conversation or generation',
      () async {
        for (final poisonedOwner in [ownerB, ownerANext]) {
          final fixture = _fixture();
          fixture.observation.pages[ownerA] = BrowserPageObservation(
            operation: _operation(poisonedOwner, 'browser_click'),
            currentUrl: 'https://poisoned.example',
          );

          await expectLater(
            fixture.handler.handle(_request(ownerA, 'browser_click')),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Browser page observation operation mismatch.',
              ),
            ),
          );
          expect(fixture.approval.gateCalls, isEmpty);
          expect(fixture.execution.calls, isEmpty);
        }
      },
    );

    test('rejects approval completions from another owner', () async {
      for (final poisonedOwner in [ownerB, ownerANext]) {
        final gateFixture = _fixture();
        gateFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(poisonedOwner, 'browser_click'),
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        );

        await expectLater(
          gateFixture.handler.handle(_request(ownerA, 'browser_click')),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Browser approval gate operation mismatch.',
            ),
          ),
        );
        expect(gateFixture.approval.expiredOwners, isEmpty);
        expect(gateFixture.execution.calls, isEmpty);

        final manualFixture = _fixture();
        manualFixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_click'),
          decision: ToolApprovalGateDecision.needsManualApproval,
        );
        manualFixture.approval.manualResults[ownerA] =
            BrowserManualApprovalResult(
              operation: _operation(poisonedOwner, 'browser_click'),
              approved: true,
            );

        await expectLater(
          manualFixture.handler.handle(_request(ownerA, 'browser_click')),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Browser manual approval operation mismatch.',
            ),
          ),
        );
        expect(manualFixture.execution.calls, isEmpty);
      }
    });

    test('rejects save-target metadata from another owner', () async {
      for (final poisonedOwner in [ownerB, ownerANext]) {
        final fixture = _fixture();
        fixture.approval.gates[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_save_data'),
          decision: ToolApprovalGateDecision.needsManualApproval,
        );
        fixture.observation.targets[ownerA] = _saveTarget(
          _operation(poisonedOwner, 'browser_save_data'),
        );

        await expectLater(
          fixture.handler.handle(_request(ownerA, 'browser_save_data')),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Browser save target observation operation mismatch.',
            ),
          ),
        );
        expect(fixture.approval.manualCalls, isEmpty);
        expect(fixture.execution.calls, isEmpty);
      }
    });

    test('contains a mismatched browser transport completion', () async {
      for (final poisonedOwner in [ownerB, ownerANext]) {
        final fixture = _fixture();
        fixture.execution.results[ownerA] = BrowserExecutionResult(
          operation: _operation(poisonedOwner, 'browser_open'),
          result: _toolResult('browser_open', result: 'poisoned'),
        );

        await expectLater(
          fixture.handler.handle(_request(ownerA, 'browser_open')),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Browser execution operation mismatch.',
            ),
          ),
        );
      }
    });

    test('consults only the exact owner across all ports', () async {
      final fixture = _fixture();
      fixture.observation.pages
        ..[ownerA] = BrowserPageObservation(
          operation: _operation(ownerA, 'browser_click'),
          currentUrl: 'https://owner-a.example',
        )
        ..[ownerB] = BrowserPageObservation(
          operation: _operation(ownerB, 'browser_click'),
          currentUrl: 'https://owner-b.example',
        )
        ..[ownerANext] = BrowserPageObservation(
          operation: _operation(ownerANext, 'browser_click'),
          currentUrl: 'https://successor.example',
        );
      fixture.approval.gates
        ..[ownerA] = BrowserApprovalGateResult(
          operation: _operation(ownerA, 'browser_click'),
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        )
        ..[ownerB] = BrowserApprovalGateResult(
          operation: _operation(ownerB, 'browser_click'),
          decision: ToolApprovalGateDecision.denied('Owner B denied.'),
        )
        ..[ownerANext] = BrowserApprovalGateResult(
          operation: _operation(ownerANext, 'browser_click'),
          decision: ToolApprovalGateDecision.denied('Successor denied.'),
        );
      fixture.execution.results
        ..[ownerA] = BrowserExecutionResult(
          operation: _operation(ownerA, 'browser_click'),
          result: _toolResult('browser_click', result: 'owner-a-result'),
        )
        ..[ownerB] = BrowserExecutionResult(
          operation: _operation(ownerB, 'browser_click'),
          result: _toolResult('browser_click', result: 'owner-b-result'),
        );

      final result = await fixture.handler.handle(
        _request(ownerA, 'browser_click'),
      );

      expect(result.result, 'owner-a-result');
      expect(
        fixture.approval.gateCalls.single.request.reviewArguments['pageHost'],
        'owner-a.example',
      );
      expect(fixture.observation.owners.toSet(), {ownerA});
      expect(fixture.approval.owners.toSet(), {ownerA});
      expect(fixture.execution.owners.toSet(), {ownerA});
    });
  });
}

BrowserToolRequest _request(
  ChatTurnOwner owner,
  String toolName, {
  Map<String, dynamic> arguments = const {},
  String? toolCallId,
}) {
  return BrowserToolRequest(
    operation: _operation(owner, toolName, toolCallId: toolCallId),
    arguments: arguments,
  );
}

BrowserSessionOperationIdentity _operation(
  ChatTurnOwner owner,
  String toolName, {
  String? toolCallId,
}) {
  return BrowserSessionOperationIdentity(
    owner: owner,
    toolCallId: toolCallId ?? 'call-$toolName',
    toolName: toolName,
  );
}

McpToolResult _toolResult(
  String toolName, {
  String result = '{"ok":true}',
  bool isSuccess = true,
  String? errorMessage,
}) {
  return McpToolResult(
    toolName: toolName,
    result: result,
    isSuccess: isSuccess,
    errorMessage: errorMessage,
  );
}

BrowserSaveTargetObservation _saveTarget(
  BrowserSessionOperationIdentity operation,
) {
  return BrowserSaveTargetObservation(
    operation: operation,
    destinationLabel: 'Downloads folder',
    destinationChanged: false,
    requestedDestination: 'downloads',
    requestedFilename: 'report.json',
    filename: 'report.json',
    directoryPath: '/downloads',
    path: '/downloads/report.json',
  );
}

typedef _Fixture = ({
  BrowserToolHandler handler,
  BrowserSessionOwnershipCoordinator session,
  _ExecutionPort execution,
  _ApprovalPort approval,
  _ObservationPort observation,
  List<String> events,
});

_Fixture _fixture() {
  final events = <String>[];
  final execution = _ExecutionPort(events);
  final approval = _ApprovalPort(events);
  final observation = _ObservationPort(events);
  final session = BrowserSessionOwnershipCoordinator();
  return (
    handler: BrowserToolHandler(
      executionPort: execution,
      approvalPort: approval,
      observationPort: observation,
      sessionCoordinator: session,
    ),
    session: session,
    execution: execution,
    approval: approval,
    observation: observation,
    events: events,
  );
}

typedef _ExecutionCall = ({
  BrowserSessionOperationIdentity operation,
  BrowserExecutionRequest request,
});

final class _ExecutionPort implements BrowserExecutionPort {
  _ExecutionPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, BrowserExecutionResult> results = {};
  final Map<ChatTurnOwner, Object> errors = {};
  final List<_ExecutionCall> calls = [];
  void Function(BrowserSessionOperationIdentity operation)? beforeReturn;

  List<ChatTurnOwner> get owners => [
    for (final call in calls) call.operation.owner,
  ];

  @override
  Future<BrowserExecutionResult> execute(
    BrowserSessionOperationIdentity operation,
    BrowserExecutionRequest request,
    BrowserSessionEffectPermit permit,
  ) {
    return permit.runEffect(() async {
      final owner = operation.owner;
      events.add(_event('execution:${request.toolName}', owner));
      calls.add((operation: operation, request: request));
      final error = errors[owner];
      if (error != null) {
        throw error;
      }
      beforeReturn?.call(operation);
      return results[owner] ??
          BrowserExecutionResult(
            operation: operation,
            result: _toolResult(request.toolName),
          );
    });
  }
}

typedef _GateCall = ({
  BrowserSessionOperationIdentity operation,
  BrowserApprovalGateRequest request,
});
typedef _ManualCall = ({
  BrowserSessionOperationIdentity operation,
  BrowserManualApprovalRequest request,
});

final class _ApprovalPort implements BrowserApprovalPort {
  _ApprovalPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, BrowserApprovalGateResult> gates = {};
  final Map<ChatTurnOwner, BrowserManualApprovalResult> manualResults = {};
  final Map<ChatTurnOwner, Object> gateErrors = {};
  final Map<ChatTurnOwner, Object> manualErrors = {};
  final Map<ChatTurnOwner, bool> current = {};
  final Map<ChatTurnOwner, Queue<bool>> currentResults = {};
  final Map<ChatTurnOwner, Queue<McpToolResult?>> expirations = {};
  bool materializeReviewArguments = true;
  final List<_GateCall> gateCalls = [];
  final List<_ManualCall> manualCalls = [];
  final List<ChatTurnOwner> currentOwners = [];
  final List<ChatTurnOwner> expiredOwners = [];

  List<ChatTurnOwner> get owners => [
    ...gateCalls.map((call) => call.operation.owner),
    ...manualCalls.map((call) => call.operation.owner),
    ...currentOwners,
    ...expiredOwners,
  ];

  @override
  Future<BrowserApprovalGateResult> resolveGate(
    BrowserSessionOperationIdentity operation,
    BrowserApprovalGateRequest request,
  ) async {
    final owner = operation.owner;
    if (materializeReviewArguments) {
      request.reviewArguments;
    }
    events.add(_event('approval.gate:${request.toolRequest.toolName}', owner));
    gateCalls.add((operation: operation, request: request));
    final error = gateErrors[owner];
    if (error != null) {
      throw error;
    }
    return gates[owner] ??
        BrowserApprovalGateResult(
          operation: operation,
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        );
  }

  @override
  Future<BrowserManualApprovalResult> requestManualApproval(
    BrowserSessionOperationIdentity operation,
    BrowserManualApprovalRequest request,
  ) async {
    final owner = operation.owner;
    events.add(
      _event('approval.manual:${request.toolRequest.toolName}', owner),
    );
    manualCalls.add((operation: operation, request: request));
    final error = manualErrors[owner];
    if (error != null) {
      throw error;
    }
    return manualResults[owner] ??
        BrowserManualApprovalResult(operation: operation, approved: true);
  }

  @override
  bool isOperationCurrent(BrowserSessionOperationIdentity operation) {
    final owner = operation.owner;
    events.add(_event('approval.current', owner));
    currentOwners.add(owner);
    final queue = currentResults[owner];
    if (queue != null && queue.isNotEmpty) return queue.removeFirst();
    return current[owner] ?? true;
  }

  @override
  McpToolResult? expiredResult(BrowserSessionOperationIdentity operation) {
    final owner = operation.owner;
    events.add(_event('approval.expired:${operation.toolName}', owner));
    expiredOwners.add(owner);
    final queue = expirations[owner];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeFirst();
  }
}

typedef _TargetCall = ({
  BrowserSessionOperationIdentity operation,
  BrowserSaveTargetRequest request,
});

final class _ObservationPort implements BrowserObservationPort {
  _ObservationPort(this.events);

  final List<String> events;
  final Map<ChatTurnOwner, BrowserPageObservation> pages = {};
  final Map<ChatTurnOwner, BrowserSaveTargetObservation> targets = {};
  final Map<ChatTurnOwner, Object> pageErrors = {};
  final Map<ChatTurnOwner, Object> targetErrors = {};
  final List<ChatTurnOwner> pageOwners = [];
  final List<_TargetCall> targetCalls = [];
  void Function(BrowserSessionOperationIdentity operation)? beforeTargetReturn;

  List<ChatTurnOwner> get owners => [
    ...pageOwners,
    ...targetCalls.map((call) => call.operation.owner),
  ];

  @override
  BrowserPageObservation currentPage(
    BrowserSessionOperationIdentity operation,
  ) {
    final owner = operation.owner;
    events.add(_event('observation.page', owner));
    pageOwners.add(owner);
    final error = pageErrors[owner];
    if (error != null) {
      throw error;
    }
    return pages[owner] ??
        BrowserPageObservation(
          operation: operation,
          currentUrl: 'https://example.com/path',
        );
  }

  @override
  Future<BrowserSaveTargetObservation> resolveSaveTarget(
    BrowserSessionOperationIdentity operation,
    BrowserSaveTargetRequest request,
  ) async {
    final owner = operation.owner;
    events.add(_event('observation.target', owner));
    targetCalls.add((operation: operation, request: request));
    final error = targetErrors[owner];
    if (error != null) {
      throw error;
    }
    beforeTargetReturn?.call(operation);
    return targets[owner] ?? _saveTarget(operation);
  }
}

String _event(String name, ChatTurnOwner owner) {
  return '$name:${owner.conversationId}:${owner.interactionGeneration}';
}

final class _MutableValue {
  var value = 0;
}

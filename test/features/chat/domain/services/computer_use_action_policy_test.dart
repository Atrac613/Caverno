import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/computer_use_action_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = ComputerUseActionPolicy();

  group('ComputerUseActionInput immutability', () {
    test('recursively freezes nested JSON maps and lists', () {
      final labels = <Object?>['button'];
      final metadata = <String, dynamic>{
        'labels': labels,
        'flags': <Object?>['safe'],
      };
      final arguments = <String, dynamic>{
        'target': metadata,
        'reason': '  Review the target.  ',
      };

      final input = ComputerUseActionInput(
        toolName: 'computer_click',
        arguments: arguments,
      );

      labels.add('poisoned');
      (metadata['flags'] as List<Object?>).add('poisoned');
      metadata['labels'] = ['replaced'];
      arguments['reason'] = 'Poisoned';

      expect(input.toolName, 'computer_click');
      expect(input.arguments['reason'], '  Review the target.  ');
      expect(input.arguments['target'], {
        'labels': ['button'],
        'flags': ['safe'],
      });
      expect(
        () => (input.arguments['target'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.arguments['target'] as Map)['labels'] as List).add('late'),
        throwsUnsupportedError,
      );
      expect(
        () => ((input.arguments['target'] as Map)['flags'] as List).add('late'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON action arguments', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
        double.infinity,
      ]) {
        expect(
          () => ComputerUseActionInput(
            toolName: 'computer_click',
            arguments: {'invalid': invalidValue},
          ),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });

    test('freezes presentation, context, and blocked-input lists', () {
      final presentation = policy.approvalPresentation(
        _action('computer_focus_window', {'window_id': 7}),
      );
      final context = policy.visionObservationContext(
        _action('computer_click', {'window_id': 7}),
      );
      final blockers = <String>['target_missing'];
      final blocked = ComputerUseBlockedInput(
        action: _action('computer_click'),
        policy: null,
        code: 'action_policy_blocked',
        approvalBlockerCodes: blockers,
      );

      blockers.add('poisoned');

      expect(() => presentation.details.add('late'), throwsUnsupportedError);
      expect(() => context.details.add('late'), throwsUnsupportedError);
      expect(blocked.approvalBlockerCodes, ['target_missing']);
      expect(
        () => blocked.approvalBlockerCodes.add('late'),
        throwsUnsupportedError,
      );
    });
  });

  group('ComputerUseActionPolicy supported action presentation', () {
    test('preserves every action-specific description, detail, and target', () {
      final cases =
          <
            ({
              String toolName,
              Map<String, dynamic> arguments,
              String summary,
              List<String> details,
              Map<String, dynamic>? target,
              String? exactText,
            })
          >[
            (
              toolName: 'computer_focus_window',
              arguments: {'window_id': 42, 'reason': '  Focus the editor.  '},
              summary: 'Focus window 42',
              details: [
                'Tool: computer_focus_window',
                'Window ID: 42',
                'Model reason: Focus the editor.',
              ],
              target: {
                'label': 'Window 42',
                'role': 'window',
                'action': 'focus',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_move_mouse',
              arguments: {
                'x': 10,
                'y': 20,
                'window_id': 42,
                'source_width': 640,
                'source_height': 480,
                'display_id': 2,
              },
              summary: 'Move pointer to (10, 20)',
              details: [
                'Tool: computer_move_mouse',
                'Coordinates: x=10, y=20',
                'Window ID: 42',
                'Source screenshot: 640 x 480 px',
                'Display ID: 2',
              ],
              target: {
                'label': 'Pointer target (10, 20)',
                'role': 'coordinate',
                'action': 'move',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_click',
              arguments: {
                'x': 10,
                'y': 20,
                'button': 'right',
                'click_count': 2,
                'window_id': 42,
                'source_width': 640,
                'source_height': 480,
                'display_id': 2,
              },
              summary: 'Click right at (10, 20)',
              details: [
                'Tool: computer_click',
                'Coordinates: x=10, y=20',
                'Button: right',
                'Click count: 2',
                'Window ID: 42',
                'Source screenshot: 640 x 480 px',
                'Display ID: 2',
              ],
              target: {
                'label': 'Click target (10, 20)',
                'role': 'coordinate',
                'action': 'click',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_drag',
              arguments: {
                'from_x': 1,
                'from_y': 2,
                'to_x': 30,
                'to_y': 40,
                'duration_ms': 450,
                'window_id': 42,
                'source_width': 640,
                'source_height': 480,
                'display_id': 2,
              },
              summary: 'Drag from (1, 2) to (30, 40)',
              details: [
                'Tool: computer_drag',
                'From: x=1, y=2',
                'To: x=30, y=40',
                'Duration: 450 ms',
                'Window ID: 42',
                'Source screenshot: 640 x 480 px',
                'Display ID: 2',
              ],
              target: {
                'label': 'Drag target (1, 2) to (30, 40)',
                'role': 'coordinate_range',
                'action': 'drag',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_scroll',
              arguments: {
                'delta_x': 1,
                'delta_y': -7,
                'window_id': 42,
                'x': 10,
                'y': 20,
              },
              summary: 'Scroll by (1, -7)',
              details: [
                'Tool: computer_scroll',
                'Delta X: 1',
                'Delta Y: -7',
                'Window ID: 42',
                'Pointer target: x=10, y=20',
              ],
              target: {
                'label': 'Scroll target (10, 20)',
                'role': 'scroll_target',
                'action': 'scroll',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_type_text',
              arguments: {'text': 'hello\nworld'},
              summary: 'Type "hello world"',
              details: [
                'Tool: computer_type_text',
                'Text length: 11 characters',
                'Text preview: "hello world"',
              ],
              target: {
                'label': 'Focused text input',
                'role': 'text_input',
                'action': 'type_text',
              },
              exactText: 'hello\nworld',
            ),
            (
              toolName: 'computer_switch_space',
              arguments: {'direction': 'left'},
              summary: 'Switch to previous macOS Space',
              details: [
                'Tool: computer_switch_space',
                'Direction: previous',
                'Shortcut: control+left',
              ],
              target: {
                'label': 'macOS Space previous',
                'role': 'macos_space',
                'action': 'switch_space',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_press_key',
              arguments: {
                'key': 'enter',
                'modifiers': ['command', 'shift'],
              },
              summary: 'Press command+shift+enter',
              details: ['Tool: computer_press_key', 'Key: command+shift+enter'],
              target: {
                'label': 'command+shift+enter',
                'role': 'keyboard_shortcut',
                'action': 'press_key',
              },
              exactText: null,
            ),
            (
              toolName: 'computer_start_system_audio_recording',
              arguments: {
                'output_path': '/tmp/system.caf',
                'exclude_current_process_audio': false,
              },
              summary: 'Start recording system audio to /tmp/system.caf',
              details: [
                'Tool: computer_start_system_audio_recording',
                'Output: /tmp/system.caf',
                'Exclude Caverno audio: false',
              ],
              target: null,
              exactText: null,
            ),
          ];

      for (final testCase in cases) {
        final action = _action(testCase.toolName, testCase.arguments);
        final presentation = policy.approvalPresentation(action);

        expect(
          presentation.summary,
          testCase.summary,
          reason: testCase.toolName,
        );
        expect(
          presentation.details,
          testCase.details,
          reason: testCase.toolName,
        );
        expect(
          policy.describeAction(action),
          testCase.summary,
          reason: testCase.toolName,
        );
        expect(
          policy.actionDetails(action),
          testCase.details,
          reason: testCase.toolName,
        );
        expect(
          policy.actionTarget(action),
          testCase.target,
          reason: testCase.toolName,
        );
        expect(
          policy.exactText(action),
          testCase.exactText,
          reason: testCase.toolName,
        );
      }
    });

    test('preserves action defaults and absent optional details', () {
      final cases =
          <
            ({
              String toolName,
              Map<String, dynamic> arguments,
              String summary,
              List<String> details,
              Map<String, dynamic>? target,
            })
          >[
            (
              toolName: 'computer_move_mouse',
              arguments: {'x': null, 'y': null},
              summary: 'Move pointer to (null, null)',
              details: [
                'Tool: computer_move_mouse',
                'Coordinates: x=null, y=null',
              ],
              target: {
                'label': 'Pointer target (null, null)',
                'role': 'coordinate',
                'action': 'move',
              },
            ),
            (
              toolName: 'computer_click',
              arguments: {'x': 4, 'y': 5},
              summary: 'Click left at (4, 5)',
              details: [
                'Tool: computer_click',
                'Coordinates: x=4, y=5',
                'Button: left',
                'Click count: 1',
              ],
              target: {
                'label': 'Click target (4, 5)',
                'role': 'coordinate',
                'action': 'click',
              },
            ),
            (
              toolName: 'computer_drag',
              arguments: {'from_x': 1, 'from_y': 2, 'to_x': 3, 'to_y': 4},
              summary: 'Drag from (1, 2) to (3, 4)',
              details: [
                'Tool: computer_drag',
                'From: x=1, y=2',
                'To: x=3, y=4',
                'Duration: 300 ms',
              ],
              target: {
                'label': 'Drag target (1, 2) to (3, 4)',
                'role': 'coordinate_range',
                'action': 'drag',
              },
            ),
            (
              toolName: 'computer_scroll',
              arguments: const {},
              summary: 'Scroll by (0, -5)',
              details: ['Tool: computer_scroll', 'Delta X: 0', 'Delta Y: -5'],
              target: {
                'label': 'Scroll target (current, current)',
                'role': 'scroll_target',
                'action': 'scroll',
              },
            ),
            (
              toolName: 'computer_type_text',
              arguments: const {},
              summary: 'Type (empty text)',
              details: [
                'Tool: computer_type_text',
                'Text length: 0 characters',
                'Text preview: (empty text)',
              ],
              target: {
                'label': 'Focused text input',
                'role': 'text_input',
                'action': 'type_text',
              },
            ),
            (
              toolName: 'computer_switch_space',
              arguments: const {},
              summary: 'Switch to next macOS Space',
              details: [
                'Tool: computer_switch_space',
                'Direction: next',
                'Shortcut: control+right',
              ],
              target: {
                'label': 'macOS Space next',
                'role': 'macos_space',
                'action': 'switch_space',
              },
            ),
            (
              toolName: 'computer_press_key',
              arguments: const {},
              summary: 'Press (unknown key)',
              details: ['Tool: computer_press_key', 'Key: (unknown key)'],
              target: {
                'label': '(unknown key)',
                'role': 'keyboard_shortcut',
                'action': 'press_key',
              },
            ),
            (
              toolName: 'computer_start_system_audio_recording',
              arguments: const {},
              summary: 'Start recording system audio to a temporary CAF file',
              details: [
                'Tool: computer_start_system_audio_recording',
                'Output: temporary CAF file',
                'Exclude Caverno audio: true',
              ],
              target: null,
            ),
          ];

      for (final testCase in cases) {
        final action = _action(testCase.toolName, testCase.arguments);
        expect(policy.describeAction(action), testCase.summary);
        expect(policy.actionDetails(action), testCase.details);
        expect(policy.actionTarget(action), testCase.target);
      }
    });

    test('uses the generic presentation for every other supported tool', () {
      final genericTools = MacosComputerUseToolPolicy.allToolNames
          .difference(const {
            'computer_focus_window',
            'computer_move_mouse',
            'computer_click',
            'computer_drag',
            'computer_scroll',
            'computer_type_text',
            'computer_switch_space',
            'computer_press_key',
            'computer_start_system_audio_recording',
          });

      for (final toolName in genericTools) {
        final action = _action(toolName);
        expect(policy.describeAction(action), '$toolName {}');
        expect(policy.actionDetails(action), ['Tool: $toolName']);
        expect(policy.actionTarget(action), isNull);
        expect(policy.exactText(action), isNull);
      }
    });

    test('preserves generic argument order and trimmed model reason', () {
      final action = _action('computer_custom', {
        'reason': '  Explain the action.  ',
        'value': 1,
      });

      expect(
        policy.describeAction(action),
        'computer_custom {"reason":"  Explain the action.  ","value":1}',
      );
      expect(policy.actionDetails(action), [
        'Tool: computer_custom',
        'Model reason: Explain the action.',
      ]);
    });
  });

  group('ComputerUseActionPolicy targets and exact text', () {
    test('prefers and freezes a structured target without normalizing it', () {
      final nested = <Object?>['original'];
      final source = <String, dynamic>{
        'label': '  Save  ',
        'role': 'button',
        'nested': nested,
      };
      final action = _action('computer_click', {
        'target': source,
        'target_label': 7,
        'x': 1,
        'y': 2,
      });

      nested.add('poisoned');
      source['label'] = 'Poisoned';
      final target = policy.actionTarget(action)!;

      expect(target, {
        'label': '  Save  ',
        'role': 'button',
        'nested': ['original'],
      });
      expect(() => target['new'] = true, throwsUnsupportedError);
      expect(
        () => (target['nested'] as List).add('late'),
        throwsUnsupportedError,
      );
    });

    test('builds a trimmed explicit target and omits blank fields', () {
      final target = policy.actionTarget(
        _action('computer_click', {
          'target_label': '  Send  ',
          'target_role': '  button  ',
          'target_risk': '  public_action  ',
          'target_action': '   ',
        }),
      );

      expect(target, {
        'label': 'Send',
        'role': 'button',
        'risk': 'public_action',
      });
    });

    test('preserves explicit target field validation order', () async {
      final cases = <Map<String, dynamic>>[
        {'target_label': 1},
        {'target_label': null, 'target_role': 1},
        {'target_label': null, 'target_role': null, 'target_risk': 1},
        {
          'target_label': null,
          'target_role': null,
          'target_risk': null,
          'target_action': 1,
        },
      ];

      for (final arguments in cases) {
        expect(
          () => policy.actionTarget(_action('computer_click', arguments)),
          throwsA(isA<TypeError>()),
        );
      }
    });

    test('returns null for absent targets and preserves exact typing text', () {
      const secret = 'password = "do-not-log"';

      expect(
        policy.actionTarget(_action('computer_start_system_audio_recording')),
        isNull,
      );
      expect(policy.actionTarget(_action('computer_custom')), isNull);
      expect(
        policy.exactText(_action('computer_type_text', {'text': secret})),
        secret,
      );
      expect(
        policy.exactText(_action('computer_type_text', {'text': null})),
        isNull,
      );
      expect(policy.exactText(_action('computer_click', {'text': 7})), isNull);
      expect(
        () => policy.exactText(_action('computer_type_text', {'text': 7})),
        throwsA(isA<TypeError>()),
      );
    });

    test('extracts metadata by source, key, and supported scalar type', () {
      final target = <String, dynamic>{
        'primary': '   ',
        'secondary': '  target value  ',
        'number': 7,
        'flag': false,
        'ignored': <String>['not scalar'],
      };
      final arguments = <String, dynamic>{
        'primary': 'argument value',
        'secondary': 'argument fallback',
      };

      expect(
        policy.metadataString(target, arguments, const [
          'primary',
          'secondary',
        ]),
        'target value',
      );
      expect(policy.metadataString(target, arguments, const ['number']), '7');
      expect(policy.metadataString(target, arguments, const ['flag']), 'false');
      expect(
        policy.metadataString(null, arguments, const ['primary']),
        'argument value',
      );
      expect(
        policy.metadataString(target, arguments, const ['ignored', 'missing']),
        isNull,
      );
      expect(policy.metadataString(null, const {}, const []), isNull);
    });
  });

  group('ComputerUseActionPolicy text, key, and space formatting', () {
    test('preserves empty, normalized, long, and escaped text formatting', () {
      expect(policy.summarizeText(null), '(empty text)');
      expect(policy.summarizeText(''), '(empty text)');
      expect(policy.summarizeText('   \n  '), '""');
      expect(
        policy.summarizeText('  say  "hello"\nnext  '),
        '"say \\"hello\\" next"',
      );
      expect(policy.summarizeText('abcdef', maxLength: 4), '"abc..."');
      expect(() => policy.summarizeText(7), throwsA(isA<TypeError>()));
    });

    test('preserves keyboard modifier filtering and key formatting', () {
      expect(policy.formatKey(null, null), '(unknown key)');
      expect(policy.formatKey('enter', null), 'enter');
      expect(policy.formatKey(' ', const []), '(unknown key)');
      expect(policy.formatKey(7, 'command'), '7');
      expect(
        policy.formatKey('K', ['', ' ', null, 2, 'command']),
        'null+2+command+K',
      );
    });

    test('preserves every previous alias and next fallback', () {
      for (final value in ['previous', 'PREV', ' left ']) {
        expect(policy.formatSpaceDirection(value), 'previous');
      }
      for (final value in [null, '', 'next', 'right', 'unknown', 7]) {
        expect(policy.formatSpaceDirection(value), 'next');
      }
    });
  });

  group('ComputerUseActionPolicy observation inputs', () {
    test('builds and freezes front-window observation arguments', () {
      final arguments = policy.postActionVisionArguments(
        _action('computer_click'),
      );

      expect(arguments, {
        'target': 'front_window',
        'max_width': 800,
        'include_windows': true,
      });
      expect(() => arguments['late'] = true, throwsUnsupportedError);
    });

    test('preserves window and display identifiers independently', () {
      final cases = [
        (
          arguments: <String, dynamic>{'window_id': 42},
          expected: <String, dynamic>{
            'target': 'window',
            'max_width': 800,
            'include_windows': true,
            'window_id': 42,
          },
        ),
        (
          arguments: <String, dynamic>{'display_id': 2},
          expected: <String, dynamic>{
            'target': 'front_window',
            'max_width': 800,
            'include_windows': true,
            'display_id': 2,
          },
        ),
        (
          arguments: <String, dynamic>{'window_id': 42, 'display_id': 2},
          expected: <String, dynamic>{
            'target': 'window',
            'max_width': 800,
            'include_windows': true,
            'window_id': 42,
            'display_id': 2,
          },
        ),
      ];

      for (final testCase in cases) {
        expect(
          policy.postActionVisionArguments(
            _action('computer_click', testCase.arguments),
          ),
          testCase.expected,
        );
      }
    });

    test('builds exact vision context with present and absent metadata', () {
      final full = policy.visionObservationContext(
        _action('computer_click', {
          'vision_observation_id': 'vision-1',
          'coordinate_space': 'window_pixels',
          'source_width': 640,
          'source_height': 480,
          'window_id': 42,
          'display_id': 2,
        }),
      );
      final partial = policy.visionObservationContext(
        _action('computer_click', {'source_width': 640}),
      );

      expect(
        full.summary,
        'Verify this action against the latest vision observation before approving.',
      );
      expect(full.details, [
        'Observation ID: vision-1',
        'Coordinate space: window_pixels',
        'Source screenshot: 640 x 480 px',
        'Target window ID: 42',
        'Target display ID: 2',
      ]);
      expect(
        partial.summary,
        'Verify this action against the latest vision observation before approving.',
      );
      expect(partial.details, isEmpty);
    });
  });

  group('ComputerUseActionPolicy result composition', () {
    test('returns the original result when observation is absent', () {
      const original = McpToolResult(
        toolName: 'computer_click',
        result: '{"ok":true}',
        isSuccess: true,
        isExternalMcpResult: true,
      );

      final composed = policy.resultWithPostActionObservation(
        const ComputerUseResultCompositionInput(
          actionResult: original,
          policy: null,
          observation: null,
        ),
      );

      expect(composed, same(original));
    });

    test('redacts action text and image while attaching observation image', () {
      const secret = 'secret typed text';
      const image = 'base64-image';
      final decision = MacosComputerUseToolPolicy.decision('computer_click');
      const actionResult = McpToolResult(
        toolName: 'computer_click',
        result:
            '{"ok":true,"code":"ok","text":"secret typed text",'
            '"imageBase64":"action-image"}',
        isSuccess: true,
      );
      const observation = ComputerUsePostActionObservation(
        toolName: 'computer_vision_observe',
        success: true,
        result:
            '{"schemaName":"vision","imageBase64":"base64-image",'
            '"imageMimeType":"image/jpeg","windowId":42}',
      );

      final result = policy.resultWithPostActionObservation(
        ComputerUseResultCompositionInput(
          actionResult: actionResult,
          policy: decision,
          observation: observation,
        ),
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(result.toolName, 'computer_click');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(payload, {
        'ok': true,
        'schemaName': 'macos_computer_use_action_result',
        'schemaVersion': 1,
        'toolName': 'computer_click',
        'policy': decision!.toJson(),
        'action': {
          'ok': true,
          'code': 'ok',
          'textRedacted': true,
          'textLength': secret.length,
        },
        'postActionObservationRequired': true,
        'postActionObservation': {
          'toolName': 'computer_vision_observe',
          'success': true,
          'imageAttached': true,
          'schemaName': 'vision',
          'imageMimeType': 'image/jpeg',
          'windowId': 42,
        },
        'imageBase64': image,
        'imageMimeType': 'image/jpeg',
        'nextAction':
            'Inspect the attached post-action observation before proposing another desktop action.',
      });
    });

    test('uses the default image MIME type when observation omits it', () {
      final result = policy.resultWithPostActionObservation(
        const ComputerUseResultCompositionInput(
          actionResult: McpToolResult(
            toolName: 'computer_click',
            result: '{"ok":true}',
            isSuccess: true,
          ),
          policy: null,
          observation: ComputerUsePostActionObservation(
            toolName: 'computer_vision_observe',
            success: true,
            result: '{"imageBase64":"image"}',
          ),
        ),
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(payload['imageBase64'], 'image');
      expect(payload['imageMimeType'], 'image/png');
      expect(payload['policy'], isNull);
      expect(payload['postActionObservationRequired'], isFalse);
    });

    test('preserves an empty image MIME field without attaching an image', () {
      final result = policy.resultWithPostActionObservation(
        const ComputerUseResultCompositionInput(
          actionResult: McpToolResult(
            toolName: 'computer_click',
            result: '{"text":7,"imageBase64":"action"}',
            isSuccess: false,
            errorMessage: 'action failed',
          ),
          policy: null,
          observation: ComputerUsePostActionObservation(
            toolName: 'computer_vision_observe',
            success: true,
            result: '{"imageBase64":"","imageMimeType":"image/gif"}',
          ),
        ),
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      final post = payload['postActionObservation'] as Map<String, dynamic>;

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'action failed');
      expect(payload['action'], <String, dynamic>{});
      expect(payload, isNot(contains('imageBase64')));
      expect(payload, isNot(contains('imageMimeType')));
      expect(post, {
        'toolName': 'computer_vision_observe',
        'success': true,
        'imageAttached': false,
        'imageMimeType': 'image/gif',
      });
      expect(
        payload['nextAction'],
        'Run computer_vision_observe before proposing another desktop action.',
      );
    });

    test('falls back for raw action and failed observation results', () {
      const rawAction = 'not-json';
      final result = policy.resultWithPostActionObservation(
        const ComputerUseResultCompositionInput(
          actionResult: McpToolResult(
            toolName: 'computer_click',
            result: rawAction,
            isSuccess: true,
          ),
          policy: null,
          observation: ComputerUsePostActionObservation(
            toolName: 'computer_vision_observe',
            success: false,
            result: '[1,2]',
            errorCode: 'observe_failed',
          ),
        ),
      );
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(payload['action'], {'rawResult': rawAction});
      expect(payload['postActionObservation'], {
        'toolName': 'computer_vision_observe',
        'success': false,
        'imageAttached': false,
        'errorCode': 'observe_failed',
        'ok': false,
        'code': 'observe_failed',
      });
    });

    test(
      'falls back when action is non-map JSON and observation is invalid',
      () {
        final result = policy.resultWithPostActionObservation(
          const ComputerUseResultCompositionInput(
            actionResult: McpToolResult(
              toolName: 'computer_click',
              result: '[1,2]',
              isSuccess: true,
            ),
            policy: null,
            observation: ComputerUsePostActionObservation(
              toolName: 'computer_vision_observe',
              success: false,
              result: 'invalid-json',
            ),
          ),
        );
        final payload = jsonDecode(result.result) as Map<String, dynamic>;

        expect(payload['action'], {'rawResult': '[1,2]'});
        expect(payload['postActionObservation'], {
          'toolName': 'computer_vision_observe',
          'success': false,
          'imageAttached': false,
          'ok': false,
        });
      },
    );

    test('rejects a non-string observation image MIME type', () {
      expect(
        () => policy.resultWithPostActionObservation(
          const ComputerUseResultCompositionInput(
            actionResult: McpToolResult(
              toolName: 'computer_click',
              result: '{}',
              isSuccess: true,
            ),
            policy: null,
            observation: ComputerUsePostActionObservation(
              toolName: 'computer_vision_observe',
              success: true,
              result: '{"imageMimeType":7}',
            ),
          ),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('redacts only top-level action image and typed text fields', () {
      final redacted = policy.redactActionResult({
        'imageBase64': 'image',
        'text': '',
        'token': 'preserved',
        'nested': {'text': 'nested'},
      });
      final nonString = policy.redactActionResult({
        'text': 7,
        'imageBase64': 9,
      });

      expect(redacted, {
        'token': 'preserved',
        'nested': {'text': 'nested'},
        'textRedacted': true,
        'textLength': 0,
      });
      expect(nonString, isEmpty);
    });
  });

  group('ComputerUseActionPolicy blocked outcomes', () {
    test('preserves every blocked code, message, and next action', () {
      final cases =
          <
            ({
              String code,
              String error,
              String nextAction,
              List<String> blockers,
              String? proposalNextAction,
            })
          >[
            (
              code: 'arming_missing',
              error:
                  'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
              nextAction:
                  'Ask the user to explicitly arm the pending Computer Use action before retrying.',
              blockers: const [],
              proposalNextAction: null,
            ),
            (
              code: 'approval_denied',
              error: 'User denied macOS computer use action.',
              nextAction:
                  'Ask the user for explicit approval before retrying this Computer Use action.',
              blockers: const [],
              proposalNextAction: null,
            ),
            (
              code: 'action_policy_blocked',
              error: 'Computer Use action blocked by the target safety policy.',
              nextAction: 'Choose a safe target.',
              blockers: const ['target_missing', 'credential_target_blocked'],
              proposalNextAction: 'Choose a safe target.',
            ),
            (
              code: 'unexpected',
              error: 'macOS computer use action was blocked.',
              nextAction:
                  'Inspect the Computer Use approval state before retrying.',
              blockers: const [],
              proposalNextAction: null,
            ),
          ];

      for (final testCase in cases) {
        final outcome = policy.blockedOutcome(
          ComputerUseBlockedInput(
            action: _action('computer_click'),
            policy: null,
            code: testCase.code,
            approvalBlockerCodes: testCase.blockers,
            actionProposalNextAction: testCase.proposalNextAction,
          ),
        );
        final payload = jsonDecode(outcome.result) as Map<String, dynamic>;

        expect(outcome.errorMessage, testCase.error);
        expect(policy.blockedErrorMessage(testCase.code), testCase.error);
        expect(payload, {
          'ok': false,
          'toolName': 'computer_click',
          'code': testCase.code,
          'error': testCase.error,
          'policy': null,
          'requiresUserApproval': false,
          'requiresSmokeArming': false,
          'emergencyStop': false,
          if (testCase.blockers.isNotEmpty)
            'approvalBlockers': testCase.blockers,
          'nextAction': testCase.nextAction,
        });
      }
    });

    test('uses the action-policy fallback and exact unknown JSON payload', () {
      final fallback = policy.blockedOutcome(
        ComputerUseBlockedInput(
          action: _action('computer_click'),
          policy: null,
          code: 'action_policy_blocked',
        ),
      );
      final unknown = policy.blockedResult(
        ComputerUseBlockedInput(
          action: _action('computer_click'),
          policy: null,
          code: 'unexpected',
        ),
      );

      expect(
        jsonDecode(fallback.result),
        containsPair(
          'nextAction',
          'Resolve the Computer Use action policy blockers before retrying.',
        ),
      );
      expect(
        unknown,
        '{"ok":false,"toolName":"computer_click","code":"unexpected",'
        '"error":"macOS computer use action was blocked.","policy":null,'
        '"requiresUserApproval":false,"requiresSmokeArming":false,'
        '"emergencyStop":false,"nextAction":"Inspect the Computer Use '
        'approval state before retrying."}',
      );
    });

    test('preserves policy flags including the emergency stop', () {
      final decision = MacosComputerUseToolPolicy.decision(
        'computer_stop_system_audio_recording',
      )!;
      final outcome = policy.blockedOutcome(
        ComputerUseBlockedInput(
          action: _action('computer_stop_system_audio_recording'),
          policy: decision,
          code: 'unexpected',
        ),
      );
      final payload = jsonDecode(outcome.result) as Map<String, dynamic>;

      expect(payload['policy'], decision.toJson());
      expect(payload['requiresUserApproval'], isFalse);
      expect(payload['requiresSmokeArming'], isFalse);
      expect(payload['emergencyStop'], isTrue);
    });
  });
}

ComputerUseActionInput _action(
  String toolName, [
  Map<String, dynamic> arguments = const {},
]) {
  return ComputerUseActionInput(toolName: toolName, arguments: arguments);
}

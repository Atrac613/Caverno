import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/claims/skipped_browser_action_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

const policy = SkippedBrowserActionRecovery();
const snapshot = {
  'type': 'function',
  'function': {'name': 'browser_snapshot'},
};

ToolResultInfo result({
  String id = 'recovered_browser_snapshot_42',
  String name = 'browser_snapshot',
  String content = 'ok',
}) => ToolResultInfo(id: id, name: name, arguments: const {}, result: content);

void main() {
  for (final prompt in [
    'Click the link',
    '\u30ea\u30f3\u30af\u3092\u30af\u30ea\u30c3\u30af',
  ]) {
    test('recovers snapshot with original arguments and clock: $prompt', () {
      var reads = 0;
      final now = DateTime.fromMicrosecondsSinceEpoch(123456);
      final call = policy.resolve(
        hasToolCalls: false,
        disabledToolNames: {},
        availableTools: [snapshot],
        latestUserContent: prompt,
        now: () {
          reads++;
          return now;
        },
      );
      expect(reads, 1);
      expect(call!.id, 'recovered_browser_snapshot_123456');
      expect(call.name, 'browser_snapshot');
      expect(call.arguments, {'max_elements': 80});
    });
  }
  for (final mode in [
    'existing-call',
    'disabled',
    'unavailable',
    'no-intent',
    'empty',
  ]) {
    test('skips ineligible recovery without reading clock: $mode', () {
      final call = policy.resolve(
        hasToolCalls: mode == 'existing-call',
        disabledToolNames: mode == 'disabled' ? {'browser_snapshot'} : {},
        availableTools: mode == 'unavailable' ? [] : [snapshot],
        latestUserContent: mode == 'no-intent'
            ? 'Describe the page'
            : mode == 'empty'
            ? '   '
            : 'Click link',
        now: () => throw StateError('ineligible recovery must not read clock'),
      );
      expect(call, isNull);
    });
  }
  for (final hasCalls in [false, true]) {
    test(
      'early guards avoid parsing malformed definitions: calls=$hasCalls',
      () {
        expect(
          policy.resolve(
            hasToolCalls: hasCalls,
            disabledToolNames: hasCalls ? {} : {'browser_snapshot'},
            availableTools: [
              {'function': 42},
            ],
            latestUserContent: 'Click link',
            now: () => throw StateError('must not read clock'),
          ),
          isNull,
        );
      },
    );
  }

  test('repair needs response, recovered snapshot and owner action intent', () {
    expect(
      policy.shouldRepairAfterSnapshot(
        candidateResponse: 'Click done',
        batchToolResults: [result()],
        latestUserContent: 'Click link',
      ),
      true,
    );
    expect(
      policy.shouldRepairAfterSnapshot(
        candidateResponse: '   ',
        batchToolResults: [result()],
        latestUserContent: 'Click link',
      ),
      false,
    );
    expect(
      policy.shouldRepairAfterSnapshot(
        candidateResponse: 'done',
        batchToolResults: [],
        latestUserContent: 'Click link',
      ),
      false,
    );
    expect(
      policy.shouldRepairAfterSnapshot(
        candidateResponse: 'done',
        batchToolResults: [result()],
        latestUserContent: 'Describe page',
      ),
      false,
    );
  });
  test(
    'ordinary snapshot or another recovered tool is not recovery evidence',
    () {
      for (final evidence in [
        result(id: 'ordinary_snapshot'),
        result(name: 'browser_click'),
      ]) {
        expect(
          policy.shouldRepairAfterSnapshot(
            candidateResponse: 'done',
            batchToolResults: [evidence],
            latestUserContent: 'Click link',
          ),
          false,
        );
      }
    },
  );
  test(
    'snapshot result content does not change recovered-result recognition',
    () {
      expect(
        policy.shouldRepairAfterSnapshot(
          candidateResponse: 'done',
          batchToolResults: [result(content: '{"ok":false}')],
          latestUserContent: 'Click link',
        ),
        true,
      );
    },
  );
}

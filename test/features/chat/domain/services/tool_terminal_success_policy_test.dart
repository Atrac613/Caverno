import 'package:caverno/features/chat/domain/services/tool_terminal_success_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ToolTerminalSuccessPolicy();

  test('accepts only an explicit boolean terminal success marker', () {
    expect(
      policy.terminalMessage(
        '{"exit_code":0,"terminal_success":true,'
        '"terminal_message":"Verifier passed."}',
      ),
      'Verifier passed.',
    );
    expect(policy.terminalMessage('{"exit_code":0}'), isNull);
    expect(policy.terminalMessage('{"terminal_success":"true"}'), isNull);
  });

  test('uses a stable fallback when the terminal message is absent', () {
    expect(
      policy.terminalMessage('{"terminal_success":true}'),
      'Verification succeeded. The requested work is complete.',
    );
  });

  test('rejects malformed and non-object results', () {
    expect(policy.terminalMessage('not json'), isNull);
    expect(policy.terminalMessage('[]'), isNull);
  });

  test('terminal marker overrides a mutation-capable tool classification', () {
    final state = ToolTerminalSuccessBatchState();

    state.observeSuccessfulResult(
      rawResult:
          '{"terminal_success":true,"terminal_message":"Verifier passed."}',
      isMutationTool: true,
    );

    expect(state.message, 'Verifier passed.');
  });

  test('a later mutation invalidates earlier terminal evidence', () {
    final state = ToolTerminalSuccessBatchState()
      ..observeSuccessfulResult(
        rawResult: '{"terminal_success":true}',
        isMutationTool: true,
      )
      ..observeSuccessfulResult(
        rawResult: '{"path":"lib/main.dart"}',
        isMutationTool: true,
      );

    expect(state.message, isNull);
  });
}

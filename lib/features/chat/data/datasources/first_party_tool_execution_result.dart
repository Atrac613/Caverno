import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// Result text and trusted facts returned directly by a first-party tool.
class FirstPartyToolExecutionResult {
  const FirstPartyToolExecutionResult({
    required this.result,
    this.outcome,
    this.errorMessage,
  });

  const FirstPartyToolExecutionResult.payloadOnly(String result)
    : this(result: result);

  final String result;
  final ToolOutcome? outcome;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

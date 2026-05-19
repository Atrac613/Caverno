/// Tool call information emitted by the LLM.
class ToolCallInfo {
  ToolCallInfo({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Tool call result, including the originating arguments for later inspection.
class ToolResultInfo {
  ToolResultInfo({
    required this.id,
    required this.name,
    required this.arguments,
    required this.result,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String result;
}

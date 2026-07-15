enum CavernoRuntimeSurface { flutterGui, headless, terminal }

extension CavernoRuntimeSurfaceWireName on CavernoRuntimeSurface {
  String get wireName => switch (this) {
    CavernoRuntimeSurface.flutterGui => 'flutter_gui',
    CavernoRuntimeSurface.headless => 'headless',
    CavernoRuntimeSurface.terminal => 'terminal',
  };
}

enum CavernoRuntimeToolLifecycleState { queued, started, completed }

enum CavernoRuntimeApprovalRisk { low, medium, high }

abstract base class CavernoRuntimeEvent {
  const CavernoRuntimeEvent({
    required this.sequence,
    required this.timestamp,
    required this.turnId,
    this.conversationId,
  });

  static const schema = 'caverno_cli_event';
  static const schemaVersion = 1;

  final int sequence;
  final DateTime timestamp;
  final String turnId;
  final String? conversationId;

  String get type;

  Map<String, Object?> get payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'schemaVersion': schemaVersion,
    'sequence': sequence,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'type': type,
    if (conversationId != null) 'conversationId': conversationId,
    'turnId': turnId,
    'payload': payload,
  };
}

final class CavernoRuntimeRunStarted extends CavernoRuntimeEvent {
  const CavernoRuntimeRunStarted({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.surface,
    required this.mode,
    required this.model,
    required this.baseUrl,
    required this.workspace,
    required this.toolNames,
    required this.hidden,
    super.conversationId,
  });

  final CavernoRuntimeSurface surface;
  final String mode;
  final String model;
  final String baseUrl;
  final String? workspace;
  final List<String> toolNames;
  final bool hidden;

  @override
  String get type => 'run_started';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'surface': surface.wireName,
    'mode': mode,
    'model': model,
    'baseUrl': baseUrl,
    if (workspace != null) 'workspace': workspace,
    'toolNames': toolNames,
    'hidden': hidden,
  };
}

final class CavernoRuntimeAssistantDelta extends CavernoRuntimeEvent {
  const CavernoRuntimeAssistantDelta({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.delta,
    super.conversationId,
  });

  final String delta;

  @override
  String get type => 'assistant_delta';

  @override
  Map<String, Object?> get payload => <String, Object?>{'delta': delta};
}

final class CavernoRuntimeToolLifecycle extends CavernoRuntimeEvent {
  const CavernoRuntimeToolLifecycle({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.toolCallId,
    required this.toolName,
    required this.state,
    required this.loopIndex,
    this.schedulerClass,
    this.resultStatus,
    this.skipReason,
    this.durationMs,
    super.conversationId,
  });

  final String toolCallId;
  final String toolName;
  final CavernoRuntimeToolLifecycleState state;
  final int loopIndex;
  final String? schedulerClass;
  final String? resultStatus;
  final String? skipReason;
  final int? durationMs;

  @override
  String get type => 'tool_lifecycle';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'toolCallId': toolCallId,
    'toolName': toolName,
    'state': state.name,
    'loopIndex': loopIndex,
    if (schedulerClass != null) 'schedulerClass': schedulerClass,
    if (resultStatus != null) 'resultStatus': resultStatus,
    if (skipReason != null) 'skipReason': skipReason,
    if (durationMs != null) 'durationMs': durationMs,
  };
}

final class CavernoRuntimeApprovalRequest {
  const CavernoRuntimeApprovalRequest({
    required this.id,
    required this.capability,
    required this.risk,
    required this.summary,
    this.target,
    this.rememberAllowed = false,
  });

  final String id;
  final String capability;
  final CavernoRuntimeApprovalRisk risk;
  final String summary;
  final String? target;
  final bool rememberAllowed;
}

final class CavernoRuntimeApprovalRequired extends CavernoRuntimeEvent {
  const CavernoRuntimeApprovalRequired({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.request,
    super.conversationId,
  });

  final CavernoRuntimeApprovalRequest request;

  @override
  String get type => 'approval_required';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'id': request.id,
    'capability': request.capability,
    'risk': request.risk.name,
    'summary': request.summary,
    if (request.target != null) 'target': request.target,
    'rememberAllowed': request.rememberAllowed,
  };
}

final class CavernoRuntimeQuestionRequest {
  const CavernoRuntimeQuestionRequest({
    required this.id,
    required this.prompt,
    this.options = const <String>[],
    this.multiple = false,
  });

  final String id;
  final String prompt;
  final List<String> options;
  final bool multiple;
}

final class CavernoRuntimeQuestionRequired extends CavernoRuntimeEvent {
  const CavernoRuntimeQuestionRequired({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.request,
    super.conversationId,
  });

  final CavernoRuntimeQuestionRequest request;

  @override
  String get type => 'question_required';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'id': request.id,
    'prompt': request.prompt,
    'options': request.options,
    'multiple': request.multiple,
  };
}

final class CavernoRuntimeWorkflowTransition extends CavernoRuntimeEvent {
  const CavernoRuntimeWorkflowTransition({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.stage,
    this.taskId,
    this.taskStatus,
    super.conversationId,
  });

  final String stage;
  final String? taskId;
  final String? taskStatus;

  @override
  String get type => 'workflow_transition';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'stage': stage,
    if (taskId != null) 'taskId': taskId,
    if (taskStatus != null) 'taskStatus': taskStatus,
  };
}

final class CavernoRuntimeUsage extends CavernoRuntimeEvent {
  const CavernoRuntimeUsage({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    super.conversationId,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  @override
  String get type => 'usage';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
  };
}

sealed class CavernoRuntimeTerminalEvent extends CavernoRuntimeEvent {
  const CavernoRuntimeTerminalEvent({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    super.conversationId,
  });
}

final class CavernoRuntimeRunCompleted extends CavernoRuntimeTerminalEvent {
  const CavernoRuntimeRunCompleted({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.content,
    super.conversationId,
  });

  final String content;

  @override
  String get type => 'run_completed';

  @override
  Map<String, Object?> get payload => <String, Object?>{'content': content};
}

final class CavernoRuntimeRunFailed extends CavernoRuntimeTerminalEvent {
  const CavernoRuntimeRunFailed({
    required super.sequence,
    required super.timestamp,
    required super.turnId,
    required this.code,
    required this.message,
    required this.exitCode,
    super.conversationId,
  });

  final String code;
  final String message;
  final int exitCode;

  @override
  String get type => 'run_failed';

  @override
  Map<String, Object?> get payload => <String, Object?>{
    'code': code,
    'message': message,
    'exitCode': exitCode,
  };
}

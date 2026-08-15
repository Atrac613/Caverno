import 'dart:convert';

import '../../data/datasources/chat_datasource.dart';
import '../entities/flutter_run_issue.dart';
import 'flutter_run_issue_request.dart';
import '../entities/message.dart';

/// Sends one candidate block to the model and reads back a judgement.
///
/// Only the block is sent, never the whole log: the buffer is thousands of
/// lines of progress chatter and the evidence is the twenty that matter.
class FlutterRunIssueAnalyser {
  const FlutterRunIssueAnalyser();

  static const marker = 'CAVERNO_RUN_ISSUE';

  /// Analyses [candidate], returning it as an issue.
  ///
  /// Never throws and never returns null: a failed or unusable analysis still
  /// produces the issue, carrying the segmenter's own headline and marked
  /// unanalysed. The block was a real failure whether or not a model could
  /// describe it, and dropping it would hide that.
  Future<FlutterRunIssue> analyse({
    required ChatDataSource dataSource,
    required FlutterRunLogCandidate candidate,
    required String model,
    int occurrences = 1,
  }) async {
    final fallback = FlutterRunIssue(
      signature: candidate.signature,
      kind: candidate.kind,
      title: candidate.headline,
      evidence: candidate.evidence,
      location: candidate.location,
      occurrences: occurrences,
    );

    // Cast rather than promote: the structured-output capability is a separate
    // interface from ChatDataSource, and Dart does not narrow across the two.
    if (dataSource is! StructuredOutputChatDataSource) return fallback;
    final source = dataSource as StructuredOutputChatDataSource;

    try {
      final result = await source.createStructuredChatCompletion(
        messages: [
          Message(
            id: 'flutter-run-issue-${candidate.signature.hashCode}',
            role: MessageRole.user,
            content: FlutterRunIssueRequest.prompt(candidate),
            timestamp: DateTime.now(),
          ),
        ],
        responseFormat: const StructuredOutputRequest.jsonSchema(
          name: 'caverno_run_issue',
          schema: FlutterRunIssueRequest.schema,
        ),
        model: model,
        temperature: 0,
        maxTokens: 400,
      );
      final decoded = jsonDecode(result.content.trim());
      if (decoded is! Map) return fallback;
      final map = Map<String, dynamic>.from(decoded);
      final title = _string(map['title']);
      if (title.isEmpty) return fallback;
      return fallback.copyWith(
        // Only a window handed over on a bad exit may be ruled out; a block the
        // toolchain itself framed as a failure is one whatever the model says.
        dismissed:
            candidate.kind == FlutterRunIssueKind.unclassifiedFailure &&
            map['isFailure'] == false,
        title: title,
        cause: _string(map['cause']),
        severity: _severity(_string(map['severity'])),
        location: _string(map['location']).isEmpty
            ? candidate.location
            : _string(map['location']),
        analysed: true,
      );
    } on Object {
      return fallback;
    }
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static FlutterRunIssueSeverity _severity(String value) {
    return switch (value.toLowerCase()) {
      'warning' => FlutterRunIssueSeverity.warning,
      'info' => FlutterRunIssueSeverity.info,
      _ => FlutterRunIssueSeverity.error,
    };
  }
}
